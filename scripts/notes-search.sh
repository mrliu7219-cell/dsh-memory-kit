#!/bin/bash
# notes-search.sh — 在记忆 notes/ 目录做全文搜索（先搜后读）。
# 用途：agent 或用户找旧知识时，先关键词搜出"哪个文件哪一行"，再 read 具体文件。
# 用法：
#   notes-search.sh <关键词>            # 简单搜索，返回 文件:行号:内容
#   notes-search.sh -l <关键词>          # 只列文件名（-l）
#   notes-search.sh -i <关键词>          # 忽略大小写
#   notes-search.sh <关键词1> <关键词2>  # 多词 AND（同时出现才命中）
set -u

MEM_DIR="${MEMORY_DIR:-$HOME/.dsh/memory}"
NOTES="$MEM_DIR/notes"
[ -d "$NOTES" ] || { echo "notes 目录不存在: $NOTES（先跑 dsh-memory-kit setup）" >&2; exit 1; }

if [ $# -lt 1 ]; then
  echo "用法: notes-search.sh [-l] [-i] <关键词> [更多关键词...]" >&2
  exit 1
fi

# 解析选项（-i 用变量而非数组——bash 3.2 空数组 ${arr[@]:-} 会展开成空参数被当路径）
LIST_ONLY=0
IGNORE_CASE=""
while [ $# -gt 0 ]; do
  case "$1" in
    -l) LIST_ONLY=1; shift ;;
    -i) IGNORE_CASE="-i"; shift ;;
    *) break ;;
  esac
done

[ $# -ge 1 ] || { echo "缺少关键词" >&2; exit 1; }

# 第一关键词：IGNORE_CASE 为空时直接不展开（避免空参数被当路径）
if [ -n "$IGNORE_CASE" ]; then
  RESULTS=$(rg -i -n -e "$1" "$NOTES" 2>/dev/null) || { echo "无匹配"; exit 0; }
else
  RESULTS=$(rg -n -e "$1" "$NOTES" 2>/dev/null) || { echo "无匹配"; exit 0; }
fi

shift
# bash 3.2：`for kw in "$@"` 在 $@ 为空时仍循环一次且 kw=""，会把结果清空；先判断再循环
if [ $# -gt 0 ]; then
  for kw in "$@"; do
    if [ -n "$IGNORE_CASE" ]; then
      RESULTS=$(echo "$RESULTS" | rg -i "$kw")
    else
      RESULTS=$(echo "$RESULTS" | rg "$kw")
    fi
  done
fi

if [ -z "$RESULTS" ]; then
  echo "无匹配"
  exit 0
fi

if [ "$LIST_ONLY" = "1" ]; then
  echo "$RESULTS" | cut -d: -f1 | sort -u
else
  # 相对路径显示，更可读
  echo "$RESULTS" | sed "s|$NOTES/||"
fi
