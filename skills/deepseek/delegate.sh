#!/bin/bash
# OpenCode + OpenRouter + DeepSeek を、読み取り専用調査または隔離実装として共通実行する。
set -u

readonly SOFT_BUDGET_USD="38"
readonly HARD_BUDGET_USD="40"
readonly MODEL="openrouter/~deepseek/deepseek-v4-flash-latest"
readonly MODEL_ID="~deepseek/deepseek-v4-flash-latest"
readonly MODEL_VARIANT="high"
readonly SURVEY_SCOPE_COUNT="4"
readonly SURVEY_STEPS_PER_SCOPE="3"
readonly SURVEY_MAX_STEPS="$((SURVEY_SCOPE_COUNT * SURVEY_STEPS_PER_SCOPE))"
readonly SMOKE_PROMPT="hello"
readonly SMOKE_ERROR_LINE_LIMIT="20"
readonly OPENROUTER_KEY_ENDPOINT="https://openrouter.ai/api/v1/key"
readonly TASK_ID_PATTERN='^[a-z0-9][a-z0-9-]{0,62}$'

MODE="${1:-}"
TASK_ID="${2:-}"
SPEC_PATH="${3:-}"
DIRECT_INSTRUCTION="${3:-}"
NESTING_PATHS=()

fail() {
  printf 'deepseek: %s\n' "$1" >&2
  exit 1
}

extract_report() {
  jq -rs '
    [
      .[]
      | select(.type == "text")
      | (.part.text // .text // empty)
      | select(type == "string" and test("[^[:space:]]"))
    ]
    | last // "DeepSeek returned no textual report. Inspect opencode.jsonl."
  ' "$1"
}

validate_repo_path() {
  local path="$1"
  local cursor="$REPO_ROOT"
  local segment

  case "$path" in
    ''|/*|./*|../*|*/../*|*/..|*//* ) fail "path must be normalized and repository-relative: $path" ;;
  esac
  IFS='/' read -r -a segments <<< "$path"
  for segment in "${segments[@]}"; do
    cursor="$cursor/$segment"
    [ ! -L "$cursor" ] || fail "symlink paths cannot be delegated: $path"
  done
}

case "$MODE" in
  research|implement)
    [[ "$TASK_ID" =~ $TASK_ID_PATTERN ]] || fail "task id must be lowercase kebab-case"
    [ "$#" -ge 3 ] || fail "$MODE mode requires task id and spec path"
    shift 3
    ;;
  survey)
    [[ "$TASK_ID" =~ $TASK_ID_PATTERN ]] || fail "task id must be lowercase kebab-case"
    [ "$#" -eq 3 ] || fail "survey mode requires task id and instruction"
    [ -n "$DIRECT_INSTRUCTION" ] || fail "survey instruction must not be empty"
    shift 3
    ;;
  errand)
    [[ "$TASK_ID" =~ $TASK_ID_PATTERN ]] || fail "task id must be lowercase kebab-case"
    [ "$#" -ge 5 ] || fail "errand mode requires task id, instruction, --, and production paths"
    [ -n "$DIRECT_INSTRUCTION" ] || fail "errand instruction must not be empty"
    [ "$4" = "--" ] || fail "errand mode requires -- before production paths"
    shift 4
    ;;
  nesting)
    [[ "$TASK_ID" =~ $TASK_ID_PATTERN ]] || fail "task id must be lowercase kebab-case"
    [ "$#" -ge 3 ] || fail "nesting mode requires task id and at least one production path"
    shift 2
    NESTING_PATHS=("$@")
    ;;
  smoke)
    [ "$#" -eq 1 ] || fail "smoke mode does not accept arguments"
    ;;
  show)
    [[ "$TASK_ID" =~ $TASK_ID_PATTERN ]] || fail "task id must be lowercase kebab-case"
    [ "$#" -eq 2 ] || fail "show mode requires task id"
    ;;
  *) fail "mode must be research, survey, implement, errand, nesting, smoke, or show" ;;
esac
command -v git >/dev/null 2>&1 || fail "git is required"
command -v jq >/dev/null 2>&1 || fail "jq is required"

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || fail "not inside a git repository"
cd "$REPO_ROOT" || fail "cannot enter repository root"

if [ "$MODE" = "show" ]; then
  RESULT_ROOT="$REPO_ROOT/.[agent_name]/tmp/deepseek/$TASK_ID"
  [ -f "$RESULT_ROOT/result.json" ] || fail "result metadata not found: $RESULT_ROOT/result.json"
  [ -f "$RESULT_ROOT/candidate.patch" ] || fail "candidate patch not found: $RESULT_ROOT/candidate.patch"
  printf '%s\n' 'metadata:'
  jq . "$RESULT_ROOT/result.json" || fail "cannot read result metadata"
  printf '%s\n' 'report:'
  if [ -f "$RESULT_ROOT/report.md" ]; then
    cat "$RESULT_ROOT/report.md" || fail "cannot read result report"
  else
    [ -f "$RESULT_ROOT/opencode.jsonl" ] || fail "result report source not found: $RESULT_ROOT/opencode.jsonl"
    extract_report "$RESULT_ROOT/opencode.jsonl" || fail "cannot extract legacy result report"
  fi
  if [ -s "$RESULT_ROOT/candidate.patch" ]; then
    printf '%s\n' 'candidate.patch:'
    cat "$RESULT_ROOT/candidate.patch" || fail "cannot read candidate patch"
  fi
  exit 0
fi

command -v curl >/dev/null 2>&1 || fail "curl is required"
command -v opencode >/dev/null 2>&1 || fail "opencode is required"
[ -n "${OPENROUTER_API_KEY:-}" ] || fail "OPENROUTER_API_KEY is not set"

if [ "$MODE" = "research" ] || [ "$MODE" = "implement" ]; then
  validate_repo_path "$SPEC_PATH"
  [ -f "$SPEC_PATH" ] || fail "spec file not found: $SPEC_PATH"
fi

if [ "$MODE" = "nesting" ]; then
  for path in "${NESTING_PATHS[@]}"; do
    validate_repo_path "$path"
    case "$path" in
      *.test.*|*.spec.*|*/test/*|*/tests/*|*/__tests__/*|*.snap|*fixture*|*mock*|*stub*|*fake*) fail "test assets cannot be inspected for nesting: $path" ;;
      AGENTS.md|*/AGENTS.md|*.md|package.json|*/package.json|*lock*.json|*.lock|*.toml|*.yaml|*.yml|*.env|*.env.*|*/migrations/*|*.prisma) fail "protected path cannot be inspected for nesting: $path" ;;
    esac
    git ls-files --error-unmatch -- "$path" >/dev/null 2>&1 || fail "nesting path must be tracked: $path"
  done
fi

TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/delegate-deepseek.XXXXXX") || fail "cannot create temporary directory"
WORKTREE="$TEMP_ROOT/worktree"
CURL_CONFIG="$TEMP_ROOT/curl.conf"
WORKTREE_ADDED=0
RESULT_ROOT=""
RESULT_STAGING=""

cleanup() {
  if [ "$WORKTREE_ADDED" -eq 1 ]; then
    git worktree remove --force "$WORKTREE" >/dev/null 2>&1 || true
  fi
  if [ -n "$RESULT_STAGING" ] && [ -d "$RESULT_STAGING" ]; then
    rm -rf "$RESULT_STAGING"
  fi
  rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if [ "$MODE" != "smoke" ]; then
  RESULT_ROOT="$REPO_ROOT/.[agent_name]/tmp/deepseek/$TASK_ID"
  [ ! -e "$RESULT_ROOT" ] || fail "result already exists: $RESULT_ROOT"
  RESULT_PARENT=${RESULT_ROOT%/*}
  mkdir -p "$RESULT_PARENT" || fail "cannot create result parent directory"
  RESULT_STAGING=$(mktemp -d "$RESULT_PARENT/.${TASK_ID}.incomplete.XXXXXX") || fail "cannot create staging result directory"
fi

umask 077
printf 'header = "Authorization: Bearer %s"\nsilent\nshow-error\nfail\n' "$OPENROUTER_API_KEY" > "$CURL_CONFIG" || fail "cannot prepare budget request"
KEY_INFO=$(curl --config "$CURL_CONFIG" "$OPENROUTER_KEY_ENDPOINT") || fail "cannot read OpenRouter key usage"
USAGE_MONTHLY=$(printf '%s' "$KEY_INFO" | jq -er '.data.usage_monthly') || fail "OpenRouter response has no monthly usage"
KEY_LIMIT=$(printf '%s' "$KEY_INFO" | jq -er '.data.limit') || fail "OpenRouter API key must have a hard limit"
KEY_RESET=$(printf '%s' "$KEY_INFO" | jq -r '.data.limit_reset // "none"') || fail "cannot read OpenRouter key reset period"
case "$KEY_RESET" in
  monthly) CURRENT_USAGE="$USAGE_MONTHLY" ;;
  none) CURRENT_USAGE=$(printf '%s' "$KEY_INFO" | jq -er '.data.usage') || fail "OpenRouter response has no total usage" ;;
  *) fail "API key hard limit must reset monthly or never" ;;
esac
jq -ne --argjson usage "$CURRENT_USAGE" --argjson soft "$SOFT_BUDGET_USD" '$usage < $soft' >/dev/null || fail "soft budget exceeded: $CURRENT_USAGE USD"
jq -ne --argjson limit "$KEY_LIMIT" --argjson hard "$HARD_BUDGET_USD" '$limit <= $hard' >/dev/null || fail "API key hard limit exceeds $HARD_BUDGET_USD USD"

if [ "$MODE" != "smoke" ]; then
  git worktree add --detach "$WORKTREE" HEAD >/dev/null || fail "cannot create isolated worktree"
  WORKTREE_ADDED=1
fi

if [ "$MODE" = "research" ] || [ "$MODE" = "implement" ]; then
  mkdir -p "$WORKTREE/.deepseek-request" || fail "cannot create delegated request directory"
  cp "$REPO_ROOT/$SPEC_PATH" "$WORKTREE/.deepseek-request/spec.md" || fail "cannot copy spec into isolated worktree"
fi

ALLOWED_PATHS=()
if [ "$MODE" = "implement" ] || [ "$MODE" = "errand" ]; then
  [ "$#" -gt 0 ] || fail "$MODE mode requires at least one allowed production path"
  for path in "$@"; do
    validate_repo_path "$path"
    case "$path" in
      *.test.*|*.spec.*|*/test/*|*/tests/*|*/__tests__/*|*.snap|*fixture*|*mock*|*stub*|*fake*) fail "test assets cannot be delegated: $path" ;;
      AGENTS.md|*/AGENTS.md|*.md|package.json|*/package.json|*lock*.json|*.lock|*.toml|*.yaml|*.yml|*.env|*.env.*|*/migrations/*|*.prisma) fail "protected path cannot be delegated: $path" ;;
    esac
    if [ -e "$REPO_ROOT/$path" ]; then
      git ls-files --error-unmatch -- "$path" >/dev/null 2>&1 || fail "existing allowed path must be tracked: $path"
    else
      parent=${path%/*}
      [ "$parent" != "$path" ] || parent="."
      [ -d "$REPO_ROOT/$parent" ] || fail "new allowed path parent must exist: $path"
      git check-ignore -q -- "$path" && fail "new allowed path must not be ignored: $path"
    fi
    [ -z "$(git status --porcelain -- "$path")" ] || fail "allowed path has uncommitted changes: $path"
    ALLOWED_PATHS+=("$path")
  done
fi

EDIT_RULES='{"*":"deny"}'
if [ "$MODE" = "implement" ] || [ "$MODE" = "errand" ]; then
  for path in "${ALLOWED_PATHS[@]}"; do
    EDIT_RULES=$(printf '%s' "$EDIT_RULES" | jq -c --arg path "$path" '. + {($path): "allow"}') || fail "cannot build edit allowlist"
  done
fi

jq -cn \
  --argjson permission_edit "$EDIT_RULES" \
  --arg model_id "$MODEL_ID" \
  --arg model_variant "$MODEL_VARIANT" \
  --argjson survey_max_steps "$SURVEY_MAX_STEPS" \
  --arg mode "$MODE" '
  {
    "$schema":"https://opencode.ai/config.json",
    "share":"disabled",
    "default_agent":"delegate",
    "agent":{
      "delegate":({
        "description":"Execute the fixed delegated task"
      } + (if $mode == "survey" then {"steps":$survey_max_steps} else {} end))
    },
    "permission":{
      "*":"deny",
      "read":(if $mode == "smoke" then "deny" else {
          "*":"allow",
          "*.env":"deny",
          "*.env.*":"deny",
          "**/.env":"deny",
          "**/.env.*":"deny",
          ".git/**":"deny",
          ".codex/**":"deny",
          ".claude/**":"deny",
          ".agents/**":"deny"
        } end),
      "glob":(if $mode == "smoke" then "deny" else "allow" end),
      "grep":(if $mode == "smoke" then "deny" else "allow" end),
      "list":(if $mode == "smoke" then "deny" else "allow" end),
      "lsp":(if $mode == "smoke" then "deny" else "allow" end),
      "edit":$permission_edit,
      "bash":"deny",
      "task":"deny",
      "external_directory":"deny",
      "webfetch":"deny",
      "websearch":"deny",
      "skill":"deny",
      "question":"deny",
      "doom_loop":"deny"
    },
    "provider":{
      "openrouter":{
        "models":{
          ($model_id):{
            "options":{
              "reasoningEffort":$model_variant,
              "provider":{
                "zdr":true,
                "data_collection":"deny"
              }
            },
            "variants":{
              ($model_variant):{
                "reasoningEffort":$model_variant
              }
            }
          }
        }
      }
    }
  }
' > "$TEMP_ROOT/opencode.json" || fail "cannot create OpenCode config"

if [ "$MODE" = "smoke" ]; then
  PROMPT="$SMOKE_PROMPT"
  EXECUTION_ROOT="$REPO_ROOT"
  OPENCODE_OUTPUT="$TEMP_ROOT/opencode.jsonl"
  OPENCODE_ERROR="$TEMP_ROOT/opencode.stderr"
elif [ "$MODE" = "research" ]; then
  PROMPT="設計案 .deepseek-request/spec.md のためにコードベースを調査してください。変更は禁止です。根拠を file:line で示し、不明点と設計上のリスクを報告してください。"
  EXECUTION_ROOT="$WORKTREE"
  OPENCODE_OUTPUT="$RESULT_STAGING/opencode.jsonl"
  OPENCODE_ERROR="$RESULT_STAGING/opencode.stderr"
elif [ "$MODE" = "survey" ]; then
  PROMPT="次の調査依頼についてコードベースを読み取り専用で調査してください。変更は禁止です。調査指示に含まれる識別子、パス、番号、固有名詞を省略・言い換えず保持してください。識別子の完全一致と指定パス、機能語・ドメイン語、隣接モジュール、リポジトリ全体の順に調査範囲を広げ、現在の範囲で直接根拠が足りない場合だけ次へ進んでください。調査依頼が類似機能の全体探索を明示する場合、または狭い範囲で根拠を得られない場合はリポジトリ全体を調べてください。調査依頼へ回答できる根拠が揃った時点で直ちに終了し、依頼が求めていない設定、DB、schema、migration、テストを網羅監査してはなりません。調査範囲内の根拠を file:line で示し、不明点と確認できた反証候補を報告してください。調査依頼:\n$DIRECT_INSTRUCTION"
  EXECUTION_ROOT="$WORKTREE"
  OPENCODE_OUTPUT="$RESULT_STAGING/opencode.jsonl"
  OPENCODE_ERROR="$RESULT_STAGING/opencode.stderr"
elif [ "$MODE" = "nesting" ]; then
  NESTING_LIST=$(printf '%s\n' "${NESTING_PATHS[@]}" | sed 's/^/- /')
  PROMPT="次の本体コードだけを読み取り専用で検査してください。修正案・コード変更は不要です。if/else、loop、switch、try/catch/finally が同じ実行経路で三段階以上重なる候補だけを検出し、各候補を file:line、最大深さ、到達条件、該当する制御構造の順で報告してください。else if は一つの選択、switch の case は switch より深く数えません。候補が無ければ『3段階以上の制御フローネストなし』と明記してください。指定外のファイルは検出対象にしません。対象ファイル:\n$NESTING_LIST"
  EXECUTION_ROOT="$WORKTREE"
  OPENCODE_OUTPUT="$RESULT_STAGING/opencode.jsonl"
  OPENCODE_ERROR="$RESULT_STAGING/opencode.stderr"
elif [ "$MODE" = "implement" ]; then
  ALLOWED_LIST=$(printf '%s\n' "${ALLOWED_PATHS[@]}" | sed 's/^/- /')
  PROMPT="承認済み設計 .deepseek-request/spec.md に従い、次の本体コードだけを実装してください。テスト、設計、設定、Gitは変更禁止です。テストに穴・矛盾・曖昧さを見つけた場合は変更せず consultation_required として根拠を報告してください。許可ファイル:\n$ALLOWED_LIST"
  EXECUTION_ROOT="$WORKTREE"
  OPENCODE_OUTPUT="$RESULT_STAGING/opencode.jsonl"
  OPENCODE_ERROR="$RESULT_STAGING/opencode.stderr"
else
  ALLOWED_LIST=$(printf '%s\n' "${ALLOWED_PATHS[@]}" | sed 's/^/- /')
  PROMPT="次の短い実装指示に従い、許可された本体コードだけを実装してください。テスト、設定、Git、設計資産を変更させないでください。要件が曖昧、または許可外の変更が必要なら変更せず consultation_required として根拠を報告してください。実装指示:\n$DIRECT_INSTRUCTION\n許可ファイル:\n$ALLOWED_LIST"
  EXECUTION_ROOT="$WORKTREE"
  OPENCODE_OUTPUT="$RESULT_STAGING/opencode.jsonl"
  OPENCODE_ERROR="$RESULT_STAGING/opencode.stderr"
fi

cd "$EXECUTION_ROOT" || fail "cannot enter execution root"
set +e
env -i \
  HOME="$HOME" \
  PATH="$PATH" \
  LANG="${LANG:-C.UTF-8}" \
  TERM="${TERM:-dumb}" \
  OPENROUTER_API_KEY="$OPENROUTER_API_KEY" \
  OPENCODE_CONFIG="$TEMP_ROOT/opencode.json" \
  OPENCODE_DISABLE_AUTOUPDATE=true \
  opencode --pure run --agent delegate --format json --model "$MODEL" --variant "$MODEL_VARIANT" "$PROMPT" > "$OPENCODE_OUTPUT" 2> "$OPENCODE_ERROR"
OPENCODE_STATUS=$?
set -e

if [ "$MODE" = "smoke" ]; then
  [ "$OPENCODE_STATUS" -eq 0 ] || { sed -n "1,${SMOKE_ERROR_LINE_LIMIT}p" "$OPENCODE_ERROR" >&2; fail "smoke request failed with status $OPENCODE_STATUS"; }
  [ -s "$OPENCODE_OUTPUT" ] || fail "smoke request returned no events"
  printf 'smoke: ok model=%s variant=%s\n' "$MODEL" "$MODEL_VARIANT"
  exit 0
fi

if [ "$MODE" = "research" ] || [ "$MODE" = "implement" ]; then
  rm -rf "$WORKTREE/.deepseek-request"
fi

extract_report "$OPENCODE_OUTPUT" > "$RESULT_STAGING/report.md" || fail "cannot extract DeepSeek report"

if [ "$MODE" = "implement" ] || [ "$MODE" = "errand" ]; then
  git add -N -- "${ALLOWED_PATHS[@]}" >/dev/null 2>&1 || true
fi

CHANGED_PATHS=()
while IFS= read -r -d '' changed; do
  CHANGED_PATHS+=("$changed")
done < <(git diff --name-only -z)
while IFS= read -r -d '' changed; do
  CHANGED_PATHS+=("$changed")
done < <(git ls-files --others --exclude-standard -z)
if [ "${#CHANGED_PATHS[@]}" -gt 0 ]; then
  for changed in "${CHANGED_PATHS[@]}"; do
    allowed=false
    if [ "${#ALLOWED_PATHS[@]}" -gt 0 ]; then
      for path in "${ALLOWED_PATHS[@]}"; do
        [ "$changed" = "$path" ] && allowed=true
      done
    fi
    [ "$allowed" = true ] || fail "DeepSeek changed a protected path: $changed"
  done
  CHANGED_PATHS_JSON=$(printf '%s\n' "${CHANGED_PATHS[@]}" | jq -Rsc 'split("\n") | map(select(length > 0))') || fail "cannot serialize changed paths"
else
  CHANGED_PATHS_JSON='[]'
fi

if [ "$MODE" = "implement" ] || [ "$MODE" = "errand" ]; then
  git diff --binary -- "${ALLOWED_PATHS[@]}" > "$RESULT_STAGING/candidate.patch" || fail "cannot create candidate patch"
else
  : > "$RESULT_STAGING/candidate.patch"
fi

jq -n \
  --arg mode "$MODE" \
  --arg task_id "$TASK_ID" \
  --arg model "$MODEL" \
  --arg model_variant "$MODEL_VARIANT" \
  --arg report_file "report.md" \
  --argjson survey_max_steps "$SURVEY_MAX_STEPS" \
  --argjson opencode_status "$OPENCODE_STATUS" \
  --argjson usage_current "$CURRENT_USAGE" \
  --arg limit_reset "$KEY_RESET" \
  --argjson changed_paths "$CHANGED_PATHS_JSON" \
  '{mode:$mode,task_id:$task_id,model:$model,model_variant:$model_variant,opencode_status:$opencode_status,usage_before:$usage_current,limit_reset:$limit_reset,changed_paths:$changed_paths,report_file:$report_file,step_limit:(if $mode == "survey" then $survey_max_steps else null end)}' \
  > "$RESULT_STAGING/result.json" || fail "cannot create result metadata"

mv "$RESULT_STAGING" "$RESULT_ROOT" || fail "cannot publish result directory"
RESULT_STAGING=""

printf 'result: %s\n' "$RESULT_ROOT"
printf '%s\n' 'report:'
cat "$RESULT_ROOT/report.md"
[ "$OPENCODE_STATUS" -eq 0 ] || exit "$OPENCODE_STATUS"
