#!/bin/bash
# PreToolUse(Bash) hook: 読み取り検索の stderr 破棄と安全な sort pipeline を正規化する。
# Why: 2>/dev/null があると Codex は shell wrapper を静的に分解できず、読み取り専用の
#      コード探索でも承認を要求する。rg は自身の同等 option へ置き換え、find は変更系
#      action を拒否してから許可すれば、opaque shell の prompt 規則を緩めずに不要な
#      承認だけを除去できる。
exec 2>/dev/null
. "$(dirname "$0")/hook-io.sh"
[ "$(hook_tool_name)" = "Bash" ] || exit 0
CMD=$(hook_command)
[ -z "$CMD" ] && exit 0

has_safe_shell_syntax() {
  printf '%s\n' "$1" | awk '
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
  '
}

normalize_readonly_find() {
  local find_command=$1
  local base_command
  local command_suffix

  case "$find_command" in
    find\ *" 2>/dev/null | sort")
      base_command=${find_command%" 2>/dev/null | sort"}
      command_suffix=" 2>/dev/null | sort"
      ;;
    find\ *" 2> /dev/null | sort")
      base_command=${find_command%" 2> /dev/null | sort"}
      command_suffix=" 2>/dev/null | sort"
      ;;
    find\ *" | sort")
      base_command=${find_command%" | sort"}
      command_suffix=" | sort"
      ;;
    find\ *" 2>/dev/null")
      base_command=${find_command%" 2>/dev/null"}
      command_suffix=" 2>/dev/null"
      ;;
    find\ *" 2> /dev/null")
      base_command=${find_command%" 2> /dev/null"}
      command_suffix=" 2>/dev/null"
      ;;
    *) return ;;
  esac

  has_safe_shell_syntax "$base_command" || return

  # quote の連結で action 名を分割すると文字列検査を回避できるため、find だけは quote を
  # 許可しない。空白を含む path は承認側へ戻し、安全判定できる単純形だけを扱う。
  case "$base_command" in
    *"'"*|*'"'*) return ;;
  esac

  # find の変更系 action と任意コマンド実行を拒否する。部分一致による false positive は
  # 自動許可を狭めるだけなので、安全側に倒して既存の approval 判定へ委ねる。
  case "$base_command" in
    *-delete*|*-exec*|*-ok*|*-fprint*|*-fprintf*|*-fls*) return ;;
  esac

  hook_rewrite_command "$base_command$command_suffix"
}

case "$CMD" in
  find\ *)
    normalize_readonly_find "$CMD"
    exit 0
    ;;
esac

# stderr だけを /dev/null へ捨てる形と、後続が引数なし sort だけの形に限定する。
# stdout のリダイレクトや他の pipeline は書き込み・副作用を持ち得るため正規化せず、
# 既存の approval / sandbox 判定へ委ねる。
SUPPRESS_MESSAGES=0
SORT_SUFFIX=
case "$CMD" in
  rg\ *" 2>/dev/null | sort")
    BASE_CMD=${CMD%" 2>/dev/null | sort"}
    SUPPRESS_MESSAGES=1
    SORT_SUFFIX=" | sort"
    ;;
  rg\ *" 2> /dev/null | sort")
    BASE_CMD=${CMD%" 2> /dev/null | sort"}
    SUPPRESS_MESSAGES=1
    SORT_SUFFIX=" | sort"
    ;;
  rg\ *" | sort")
    BASE_CMD=${CMD%" | sort"}
    SORT_SUFFIX=" | sort"
    ;;
  rg\ *" 2>/dev/null")
    BASE_CMD=${CMD%" 2>/dev/null"}
    SUPPRESS_MESSAGES=1
    ;;
  rg\ *" 2> /dev/null")
    BASE_CMD=${CMD%" 2> /dev/null"}
    SUPPRESS_MESSAGES=1
    ;;
  *) exit 0 ;;
esac

# 末尾の redirection 以外にも shell 構文がある場合は書き換えない。single quote 内の
# regex や --glob は shell 展開されないため許可し、double quote 内の展開は拒否する。
has_safe_shell_syntax "$BASE_CMD" || exit 0

NORMALIZED_CMD=$BASE_CMD
if [ "$SUPPRESS_MESSAGES" -eq 1 ]; then
  case " $BASE_CMD " in
    *" --no-messages "*) ;;
    *) NORMALIZED_CMD="rg --no-messages${BASE_CMD#rg}" ;;
  esac
fi

hook_rewrite_command "$NORMALIZED_CMD$SORT_SUFFIX"
