#!/bin/bash
# notes-embed.sh — 对 notes/ 目录生成语义向量索引（本地 LM Studio embedding，不上云）。
# 用途：为 notes-semantic-search.sh 提供索引。
# 依赖：LM Studio 服务（端口 1235）+ 本地 embedding 模型
# 模型：bge-small-zh-v1.5（BERT，中文最优）优先，回退 bge/nomic
#
# 2026-08-16 v2 升级（"铺轨道"方案）：
#   * 分块：按段落（## 标题/空行分隔）切成块，每块一个向量——笔记变长时语义不糊，
#     检索按"块"命中，再聚合成文件。一个文件多个块。
#   * 增量：只重算内容变更的文件（md5 对比），未变的沿用旧向量——笔记多了重建也快。
#   * 触发阈值（写入 memory-research.md）：笔记 > 500 或重建 > 5s 时再评估真向量库。
# 用法：
#   notes-embed.sh          # 全量重建（或增量，默认）
#   notes-embed.sh -f       # 强制全量重建
#   notes-embed.sh -q       # 静默（成功无输出，失败 stderr）
set -u

MEM_DIR="${MEMORY_DIR:-$HOME/.dsh/memory}"
NOTES="$MEM_DIR/notes"
INDEX="$MEM_DIR/.vector-index.json"
PORT="${VISION_PORT:-1235}"
MODEL=""
QUIET=0
FORCE=0
for arg in "$@"; do
  case "$arg" in
    -q) QUIET=1 ;;
    -f) FORCE=1 ;;
  esac
done

fail() { [ "$QUIET" = "0" ] && echo "notes-embed: $*" >&2; exit 1; }
log() { [ "$QUIET" = "0" ] && echo "$*" >&2; }

[ -d "$NOTES" ] || fail "notes 目录不存在: $NOTES"

# 服务就绪（幂等拉起）
api_ready() { curl -s --max-time 2 "http://localhost:${PORT}/v1/models" >/dev/null 2>&1; }
if ! api_ready; then
  "$HOME/.lmstudio/bin/lms" server start -p "$PORT" >/dev/null 2>&1 &
  for _ in $(seq 1 25); do
    api_ready && break
    sleep 2
  done
  api_ready || fail "LM Studio server 未就绪"
  sleep 2
fi

# 模型自动探测：bge 优先（中文），回退 nomic/embed
pick_model() {
  curl -s --max-time 5 "http://localhost:${PORT}/v1/models" 2>/dev/null | python3 -c '
import json, sys
try:
    models = [m["id"].lower() for m in json.load(sys.stdin)["data"]]
except Exception:
    sys.exit(0)
for pref in ("bge", "nomic", "embed"):
    for m in models:
        if pref in m:
            print(m)
            sys.exit(0)
'
}
MODEL=$(pick_model)
[ -n "$MODEL" ] || fail "未找到可用的 embedding 模型（服务里无 bge/nomic/embed）"
log "使用 embedding 模型: $MODEL"

python3 - "$NOTES" "$INDEX" "$PORT" "$MODEL" "$FORCE" "$QUIET" <<'PY'
import json, os, sys, urllib.request, hashlib, re

notes, index_path, port, model, force, quiet = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], int(sys.argv[5]), int(sys.argv[6])

def log(msg):
    if not quiet:
        print(msg, file=sys.stderr)

def embed(text):
    body = json.dumps({"model": model, "input": text}).encode()
    req = urllib.request.Request(f"http://localhost:{port}/v1/embeddings", body,
                                 {"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)["data"][0]["embedding"]

# 读旧索引（增量用）
old_entries = {}
old_model = None
if os.path.exists(index_path) and not force:
    try:
        old = json.load(open(index_path, encoding="utf-8"))
        old_model = old.get("model")
        for e in old.get("entries", []):
            old_entries[e["file"]] = e
    except Exception:
        pass

# 切块：按 markdown 标题/空行分块，每块 ≤ 1200 字符（embedding 模型上下文内安全）
def chunk_text(content):
    # 先按 ##/### 标题分大块，再按空行细分超长块
    parts = re.split(r'(?m)^(?=#{1,3} )', content)
    chunks = []
    for p in parts:
        p = p.strip()
        if not p:
            continue
        if len(p) <= 1200:
            chunks.append(p)
        else:
            # 超长块按空行再切
            for sub in re.split(r'\n\s*\n', p):
                sub = sub.strip()
                if sub:
                    chunks.append(sub[:1200])
    return chunks or [content[:1200]]

# 收集所有 .md 文件
files = sorted(f for f in os.listdir(notes) if f.endswith(".md"))
if not files:
    log("notes/ 下没有 .md 文件")
    sys.exit(1)

new_entries = []
changed = 0
skipped = 0
for rel in files:
    abs_path = os.path.join(notes, rel)
    try:
        content = open(abs_path, encoding="utf-8").read()
    except Exception as e:
        log(f"skip {rel}: {e}")
        continue
    if not content.strip():
        continue
    h = hashlib.md5(content.encode()).hexdigest()[:12]
    old = old_entries.get(rel)
    if old and old.get("hash") == h and old.get("chunks"):
        # 未变更：沿用旧向量
        new_entries.append(old)
        skipped += 1
        continue
    # 变更/新增：分块重算
    chunks = chunk_text(content)
    vectors = []
    ok = True
    for c in chunks:
        try:
            vectors.append(embed(c))
        except Exception as e:
            log(f"embed 失败 {rel}: {e}")
            ok = False
            break
    if not ok:
        continue
    new_entries.append({
        "file": rel,
        "hash": h,
        "chars": len(content),
        "chunks": chunks,
        "vectors": vectors,
    })
    changed += 1

# 原子写
tmp = index_path + ".tmp"
dim = len(new_entries[0]["vectors"][0]) if new_entries and new_entries[0]["vectors"] else 0
with open(tmp, "w", encoding="utf-8") as fh:
    json.dump({
        "model": model,
        "dim": dim,
        "chunked": True,
        "updated": __import__("datetime").datetime.now().isoformat(),
        "entries": new_entries,
    }, fh, ensure_ascii=False)
os.replace(tmp, index_path)
log(f"索引完成: {len(new_entries)} 个文件 {sum(len(e['vectors']) for e in new_entries)} 个块 "
    f"(变更 {changed}，沿用 {skipped}) → {index_path}")
PY
exit $?
