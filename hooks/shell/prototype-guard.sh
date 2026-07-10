#!/bin/bash
# prototype スキル稼働中の Edit|Write 判定。テストファイルのみ禁止(deny)する deny 専任 hook。
# それ以外は棄権し、自動化は settings の allow(Edit(**)/Write(**)) が担う。
# Why: プロトタイプ段階で雑なテストを残すと、後で残すべき正規テストか判別できなくなるため。
# 出力汚染の根絶: 決定 hook は stdout の決定JSON 以外を外へ出さない契約。
# stderr を捨て、jq 等サブプロセスのエラー文字がツール出力へ混入する経路を断つ。
exec 2>/dev/null
INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
[ -z "$FILE" ] && exit 0

# テストファイルは prototype 中は作らせない（テストは OK 後のフェーズで書く）
if echo "$FILE" | grep -q '\.test\.'; then
  jq -n --arg r "prototype 中はテストファイルを作成できません。動作確認は実行で行い、テストは OK 後（tdd-run 等）で書いてください。" \
    '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":$r}}'
  exit 0
fi

# それ以外は棄権して settings に委ねる（hook が allow を配ると密度の定義が二重化する）
exit 0
