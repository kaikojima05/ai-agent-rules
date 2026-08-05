#!/bin/bash
# PreToolUse(Bash) hook: rg の stderr 破棄を --no-messages へ正規化する。
# Why: 2>/dev/null があると Codex は shell wrapper を静的に分解できず、読み取り専用の
#      コード探索でも承認を要求する。rg 自身の同等 option へ置き換えれば、危険な
#      shell wrapper の prompt 規則を緩めずに不要な承認だけを除去できる。
exec 2>/dev/null
. "$(dirname "$0")/hook-io.sh"
[ "$(hook_tool_name)" = "Bash" ] || exit 0
CMD=$(hook_command)
[ -z "$CMD" ] && exit 0

# stderr だけを /dev/null へ捨てる末尾形に限定する。stdout のリダイレクトは書き込みに
# なり得るため正規化せず、既存の approval / sandbox 判定へ委ねる。
case "$CMD" in
  rg\ *" 2>/dev/null") BASE_CMD=${CMD%" 2>/dev/null"} ;;
  rg\ *" 2> /dev/null") BASE_CMD=${CMD%" 2> /dev/null"} ;;
  *) exit 0 ;;
esac

# 末尾の redirection 以外にも shell 構文がある場合は書き換えない。single quote 内の
# regex や --glob は shell 展開されないため許可し、double quote 内の展開は拒否する。
if ! printf '%s\n' "$BASE_CMD" | awk '
  BEGIN { valid = 1; state = "plain"; escaped = 0; sq = sprintf("%c", 39) }
  NR != 1 { valid = 0 }
  {
    for (i = 1; i <= length($0); i++) {
      ch = substr($0, i, 1)
      if (state == "single") {
        if (ch == sq) state = "plain"
        continue
      }
      if (state == "double") {
        if (escaped) { escaped = 0; continue }
        if (ch == "\\") { escaped = 1; continue }
        if (ch == "\"") { state = "plain"; continue }
        if (ch == "$" || ch == "`") valid = 0
        continue
      }
      if (ch == sq) { state = "single"; continue }
      if (ch == "\"") { state = "double"; continue }
      if (ch == "\\" || index(";&|<>`$(){}#*?[]", ch) > 0) valid = 0
    }
  }
  END {
    if (state != "plain" || escaped) valid = 0
    exit(valid ? 0 : 1)
  }
'; then
  exit 0
fi

case " $BASE_CMD " in
  *" --no-messages "*) NORMALIZED_CMD=$BASE_CMD ;;
  *) NORMALIZED_CMD="rg --no-messages${BASE_CMD#rg}" ;;
esac

hook_rewrite_command "$NORMALIZED_CMD"
