#!/bin/bash
# prototype スキル稼働中の Edit|Write 判定。テストファイルのみ禁止(deny)する deny 専任 hook。
# それ以外は棄権し、自動化は settings の allow(Edit(**)/Write(**)) が担う。
# Why: プロトタイプ段階で雑なテストを残すと、後で残すべき正規テストか判別できなくなるため。
exec 2>/dev/null
. "$(dirname "$0")/hook-io.sh"

# codex では session marker（$prototype 起動時に session.sh が記録）が
# 現セッションを指す時だけ執行する。claude は prototype の frontmatter hooks が起動を絞る
if [ "$HOOK_AGENT" = "codex" ] && ! hook_skill_session_active "prototype"; then
  exit 0
fi
# テストファイルは prototype 中は作らせない（テストは OK 後のフェーズで書く）
while IFS= read -r FILE; do
  [ -z "$FILE" ] && continue
  echo "$FILE" | grep -q '\.test\.' && \
    hook_deny "prototype 中はテストファイルを作成できません。動作確認は実行で行い、テストは OK 後（tdd 等）で書いてください。"
done < <(hook_file_paths)

# それ以外は棄権して settings に委ねる（hook が allow を配ると密度の定義が二重化する）
exit 0
