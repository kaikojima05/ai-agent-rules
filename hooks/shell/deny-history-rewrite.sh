#!/bin/bash
# PreToolUse(Bash) hook: エージェント自身による履歴書き換えコマンドを deny する。
# 契約: コミット履歴の書き換えは禁止。唯一の例外は rebase-squash スキルの決定的スクリプト
#       （未 push 範囲・backup 作成・tree 同一性検証を条件とする squash）。
#       スクリプトの呼び出しは git コマンドではないため本 hook には掛からず、
#       settings.local.json の ask ルール（人間の承認）に乗る。
#       ※ かつては sandbox(denyWrite .git) が暗黙のゲートだったが、denyWrite を
#         .git/hooks と .git/config に絞ったため、ask ルールが明示的なゲートを引き継いだ。
# 役割分担: git commit --amend の deny は enforce-claude-commit.sh が担う。
#       git reset --hard は履歴書き換えではなく作業ツリー破壊なので対象外（ask 層が担う）。
#       .git ディレクトリ自体を狙う破壊系コマンドの deny は protect-git-dir.sh が担う。
# 本 hook はコマンド文字列検査のトリップワイヤであり、迂回への最終防壁は
# ask 層と push 済み履歴（sandbox が守るのは .git/hooks と .git/config のみ）。
exec 2>/dev/null
. "$(dirname "$0")/hook-io.sh"
[ "$(hook_tool_name)" = "Bash" ] || exit 0
CMD=$(hook_command)
[ -z "$CMD" ] && exit 0

# 検査はクォート内（コミットメッセージ等の本文）を除去してから行う。
# メッセージ内の文字列（例:「rebase の説明」）をコマンドと誤認しないため
MASKED=$(echo "$CMD" | sed 's/"[^"]*"//g' | sed "s/'[^']*'//g")

# 履歴の並べ替え・改変
echo "$MASKED" | grep -qE '(^|[;&|[:space:]])git[[:space:]]+rebase([[:space:]]|$)' && \
  hook_deny "git rebase は履歴書き換えのため禁止です。コミットの整理は rebase-squash スキル（決定的スクリプト）経由でのみ行ってください。"
echo "$MASKED" | grep -qE '(^|[;&|[:space:]])git[[:space:]]+filter-(branch|repo)' && \
  hook_deny "git filter-branch / filter-repo は履歴の一括改変のため禁止です。"

# 共有履歴の破壊
echo "$MASKED" | grep -qE '(^|[;&|[:space:]])git[[:space:]]+push[^;&|]*([[:space:]](-f|--force)([[:space:]]|$)|--force-with-lease|--force-if-includes)' && \
  hook_deny "force push は共有履歴の破壊のため禁止です。必要ならユーザー自身が実行してください。"

# 復旧手段（reflog / 到達不能オブジェクト）の破壊。
# rebase-squash の安全網は backup ブランチと reflog なので、これらを消す操作は例外なく止める
echo "$MASKED" | grep -qE '(^|[;&|[:space:]])git[[:space:]]+reflog[[:space:]]+(expire|delete)' && \
  hook_deny "git reflog expire/delete は履歴復旧の安全網を壊すため禁止です。"
echo "$MASKED" | grep -qE '(^|[;&|[:space:]])git[[:space:]]+gc[^;&|]*--prune=(now|all)' && \
  hook_deny "git gc --prune=now/all は到達不能コミットの復旧を不可能にするため禁止です。"
echo "$MASKED" | grep -qE '(^|[;&|[:space:]])git[[:space:]]+prune([[:space:]]|$)' && \
  hook_deny "git prune は到達不能コミットの復旧を不可能にするため禁止です。"

# rebase-squash の backup ブランチ削除（squash 結果の最終確認と backup の削除は人間の仕事）
if echo "$MASKED" | grep -q 'backup/rebase-squash-'; then
  echo "$MASKED" | grep -qE '(^|[;&|[:space:]])git[[:space:]]+(branch[^;&|]*[[:space:]](-D|-d|--delete)([[:space:]]|$)|update-ref[^;&|]*[[:space:]]-d[[:space:]])' && \
    hook_deny "backup/rebase-squash-* ブランチの削除は禁止です。squash 結果の最終確認と backup の削除はユーザー自身が行ってください。"
fi

exit 0
