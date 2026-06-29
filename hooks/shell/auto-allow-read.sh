#!/bin/bash
# PreToolUse(Bash) hook: read-only な検索系コマンドだけ承認なしで許可する。
# cd+リダイレクト等のビルトイン手動承認を越えるのが目的。安全側に倒し、
# read-only と確証できた時だけ allow、それ以外は exit 0 で permission に委ねる。
INPUT=$(cat)
[ "$(echo "$INPUT" | jq -r '.tool_name')" = "Bash" ] || exit 0
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
[ -z "$CMD" ] && exit 0

# permissionDecision: allow を返して permission prompt をスキップさせる
allow() {
  jq -n '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
  exit 0
}

# 承認なしで許可するコマンド（オプションを足しても書き込み/任意実行ができない read-only のみ）
ALLOWED=" cd grep rg ls cat head tail wc cut tr pwd basename dirname file stat jq column nl echo printf "

# コマンド置換があれば棄権（ダブルクォート内でも実行されうるので元コマンドで判定）
echo "$CMD" | grep -Eq '\$\(|`' && exit 0

# 以降の構文判定はクォート内文字列を除去してから行う
# （正規表現中の | や > を区切り・リダイレクトと誤認しないため。許可は広げず誤検出だけ減らす）
MASKED=$(echo "$CMD" | sed 's/"[^"]*"//g' | sed "s/'[^']*'//g")

# /dev/null 行き・fd 複製の無害なリダイレクトを除去し、残った > は書き込みとみなし棄権
SANITIZED=$(echo "$MASKED" | sed -E 's/[0-9]*>>?[[:space:]]*\/dev\/null//g; s/[0-9]*>&[0-9]//g')
echo "$SANITIZED" | grep -q '>' && exit 0

# パイプ・連結・改行で分割し、先頭コマンドが全て許可リストにあるか検査
set -f
while IFS= read -r LINE; do
  set -- $LINE
  # `command`/`builtin` は alias/関数回避目的の透過プレフィックス。剥がして本体コマンドで判定する
  while [ "${1:-}" = "command" ] || [ "${1:-}" = "builtin" ]; do shift; done
  [ -z "${1:-}" ] && continue
  case "$ALLOWED" in *" $1 "*) ;; *) exit 0 ;; esac
done <<EOF
$(echo "$SANITIZED" | sed -E 's/&&/\n/g; s/\|\|/\n/g' | tr '|;' '\n')
EOF

allow
