#!/bin/bash
# prototype スキル稼働中の Bash 判定。
# 原則すべて許可（sandbox の檻の中で可逆領域を自由にぶん回す前提）。
# ただし sandbox の denyWrite に登録されたパスに触れるコマンドは自動許可せず ask に回す。
# denyWrite はプロジェクトごとに育つため、ハードコードせず settings から動的に抽出する。
# 完全な物理防御は sandbox の denyWrite / CWD 境界（OS 段階）が担う。本 hook はその backstop。
INPUT=$(cat)
[ "$(echo "$INPUT" | jq -r '.tool_name')" = "Bash" ] || exit 0
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
[ -z "$CMD" ] && exit 0
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

# 有効な settings 階層から denyWrite パターンを収集（user → project → local）
PATTERNS=$(for f in "$HOME/.claude/settings.json" "$CWD/.claude/settings.json" "$CWD/.claude/settings.local.json"; do
  [ -f "$f" ] && jq -r '.sandbox.filesystem.denyWrite[]?' "$f" 2>/dev/null
done | sort -u)

ask() {
  jq -n --arg r "$1" '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":$r}}'
  exit 0
}

# denyWrite パターンに触れるコマンドは自動許可しない
# glob 付き(.env.*)は * より前で前方一致、完全パス(.git)は後ろがパス区切り/空白/引用符/行末の時だけ一致
# （.gitignore のような部分一致の誤検出を避けるため）
while IFS= read -r p; do
  [ -z "$p" ] && continue
  case "$p" in
    *\**) base="${p%%\**}"; base="${base%/}"; tail='' ;;
    *)    base="${p%/}";    tail="([/[:space:]\"']|\$)" ;;
  esac
  [ -z "$base" ] && continue
  pat="$(printf '%s' "$base" | sed 's/\./\\./g')$tail"
  echo "$CMD" | grep -Eq "$pat" && ask "denyWrite 対象（$p）に触れる可能性があるため自動許可しません。意図的な操作なら個別に承認してください。"
done <<EOF
$PATTERNS
EOF

# それ以外は sandbox の檻の中で自由に許可
jq -n '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
exit 0
