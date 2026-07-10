#!/bin/bash
# 出力汚染の根絶: 決定 hook は stdout の決定JSON 以外を外へ出さない契約。
# stderr を捨て、jq 等サブプロセスのエラー文字がツール出力へ混入する経路を断つ。
exec 2>/dev/null
INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name')

# 本 hook は deny(執行)専任。allow は返さない — ask/deny ルールは hook の allow より
# 常に優先される(公式仕様)ので素通りの危険は無いが、自動化は settings.local.json の
# allow(Edit(**)/Write(**)) が既に担っており、hook 側の allow は密度の定義を二重化する
# だけの死荷重になるため。

# [NOTE]: init-agent 対象
# copilot cli: if [ "$TOOL" = "edit" ] || [ "$TOOL" = "create" ]; then
# claude code: if [ "$TOOL" = "Edit" ] || [ "$TOOL" = "Write" ]; then
# codex: if [ "$TOOL" = "apply_patch" ]; then
if 
  FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

  # ファイルパスが取れなければスキップ
  [ -z "$FILE" ] && exit 0

  # テストファイル自体は TDD の Red フェーズ。deny 対象外(棄権して settings に委ねる)
  echo "$FILE" | grep -q '\.test\.' && exit 0

  # 対応するテストファイルが存在するか確認
  DIR=$(dirname "$FILE")
  BASE=$(basename "$FILE" | sed 's/\.[^.]*$//')
  EXT=$(basename "$FILE" | sed 's/^.*\.//')

  # ロジックファイル(ts/js)のみ対象。tsx/jsx は意図的な除外 — コンポーネントのテストは
  # モックや {} での辻褄合わせに堕ちやすく強制する価値が薄いため、テストを門前払いの
  # 条件にしない(書きたければ tdd-run に任意で乗せられる)。.md .json .sh 等も対象外
  case "$EXT" in
    ts|js) ;;
    *) exit 0 ;;
  esac

  TEST_FILE="$DIR/$BASE.test.$EXT"

  if [ ! -f "$TEST_FILE" ]; then
    jq -n --arg r "テストファイル($TEST_FILE)が無い状態でのコード実装は禁止です。直接実装せず、tdd-run スキルの TDD フロー（シナリオ → Red → Green → Refactor）に乗せてください。" \
      '{
        "hookSpecificOutput": {
          "hookEventName": "PreToolUse",
          "permissionDecision": "deny",
          "permissionDecisionReason": $r
        }
      }'
    exit 0
  fi

  # 対応テストがあるコード本体 = 棄権して settings の permission 層に委ねる。
  # 自動化(allow Edit(**)/Write(**))も停止(ask: auth/migrations 等)も settings が決める
  exit 0
fi

exit 0
