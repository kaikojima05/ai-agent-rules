#!/bin/bash
INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name')

# [NOTE]: init-agent 対象
# copilot cli: if [ "$TOOL" = "edit" ] || [ "$TOOL" = "create" ]; then
# claude code: if [ "$TOOL" = "Edit" ] || [ "$TOOL" = "Write" ] || [ "$TOOL" = "MultiEdit" ]; then
if # 条件式
  FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

  # ファイルパスが取れなければスキップ
  [ -z "$FILE" ] && exit 0

  # テストファイル自体の編集は許可
  echo "$FILE" | grep -q '\.test\.' && exit 0

  # 対応するテストファイルが存在するか確認
  DIR=$(dirname "$FILE")
  BASE=$(basename "$FILE" | sed 's/\.[^.]*$//')
  EXT=$(basename "$FILE" | sed 's/^.*\.//')

  TEST_FILE="$DIR/$BASE.test.$EXT"

  if [ ! -f "$TEST_FILE" ]; then
    jq -n --arg r "テストファイル($TEST_FILE)が存在しません。TDD規約により、先にテストを作成してください。" \
      '{
        "hookSpecificOutput": {
          "hookEventName": "PreToolUse",
          "permissionDecision": "deny",
          "permissionDecisionReason": $r
        }
      }'
    exit 0
  fi
fi

exit 0
