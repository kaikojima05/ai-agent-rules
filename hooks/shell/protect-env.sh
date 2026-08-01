#!/bin/bash
# PreToolUse(Bash|Edit|Write|NotebookEdit|apply_patch) hook: .env / .env.* への書き込み・削除を deny する。
# 背景: claude の sandbox denyWrite と codex の distributed permission profile は .env 系を
#       read-only にする。本 hook は編集ツールと直接 Bash の両経路を拒否する共通の第二層になる。
# 対象パターンは両エージェントで同じ契約になるようテンプレート側へ固定する。
# 読み取り（cat / grep 等）は対象外。書き込み verb・リダイレクト・コピー先・sed -i のみ止める。
# 限界: コマンド文字列検査のトリップワイヤ。迂回への最終防壁は sandbox / permission profile。
exec 2>/dev/null
. "$(dirname "$0")/hook-io.sh"
TOOL=$(hook_tool_name)

ENV_MSG=".env 系ファイルへの書き込み・削除は禁止です。機密設定の変更が必要ならユーザー自身が行ってください。"

case "$TOOL" in
  Edit|Write|NotebookEdit|apply_patch)
    while IFS= read -r FILE; do
      [ -z "$FILE" ] && continue
      echo "$FILE" | grep -qiE '(^|/)\.env(\.[^/]+)?$' && hook_deny "$ENV_MSG"
    done < <(hook_file_paths)
    exit 0
    ;;
  Bash) ;;
  *) exit 0 ;;
esac

CMD=$(hook_command)
[ -z "$CMD" ] && exit 0

# .env への言及検出は RAW のまま行う（クォートで包むだけの迂回を許さない）。
# 大文字小文字非区別 FS（macOS 既定）対策で -i
ENV_RE="(^|[[:space:]\"'=/])\.env(\.[^[:space:]\"']+)?([[:space:]\"']|\$)"
echo "$CMD" | grep -qiE "$ENV_RE" || exit 0

# 削除・移動・上書きの実行体
echo "$CMD" | grep -qiE '(^|[;&|[:space:]])(rm|rmdir|unlink|shred|srm|mv|dd|truncate|tee|ln)([[:space:]]|$)' && hook_deny "$ENV_MSG"
# リダイレクトによる生成・切り詰め（> .env / >> .env.local）
echo "$CMD" | grep -qiE '>>?[[:space:]]*[^[:space:]]*\.env(\.[^[:space:]]+)?([[:space:]]|$)' && hook_deny "$ENV_MSG"
# コピー系の書き込み先が .env 系
echo "$CMD" | grep -qiE '(^|[;&|[:space:]])(cp|rsync|install)[[:space:]][^;&|]*[[:space:]][^[:space:]]*\.env(\.[^[:space:]]*)?[[:space:]]*($|[;&|])' && hook_deny "$ENV_MSG"
# ダウンロード出力先（curl -o / wget -O / --output）
echo "$CMD" | grep -qiE '(^|[[:space:]])-{1,2}(o|output(-document)?)([[:space:]]+|=)[^[:space:]]*\.env' && hook_deny "$ENV_MSG"
# sed -i による in-place 編集
echo "$CMD" | grep -qiE '(^|[;&|[:space:]])sed[[:space:]][^;&|]*-i' && hook_deny "$ENV_MSG"

exit 0
