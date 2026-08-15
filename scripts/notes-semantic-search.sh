#!/bin/bash
# notes-semantic-search.sh — 语义搜索 notes/（余弦相似度，找"意思相近"而非字面匹配）。
# 与 notes-search.sh（关键词精确）互补：关键词搜得到就用关键词，搜不到/记不清措辞用语义。
# 用法：
#   notes-semantic-search.sh "我想找上次关于省内存的讨论" [-n 3]   # 默认 top-3
set -u

MEM_DIR="${MEMORY_DIR:-$HOME/.dsh/memory}"
NOTES="$MEM_DIR/notes"
INDEX="$MEM_DIR/.vector-index.json"
PORT="${VISION_PORT:-1235}"
MODEL=""
TOP_N=3

# 解析 -n
while [ $# -gt 0 ]; do
  case "$1" in
    -n) TOP_N="${2:-3}"; shift 2 ;;
    *) break ;;
  esac
done
QUERY="${*:-}"
[ -n "$QUERY" ] || { echo "用法: notes-semantic-search.sh <查询> [-n 数量]" >&2; exit 1; }

# 索引存在？
if [ ! -f "$INDEX" ]; then
  echo "向量索引不存在，先生成: notes-embed.sh" >&2
  SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
  bash "$SCRIPT_DIR/notes-embed.sh" -q 2>/dev/null || {
    echo "向量索引生成失败。若需要语义搜索，请先安装 LM Studio 并跑: dsh-memory-kit setup --semantic" >&2
    exit 1
  }
fi

# 服务就绪：LM Studio 未启动则拉起；未安装则优雅降级提示
LMS_BIN="$HOME/.lmstudio/bin/lms"
if [ ! -x "$LMS_BIN" ]; then
  echo "未检测到 LM Studio。语义搜索需要本机 embedding 服务（可选）：" >&2
  echo "  1. 安装 LM Studio（lmstudio.ai）并下载 bge-small-zh-v1.5" >&2
  echo "  2. 跑: dsh-memory-kit setup --semantic" >&2
  echo "当前可用关键词搜索: notes-search.sh <关键词>" >&2
  exit 1
fi
api_ready() { curl -s --max-time 2 "http://localhost:${PORT}/v1/models" >/dev/null 2>&1; }
if ! api_ready; then
  "$LMS_BIN" server start -p "$PORT" >/dev/null 2>&1 &
  for _ in $(seq 1 25); do
    api_ready && break
    sleep 2
  done
  api_ready || { echo "LM Studio 服务拉起失败" >&2; exit 1; }
  sleep 2
fi

# 模型从索引读取（与生成时一致），避免探测不一致
MODEL=$(python3 -c "import json; print(json.load(open('$INDEX'))['model'])" 2>/dev/null)

python3 - "$INDEX" "$PORT" "$MODEL" "$QUERY" "$TOP_N" "$NOTES" <<'PY'
import json, sys, urllib.request, math, os

index_path, port, model, query, top_n, notes_dir = sys.argv[1:7]
top_n = int(top_n)

def embed(text):
    body = json.dumps({"model": model, "input": text}).encode()
    req = urllib.request.Request(f"http://localhost:{port}/v1/embeddings", body,
                                 {"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)["data"][0]["embedding"]

def cosine(a, b):
    dot = sum(x*y for x, y in zip(a, b))
    na = math.sqrt(sum(x*x for x in a)); nb = math.sqrt(sum(x*x for x in b))
    return dot / (na * nb) if na and nb else 0.0

idx = json.load(open(index_path, encoding="utf-8"))
if not idx.get("entries"):
    print("索引为空"); sys.exit(0)

chunked = idx.get("chunked", False)
qv = embed(query)

if chunked:
    # 分块索引：每块算相似度，文件分数 = 最高分块分数，并记录命中块
    best = {}  # file -> (max_score, chunk_text)
    for e in idx["entries"]:
        chunks = e.get("chunks", [])
        vectors = e.get("vectors", [])
        bscore, bchunk = -1.0, ""
        for c, v in zip(chunks, vectors):
            s = cosine(qv, v)
            if s > bscore:
                bscore, bchunk = s, c
        if bscore >= 0:
            best[e["file"]] = (bscore, bchunk)
    results = [(s, f, c) for f, (s, c) in best.items()]
else:
    # 旧格式（整文件单向量）
    results = [(cosine(qv, e["vector"]), e["file"], "") for e in idx["entries"]]

results.sort(key=lambda x: -x[0])
print(f"「{query}」语义相关 top-{top_n}：\n")
for score, rel, chunk in results[:top_n]:
    fpath = os.path.join(notes_dir, rel)
    # 摘要优先用命中块，否则文件第一行
    first = ""
    if chunk:
        first = chunk.strip().replace("\n", " ")[:60]
    else:
        try:
            for line in open(fpath, encoding="utf-8"):
                line = line.strip()
                if line and not line.startswith("#"):
                    first = line[:60]; break
        except Exception:
            pass
    print(f"  {score:.3f}  {rel}" + (f"  — {first}" if first else ""))
PY
