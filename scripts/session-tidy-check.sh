#!/bin/bash
# session-tidy-check.sh — Stop hook：会话收尾时的轻量"整理提醒"。
# 注意：command hook 拿不到模型上下文，本脚本做的是**状态检查 + 提醒**，
# 真正的"提炼坑/决策"由模型在回合内按 AGENTS.md 纪律主动完成。
# 检查项：
#   1. 索引行数是否接近上限（提醒整理）
#   2. 向量索引是否过期（notes 变了但没重新 embed）
#   3. 踩坑库最近是否有新增（纯信息，不强制）
# 输出走 stderr（hook 协议里 stderr 对用户可见，不污染上下文）
set -u

MEM_DIR="${MEMORY_DIR:-$HOME/.dsh/memory}"
MEM="$MEM_DIR/MEMORY.md"
NOTES="$MEM_DIR/notes"
IDX="$MEM_DIR/.vector-index.json"

# 1. 索引行数
if [ -f "$MEM" ]; then
  LINES=$(wc -l < "$MEM" | tr -d ' ')
  if [ "$LINES" -gt 180 ]; then
    echo "⚠️ 记忆索引已 $LINES 行（上限 200），建议新开会话前整理合并。" >&2
  fi
fi

# 2. 向量索引过期检查（notes 最新 mtime vs 索引生成时间；find -newer 跨平台通用）
if [ -f "$IDX" ]; then
  NEWEST=$(find "$NOTES" -name "*.md" -type f -newer "$IDX" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$NEWEST" -gt 0 ]; then
    echo "ℹ️ 有 $NEWEST 个 notes 文件在向量索引之后变更，可跑 notes-embed.sh 刷新索引。" >&2
  fi
else
  echo "ℹ️ 向量索引不存在，可跑 notes-embed.sh 生成（供语义搜索）。" >&2
fi

exit 0
