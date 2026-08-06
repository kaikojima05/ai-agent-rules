#!/bin/bash
# PreToolUse(Read|Grep|Glob|Bash) hook: コードベース調査を隔離したDeepSeekへ固定する。
# 上位モデルは設定・skill・DeepSeek結果だけを読める。実装・設定・テストの探索は
# deepseek/delegate.sh survey 経由だけにし、Read系toolと直接検索の迂回を拒否する。
exec 2>/dev/null
. "$(dirname "$0")/hook-io.sh"

TOOL=$(hook_tool_name)
ROOT=$(hook_cwd)
DENY_MESSAGE="コードベースの調査は DeepSeek に固定されています。上位モデルの Read / Grep / Glob / 直接検索は使わず、bash [skills_root]/deepseek/delegate.sh survey <task-id> <調査指示> を実行し、返却された結果だけを読んでください。"

allowed_read_path() {
  path=$1
  case "$path" in
    "$ROOT"/*) relative=${path#"$ROOT"/} ;;
    /*) return 1 ;;
    *) relative=$path ;;
  esac

  case "$relative" in
    AGENTS.md|CLAUDE.md|.claude/skills/*|.claude/rules/*|.codex/rules/*|.agents/skills/*|.claude/tmp/deepseek/*|.codex/tmp/deepseek/*) return 0 ;;
    *) return 1 ;;
  esac
}

case "$TOOL" in
  Read|Grep|Glob)
    FOUND_PATH=0
    while IFS= read -r PATH_VALUE; do
      [ -n "$PATH_VALUE" ] || continue
      FOUND_PATH=1
      allowed_read_path "$PATH_VALUE" || hook_deny "$DENY_MESSAGE"
    done < <(hook_file_paths)
    [ "$FOUND_PATH" = 1 ] || hook_deny "$DENY_MESSAGE"
    exit 0
    ;;
  Bash) ;;
  *) exit 0 ;;
esac

CMD=$(hook_command)
[ -n "$CMD" ] || exit 0

# 固定委任実行器そのものは検索ではない。内部の隔離worktreeでだけ読取を許可する。
case "$CMD" in
  "bash .claude/skills/deepseek/delegate.sh "*|"bash .agents/skills/deepseek/delegate.sh "*) exit 0 ;;
esac

# 上位モデルの単独検索・一覧・差分読取を拒否する。複合shellはreadonly-search.shが別途拒否する。
case "$CMD" in
  rg\ *|grep\ *|find\ *|ls|ls\ *|cat\ *|head\ *|tail\ *|sed\ *|awk\ *|wc\ *|jq\ *|git\ diff*|git\ log*|git\ show*|git\ ls-files*|git\ grep*)
    hook_deny "$DENY_MESSAGE"
    ;;
esac

exit 0
