#!/bin/bash
# init-agent: 配置済みエージェント設定ツリーの placeholder を確定させる決定的スクリプト。
# [agent_name] の置換と [NOTE]: init-agent 対象 ブロックの解決を、レビュー済みの単一
# 成果物として実行する（その都度インタプリタで書き捨てコードを生成しないため）。
# 使い方: bash init-agent.sh <claude|github|codex>
set -u

AGENT="${1:?usage: init-agent.sh <claude|github|codex>}"

# 種別ごとに: 配置ディレクトリ / 置換値 / [NOTE] 確定条件 を決める
case "$AGENT" in
  claude) DIR=".claude"; NAME="claude"
    COND='if [ "$TOOL" = "Edit" ] || [ "$TOOL" = "Write" ] || [ "$TOOL" = "MultiEdit" ]; then' ;;
  github) DIR=".github"; NAME="github"
    COND='if [ "$TOOL" = "edit" ] || [ "$TOOL" = "create" ]; then' ;;
  codex)  DIR=".codex";  NAME="codex"
    COND='if [ "$TOOL" = "apply_patch" ]; then' ;;
  *) echo "unknown agent: $AGENT (claude|github|codex)" >&2; exit 1 ;;
esac
[ -d "$DIR" ] || { echo "config dir not found: $DIR" >&2; exit 1; }

# 1) [agent_name] 置換: init-agent スキル自身（placeholder の説明文と処理本体）は除外する
grep -rl '\[agent_name\]' "$DIR" | grep -v '/init-agent/' | while IFS= read -r f; do
  sed -i.bak "s/\[agent_name\]/$NAME/g" "$f" && rm -f "$f.bak"
  echo "replaced [agent_name]->$NAME : $f"
done

# 2) [NOTE] 解決: [NOTE] 行から直後の bare if 行までを確定条件へ畳む（init-agent 自身は除外）
grep -rl '\[NOTE\]: init-agent' "$DIR" | grep -v '/init-agent/' | while IFS= read -r f; do
  awk -v cond="$COND" '
    /\[NOTE\]: init-agent/ { skip=1; next }
    skip && /^[[:space:]]*if[[:space:]]*$/ { print cond; skip=0; next }
    skip { next }
    { print }
  ' "$f" > "$f.tmp"
  if grep -qF "$COND" "$f.tmp"; then mv "$f.tmp" "$f"; echo "resolved [NOTE] : $f"
  else rm -f "$f.tmp"; echo "WARN: bare if not found, skipped $f" >&2; fi
done
