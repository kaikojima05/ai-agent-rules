#!/bin/bash
# PreToolUse(Bash) hook: インライン eval(python3 -c / node -e 等)を deny する。
# その場書き捨ての任意コード実行を禁じ、read-only ツール(jq/grep/sed)か、
# 痕跡の残るスクリプトファイル実行(python3 foo.py)へ誘導するのが目的。
# Why: -c/-e の中身は任意コードで静的に安全判定できず、承認の乱発と乱用の温床になるため。
exec 2>/dev/null
. "$(dirname "$0")/hook-io.sh"
[ "$(hook_tool_name)" = "Bash" ] || exit 0
CMD=$(hook_command)
[ -z "$CMD" ] && exit 0

# クォート内文字列を除去してから分割する（コード文字列中の | ; を区切りと誤認しないため）
MASKED=$(echo "$CMD" | sed 's/"[^"]*"//g' | sed "s/'[^']*'//g")

# パイプ・連結・改行・セミコロンでセグメント分割し、各先頭コマンドを検査する
set -f
while IFS= read -r LINE; do
  set -- $LINE
  # `command`/`builtin` は alias/関数回避目的の透過プレフィックス。剥がして本体で判定する
  while [ "${1:-}" = "command" ] || [ "${1:-}" = "builtin" ]; do shift; done
  BIN="${1:-}"
  # パス経由の起動（./node_modules/.bin/tsx や /usr/bin/python3 等）をすり抜けさせないため、
  # 判定はフルトークンではなく basename で行う
  BIN_BASE="${BIN##*/}"
  # 言語ごとに eval フラグと正規スクリプトの拡張子を対応付ける（無関係な言語は次へ）
  case "$BIN_BASE" in
    python|python2|python3) EVAL_FLAGS="-c"; SCRIPT_RE='\.py$' ;;
    node|nodejs)            EVAL_FLAGS="-e --eval -p --print"; SCRIPT_RE='\.[cm]?js$' ;;
    tsx|ts-node)            EVAL_FLAGS="-e --eval -p --print"; SCRIPT_RE='\.[cm]?[jt]sx?$' ;;
    perl)                   EVAL_FLAGS="-e -E"; SCRIPT_RE='\.pl$' ;;
    ruby)                   EVAL_FLAGS="-e"; SCRIPT_RE='\.rb$' ;;
    php)                    EVAL_FLAGS="-r"; SCRIPT_RE='\.php$' ;;
    *) continue ;;
  esac
  shift
  MSG="インライン eval（$BIN の -c/-e 等・stdin・heredoc からのコード実行）は禁止です。JSON/テキスト整形は jq・grep・sed 等の read-only ツールを使い、任意コードが必要ならファイルに書いてから実行してください（例: $BIN script）。書き捨てコードは痕跡が残らず、承認の乱発と乱用の温床になるため。"
  # 正規スクリプトファイル / -m module を伴うなら「ファイル実行」とみなし eval 判定から外す
  HAS_SCRIPT=0
  for arg in "$@"; do
    case "$arg" in -m|-m*) HAS_SCRIPT=1 ;; -*) ;; *) echo "$arg" | grep -Eq "$SCRIPT_RE" && HAS_SCRIPT=1 ;; esac
    # `-`(stdin をプログラムとして読む) と eval フラグ（-c'...' の連結形も prefix で拾う）を拒否
    [ "$arg" = "-" ] && hook_deny "$MSG"
    for flag in $EVAL_FLAGS; do
      case "$arg" in "$flag"|"$flag"*) hook_deny "$MSG" ;; esac
    done
  done
  # スクリプト無しで stdin からコードを食う形（bare 起動=パイプ先 / heredoc）を拒否する
  if [ "$HAS_SCRIPT" = 0 ]; then
    [ "$#" -eq 0 ] && hook_deny "$MSG"
    echo "$LINE" | grep -q '<<' && hook_deny "$MSG"
  fi
done <<EOF
$(echo "$MASKED" | sed -E 's/&&/\n/g; s/\|\|/\n/g' | tr '|;' '\n')
EOF

exit 0
