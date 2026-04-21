#!/bin/bash

INPUT=$(cat)
TOO_NAME=$(ehoc "$INPUT" | jq -r '.toolName')

# edit / create のツール使用時のみ発火
if [ "$TOOL_NAME" = "edit" ] || [ "$TOOL_NAME" = "create" ]; then
  RULES=$(cat ./.github/agent_docs/pre-coding.md 2>/dev/null)

  if [ -n "$RULES" ]; then
    jq -n --arg reason "コーディング規約を遵守してください:
    echo "$RULES"
$RULES" \
      '{"permissionDecision":"allow","permissionDecisionReason":$reason}'
  fi
fi

exit 0
