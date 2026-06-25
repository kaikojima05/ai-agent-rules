#!/bin/bash
INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name')

# permissionDecision: allow を返して permission prompt をスキップさせる
allow() {
  jq -n '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "allow"
    }
  }'
  exit 0
}

# [NOTE]: init-agent 対象
# copilot cli: if [ "$TOOL" = "edit" ] || [ "$TOOL" = "create" ]; then
# claude code: if [ "$TOOL" = "Edit" ] || [ "$TOOL" = "Write" ]; then
# codex: if [ "$TOOL" = "apply_patch" ]; then
if 
  FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

  # ファイルパスが取れなければスキップ
  [ -z "$FILE" ] && exit 0

  # テストファイル自体は TDD の Red フェーズ。承認なしで書かせる
  echo "$FILE" | grep -q '\.test\.' && allow

  # 対応するテストファイルが存在するか確認
  DIR=$(dirname "$FILE")
  BASE=$(basename "$FILE" | sed 's/\.[^.]*$//')
  EXT=$(basename "$FILE" | sed 's/^.*\.//')

  # コードファイルのみ対象（.md, .json, .sh などは対象外）
  case "$EXT" in
    ts|js) ;;
    *) exit 0 ;;
  esac

  TEST_FILE="$DIR/$BASE.test.$EXT"

  if [ ! -f "$TEST_FILE" ]; then
    jq -n --arg r "テストファイル($TEST_FILE)が無い状態でのコード実装は禁止です。直接実装せず、tdd-run スキルの TDD フロー（シナリオ → Red → Green → Refactor）に乗せてください。" \
      '{
        "hookSpecificOutput": {
          "hookEventName": "PreToolUse",
          "permissionDecision": "deny",
          "permissionDecisionReason": $r
        }
      }'
    exit 0
  fi

  # 対応テストがあるコード本体の編集 = 最小実装 / リファクタ適用フェーズ。承認なしで通す
  allow
fi

exit 0
