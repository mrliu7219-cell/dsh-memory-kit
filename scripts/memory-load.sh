#!/bin/bash
# memory-load.sh — SessionStart hook：把记忆索引注入上下文（插件版）。
# 索引位置：$MEMORY_DIR/MEMORY.md（默认 ~/.dsh/memory，可用环境变量 MEMORY_DIR 覆盖）。
# 索引不存在则静默跳过（首次使用先跑 dsh-memory-kit setup 初始化）。
# 协议：stdout 输出 hook JSON（additionalContext 注入）。
set -u

MEM_DIR="${MEMORY_DIR:-$HOME/.dsh/memory}"
MEM="$MEM_DIR/MEMORY.md"
[ -f "$MEM" ] || exit 0

CONTENT=$(cat "$MEM" 2>/dev/null) || exit 0
export MEMORY_CONTENT="$CONTENT"
python3 - <<'PY'
import json, os
content = os.environ.get("MEMORY_CONTENT", "").strip()
if not content:
    raise SystemExit(0)
line_count = content.count("\n") + 1
warn = ""
if line_count > 180:
    warn = f"\n⚠️ 记忆索引已 {line_count} 行（上限 200），建议整理合并。"
header = (
    "【记忆索引】以下为本机持久记忆索引（MEMORY.md），每次会话开始时自动加载。"
    "需要细节时用 read 读取 notes/ 对应文件；重要新事实、用户偏好、关键决策应写入记忆"
    "（索引 + notes/ 文件），不要把记忆写进 AGENTS.md（那里只放规则）。"
    "找旧知识：关键词精确搜用 notes-search.sh <词>；记不清措辞用 notes-semantic-search.sh <描述>"
    "（语义搜索需先 dsh-memory-kit setup --semantic）。"
    "会话收尾时按纪律把新坑/决策写入 notes/（traps.md 三档状态）。\n\n"
)
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": header + content + warn,
    }
}, ensure_ascii=False))
PY
