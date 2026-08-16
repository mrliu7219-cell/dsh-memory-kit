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
# 主动模式（2026-08-17）：检测到有变更 → 自动静默增量刷新索引（notes-embed.sh -q，
# 增量只重算变更文件）；自动刷新失败（如未装 LM Studio）才降级为提醒。
if [ -f "$IDX" ]; then
  NEWEST=$(find "$NOTES" -name "*.md" -type f -newer "$IDX" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$NEWEST" -gt 0 ]; then
    EMBED="$(dirname "$0")/notes-embed.sh"
    if [ -f "$EMBED" ]; then
      if bash "$EMBED" -q 2>/dev/null; then
        echo "✓ 已自动刷新语义索引（$NEWEST 个文件变更）。" >&2
      else
        echo "ℹ️ 语义索引过期（$NEWEST 个文件变更），自动刷新失败（需 LM Studio），可手动跑 notes-embed.sh。" >&2
      fi
    else
      echo "ℹ️ 有 $NEWEST 个 notes 文件在向量索引之后变更，可跑 notes-embed.sh 刷新索引。" >&2
    fi
  fi
else
  # 索引不存在：尝试自动生成（仅当 embed 脚本存在）
  EMBED="$(dirname "$0")/notes-embed.sh"
  if [ -f "$EMBED" ]; then
    if bash "$EMBED" -q 2>/dev/null; then
      echo "✓ 已自动生成语义索引。" >&2
    else
      echo "ℹ️ 向量索引不存在，自动生成失败（需 LM Studio），可跑 notes-embed.sh 生成。" >&2
    fi
  else
    echo "ℹ️ 向量索引不存在，可跑 notes-embed.sh 生成（供语义搜索）。" >&2
  fi
fi

exit 0
