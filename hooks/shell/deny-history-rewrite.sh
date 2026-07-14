#!/bin/bash
# PreToolUse(Bash) hook: エージェント自身による履歴書き換えコマンドを deny する。
# 契約: コミット履歴の書き換えは禁止。唯一の例外は rebase-squash スキルの決定的スクリプト
#       （未 push 範囲・backup 作成・tree 同一性検証を条件とする squash）。
#       スクリプトの呼び出しは git コマンドではないため本 hook には掛からず、
#       sandbox(denyWrite .git) + permission prompt の承認フローに乗る。
# 役割分担: git commit --amend の deny は enforce-claude-commit.sh が担う。
#       git reset --hard は履歴書き換えではなく作業ツリー破壊なので対象外（ask 層が担う）。
# 本 hook はコマンド文字列検査のトリップワイヤであり、迂回への最終防壁は sandbox + ask 層。
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

# 検査はクォート内（コミットメッセージ等の本文）を除去してから行う。
# メッセージ内の文字列（例:「rebase の説明」）をコマンドと誤認しないため
MASKED=$(echo "$CMD" | sed 's/"[^"]*"//g' | sed "s/'[^']*'//g")

# 履歴の並べ替え・改変
echo "$MASKED" | grep -qE '(^|[;&|[:space:]])git[[:space:]]+rebase([[:space:]]|$)' && \
  deny "git rebase は履歴書き換えのため禁止です。コミットの整理は rebase-squash スキル（決定的スクリプト）経由でのみ行ってください。"
echo "$MASKED" | grep -qE '(^|[;&|[:space:]])git[[:space:]]+filter-(branch|repo)' && \
  deny "git filter-branch / filter-repo は履歴の一括改変のため禁止です。"

# 共有履歴の破壊
echo "$MASKED" | grep -qE '(^|[;&|[:space:]])git[[:space:]]+push[^;&|]*([[:space:]](-f|--force)([[:space:]]|$)|--force-with-lease|--force-if-includes)' && \
  deny "force push は共有履歴の破壊のため禁止です。必要ならユーザー自身が実行してください。"

# 復旧手段（reflog / 到達不能オブジェクト）の破壊。
# rebase-squash の安全網は backup ブランチと reflog なので、これらを消す操作は例外なく止める
echo "$MASKED" | grep -qE '(^|[;&|[:space:]])git[[:space:]]+reflog[[:space:]]+(expire|delete)' && \
  deny "git reflog expire/delete は履歴復旧の安全網を壊すため禁止です。"
echo "$MASKED" | grep -qE '(^|[;&|[:space:]])git[[:space:]]+gc[^;&|]*--prune=(now|all)' && \
  deny "git gc --prune=now/all は到達不能コミットの復旧を不可能にするため禁止です。"
echo "$MASKED" | grep -qE '(^|[;&|[:space:]])git[[:space:]]+prune([[:space:]]|$)' && \
  deny "git prune は到達不能コミットの復旧を不可能にするため禁止です。"

# rebase-squash の backup ブランチ削除（squash 結果の最終確認と backup の削除は人間の仕事）
if echo "$MASKED" | grep -q 'backup/rebase-squash-'; then
  echo "$MASKED" | grep -qE '(^|[;&|[:space:]])git[[:space:]]+(branch[^;&|]*[[:space:]](-D|-d|--delete)([[:space:]]|$)|update-ref[^;&|]*[[:space:]]-d[[:space:]])' && \
    deny "backup/rebase-squash-* ブランチの削除は禁止です。squash 結果の最終確認と backup の削除はユーザー自身が行ってください。"
fi

exit 0
