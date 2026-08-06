#!/bin/bash
# コミット subject の唯一の契約。通常コミット hook と rebase-squash 実行器が source して使う。
# 配置時に init-agent が agent 名を確定する。直接実行時は prefix 生成と形式検証にも使える。

COMMIT_MESSAGE_AGENT="[agent_name]"
COMMIT_MESSAGE_JAPANESE_RE='[ぁ-んァ-ヶ一-龠々ー]'

commit_message_prefix() {
  printf '[%s]: %s/' "$COMMIT_MESSAGE_AGENT" "$1"
}

commit_message_format() {
  printf '[%s]: {対象名}/{変更内容（日本語を含む）}\n' "$COMMIT_MESSAGE_AGENT"
}

commit_message_has_forbidden_ai_signature() {
  printf '%s\n' "$1" | grep -qiE 'co-authored-by|generated with'
}

commit_message_is_valid_for_scope() {
  scope=$1
  subject=$2
  prefix=$(commit_message_prefix "$scope")

  case "$subject" in
    "$prefix"*) description=${subject#"$prefix"} ;;
    *) return 1 ;;
  esac

  [ -n "$description" ] && printf '%s\n' "$description" | grep -qE "$COMMIT_MESSAGE_JAPANESE_RE"
}

commit_message_subject_is_valid() {
  subject=$1
  agent_prefix="[$COMMIT_MESSAGE_AGENT]: "

  case "$subject" in
    "$agent_prefix"*) scoped_description=${subject#"$agent_prefix"} ;;
    *) return 1 ;;
  esac

  scope=${scoped_description%%/*}
  description=${scoped_description#*/}
  [ "$scope" != "$scoped_description" ] || return 1
  printf '%s\n' "$scope" | grep -qE '^[^[:space:]/]+(/[^[:space:]/]+)*$' || return 1
  [ -n "$description" ] && printf '%s\n' "$description" | grep -qE "$COMMIT_MESSAGE_JAPANESE_RE"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  case "${1:-}" in
    --format)
      [ "$#" -eq 1 ] || exit 2
      commit_message_format
      ;;
    --prefix)
      [ "$#" -eq 2 ] || exit 2
      commit_message_prefix "$2"
      printf '\n'
      ;;
    --validate)
      [ "$#" -eq 2 ] || exit 2
      commit_message_subject_is_valid "$2"
      ;;
    *)
      exit 2
      ;;
  esac
fi
