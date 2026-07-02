#!/bin/bash
# PreToolUse(Bash) hook: registry から取得して実行する系コマンドを deny する。
# 目的: npx 等の fetch-and-run と install 系を止め、ローカルの node_modules/.bin か
#       yarn <script>（yarn v1 はローカル binary へ fallback）へ誘導すること。registry
#       への network egress 自体を発生させないので、sandbox の「外に出るか？」prompt も
#       そもそも出なくなる。
# Why: 見慣れない registry ドメインへの都度承認は判断コストが高く、承認の乱発と
#      cwd 誤りによる意図せぬ registry fetch の温床になるため。
# 出力汚染の根絶: 決定 hook は stdout の決定JSON 以外を外へ出さない契約。stderr を捨てる。
exec 2>/dev/null
INPUT=$(cat)
[ "$(echo "$INPUT" | jq -r '.tool_name')" = "Bash" ] || exit 0
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
[ -z "$CMD" ] && exit 0

# permissionDecision: deny を返して当該コマンドを拒否し、理由を Claude に伝える
deny() {
  jq -n --arg r "$1" \
    '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":$r}}'
  exit 0
}

FETCH="registry から取得して実行する系（npx / *x / dlx 等）は禁止です。ローカル導入済みなら node_modules/.bin/<tool> か yarn <tool> を使ってください（yarn v1 はローカル binary へ fallback します）。未導入パッケージの実行が必要ならユーザーに確認してください。"
INST="依存の install / add / update は registry へ出るため禁止です。既存の node_modules で実行し、依存追加が必要ならユーザーに相談してください。"

# クォート内文字列を除去してから分割する（コード文字列中の | ; を区切りと誤認しないため）
MASKED=$(echo "$CMD" | sed 's/"[^"]*"//g' | sed "s/'[^']*'//g")

# パイプ・連結・改行・セミコロンで分割し、各セグメント先頭コマンドを検査する
set -f
while IFS= read -r LINE; do
  set -- $LINE
  # `command`/`builtin` は alias/関数回避目的の透過プレフィックス。剥がして本体で判定する
  while [ "${1:-}" = "command" ] || [ "${1:-}" = "builtin" ]; do shift; done
  BIN="${1:-}"; SUB="${2:-}"
  case "$BIN" in
    npx|pnpx|bunx) deny "$FETCH" ;;
    yarn)
      case "$SUB" in
        ""|add|install|up|upgrade|upgrade-interactive|global|import) deny "$INST" ;;
        dlx|create) deny "$FETCH" ;;
      esac ;;
    npm|pnpm|bun)
      case "$SUB" in
        i|install|ci|add|update|up) deny "$INST" ;;
        x|exec|dlx|create) deny "$FETCH" ;;
      esac ;;
  esac
done <<EOF
$(echo "$MASKED" | sed -E 's/&&/\n/g; s/\|\|/\n/g' | tr '|;' '\n')
EOF

exit 0
