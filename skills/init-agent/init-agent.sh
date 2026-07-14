#!/bin/bash
# init-agent: 配置済みエージェント設定ツリーの placeholder を確定させる決定的スクリプト。
# [agent_name] の置換と [NOTE]: init-agent 対象 ブロックの解決を、レビュー済みの単一
# 成果物として実行する（その都度インタプリタで書き捨てコードを生成しないため）。
# 使い方: bash init-agent.sh <claude|github|codex>
# 失敗の扱い: 置換失敗・[NOTE] 未解決（tmp 書き込み不能 / bare if 不在）が 1 件でも
# あれば exit 1。成功ログは実際に書き換えできた時だけ出す（失敗の握りつぶし禁止）。
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

# grep | while はサブシェル化して失敗フラグが親に届かないため、プロセス置換で読む。
# set -e はパイプライン内 while で期待どおり働かないので使わず、明示的に成否判定する
FAILED=0

# 1) [agent_name] 置換: init-agent スキル自身（placeholder の説明文と処理本体）は除外する
while IFS= read -r f; do
  if sed -i.bak "s/\[agent_name\]/$NAME/g" "$f"; then
    rm -f "$f.bak"
    echo "replaced [agent_name]->$NAME : $f"
  else
    rm -f "$f.bak"
    echo "ERROR: replace failed (sed): $f" >&2
    FAILED=1
  fi
done < <(grep -rl '\[agent_name\]' "$DIR" | grep -v '/init-agent/')

# 2) [NOTE] 解決: [NOTE] 行から直後の bare if 行までを確定条件へ畳む（init-agent 自身は除外）
while IFS= read -r f; do
  if ! awk -v cond="$COND" '
    /\[NOTE\]: init-agent/ { skip=1; next }
    skip && /^[[:space:]]*if[[:space:]]*$/ { print cond; skip=0; next }
    skip { next }
    { print }
  ' "$f" > "$f.tmp"; then
    rm -f "$f.tmp"
    echo "ERROR: cannot write tmp for [NOTE] resolve: $f.tmp" >&2
    FAILED=1
    continue
  fi
  if ! grep -qF "$COND" "$f.tmp"; then
    # マーカーがあるのに bare if が無い = 配置ツリーが壊れている。黙って続行すると
    # マーカーが残ったまま成功に見えるため、失敗として報告する
    rm -f "$f.tmp"
    echo "ERROR: bare if not found, cannot resolve [NOTE]: $f" >&2
    FAILED=1
    continue
  fi
  if mv "$f.tmp" "$f"; then
    echo "resolved [NOTE] : $f"
  else
    rm -f "$f.tmp"
    echo "ERROR: cannot overwrite (mv failed): $f" >&2
    FAILED=1
  fi
done < <(grep -rl '\[NOTE\]: init-agent' "$DIR" | grep -v '/init-agent/')

exit "$FAILED"
