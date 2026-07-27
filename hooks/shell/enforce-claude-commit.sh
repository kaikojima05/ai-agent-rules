#!/bin/bash
# PreToolUse(Bash) hook: git add / git commit をコミット契約に適合する形だけ通す。
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

# フラグ検査はクォート内(コミットメッセージ本文)を除去してから行う。
# メッセージ内の文字列(例:「-a オプションの説明」)をフラグと誤認しないため
MASKED=$(echo "$CMD" | sed 's/"[^"]*"//g' | sed "s/'[^']*'//g")

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
  # メッセージ形式契約: 「[<エージェント名>]: {対象ファイル名}/{変更内容}」（本文はクォート内のため RAW を検査）
  echo "$CMD" | grep -qE "\[$HOOK_AGENT\]: [^[:space:]/]+(/[^[:space:]/]+)*/." || \
    hook_deny "コミットメッセージは「[$HOOK_AGENT]: {対象ファイル名}/{変更内容(日本語)}」の形式で書いてください。例: [$HOOK_AGENT]: require-test.sh/tsx を対象外にした理由をコメントに明記した"
fi

# 一括ステージングも 1 ファイル = 1 コミットの契約違反
echo "$MASKED" | grep -qE '(^|[;&|[:space:]])git[[:space:]]+add[[:space:]]+(-A|--all|\.)([[:space:]]|$)' && \
  hook_deny "git add -A / git add . は禁止です。1 ファイル = 1 コミットの契約に従い、対象ファイルを個別に指定してください。"

exit 0
