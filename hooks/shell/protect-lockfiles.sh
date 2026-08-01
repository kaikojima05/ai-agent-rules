#!/bin/bash
# PreToolUse(Bash|Edit|Write|NotebookEdit|apply_patch) hook: lockfile の直接変更を deny する。
# lockfile は package manager の解決結果としてのみ更新し、編集ツールや任意の shell 書き込みで
# package manifest と不整合な内容が作られることを防ぐ。読み取りコマンドは妨げない。
exec 2>/dev/null
. "$(dirname "$0")/hook-io.sh"
TOOL=$(hook_tool_name)

LOCKFILE_MSG="lockfile の直接変更は禁止です。依存関係を変更する場合は、ユーザー承認の下で対応する package manager を実行して再生成してください。"
LOCKFILE_PATH_RE='(^|/)(yarn\.lock|package-lock\.json|pnpm-lock\.yaml)$'
LOCKFILE_COMMAND_RE="(^|[[:space:]\"'=/])(yarn\\.lock|package-lock\\.json|pnpm-lock\\.yaml)([[:space:]\"']|$)"

case "$TOOL" in
  Edit|Write|NotebookEdit|apply_patch)
    while IFS= read -r FILE; do
      [ -z "$FILE" ] && continue
      echo "$FILE" | grep -qE "$LOCKFILE_PATH_RE" && hook_deny "$LOCKFILE_MSG"
    done < <(hook_file_paths)
    exit 0
    ;;
  Bash) ;;
  *) exit 0 ;;
esac

CMD=$(hook_command)
[ -z "$CMD" ] && exit 0
echo "$CMD" | grep -qE "$LOCKFILE_COMMAND_RE" || exit 0

# 削除・移動・直接上書き。
echo "$CMD" | grep -qE '(^|[;&|[:space:]])(rm|rmdir|unlink|shred|srm|mv|dd|truncate|tee|ln)([[:space:]]|$)' && hook_deny "$LOCKFILE_MSG"
# リダイレクトによる生成・追記。
echo "$CMD" | grep -qE '>>?[[:space:]]*[^[:space:]]*(yarn\.lock|package-lock\.json|pnpm-lock\.yaml)([[:space:]]|$)' && hook_deny "$LOCKFILE_MSG"
# コピー・同期・install コマンドの出力先。
echo "$CMD" | grep -qE '(^|[;&|[:space:]])(cp|rsync|install)[[:space:]][^;&|]*[[:space:]][^[:space:]]*(yarn\.lock|package-lock\.json|pnpm-lock\.yaml)[[:space:]]*($|[;&|])' && hook_deny "$LOCKFILE_MSG"
# ダウンロードの明示的な出力先。
echo "$CMD" | grep -qE '(^|[[:space:]])-{1,2}(o|output(-document)?)([[:space:]]+|=)[^[:space:]]*(yarn\.lock|package-lock\.json|pnpm-lock\.yaml)' && hook_deny "$LOCKFILE_MSG"
# sed の in-place 編集。
echo "$CMD" | grep -qE '(^|[;&|[:space:]])sed[[:space:]][^;&|]*-i' && hook_deny "$LOCKFILE_MSG"

exit 0
