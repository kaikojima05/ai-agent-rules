#!/bin/bash
# PreToolUse(Bash) hook: Prisma schemaの編集は許可し、DBへ反映するmigration系commandだけを拒否する。
exec 2>/dev/null
. "$(dirname "$0")/hook-io.sh"
[ "$(hook_tool_name)" = "Bash" ] || exit 0
CMD=$(hook_command)
[ -n "$CMD" ] || exit 0

MIGRATION_MSG="migrationの実行は禁止です。schema.prismaの編集・format・validate・generateだけを行い、prisma migrate / prisma db push / prisma db execute は実行しないでください。"
NORMALIZED_CMD=$(printf '%s\n' "$CMD" | tr -d "\"'" | tr -d '\\')

if printf '%s\n' "$NORMALIZED_CMD" | grep -Eq '(^|[;&|[:space:]])([^;&|[:space:]]*/)?prisma[[:space:]]+(migrate([[:space:]]|$)|db[[:space:]]+(push|execute)([[:space:]]|$))'; then
  hook_deny "$MIGRATION_MSG"
fi

if printf '%s\n' "$NORMALIZED_CMD" | grep -Eq '(^|[;&|[:space:]])(yarn|npm[[:space:]]+run|pnpm[[:space:]]+run|bun[[:space:]]+run)[[:space:]]+[^;&|[:space:]]*migrat[^;&|[:space:]]*([[:space:]]|$)'; then
  hook_deny "$MIGRATION_MSG"
fi

exit 0
