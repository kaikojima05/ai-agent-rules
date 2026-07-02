#!/bin/bash
# PreToolUse(Bash) hook: localhost/127.0.0.1 だけを叩く安全な curl を承認なしで許可する。
# 外部ホスト・ファイル書き込み(-o/-O)・アップロード(-T)・プロキシ/接続先すり替え
# (--proxy/--connect-to/--resolve) を含むものは許可せず permission に委ねる（=承認を出す）。
# Why: 外部 HTTP は exfil と任意ダウンロードの経路。egress は意図的な承認を残しつつ、
#      自分の dev server 叩きだけ摩擦なく通す。curl は -o 等で書けるので allow-list に
#      丸ごと入れず localhost に限ってここで通す（[[auto-allow-readonly-only]] と同思想）。
# 出力汚染の根絶: 決定 hook は stdout の決定JSON 以外を外へ出さない契約。stderr を捨てる。
exec 2>/dev/null
INPUT=$(cat)
[ "$(echo "$INPUT" | jq -r '.tool_name')" = "Bash" ] || exit 0
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
[ -z "$CMD" ] && exit 0

allow() {
  jq -n '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
  exit 0
}

# curl と同居してよい純 read-only コマンド（curl localhost | jq 等のパイプを通すため）
READONLY=" cd grep rg ls cat head tail wc cut tr pwd basename dirname file stat jq column nl echo printf "

# コマンド置換があれば棄権
echo "$CMD" | grep -Eq '\$\(|`' && exit 0
# 先にエスケープ済み引用符(\") を除去してから通常のクォート内文字列を落とす
# （-d "{\"k\":1}" のような JSON body でマスキングが崩れ URL 破片が残るのを防ぐ）
MASKED=$(echo "$CMD" | sed 's/\\"//g' | sed 's/"[^"]*"//g' | sed "s/'[^']*'//g")
# /dev/null 行き・fd 複製以外のリダイレクトがあれば棄権（> はファイル書き込み）
SANITIZED=$(echo "$MASKED" | sed -E 's/[0-9]*>>?[[:space:]]*\/dev\/null//g; s/[0-9]*>&[0-9]//g')
echo "$SANITIZED" | grep -q '>' && exit 0

# curl セグメントが localhost 限定かつ書き込み/アップロード/接続すり替えを含まないか判定
curl_ok() {
  shift
  local has_url=0 skip=0 t
  for t in "$@"; do
    if [ "$skip" = 1 ]; then skip=0; continue; fi
    case "$t" in
      --output|--output=*|--output-dir|--output-dir=*|--upload-file|--upload-file=*|--cookie-jar|--cookie-jar=*|--proxy|--proxy=*|--connect-to|--connect-to=*|--resolve|--resolve=*|-x|-x*) return 1 ;;
      -H|--header|-X|--request|-d|--data|--data-*|-A|--user-agent|-e|--referer|-b|--cookie|-u|--user|-F|--form|-m|--max-time|-w|--write-out) skip=1 ;;
      -[!-]*) case "$t" in *[oOT]*) return 1 ;; esac ;;
      --*) : ;;
      *) echo "$t" | grep -Eq '^(https?://)?(localhost|127\.0\.0\.1)(:[0-9]+)?(/.*)?$' || return 1; has_url=1 ;;
    esac
  done
  [ "$has_url" = 1 ]
}

set -f
while IFS= read -r LINE; do
  set -- $LINE
  while [ "${1:-}" = "command" ] || [ "${1:-}" = "builtin" ]; do shift; done
  [ -z "${1:-}" ] && continue
  if [ "$1" = "curl" ]; then
    curl_ok "$@" || exit 0
  else
    case "$READONLY" in *" $1 "*) ;; *) exit 0 ;; esac
  fi
done <<EOF
$(echo "$SANITIZED" | sed -E 's/&&/\n/g; s/\|\|/\n/g' | tr '|;' '\n')
EOF

allow
