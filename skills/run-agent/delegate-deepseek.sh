#!/bin/bash
# OpenCode + OpenRouter + DeepSeek を、読み取り専用調査または隔離実装として実行する。
set -u

readonly SOFT_BUDGET_USD="38"
readonly HARD_BUDGET_USD="40"
readonly MODEL="openrouter/~deepseek/deepseek-v4-flash-latest"
readonly MODEL_ID="~deepseek/deepseek-v4-flash-latest"
readonly MODEL_VARIANT="high"
readonly OPENROUTER_KEY_ENDPOINT="https://openrouter.ai/api/v1/key"
readonly TASK_ID_PATTERN='^[a-z0-9][a-z0-9-]{0,62}$'

MODE="${1:-}"
TASK_ID="${2:-}"
SPEC_PATH="${3:-}"
shift "$(( $# >= 3 ? 3 : $# ))"

fail() {
  printf 'delegate-deepseek: %s\n' "$1" >&2
  exit 1
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

[ "$MODE" = "research" ] || [ "$MODE" = "implement" ] || fail "mode must be research or implement"
[[ "$TASK_ID" =~ $TASK_ID_PATTERN ]] || fail "task id must be lowercase kebab-case"
command -v git >/dev/null 2>&1 || fail "git is required"
command -v jq >/dev/null 2>&1 || fail "jq is required"
command -v curl >/dev/null 2>&1 || fail "curl is required"
command -v opencode >/dev/null 2>&1 || fail "opencode is required"
[ -n "${OPENROUTER_API_KEY:-}" ] || fail "OPENROUTER_API_KEY is not set"

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || fail "not inside a git repository"
cd "$REPO_ROOT" || fail "cannot enter repository root"

validate_repo_path "$SPEC_PATH"
[ -f "$SPEC_PATH" ] || fail "spec file not found: $SPEC_PATH"

RESULT_ROOT="$REPO_ROOT/.[agent_name]/tmp/deepseek/$TASK_ID"
[ ! -e "$RESULT_ROOT" ] || fail "result already exists: $RESULT_ROOT"
mkdir -p "$RESULT_ROOT" || fail "cannot create result directory"

TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/delegate-deepseek.XXXXXX") || fail "cannot create temporary directory"
WORKTREE="$TEMP_ROOT/worktree"
CURL_CONFIG="$TEMP_ROOT/curl.conf"
WORKTREE_ADDED=0

cleanup() {
  if [ "$WORKTREE_ADDED" -eq 1 ]; then
    git worktree remove --force "$WORKTREE" >/dev/null 2>&1 || true
  fi
  rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT INT TERM

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

git worktree add --detach "$WORKTREE" HEAD >/dev/null || fail "cannot create isolated worktree"
WORKTREE_ADDED=1
mkdir -p "$WORKTREE/.deepseek-request" || fail "cannot create delegated request directory"
cp "$REPO_ROOT/$SPEC_PATH" "$WORKTREE/.deepseek-request/spec.md" || fail "cannot copy spec into isolated worktree"

ALLOWED_PATHS=()
if [ "$MODE" = "implement" ]; then
  [ "$#" -gt 0 ] || fail "implement mode requires at least one allowed production path"
  for path in "$@"; do
    validate_repo_path "$path"
    case "$path" in
      *.test.*|*.spec.*|*/test/*|*/tests/*|*/__tests__/*|*.snap|*fixture*|*mock*|*stub*|*fake*) fail "test assets cannot be delegated: $path" ;;
      AGENTS.md|*/AGENTS.md|*.md|package.json|*/package.json|*lock*.json|*.lock|*.toml|*.yaml|*.yml|*.env|*.env.*|*/migrations/*|*.prisma) fail "protected path cannot be delegated: $path" ;;
    esac
    [ -z "$(git status --porcelain -- "$path")" ] || fail "allowed path has uncommitted changes: $path"
    ALLOWED_PATHS+=("$path")
  done
fi

EDIT_RULES='{"*":"deny"}'
if [ "$MODE" = "implement" ]; then
  for path in "${ALLOWED_PATHS[@]}"; do
    EDIT_RULES=$(printf '%s' "$EDIT_RULES" | jq -c --arg path "$path" '. + {($path): "allow"}') || fail "cannot build edit allowlist"
  done
fi

jq -cn \
  --argjson permission_edit "$EDIT_RULES" \
  --arg model_id "$MODEL_ID" \
  --arg model_variant "$MODEL_VARIANT" '
  {
    "$schema":"https://opencode.ai/config.json",
    "share":"disabled",
    "permission":{
      "*":"deny",
      "read":{
        "*":"allow",
        "*.env":"deny",
        "*.env.*":"deny",
        "**/.env":"deny",
        "**/.env.*":"deny",
        ".git/**":"deny",
        ".codex/**":"deny",
        ".claude/**":"deny",
        ".agents/**":"deny"
      },
      "glob":"allow",
      "grep":"allow",
      "list":"allow",
      "lsp":"allow",
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

if [ "$MODE" = "research" ]; then
  PROMPT="設計案 .deepseek-request/spec.md のためにコードベースを調査してください。変更は禁止です。根拠を file:line で示し、不明点と設計上のリスクを報告してください。"
else
  ALLOWED_LIST=$(printf '%s\n' "${ALLOWED_PATHS[@]}" | sed 's/^/- /')
  PROMPT="承認済み設計 .deepseek-request/spec.md に従い、次の本体コードだけを実装してください。テスト、設計、設定、Gitは変更禁止です。テストに穴・矛盾・曖昧さを見つけた場合は変更せず consultation_required として根拠を報告してください。許可ファイル:\n$ALLOWED_LIST"
fi

cd "$WORKTREE" || fail "cannot enter isolated worktree"
set +e
env -i \
  HOME="$HOME" \
  PATH="$PATH" \
  LANG="${LANG:-C.UTF-8}" \
  TERM="${TERM:-dumb}" \
  OPENROUTER_API_KEY="$OPENROUTER_API_KEY" \
  OPENCODE_CONFIG="$TEMP_ROOT/opencode.json" \
  OPENCODE_DISABLE_AUTOUPDATE=true \
  opencode --pure run --format json --model "$MODEL" --variant "$MODEL_VARIANT" "$PROMPT" > "$RESULT_ROOT/opencode.jsonl" 2> "$RESULT_ROOT/opencode.stderr"
OPENCODE_STATUS=$?
set -e

rm -rf "$WORKTREE/.deepseek-request"

if [ "$MODE" = "implement" ]; then
  git add -N -- "${ALLOWED_PATHS[@]}" >/dev/null 2>&1 || true
fi

CHANGED_PATHS=()
while IFS= read -r -d '' changed; do
  CHANGED_PATHS+=("$changed")
done < <(git diff --name-only -z)
while IFS= read -r -d '' changed; do
  CHANGED_PATHS+=("$changed")
done < <(git ls-files --others --exclude-standard -z)
for changed in "${CHANGED_PATHS[@]}"; do
  allowed=false
  for path in "${ALLOWED_PATHS[@]}"; do
    [ "$changed" = "$path" ] && allowed=true
  done
  [ "$allowed" = true ] || fail "DeepSeek changed a protected path: $changed"
done

if [ "$MODE" = "implement" ]; then
  git diff --binary -- "${ALLOWED_PATHS[@]}" > "$RESULT_ROOT/candidate.patch" || fail "cannot create candidate patch"
else
  : > "$RESULT_ROOT/candidate.patch"
fi

jq -n \
  --arg mode "$MODE" \
  --arg task_id "$TASK_ID" \
  --arg model "$MODEL" \
  --arg model_variant "$MODEL_VARIANT" \
  --argjson opencode_status "$OPENCODE_STATUS" \
  --argjson usage_current "$CURRENT_USAGE" \
  --arg limit_reset "$KEY_RESET" \
  --argjson changed_paths "$(printf '%s\n' "${CHANGED_PATHS[@]}" | jq -Rsc 'split("\n") | map(select(length > 0))')" \
  '{mode:$mode,task_id:$task_id,model:$model,model_variant:$model_variant,opencode_status:$opencode_status,usage_before:$usage_current,limit_reset:$limit_reset,changed_paths:$changed_paths}' \
  > "$RESULT_ROOT/result.json" || fail "cannot create result metadata"

printf 'result: %s\n' "$RESULT_ROOT"
[ "$OPENCODE_STATUS" -eq 0 ] || exit "$OPENCODE_STATUS"
