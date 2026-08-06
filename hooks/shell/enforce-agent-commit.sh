#!/bin/bash
# PreToolUse(Bash) hook: Git のコミット操作をリポジトリ共通の契約に適合する形だけ通す。
# 契約: 1 ファイル = 1 コミット / メッセージは「[<エージェント名>]: {対象ファイル名}/{変更内容(日本語)}」/
#       タグのエージェント名は hook-io.sh の HOOK_AGENT（init-agent が確定させた値）を使う。
#       author は常にユーザー本人の git config identity（AI を author・co-author に混ぜない）。
# 本 hook は deny 専任。適合するコミットの自動化は settings の allow(Bash(git commit:*)) が担う。
# 例外(squash): 未 push 範囲のコミット整理は rebase-squash スキルの決定的スクリプトのみが行い、
#       squash 後のメッセージは「[<エージェント名>]: {機能}/{変更内容(日本語)}」とする(形式 regex は共通)。
#       スクリプト内部の git commit は Bash コマンド文字列に現れず本 hook の視界外のため、
#       同スクリプトが契約検証(形式・--author 不在・AI 署名不在)を内蔵する。
#       生の履歴書き換えコマンドの deny は deny-history-rewrite.sh が担う。
# 出力汚染の根絶: 決定 hook は stdout の決定JSON 以外を外へ出さない契約。stderr を捨てる。
exec 2>/dev/null
. "$(dirname "$0")/hook-io.sh"
[ "$(hook_tool_name)" = "Bash" ] || exit 0
CMD=$(hook_command)
[ -z "$CMD" ] && exit 0

EXPECTED_STAGED_FILE_COUNT=1
JAPANESE_TEXT_RE='[ぁ-んァ-ヶ一-龠々ー]'

# フラグ検査はクォート内(コミットメッセージ本文)を除去してから行う。
# メッセージ内の文字列(例:「-a オプションの説明」)をフラグと誤認しないため
MASKED=$(echo "$CMD" | sed 's/"[^"]*"//g' | sed "s/'[^']*'//g")

# rules / settings の禁止設定が欠けても共有履歴を変更できないよう、通常形も hook で拒否する。
echo "$MASKED" | grep -qE '(^|[;&|[:space:]])git[[:space:]]+push([[:space:]]|$)' && \
  hook_deny "git push は禁止です。変更内容を確認したユーザー本人が実行してください。"
echo "$MASKED" | grep -qE '(^|[;&|[:space:]])git[[:space:]]+cherry-pick([[:space:]]|$)' && \
  hook_deny "git cherry-pick は禁止です。履歴の取り込みはユーザー本人が実行してください。"

if echo "$MASKED" | grep -qE '(^|[;&|[:space:]])git[[:space:]]+commit'; then
  # AI をコミット identity に混ぜる要素は禁止（AI 作業の表明はメッセージ先頭のタグだけ）
  echo "$CMD" | grep -qiE 'co-authored-by|generated with' && \
    hook_deny "コミットへの AI 署名(Co-Authored-By / Generated with)は禁止です。author はユーザー本人のまま、メッセージ先頭の [$HOOK_AGENT]: だけで AI 作業を示してください。"
  echo "$MASKED" | grep -qE -- '--author' && \
    hook_deny "--author の指定は禁止です。git config の identity(ユーザー本人)でコミットしてください。"
  echo "$MASKED" | grep -qE -- '--amend' && \
    hook_deny "--amend は履歴書き換えのため禁止です。修正は新しいコミットとして積んでください。"
  # 1 ファイル = 1 コミット: 変更全部を巻き込む一括コミットは禁止
  echo "$MASKED" | grep -qE 'git[[:space:]]+commit[^;&|]*[[:space:]](-a[m]?|--all)([[:space:]]|$)' && \
    hook_deny "-a / --all でのコミットは禁止です。1 ファイル = 1 コミットの契約に従い、対象ファイルだけを git add してからコミットしてください。"
  # commit 直前の index を正として検査し、別コマンドで複数 stage 済みの状態も拒否する。
  STAGED_FILES=$(git diff --cached --name-only)
  STAGED_FILE_COUNT=$(printf '%s\n' "$STAGED_FILES" | awk 'NF { count++ } END { print count + 0 }')
  [ "$STAGED_FILE_COUNT" -eq "$EXPECTED_STAGED_FILE_COUNT" ] || \
    hook_deny "コミット直前に stage 済みのファイルが $STAGED_FILE_COUNT 件あります。1 ファイル = 1 コミットの契約に従い、厳密に1件だけ stage してください。"

  STAGED_FILE=$(printf '%s\n' "$STAGED_FILES" | awk 'NF { print; exit }')
  STAGED_BASENAME=${STAGED_FILE##*/}
  COMMIT_MESSAGE=$(printf '%s\n' "$CMD" | sed -nE 's/.*(-m|--message)[[:space:]]+"([^"]*)".*/\2/p')
  [ -n "$COMMIT_MESSAGE" ] || \
    COMMIT_MESSAGE=$(printf '%s\n' "$CMD" | sed -nE "s/.*(-m|--message)[[:space:]]+'([^']*)'.*/\\2/p")
  [ -n "$COMMIT_MESSAGE" ] || \
    hook_deny "コミットメッセージを検証できません。-m または --message とクォートしたメッセージを指定してください。"

  MESSAGE_PREFIX="[$HOOK_AGENT]: $STAGED_BASENAME/"
  case "$COMMIT_MESSAGE" in
    "$MESSAGE_PREFIX"*) CHANGE_DESCRIPTION=${COMMIT_MESSAGE#"$MESSAGE_PREFIX"} ;;
    *) hook_deny "コミットメッセージの対象ファイル名を stage 済みの $STAGED_BASENAME と一致させてください。形式: [$HOOK_AGENT]: $STAGED_BASENAME/{変更内容(日本語)}" ;;
  esac
  [ -n "$CHANGE_DESCRIPTION" ] && printf '%s\n' "$CHANGE_DESCRIPTION" | grep -qE "$JAPANESE_TEXT_RE" || \
    hook_deny "コミットメッセージの変更内容には日本語を含めてください。形式: [$HOOK_AGENT]: $STAGED_BASENAME/{変更内容(日本語)}"
fi

# 一括ステージングも 1 ファイル = 1 コミットの契約違反
echo "$MASKED" | grep -qE '(^|[;&|[:space:]])git[[:space:]]+add[[:space:]]+(-A|--all|\.)([[:space:]]|$)' && \
  hook_deny "git add -A / git add . は禁止です。1 ファイル = 1 コミットの契約に従い、対象ファイルを個別に指定してください。"

# ignore 規則の迂回は、追跡対象に限るコミット契約を破る。強制ステージングは許可しない。
echo "$MASKED" | grep -qE '(^|[;&|[:space:]])git[[:space:]]+add([[:space:]]+[^;&|[:space:]]+)*[[:space:]]+(-f|--force)([[:space:];&|]|$)' && \
  hook_deny "git add -f / git add --force は禁止です。ignore されたファイルは stage せず、必要なら作業ツリー上で検証して次の工程へ進んでください。"

exit 0
