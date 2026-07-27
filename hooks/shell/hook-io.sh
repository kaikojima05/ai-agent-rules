#!/bin/bash
# hook-io: PreToolUse hook の入出力スキーマ差分をエージェント種別ごとに吸収するアダプタ。
# 各 hook は stdin の JSON や決定 JSON の形式に直接触れず、本ファイルの関数だけを使う。
# Why: [NOTE] 機構が吸収するのはツール名の差分だけで、入力(.tool_name / .tool_input)と
#      出力(hookSpecificOutput)のスキーマは Claude Code 固有のまま各 hook に散っていた。
#      スキーマの読み書きを本ファイルへ集約し、エージェント追加時はここへの分岐追加だけで
#      済ませる。
# 使い方: hook 冒頭で `. "$(dirname "$0")/hook-io.sh"` と source する。
#         source 時点で stdin を読み切り HOOK_INPUT へ保持する。
# 決定 hook の共通契約: stdout には決定 JSON 以外を出さない。stderr は各 hook が冒頭の
#         exec 2>/dev/null で捨てる（jq 等サブプロセスのエラー文字混入を断つ）。
# エージェント名 placeholder は配置後に init-agent が確定させる。

HOOK_AGENT="[agent_name]"

# 未実装エージェントの即死: スキーマ不明のまま進むと jq が空を返し「全ファイル素通し」
# という最悪の静かな故障になるため、判定せず非ゼロで終了する。
# codex: main ソース + 実機 probe（v0.145.0、2026-07-27）で入出力とも Claude 互換を
#   確定済み。Bash 系は {"command": <文字列>}、apply_patch は {"command": <パッチ全文>}
#   で file_path 無し → hook_file_paths がパッチを解析する
case "$HOOK_AGENT" in
  claude|codex) ;;
  *) exit 1 ;;
esac

# jq 不在は全 hook の静かな無効化（空抽出 → 全件素通し）になるため、判定せず非ゼロで終了する
command -v jq >/dev/null 2>&1 || exit 1

HOOK_INPUT=$(cat)

# 呼び出し元ツールの名前を返す関数
hook_tool_name() { echo "$HOOK_INPUT" | jq -r '.tool_name'; }

# 編集対象のファイルパスを改行区切りで列挙する関数（0 件なら何も出さない）。
# claude: file_path / notebook_path の単一パス。
# codex: apply_patch の tool_input に file_path は無く {"command": "<パッチ全文>"} のみ
#        （main ソース確定 2026-07）のため、パッチの対象ファイル行から抽出する
hook_file_paths() {
  case "$HOOK_AGENT" in
    codex)
      if [ "$(hook_tool_name)" = "apply_patch" ]; then
        echo "$HOOK_INPUT" | jq -r '.tool_input.command // empty' | \
          sed -nE -e 's/^\*\*\* (Add|Update|Delete) File: //p' -e 's/^\*\*\* Move to: //p'
      else
        echo "$HOOK_INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty'
      fi ;;
    *)
      echo "$HOOK_INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' ;;
  esac
}

# 実行されようとしているシェルコマンド文字列を返す関数（取れなければ空）
hook_command() { echo "$HOOK_INPUT" | jq -r '.tool_input.command // empty'; }

# セッション ID を返す関数（取れなければ空）
hook_session_id() { echo "$HOOK_INPUT" | jq -r '.session_id // empty'; }

# 作業ディレクトリを返す関数（取れなければ空）
hook_cwd() { echo "$HOOK_INPUT" | jq -r '.cwd // empty'; }

# UserPromptSubmit のプロンプト文字列を返す関数（取れなければ空）
hook_prompt() { echo "$HOOK_INPUT" | jq -r '.prompt // empty'; }

# hook イベント名（PreToolUse / UserPromptSubmit / SessionEnd 等）を返す関数
hook_event_name() { echo "$HOOK_INPUT" | jq -r '.hook_event_name // empty'; }

# skill-session marker のパスを返す関数（codex の skill スコープ再現に使う）。
# セッション別のファイル名にして、並行セッション同士の上書き競合を構造的に無くす。
# 残留 marker は別 session_id のファイルなので無害（SessionEnd の掃除でも消える）
hook_skill_session_file() { echo "$(hook_cwd)/.codex/tmp/skill-session.$1.$(hook_session_id)"; }

# 指定スキルの marker が現在のセッションに存在するか判定する関数
hook_skill_session_active() { [ -f "$(hook_skill_session_file "$1")" ]; }

# 決定 JSON(deny)を stdout へ出し、理由をエージェントに伝えて hook を終える関数
hook_deny() {
  jq -n --arg r "$1" \
    '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":$r}}'
  exit 0
}

# 決定 JSON(ask)を stdout へ出し、人間の確認を 1 回挟ませて hook を終える関数
hook_ask() {
  jq -n --arg r "$1" \
    '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":$r}}'
  exit 0
}
