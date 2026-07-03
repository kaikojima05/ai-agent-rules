#!/bin/bash
# コード書き込みを承認なしで許可するか判定する汎用 hook。
# 現在の許可条件: 対応するテストファイルがあるコード本体（tdd-run の自動実装/リファクタ区間）。
# 別ツール・別条件で許可したくなったら、下の「許可条件」ブロックだけ差し替える。
# 出力汚染の根絶: 決定 hook は stdout の決定JSON 以外を外へ出さない契約。
# stderr を捨て、jq 等サブプロセスのエラー文字がツール出力へ混入する経路を断つ。
exec 2>/dev/null
INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name')

# [NOTE]: init-agent 対象（下記から各エージェントの条件を埋める）
# claude code: if [ "$TOOL" = "Edit" ] || [ "$TOOL" = "Write" ]; then
# codex: if [ "$TOOL" = "apply_patch" ]; then
# copilot cli: if [ "$TOOL" = "edit" ] || [ "$TOOL" = "create" ]; then
if
  FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
  [ -z "$FILE" ] && exit 0

  # テストファイル自体は TDD の Red フェーズ＝無条件で allow。require-test.sh と同一判定を
  # 最終 hook である本 hook でも返す。複数 hook の集約は最後に走った hook の判定が効くため、
  # allow を先行 hook(require-test) だけが返し本 hook が無出力だと打ち消されて prompt 化する
  echo "$FILE" | grep -q '\.test\.' && { jq -n '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'; exit 0; }

  # 許可条件: 対応するテストファイルがあるコード本体なら承認なしで通す
  DIR=$(dirname "$FILE")
  BASE=$(basename "$FILE" | sed 's/\.[^.]*$//')
  EXT=$(basename "$FILE" | sed 's/^.*\.//')
  case "$EXT" in ts|js) ;; *) exit 0 ;; esac

  [ -f "$DIR/$BASE.test.$EXT" ] && jq -n '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
fi
exit 0
