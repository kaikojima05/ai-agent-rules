#!/bin/bash
# PreToolUse(Bash|Edit|Write|NotebookEdit) hook: .git ディレクトリの破壊・改変を deny する。
# 背景: sandbox の denyWrite を .git 全体から .git/hooks と .git/config に絞った
#       （.git 全面 deny では git commit が .git/index 等へ書けず sandbox 内で失敗するため）。
#       その代償として objects/refs は OS レベルでは書き込み可能になったので、
#       .git を狙う破壊系操作はこの hook がコマンド文字列とファイルパスの層で止める。
# 役割分担: git コマンド自身のメタデータ書き込み（commit 等）は素通し。
#       履歴書き換え系 git コマンドの deny は deny-history-rewrite.sh が担う。
# 限界: 本 hook はコマンド文字列検査のトリップワイヤ。スクリプトファイル経由・グロブ・
#       シンボリックリンク等の迂回は検出できない。誤削除への残りの防壁は
#       ask 層（rm/mv/dd 等）と push 済み履歴（origin が真のバックアップ）。
exec 2>/dev/null
. "$(dirname "$0")/hook-io.sh"
TOOL=$(hook_tool_name)

# ファイル編集ツールによる .git 配下への書き込みは全面禁止。
# permission の Edit deny ルールは sandbox 設定へマージされ git commit まで殺すため
# hooks/config までしか deny できない。ツール層の hook はマージされないのでここで全面遮断する
case "$TOOL" in
  Edit|Write|NotebookEdit|apply_patch)
    while IFS= read -r FILE; do
      [ -z "$FILE" ] && continue
      echo "$FILE" | grep -qiE '(^|/)\.git(/|$)' && \
        hook_deny ".git 配下へのファイル編集ツールによる書き込みは禁止です。.git の中身は git コマンドだけが管理します。"
    done < <(hook_file_paths)
    exit 0
    ;;
  Bash) ;;
  *) exit 0 ;;
esac

CMD=$(hook_command)
[ -z "$CMD" ] && exit 0

# .git への言及検出は RAW のまま行う（".git" とクォートで包むだけの迂回を許さないため、
# 兄弟 hook のようなクォート除去はしない）。大文字小文字を無視するのは、
# 大文字小文字非区別 FS（macOS 既定）では .GIT 指定でも実体の .git が消えるため
GIT_RE="(^|[[:space:]\"'=/])\.git(/|[[:space:]\"']|\$)"
echo "$CMD" | grep -qiE "$GIT_RE" || exit 0

MSG=".git を対象にした破壊系コマンドは禁止です。objects/refs/index が失われるとリポジトリは復旧できません。必要ならユーザー自身が実行してください。"

# 削除・移動・上書きの実行体（xargs / find -exec 経由も空白境界で捕捉される）
echo "$CMD" | grep -qiE '(^|[;&|[:space:]])(rm|rmdir|unlink|shred|srm|mv|dd|truncate|tee|ln)([[:space:]]|$)' && hook_deny "$MSG"
# 実行体を伴わない削除フラグ（find -delete / rsync --delete 系）
echo "$CMD" | grep -qiE '(^|[[:space:]])--?delete(-[a-z-]+)?([[:space:]]|$)' && hook_deny "$MSG"
# リダイレクトによる .git 配下ファイルの生成・切り詰め（例: > .git/HEAD）
echo "$CMD" | grep -qiE '>>?[[:space:]]*[^[:space:]]*\.git/' && hook_deny "$MSG"
# コピー系の書き込み先が .git 配下（コピー元が .git の読み出しは許可）
echo "$CMD" | grep -qiE '(^|[;&|[:space:]])(cp|rsync|install)[[:space:]][^;&|]*[[:space:]][^[:space:]]*\.git(/[^[:space:]]*)?[[:space:]]*($|[;&|])' && hook_deny "$MSG"
# ダウンロード出力先が .git 配下（curl -o / wget -O / --output）
echo "$CMD" | grep -qiE '(^|[[:space:]])-{1,2}(o|output(-document)?)([[:space:]]+|=)[^[:space:]]*\.git/' && hook_deny "$MSG"

exit 0
