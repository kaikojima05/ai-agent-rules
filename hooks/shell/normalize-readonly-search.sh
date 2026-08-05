#!/bin/bash
# PreToolUse(Bash) hook: 安全な読み取り検索を正規化し、複合 shell を分割させる。
# Why: 2>/dev/null があると Codex は shell wrapper を静的に分解できず、読み取り専用の
#      コード探索でも承認を要求する。rg は自身の同等 option へ置き換え、find は変更系
#      action を拒否してから許可する。それ以外の loop・条件分岐・pipeline は承認へ
#      送らず拒否し、単一コマンドへ分割させる。
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

has_compound_shell_syntax() {
  printf '%s\n' "$1" | awk '
    BEGIN { compound = 0; state = "plain"; escaped = 0; sq = sprintf("%c", 39) }
    NR != 1 { compound = 1 }
    {
      for (i = 1; i <= length($0); i++) {
        ch = substr($0, i, 1)
        next_ch = substr($0, i + 1, 1)
        prev_ch = i > 1 ? substr($0, i - 1, 1) : ""
        if (state == "single") {
          if (ch == sq) state = "plain"
          continue
        }
        if (state == "double") {
          if (escaped) { escaped = 0; continue }
          if (ch == "\\") { escaped = 1; continue }
          if (ch == "\"") { state = "plain"; continue }
          if (ch == "`" || (ch == "$" && next_ch == "(")) compound = 1
          continue
        }
        if (escaped) { escaped = 0; continue }
        if (ch == "\\") { escaped = 1; continue }
        if (ch == sq) { state = "single"; continue }
        if (ch == "\"") { state = "double"; continue }
        if (ch == ";" || ch == "|" || ch == "`" || ch == "(" || ch == ")") compound = 1
        if (ch == "&" && prev_ch != ">") compound = 1
        if (ch == "$" && next_ch == "(") compound = 1
      }
    }
    END {
      if (state != "plain" || escaped) compound = 1
      exit(compound ? 0 : 1)
    }
  '
}

invokes_inline_shell() {
  printf '%s\n' "$1" | awk '
    /^[[:space:]]*(\/bin\/)?(bash|zsh|sh)[[:space:]]+-[[:alnum:]]*c([[:space:]]|$)/ { found = 1 }
    END { exit(found ? 0 : 1) }
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

normalize_readonly_rg() {
  local rg_command=$1
  local base_command
  local normalized_command
  local sort_suffix=
  local suppress_messages=0

  # stderr だけを /dev/null へ捨てる形と、後続が引数なし sort だけの形に限定する。
  # stdout のリダイレクトや他の pipeline は安全な例外として扱わない。
  case "$rg_command" in
    rg\ *" 2>/dev/null | sort")
      base_command=${rg_command%" 2>/dev/null | sort"}
      suppress_messages=1
      sort_suffix=" | sort"
      ;;
    rg\ *" 2> /dev/null | sort")
      base_command=${rg_command%" 2> /dev/null | sort"}
      suppress_messages=1
      sort_suffix=" | sort"
      ;;
    rg\ *" | sort")
      base_command=${rg_command%" | sort"}
      sort_suffix=" | sort"
      ;;
    rg\ *" 2>/dev/null")
      base_command=${rg_command%" 2>/dev/null"}
      suppress_messages=1
      ;;
    rg\ *" 2> /dev/null")
      base_command=${rg_command%" 2> /dev/null"}
      suppress_messages=1
      ;;
    *) return ;;
  esac

  # single quote 内の regex や --glob は shell 展開されないため許可し、double quote 内の
  # 展開や末尾以外の shell 構文があれば安全な例外として扱わない。
  has_safe_shell_syntax "$base_command" || return

  normalized_command=$base_command
  if [ "$suppress_messages" -eq 1 ]; then
    case " $base_command " in
      *" --no-messages "*) ;;
      *) normalized_command="rg --no-messages${base_command#rg}" ;;
    esac
  fi

  hook_rewrite_command "$normalized_command$sort_suffix"
}

case "$CMD" in
  find\ *) normalize_readonly_find "$CMD" ;;
  rg\ *) normalize_readonly_rg "$CMD" ;;
esac

if has_compound_shell_syntax "$CMD" || invokes_inline_shell "$CMD"; then
  hook_deny "複数コマンドを shell loop・条件分岐・pipeline に集約してはいけません。Read/Grep/Glob または副作用を静的判定できる単一コマンドへ分割してください。複雑な処理はレビュー済み固定スクリプトへ移してください。"
fi

exit 0
