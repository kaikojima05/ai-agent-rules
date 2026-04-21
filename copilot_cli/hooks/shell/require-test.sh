#!/bin/bash
INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.toolName')

if [ "$TOOL" = "apply_patch" ]; then
  FILE=$(echo "$INPUT" | jq -r '.toolArgs' | grep -m1 'Update File:\|Create File:' | sed 's/.*: //')

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
      '{"permissionDecision":"deny","permissionDecisionReason":$r}'
    exit 0
  fi
fi

exit 0
