#!/bin/bash
# PreToolUse(Bash) hook: git add / git commit を「[claude]: 契約」に適合する形だけ通す。
# 契約: 1 ファイル = 1 コミット / メッセージは「[claude]: {対象ファイル名}/{変更内容(日本語)}」/
#       author は常にユーザー本人の git config identity（AI を author・co-author に混ぜない）。
# 本 hook は deny 専任。適合するコミットの自動化は settings の allow(Bash(git commit:*)) が担う。
# 出力汚染の根絶: 決定 hook は stdout の決定JSON 以外を外へ出さない契約。stderr を捨てる。
exec 2>/dev/null
INPUT=$(cat)
[ "$(echo "$INPUT" | jq -r '.tool_name')" = "Bash" ] || exit 0
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
[ -z "$CMD" ] && exit 0

deny() {
  jq -n --arg r "$1" \
    '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":$r}}'
  exit 0
}

# フラグ検査はクォート内(コミットメッセージ本文)を除去してから行う。
# メッセージ内の文字列(例:「-a オプションの説明」)をフラグと誤認しないため
MASKED=$(echo "$CMD" | sed 's/"[^"]*"//g' | sed "s/'[^']*'//g")

if echo "$MASKED" | grep -qE '(^|[;&|[:space:]])git[[:space:]]+commit'; then
  # AI をコミット identity に混ぜる要素は禁止（AI 作業の表明はメッセージ先頭の [claude]: だけ）
  echo "$CMD" | grep -qiE 'co-authored-by|generated with' && \
    deny "コミットへの AI 署名(Co-Authored-By / Generated with)は禁止です。author はユーザー本人のまま、メッセージ先頭の [claude]: だけで AI 作業を示してください。"
  echo "$MASKED" | grep -qE -- '--author' && \
    deny "--author の指定は禁止です。git config の identity(ユーザー本人)でコミットしてください。"
  echo "$MASKED" | grep -qE -- '--amend' && \
    deny "--amend は履歴書き換えのため禁止です。修正は新しいコミットとして積んでください。"
  # 1 ファイル = 1 コミット: 変更全部を巻き込む一括コミットは禁止
  echo "$MASKED" | grep -qE 'git[[:space:]]+commit[^;&|]*[[:space:]](-a[m]?|--all)([[:space:]]|$)' && \
    deny "-a / --all でのコミットは禁止です。1 ファイル = 1 コミットの契約に従い、対象ファイルだけを git add してからコミットしてください。"
  # メッセージ形式契約: 「[claude]: {対象ファイル名}/{変更内容}」（本文はクォート内のため RAW を検査）
  echo "$CMD" | grep -qE '\[claude\]: [^[:space:]/]+(/[^[:space:]/]+)*/.' || \
    deny "コミットメッセージは「[claude]: {対象ファイル名}/{変更内容(日本語)}」の形式で書いてください。例: [claude]: require-test.sh/tsx を対象外にした理由をコメントに明記した"
fi

# 一括ステージングも 1 ファイル = 1 コミットの契約違反
echo "$MASKED" | grep -qE '(^|[;&|[:space:]])git[[:space:]]+add[[:space:]]+(-A|--all|\.)([[:space:]]|$)' && \
  deny "git add -A / git add . は禁止です。1 ファイル = 1 コミットの契約に従い、対象ファイルを個別に指定してください。"

exit 0
