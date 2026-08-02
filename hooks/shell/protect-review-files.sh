#!/bin/bash
# PreToolUse(Bash|Edit|Write|NotebookEdit|apply_patch) hook: 配置場所に依存せず、
# レビュー対象ファイルは読み取りを許可したまま直接変更だけを deny する。
exec 2>/dev/null
. "$(dirname "$0")/hook-io.sh"
TOOL=$(hook_tool_name)

REVIEW_FILE_MSG="package manifest・CI・migration・schema・container・Terraform 設定の直接変更は禁止です。変更が必要な場合はユーザーへ依頼してください。"
REVIEW_FILE_PATH_RE='(^|/)(package\.json|schema\.prisma|Dockerfile[^/]*|docker-compose[^/]*|[^/]+\.tf)$|(^|/)(\.github/workflows|migrations)(/|$)'
REVIEW_FILE_COMMAND_RE="package\\.json|schema\\.prisma|Dockerfile|docker-compose|\\.tf([[:space:]\\\"']|$)|\\.github/workflows|migrations/"

case "$TOOL" in
  Edit|Write|NotebookEdit|apply_patch)
    while IFS= read -r FILE; do
      [ -z "$FILE" ] && continue
      echo "$FILE" | grep -qE "$REVIEW_FILE_PATH_RE" && hook_deny "$REVIEW_FILE_MSG"
    done < <(hook_file_paths)
    exit 0
    ;;
  Bash) ;;
  *) exit 0 ;;
esac

CMD=$(hook_command)
[ -z "$CMD" ] && exit 0
echo "$CMD" | grep -qE "$REVIEW_FILE_COMMAND_RE" || {
  # ファイル名を省略して対象を書き換える代表的なコマンドも止める。
  echo "$CMD" | grep -qE '(^|[;&|[:space:]])(npm|pnpm)[[:space:]]+(install|uninstall|add|remove)([[:space:]]|$)|(^|[;&|[:space:]])yarn[[:space:]]+(add|remove|upgrade)([[:space:]]|$)|(^|[;&|[:space:]])(terraform|tofu)[[:space:]]+fmt([[:space:]]|$)' && \
    hook_deny "$REVIEW_FILE_MSG"
  exit 0
}

# 読み取りコマンドは許可し、対象パスを書き換える形だけを止める。
echo "$CMD" | grep -qE '(^|[;&|[:space:]])(rm|rmdir|unlink|shred|srm|mv|dd|truncate|tee|ln|touch|chmod|chown|chgrp)([[:space:]]|$)' && hook_deny "$REVIEW_FILE_MSG"
echo "$CMD" | grep -qE '(^|[[:space:]])--?delete(-[a-z-]+)?([[:space:]]|$)' && hook_deny "$REVIEW_FILE_MSG"
echo "$CMD" | grep -qE '>>?' && hook_deny "$REVIEW_FILE_MSG"
echo "$CMD" | grep -qE '(^|[;&|[:space:]])(cp|rsync|install)([[:space:]]|$)' && hook_deny "$REVIEW_FILE_MSG"
echo "$CMD" | grep -qE '(^|[[:space:]])-{1,2}(o|output(-document)?)([[:space:]]+|=)' && hook_deny "$REVIEW_FILE_MSG"
echo "$CMD" | grep -qE '(^|[;&|[:space:]])sed[[:space:]][^;&|]*-i' && hook_deny "$REVIEW_FILE_MSG"
echo "$CMD" | grep -qE '(^|[;&|[:space:]])git[[:space:]]+(clean|checkout|restore)([[:space:]]|$)' && hook_deny "$REVIEW_FILE_MSG"

exit 0
