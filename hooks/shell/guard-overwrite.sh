#!/bin/bash
# PreToolUse(Write) hook: 既存ファイルの「全上書き」を人間の確認に通す(ask)。
# 新規作成(存在しないパスへの Write)は素通り。既存ファイルの部分修正は Edit を使う前提。
# Why: ツール出力のノイズを「汚染された」と誤読したモデルが、記憶を頼りに既存ファイルを
#      全上書きして中身を消し飛ばす事故を、モデルの心境と無関係に harness 段階で止めるため。
# 出力汚染の根絶: 決定 hook は stdout の決定JSON 以外を外へ出さない契約。stderr を捨てる。
exec 2>/dev/null
INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
[ -z "$FILE" ] && exit 0

# permissionDecision: ask を返して人間の確認を1回挟ませる。
# deny ではないので、意図的な全面再生成なら人間が承認して通せる余地を残す。
ask() {
  jq -n --arg r "$1" \
    '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":$r}}'
  exit 0
}

# 既にファイルが存在する = 全上書き。部分修正なら Edit を使うべきで、全上書きは人間に諮る
[ -f "$FILE" ] && ask "既存ファイルの全上書き(Write)です。部分修正は Edit を使ってください。出力汚染を疑った上での全上書き・記憶を根拠にした再生成は禁止。意図的な全面再生成であれば承認してください。"

# 存在しないパス = 新規作成。素通りして通常の permission に委ねる
exit 0
