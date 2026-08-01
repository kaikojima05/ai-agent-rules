#!/bin/bash
# テンプレート全体の回帰テスト。hook・スキル・配布設定を変更したら必ず走らせること。
#   bash tests/verify-all.sh
# 検証内容: 構文 / 実行ビット / claude 配置シム / hook 全数(run-tests.sh) /
#           rebase-squash E2E / codex 配布物・rules 実機検査 / skill-session スコープ / 残渣チェック
# 作業ファイルは一時ディレクトリに作りリポジトリを汚さない（終了時に自動削除）。
set -u
SUITE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SUITE/.." && pwd)"
S=$(mktemp -d "${TMPDIR:-/tmp}/ai-agent-rules-verify.XXXXXX") || { echo "temp dir を作れない" >&2; exit 1; }
trap 'rm -rf "$S"' EXIT
PASS=0; FAIL=0
MIN_SUPPORTED_CODEX_VERSION="0.138.0"
VERSION_COMPONENT_COUNT=3
EXPECTED_DUAL_HOOK_BINDINGS=2
ok(){ PASS=$((PASS+1)); echo "ok   $1"; }
ng(){ FAIL=$((FAIL+1)); echo "FAIL $1"; }
version_at_least(){
  awk -v current="$1" -v minimum="$2" -v count="$VERSION_COMPONENT_COUNT" 'BEGIN {
    split(current, c, "."); split(minimum, m, ".")
    for (i = 1; i <= count; i++) {
      if ((c[i] + 0) > (m[i] + 0)) exit 0
      if ((c[i] + 0) < (m[i] + 0)) exit 1
    }
    exit 0
  }'
}
mcp_tool_approved(){
  awk -v header="[mcp_servers.$1.tools.$2]" '
    $0 == header { getline; if ($0 == "approval_mode = \"approve\"") found = 1 }
    END { exit !found }
  ' "$3"
}
mcp_server_prompts_by_default(){
  awk -v header="[mcp_servers.$1]" '
    $0 == header { in_server = 1; next }
    in_server && /^\[/ { exit !found }
    in_server && $0 == "default_tools_approval_mode = \"prompt\"" { found = 1 }
    END { exit !found }
  ' "$2"
}

command -v jq >/dev/null 2>&1 || { echo "jq が必要" >&2; exit 1; }

echo "== 1. 構文チェック（require-test.sh は [NOTE] 未解決のため配置後に検査） =="
for f in "$REPO"/hooks/shell/*.sh "$REPO"/skills/*/*.sh "$SUITE"/*.sh; do
  case "$f" in */require-test.sh|*/verify-all.sh) continue ;; esac
  if bash -n "$f" 2>/dev/null; then ok "syntax: $(basename "$f")"; else ng "syntax: $f"; fi
done
echo "== 1.5 実行ビット（ハーネスが直接実行する hook は +x 必須。hook-io.sh は source 専用） =="
for f in "$REPO"/hooks/shell/*.sh; do
  case "$f" in */hook-io.sh) continue ;; esac
  [ -x "$f" ] && ok "exec bit: $(basename "$f")" || ng "exec bit 無し: $(basename "$f")"
done

echo "== 2. claude 配置シミュレーション =="
mkdir -p "$S/claude-sim/.claude"
cp "$REPO/AGENTS.md" "$S/claude-sim/"
cp -R "$REPO/hooks" "$S/claude-sim/.claude/hooks"
cp -R "$REPO/skills" "$S/claude-sim/.claude/skills"
cp -R "$REPO/rules" "$S/claude-sim/.claude/rules"
cd "$S/claude-sim"
if bash .claude/skills/init-agent/init-agent.sh claude > init-claude.log 2>&1; then ok "init-agent claude 実行"; else ng "init-agent claude 実行"; cat init-claude.log; fi
bash -n .claude/hooks/shell/require-test.sh 2>/dev/null && ok "解決後 require-test 構文" || ng "解決後 require-test 構文"
grep -q 'HOOK_AGENT="claude"' .claude/hooks/shell/hook-io.sh && ok "hook-io HOOK_AGENT=claude" || ng "hook-io HOOK_AGENT=claude"
grep -q '`\[claude\]: {対象ファイル名}/{変更内容}`' AGENTS.md && ok "AGENTS.md コミットタグ確定" || ng "AGENTS.md コミットタグ確定"
grep -q 'AGENT_TAG="claude"' .claude/skills/rebase-squash/rebase-squash.sh && ok "rebase-squash AGENT_TAG=claude" || ng "rebase-squash AGENT_TAG=claude"
grep -q 'bash .claude/skills/rebase-squash/rebase-squash.sh' .claude/skills/rebase-squash/SKILL.md && ok "[skills_root]→.claude/skills" || ng "[skills_root]→.claude/skills"
LEFT=$(command grep -rlE '\[agent_name\]|\[skills_root\]' AGENTS.md .claude 2>/dev/null | grep -v '/init-agent/' | wc -l | tr -d ' ')
[ "$LEFT" = "0" ] && ok "置換漏れゼロ(claude)" || { ng "置換漏れ $LEFT 件(claude)"; command grep -rlE '\[agent_name\]|\[skills_root\]' AGENTS.md .claude | grep -v '/init-agent/'; }

echo "== 2.5 compose-prompt / run-agent の設計書フロー（claude 配置） =="
AP=".claude/skills/compose-prompt/apply-prompt.sh"
MD=".claude/skills/run-agent/mark-prompt-done.sh"
mkdir -p draft-prompt
printf '# 実装順\n\n- [ ] branch-user-api-prompt.md\n- [ ] branch-user-form-prompt.md\n' > draft-prompt/.prompt.md
echo api > draft-prompt/branch-user-api-prompt.md
echo form > draft-prompt/branch-user-form-prompt.md
bash "$AP" > apply.out 2>&1
if [ -f .claude/prompt/.prompt.md ] && [ -f .claude/prompt/branch-user-api-prompt.md ] && [ -f .claude/prompt/branch-user-form-prompt.md ]; then
  ok "apply-prompt: index と設計書を固定宛先へ反映"
else
  ng "apply-prompt: 固定宛先への反映漏れ"; cat apply.out
fi
[ ! -d draft-prompt ] && ok "apply-prompt: 反映後に draft-prompt/ を畳む" || ng "apply-prompt: draft-prompt/ が残った"
# 引数を受け取らない = 削除先を外から動かせない、が安全性の根拠。引数追加の再発を検知する
grep -q 'SRC_DIR="draft-prompt"' "$AP" && ok "apply-prompt: 移動元がスクリプト内に固定" || ng "apply-prompt: 移動元が固定されていない"

mkdir -p draft-prompt
printf -- '- [ ] branch-billing-prompt.md\n' > draft-prompt/.prompt.md
echo billing > draft-prompt/branch-billing-prompt.md
bash "$AP" > apply2.out 2>&1
if [ -f .claude/prompt/branch-billing-prompt.md ] && [ ! -e .claude/prompt/branch-user-api-prompt.md ] && [ ! -e .claude/prompt/branch-user-form-prompt.md ]; then
  ok "apply-prompt: 前タスクの設計書を残さない"
else
  ng "apply-prompt: 前タスクの設計書が残った"; cat apply2.out
fi

mkdir -p draft-prompt
printf -- '- [ ] branch-a-prompt.md\n' > draft-prompt/.prompt.md
echo a > draft-prompt/branch-a-prompt.md
echo memo > draft-prompt/memo.txt
if bash "$AP" > apply3.out 2>&1; then ng "apply-prompt: 想定外ファイルを通した"; else ok "apply-prompt: 想定外ファイルを拒否"; fi
[ -d draft-prompt ] && ok "apply-prompt: 失敗時は draft-prompt/ を畳まない" || ng "apply-prompt: 失敗時に draft-prompt/ を消した"
rm -f draft-prompt/memo.txt

printf -- '- [ ] branch-a-prompt.md\n- [ ] branch-b-prompt.md\n' > draft-prompt/.prompt.md
if bash "$AP" > apply4.out 2>&1; then ng "apply-prompt: index と実体の食い違いを通した"; else ok "apply-prompt: index と実体の食い違いを拒否"; fi

printf -- '- [ ] branch-a-prompt.md\n- [ ] ../evil.md\n' > draft-prompt/.prompt.md
if bash "$AP" > apply5.out 2>&1; then ng "apply-prompt: 不正な index 行を通した"; else ok "apply-prompt: 不正な index 行を拒否"; fi
rm -rf draft-prompt

bash "$MD" billing > mark.out 2>&1
grep -qE '^\- \[x\] branch-billing-prompt\.md$' .claude/prompt/.prompt.md && ok "mark-prompt-done: index を [x] に倒す" || { ng "mark-prompt-done: [x] に倒せない"; cat mark.out; }
grep -q '^remaining: 0$' mark.out && ok "mark-prompt-done: 残件数を報告" || { ng "mark-prompt-done: 残件数の報告が無い"; cat mark.out; }
if bash "$MD" billing > mark2.out 2>&1; then ng "mark-prompt-done: 二重マークを通した"; else ok "mark-prompt-done: 二重マークを拒否"; fi
if bash "$MD" "../../etc/passwd" > mark3.out 2>&1; then ng "mark-prompt-done: 不正な機能名を通した"; else ok "mark-prompt-done: 不正な機能名を拒否"; fi
if bash "$MD" nonexistent > mark4.out 2>&1; then ng "mark-prompt-done: 未登録の機能名を通した"; else ok "mark-prompt-done: 未登録の機能名を拒否"; fi
rm -rf .claude/prompt

echo "== 3. hook 全数テスト（claude 配置） =="
cp "$SUITE/run-tests.sh" "$S/claude-sim/run-tests.sh"
bash "$S/claude-sim/run-tests.sh" > hook-tests.out 2>&1
tail -3 hook-tests.out
grep -q '^PASS=[0-9]* FAIL=0$' hook-tests.out && ok "hook 全数テスト全緑" || { ng "hook 全数テストに失敗あり"; grep '^FAIL' hook-tests.out; }

echo "== 4. rebase-squash E2E =="
RS="$S/claude-sim/.claude/skills/rebase-squash/rebase-squash.sh"
mkdir "$S/rs" && cd "$S/rs"
git init -q && git config user.email tester@example.com && git config user.name tester
echo base > base.txt && git add base.txt && git commit -qm "chore: base"
echo 1 > f1.ts && git add f1.ts && git commit -qm "[claude]: f1.ts/f1を追加した"
echo 2 > f1.test.ts && git add f1.test.ts && git commit -qm "[claude]: f1.test.ts/f1のテストを追加した"
echo 3 > f2.ts && git add f2.ts && git commit -qm "[claude]: f2.ts/f2を追加した"
BASE=$(git rev-parse HEAD~3)
if bash "$RS" --check --base "$BASE" > check.out 2>&1; then ok "--check 成功"; else ng "--check 失敗"; cat check.out; fi
grep -q "COMMITS 3" check.out && ok "対象3件を認識" || ng "対象件数が不正"
EB=$(grep '^BASE ' check.out | cut -d' ' -f2)
C1=$(git rev-parse HEAD~2); C2=$(git rev-parse HEAD~1); C3=$(git rev-parse HEAD)
printf '{"base":"%s","groups":[{"subject":"[claude]: f1/f1と対応テストを追加した","commits":["%s","%s"]},{"subject":"[claude]: f2.ts/f2を追加した","commits":["%s"]}]}\n' "$EB" "$C1" "$C2" "$C3" > plan.json
TREE_BEFORE=$(git rev-parse 'HEAD^{tree}')
if bash "$RS" plan.json --base "$BASE" > run.out 2>&1; then ok "squash 実行"; else ng "squash 失敗"; cat run.out; fi
[ "$(git rev-list --count "$EB..HEAD")" = "2" ] && ok "3→2 コミットへ縮約" || ng "コミット数が不正"
[ "$(git rev-parse 'HEAD^{tree}')" = "$TREE_BEFORE" ] && ok "tree 同一性" || ng "tree が変わった"
git branch --list 'backup/rebase-squash-*' | grep -q . && ng "backup ブランチが残っている" || ok "成功時に backup ブランチを残さない"
git reflog show HEAD --format=%H | grep -qFx "$C3" && ok "元 HEAD を reflog から辿れる" || ng "元 HEAD が reflog から失われた"
grep -q "$C3" run.out && ok "報告に元 HEAD の sha を含む" || { ng "元 HEAD の sha を報告していない"; cat run.out; }
if bash "$RS" plan.json --base "$BASE" > again.out 2>&1; then ng "base 不一致 plan が通ってしまった"; else ok "base 不一致 plan を拒否"; fi
printf '{"base":"%s","groups":[{"subject":"タグ無し不正subject","commits":["%s"]}]}\n' "$(git rev-parse HEAD)" "$(git rev-parse HEAD)" > bad.json
if bash "$RS" bad.json --base "$(git rev-parse 'HEAD~1')" > bad.out 2>&1; then ng "不正 subject が通ってしまった"; else ok "不正 subject を拒否"; fi
echo 4 > f3.ts && git add f3.ts && git commit -qm "manual: 手動変更"
echo 5 > f4.ts && git add f4.ts && git commit -qm "[claude]: f4.ts/f4を追加した"
bash "$RS" --check --base "$BASE" > b2.out 2>&1
grep -q "COMMITS 1" b2.out && ok "非タグコミットを境界として認識" || { ng "境界判定が不正"; cat b2.out; }

echo "== 5. codex 配置シミュレーション（skills は .agents/skills） =="
mkdir -p "$S/codex-sim/.codex" "$S/codex-sim/.agents"
cp "$REPO/AGENTS.md" "$S/codex-sim/"
cp "$REPO/codex/config.toml" "$S/codex-sim/.codex/"
cp "$REPO/codex/hooks.json" "$S/codex-sim/.codex/"
cp "$REPO/codex/.gitignore" "$S/codex-sim/.codex/"
cp -R "$REPO/hooks" "$S/codex-sim/.codex/hooks"
cp -R "$REPO/rules" "$S/codex-sim/.codex/rules"
cp "$REPO/codex/rules/default.rules" "$S/codex-sim/.codex/rules/"
cp -R "$REPO/prompt" "$S/codex-sim/.codex/prompt"
cp -R "$REPO/e2e" "$S/codex-sim/.codex/e2e"
cp -R "$REPO/skills" "$S/codex-sim/.agents/skills"
cd "$S/codex-sim"
if bash .agents/skills/init-agent/init-agent.sh codex > init-codex.log 2>&1; then ok "init-agent codex 実行"; else ng "init-agent codex 実行"; cat init-codex.log; fi
grep -q '`\[codex\]: {対象ファイル名}/{変更内容}`' AGENTS.md && ok "AGENTS.md → [codex]:" || ng "AGENTS.md → [codex]:"
grep -q 'HOOK_AGENT="codex"' .codex/hooks/shell/hook-io.sh && ok "hook-io HOOK_AGENT=codex" || ng "hook-io HOOK_AGENT=codex"
grep -q '"\$TOOL" = "apply_patch"' .codex/hooks/shell/require-test.sh && ok "[NOTE]→apply_patch" || ng "[NOTE]→apply_patch"
grep -q 'bash .agents/skills/rebase-squash/rebase-squash.sh' .agents/skills/rebase-squash/SKILL.md && ok "[skills_root]→.agents/skills" || ng "[skills_root]→.agents/skills"
grep -q 'AGENT_TAG="codex"' .agents/skills/rebase-squash/rebase-squash.sh && ok "rebase-squash AGENT_TAG=codex" || ng "rebase-squash AGENT_TAG=codex"
LEFT=$(command grep -rlE '\[agent_name\]|\[skills_root\]' AGENTS.md .codex .agents 2>/dev/null | grep -v '/init-agent/' | wc -l | tr -d ' ')
[ "$LEFT" = "0" ] && ok "置換漏れゼロ(codex)" || { ng "置換漏れ $LEFT 件(codex)"; command grep -rlE '\[agent_name\]|\[skills_root\]' AGENTS.md .codex .agents | grep -v '/init-agent/'; }
printf 'codex e2e plan\n' > "$S/e2e-plan.md"
if bash .agents/skills/e2e/apply-e2e-plan.sh "$S/e2e-plan.md" > apply-e2e.out 2>&1 && grep -q '^codex e2e plan$' .codex/e2e/.e2e.md; then
  ok "e2e plan を固定宛先へ反映"
else
  ng "e2e plan の固定宛先反映に失敗"
  cat apply-e2e.out
fi
grep -q '^hooks = true$' .codex/config.toml && ok "config: hooks を明示有効化" || ng "config: hooks が未設定"
grep -q '^default_permissions = "distributed"$' .codex/config.toml && ok "config: distributed permission profile を既定化" || ng "config: permission profile が未設定"
grep -q '^extends = ":workspace"$' .codex/config.toml && ok "permissions: 通常ファイルは workspace write を継承" || ng "permissions: 通常書き込みが未設定"
grep -q '^enabled = false$' .codex/config.toml && grep -q '^allow_local_binding = false$' .codex/config.toml && ok "permissions: localhost を含む network を遮断" || ng "permissions: network 境界が未設定"
if grep -qE '^(sandbox_mode|\[sandbox_workspace_write\])' .codex/config.toml; then
  ng "config: permission profile と旧 sandbox_mode が混在"
else
  ok "config: 旧 sandbox_mode との混在なし"
fi
for READ_PATH in '**/package.json' '**/.github/workflows/**' '**/migrations/**' '**/schema.prisma' '**/Dockerfile*' '**/docker-compose*' '**/*.tf' '**/yarn.lock' '**/package-lock.json' '**/pnpm-lock.yaml' '**/.env' '**/.env.*'; do
  grep -Fq "\"$READ_PATH\" = \"read\"" .codex/config.toml && ok "permissions: $READ_PATH は read" || ng "permissions: $READ_PATH の保護漏れ"
done
if grep -q '@latest' .codex/config.toml || { grep 'git+https://' .codex/config.toml | grep -vqE '@[0-9a-f]{40}'; }; then
  ng "config: MCP に未固定バージョンが残存"
else
  ok "config: MCP 起動バージョンを固定"
fi
grep -q 'chrome-devtools-mcp@[0-9]' .codex/config.toml && ok "config: Chrome MCP のversion固定" || ng "config: Chrome MCP が未固定"
grep -q 'serena-agent==[0-9]' .codex/config.toml && ok "config: Serena MCP のversion固定" || ng "config: Serena MCP が未固定"
for DISABLED_TOOL in replace_symbol_body replace_regex replace_content insert_after_symbol insert_before_symbol; do
  grep -q "\"$DISABLED_TOOL\"" .codex/config.toml && ok "serena: $DISABLED_TOOL を無効化" || ng "serena: $DISABLED_TOOL の無効化漏れ"
done
for MCP_SERVER in serena chrome-devtools; do
  mcp_server_prompts_by_default "$MCP_SERVER" .codex/config.toml && ok "$MCP_SERVER: 未登録toolはprompt" || ng "$MCP_SERVER: 未登録toolのprompt漏れ"
  APPROVED_COUNT=0
  while IFS= read -r MCP_TOOL; do
    APPROVED_COUNT=$((APPROVED_COUNT+1))
    mcp_tool_approved "$MCP_SERVER" "$MCP_TOOL" .codex/config.toml && ok "$MCP_SERVER: $MCP_TOOL を approve" || ng "$MCP_SERVER: $MCP_TOOL の approve 漏れ"
  done < <(jq -r --arg prefix "mcp__${MCP_SERVER}__" '.permissions.allow[] | select(startswith($prefix)) | ltrimstr($prefix)' "$REPO/claude/settings.local.json")
  CONFIGURED_COUNT=$(grep -c "^\[mcp_servers\.$MCP_SERVER\.tools\." .codex/config.toml)
  [ "$CONFIGURED_COUNT" = "$APPROVED_COUNT" ] && ok "$MCP_SERVER: Claude allow 一覧だけ approve" || ng "$MCP_SERVER: 未登録toolのapprove混入"
done
[ -f .codex/prompt/.prompt.md ] && [ -f .codex/e2e/.e2e.md ] && ok "codex seed 配置" || ng "codex seed 配置漏れ"
jq -e . .codex/hooks.json >/dev/null 2>&1 && ok "hooks.json 構文" || ng "hooks.json 構文"
jq -e '[.hooks[][] | .hooks[] | has("timeout")] | all' .codex/hooks.json >/dev/null 2>&1 && ok "hook timeout 全件設定" || ng "hook timeout 設定漏れ"
[ "$(jq '[.hooks.PreToolUse[] | .hooks[].command | select(contains("protect-agent-config.sh"))] | length' .codex/hooks.json)" = "2" ] && ok "設定保護hookを apply_patch/Bash に配線" || ng "設定保護hookの配線漏れ"
[ "$(jq '[.hooks.PreToolUse[] | .hooks[].command | select(contains("protect-lockfiles.sh"))] | length' .codex/hooks.json)" = "$EXPECTED_DUAL_HOOK_BINDINGS" ] && ok "lockfile保護hookを apply_patch/Bash に配線" || ng "lockfile保護hookの配線漏れ"
if jq -e '[.hooks.PreToolUse[] | .hooks[].command | select(contains("guard-overwrite.sh"))] | length == 0' .codex/hooks.json >/dev/null; then
  ok "未対応 ask hook を codex へ未配線"
else
  ng "未対応 ask hook が codex に配線されている"
fi
MISSING_HOOKS=0
for SCRIPT in $(jq -r '.hooks[][] | .hooks[].command' .codex/hooks.json | sed -nE 's|.*\.codex/hooks/shell/([^"/]+).*|\1|p' | sort -u); do
  [ -x ".codex/hooks/shell/$SCRIPT" ] || { ng "hook 参照先が存在しない: $SCRIPT"; MISSING_HOOKS=1; }
done
[ "$MISSING_HOOKS" = "0" ] && ok "hook 参照先が全件実行可能"
OUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"git rebase"}}' | bash .codex/hooks/shell/deny-history-rewrite.sh)
[ "$(echo "$OUT" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null)" = "deny" ] && ok "codex: git rebase を deny" || ng "codex: rebase deny 失敗 out=[$OUT]"

echo "== 5.25 codex config / rules 実機検査 =="
if command -v codex >/dev/null 2>&1; then
  CODEX_VERSION=$(codex --version | awk '{print $2}')
  if version_at_least "$CODEX_VERSION" "$MIN_SUPPORTED_CODEX_VERSION"; then
    ok "codex $CODEX_VERSION は最低version $MIN_SUPPORTED_CODEX_VERSION 以上"
  else
    ng "codex $CODEX_VERSION は非対応（$MIN_SUPPORTED_CODEX_VERSION 以上が必要）"
  fi
  mkdir -p "$S/codex-home"
  printf '[projects."%s"]\ntrust_level = "trusted"\n' "$PWD" > "$S/codex-home/config.toml"
  if printf '' | CODEX_HOME="$S/codex-home" codex -C "$PWD" app-server --strict-config --listen stdio:// > codex-config.out 2>&1; then
    ok "codex --strict-config で配布設定を読込"
  else
    ng "codex --strict-config で配布設定を読めない"
    cat codex-config.out
  fi
  OUT=$(CODEX_HOME="$S/codex-home" codex execpolicy check --rules .codex/rules/default.rules -- rm -rf tmp/example 2>/dev/null)
  [ "$(echo "$OUT" | jq -r '.decision' 2>/dev/null)" = "prompt" ] && ok "rules: rm を prompt" || ng "rules: rm 判定失敗 out=[$OUT]"
  OUT=$(CODEX_HOME="$S/codex-home" codex execpolicy check --rules .codex/rules/default.rules -- git push origin main 2>/dev/null)
  [ "$(echo "$OUT" | jq -r '.decision' 2>/dev/null)" = "forbidden" ] && ok "rules: git push を forbidden" || ng "rules: push 判定失敗 out=[$OUT]"
  OUT=$(CODEX_HOME="$S/codex-home" codex execpolicy check --rules .codex/rules/default.rules -- git add src/example.ts 2>/dev/null)
  [ "$(echo "$OUT" | jq -r '.decision' 2>/dev/null)" = "allow" ] && ok "rules: git add を allow" || ng "rules: git add 判定失敗 out=[$OUT]"
  OUT=$(CODEX_HOME="$S/codex-home" codex execpolicy check --rules .codex/rules/default.rules -- git commit -m message 2>/dev/null)
  [ "$(echo "$OUT" | jq -r '.decision' 2>/dev/null)" = "allow" ] && ok "rules: git commit を allow" || ng "rules: git commit 判定失敗 out=[$OUT]"
  OUT=$(CODEX_HOME="$S/codex-home" codex execpolicy check --rules .codex/rules/default.rules -- git status --short 2>/dev/null)
  [ "$(echo "$OUT" | jq -r '.matchedRules | length' 2>/dev/null)" = "0" ] && ok "rules: git status は未制限" || ng "rules: git status 誤検出 out=[$OUT]"
  OUT=$(CODEX_HOME="$S/codex-home" codex execpolicy check --rules .codex/rules/default.rules -- zsh -lc 'echo x > output.txt' 2>/dev/null)
  [ "$(echo "$OUT" | jq -r '.decision' 2>/dev/null)" = "prompt" ] && ok "rules: opaque shell を prompt" || ng "rules: opaque shell 判定失敗 out=[$OUT]"
  OUT=$(CODEX_HOME="$S/codex-home" codex execpolicy check --rules .codex/rules/default.rules -- bash .agents/skills/init-agent/init-agent.sh codex 2>/dev/null)
  [ "$(echo "$OUT" | jq -r '.decision' 2>/dev/null)" = "allow" ] && ok "rules: init-agent の固定経路を allow" || ng "rules: init-agent 判定失敗 out=[$OUT]"
  OUT=$(CODEX_HOME="$S/codex-home" codex execpolicy check --rules .codex/rules/default.rules -- bash .agents/skills/e2e/apply-e2e-plan.sh "$S/e2e-plan.md" 2>/dev/null)
  [ "$(echo "$OUT" | jq -r '.decision' 2>/dev/null)" = "allow" ] && ok "rules: e2e plan の固定経路を allow" || ng "rules: e2e plan 判定失敗 out=[$OUT]"
  # 引数なしで呼ぶ apply-prompt.sh が rules に一致するか（引数前提の書き方だと取りこぼす）
  OUT=$(CODEX_HOME="$S/codex-home" codex execpolicy check --rules .codex/rules/default.rules -- bash .agents/skills/compose-prompt/apply-prompt.sh 2>/dev/null)
  [ "$(echo "$OUT" | jq -r '.decision' 2>/dev/null)" = "allow" ] && ok "rules: 引数なし apply-prompt を allow" || ng "rules: apply-prompt 判定失敗 out=[$OUT]"
  OUT=$(CODEX_HOME="$S/codex-home" codex execpolicy check --rules .codex/rules/default.rules -- bash .agents/skills/run-agent/mark-prompt-done.sh user-api 2>/dev/null)
  [ "$(echo "$OUT" | jq -r '.decision' 2>/dev/null)" = "allow" ] && ok "rules: mark-prompt-done の固定経路を allow" || ng "rules: mark-prompt-done 判定失敗 out=[$OUT]"
else
  echo "skip codex CLI が無いため config / rules 実機検査を省略"
fi

echo "== 5.5 skill-session marker と発火スコープ（codex） =="
H=.codex/hooks/shell
UP=$(jq -n --arg cwd "$PWD" '{hook_event_name:"UserPromptSubmit",session_id:"SESS1",cwd:$cwd,prompt:"$tdd-run src/foo.ts を回して",model:"m",permission_mode:"default",transcript_path:null,turn_id:"t"}')
echo "$UP" | bash $H/skill-session.sh
[ -f .codex/tmp/skill-session.tdd-run.SESS1 ] && ok "skill-session: \$tdd-run 起動で marker 記録" || ng "skill-session: marker 記録失敗"
UP2=$(jq -n --arg cwd "$PWD" '{hook_event_name:"UserPromptSubmit",session_id:"SESS9",cwd:$cwd,prompt:"tdd-run について教えて",model:"m",permission_mode:"default",transcript_path:null,turn_id:"t"}')
echo "$UP2" | bash $H/skill-session.sh
[ ! -f .codex/tmp/skill-session.tdd-run.SESS9 ] && ok "skill-session: \$ 無しの言及では発火しない" || ng "skill-session: 誤発火"
AP=$(jq -n --arg cwd "$PWD" '{session_id:"SESS1",turn_id:"t1",transcript_path:"/tmp/x.jsonl",cwd:$cwd,hook_event_name:"PreToolUse",model:"gpt-5.5",permission_mode:"bypassPermissions",tool_name:"apply_patch",tool_input:{command:"*** Begin Patch\n*** Add File: src/foo.ts\n+x\n*** End Patch\n"},tool_use_id:"call_x"}')
OUT=$(echo "$AP" | bash $H/require-test.sh)
[ "$(echo "$OUT" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null)" = "deny" ] && ok "require-test: marker 一致で執行(実機同形ペイロード)" || ng "require-test: marker 一致 out=[$OUT]"
APMD=$(jq -n --arg cwd "$PWD" '{session_id:"SESS1",cwd:$cwd,tool_name:"apply_patch",tool_input:{command:"*** Begin Patch\n*** Update File: README.md\n+x\n*** End Patch"}}')
[ -z "$(echo "$APMD" | bash $H/require-test.sh)" ] && ok "require-test: md のみのパッチは棄権" || ng "require-test: md が棄権されない"
APMX=$(jq -n --arg cwd "$PWD" '{session_id:"SESS1",cwd:$cwd,tool_name:"apply_patch",tool_input:{command:"*** Begin Patch\n*** Update File: a.md\n+x\n*** Add File: src/bar.ts\n+y\n*** End Patch"}}')
[ "$(echo "$APMX" | bash $H/require-test.sh | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null)" = "deny" ] && ok "require-test: 複数ファイルパッチの一部違反を deny" || ng "require-test: 複数ファイル検査漏れ"
APB=$(jq -n --arg cwd "$PWD" '{session_id:"SESS1",cwd:$cwd,tool_name:"Bash",tool_input:{command:"echo hi"}}')
[ -z "$(echo "$APB" | bash $H/require-test.sh)" ] && ok "require-test: Bash は棄権" || ng "require-test: Bash"
AP2=$(jq -n --arg cwd "$PWD" '{session_id:"SESS2",cwd:$cwd,tool_name:"apply_patch",tool_input:{command:"*** Begin Patch\n*** Add File: src/foo.ts\n+x\n*** End Patch"}}')
[ -z "$(echo "$AP2" | bash $H/require-test.sh)" ] && ok "require-test: 別セッションの marker では発火しない" || ng "require-test: 残骸で発火"
rm -f .codex/tmp/skill-session.tdd-run.SESS1
[ -z "$(echo "$AP" | bash $H/require-test.sh)" ] && ok "require-test: marker 無しは棄権" || ng "require-test: marker 無しで発火"
UPP=$(jq -n --arg cwd "$PWD" '{hook_event_name:"UserPromptSubmit",session_id:"SESS1",cwd:$cwd,prompt:"$prototype",model:"m",permission_mode:"default",transcript_path:null,turn_id:"t"}')
echo "$UPP" | bash $H/skill-session.sh
PT=$(jq -n --arg cwd "$PWD" '{session_id:"SESS1",cwd:$cwd,tool_name:"apply_patch",tool_input:{command:"*** Begin Patch\n*** Add File: a.test.ts\n+x\n*** End Patch"}}')
[ "$(echo "$PT" | bash $H/prototype-guard.sh | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null)" = "deny" ] && ok "prototype-guard: marker 一致でテスト作成を deny" || ng "prototype-guard: 執行されず"
PT2=$(jq -n --arg cwd "$PWD" '{session_id:"SESS2",cwd:$cwd,tool_name:"apply_patch",tool_input:{command:"*** Begin Patch\n*** Add File: a.test.ts\n+x\n*** End Patch"}}')
[ -z "$(echo "$PT2" | bash $H/prototype-guard.sh)" ] && ok "prototype-guard: 別セッションは棄権" || ng "prototype-guard: 残骸で発火"
SE=$(jq -n --arg cwd "$PWD" '{hook_event_name:"SessionEnd",session_id:"SESS1",cwd:$cwd}')
echo "$SE" | bash $H/skill-session.sh
[ ! -f .codex/tmp/skill-session.prototype.SESS1 ] && ok "skill-session: SessionEnd で自セッションの marker を掃除" || ng "skill-session: 掃除漏れ"
PG=$(jq -n --arg cwd "$PWD" '{session_id:"SESS1",cwd:$cwd,tool_name:"apply_patch",tool_input:{command:"*** Begin Patch\n*** Update File: .git/config\n+x\n*** End Patch"}}')
[ "$(echo "$PG" | bash $H/protect-git-dir.sh | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null)" = "deny" ] && ok "protect-git-dir: パッチ経由の .git 書き込みを deny" || ng "protect-git-dir: apply_patch 素通し"
PE=$(jq -n --arg cwd "$PWD" '{session_id:"SESS1",cwd:$cwd,tool_name:"apply_patch",tool_input:{command:"*** Begin Patch\n*** Update File: .env\n+X=1\n*** End Patch"}}')
[ "$(echo "$PE" | bash $H/protect-env.sh | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null)" = "deny" ] && ok "protect-env: パッチ経由の .env 書き込みを deny" || ng "protect-env: apply_patch 素通し"
PE2=$(jq -n --arg cwd "$PWD" '{session_id:"SESS1",cwd:$cwd,tool_name:"apply_patch",tool_input:{command:"*** Begin Patch\n*** Update File: config/.env.production\n+X=1\n*** End Patch"}}')
[ "$(echo "$PE2" | bash $H/protect-env.sh | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null)" = "deny" ] && ok "protect-env: .env.production も deny" || ng "protect-env: variant 素通し"
PE3=$(jq -n --arg cwd "$PWD" '{session_id:"SESS1",cwd:$cwd,tool_name:"apply_patch",tool_input:{command:"*** Begin Patch\n*** Update File: src/env.ts\n+x\n*** End Patch"}}')
[ -z "$(echo "$PE3" | bash $H/protect-env.sh)" ] && ok "protect-env: env.ts は棄権(誤爆なし)" || ng "protect-env: env.ts 誤爆"
PL=$(jq -n --arg cwd "$PWD" '{session_id:"SESS1",cwd:$cwd,tool_name:"apply_patch",tool_input:{command:"*** Begin Patch\n*** Update File: yarn.lock\n+x\n*** End Patch"}}')
[ "$(echo "$PL" | bash $H/protect-lockfiles.sh | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null)" = "deny" ] && ok "protect-lockfiles: Codex apply_patch を deny" || ng "protect-lockfiles: Codex apply_patch 素通し"
PAC=$(jq -n --arg cwd "$PWD" '{session_id:"SESS1",cwd:$cwd,tool_name:"apply_patch",tool_input:{command:"*** Begin Patch\n*** Update File: .codex/config.toml\n+x\n*** End Patch"}}')
[ "$(echo "$PAC" | bash $H/protect-agent-config.sh | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null)" = "deny" ] && ok "protect-agent-config: .codex patch を deny" || ng "protect-agent-config: .codex patch 素通し"
PAC2=$(jq -n --arg cwd "$PWD" '{session_id:"SESS1",cwd:$cwd,tool_name:"apply_patch",tool_input:{command:"*** Begin Patch\n*** Update File: .agents/skills/e2e/SKILL.md\n+x\n*** End Patch"}}')
[ "$(echo "$PAC2" | bash $H/protect-agent-config.sh | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null)" = "deny" ] && ok "protect-agent-config: .agents patch を deny" || ng "protect-agent-config: .agents patch 素通し"
echo x > codex-untracked.txt
GO=$(jq -n --arg cwd "$PWD" '{session_id:"SESS1",cwd:$cwd,tool_name:"Write",tool_input:{file_path:($cwd + "/codex-untracked.txt")}}')
[ "$(echo "$GO" | bash $H/guard-overwrite.sh | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null)" = "deny" ] && ok "hook-io: codex の未対応 ask は deny" || ng "hook-io: codex ask が fail-open"

echo "== 6. テンプレート残渣チェック =="
command grep -rn "allowed-tools:.*Shell" "$REPO/skills" >/dev/null 2>&1 && ng "allowed-tools に Shell が残存" || ok "allowed-tools: Shell 残存なし"
command grep -rn "hookSpecificOutput" "$REPO/hooks/shell" 2>/dev/null | grep -v hook-io.sh | grep -q . && ng "hook-io 以外にスキーマ直書き" || ok "スキーマ直書きは hook-io のみ"
command grep -rn '\[claude\]' "$REPO/skills" "$REPO/hooks" "$REPO/AGENTS.md" 2>/dev/null | grep -q . && { ng "[claude] 直書き残存"; command grep -rn '\[claude\]' "$REPO/skills" "$REPO/hooks" "$REPO/AGENTS.md"; } || ok "[claude] 直書きゼロ"
find "$REPO/hooks" "$REPO/skills" "$REPO/rules" -type f -iname '*claude*' | grep -q . && { ng "共有ファイル名に製品名が残存"; find "$REPO/hooks" "$REPO/skills" "$REPO/rules" -type f -iname '*claude*'; } || ok "共有ファイル名は製品非依存"
command grep -rn 'enforce-claude-commit\|claude-commit:' "$REPO" --exclude-dir=.git 2>/dev/null | grep -q . && ng "旧commit hook名が残存" || ok "旧commit hook名の残存なし"

echo "== 7. 承認プロンプト回避の設定検査 =="
# Claude Code の Bash 照合はコマンド文字列そのままで行われ、末尾 ` *` / `:*` は
# 「スペース + 何か」を要求する。引数なしで呼ぶスクリプトをワイルドカード形だけで
# 登録すると一致せず承認プロンプトが復活するため、両形の登録を必須にする。
SJ="$REPO/claude/settings.json"; SL="$REPO/claude/settings.local.json"
jq -e . "$SJ" >/dev/null 2>&1 && ok "settings.json 構文" || ng "settings.json 構文"
jq -e . "$SL" >/dev/null 2>&1 && ok "settings.local.json 構文" || ng "settings.local.json 構文"
jq -e '.sandbox.failIfUnavailable == true and .sandbox.autoAllowBashIfSandboxed == false and .sandbox.network.allowLocalBinding == false and (.sandbox.network.allowedDomains | length == 0)' "$SJ" >/dev/null 2>&1 && ok "Claude sandbox はfail-closedかつnetwork自動許可なし" || ng "Claude sandbox境界が不正"
jq -e '.permissions.allow | index("WebFetch(domain:localhost)") | not' "$SL" >/dev/null 2>&1 && ok "Claude localhost WebFetch 自動許可なし" || ng "Claude localhost WebFetch が自動許可"
[ "$(jq '[.hooks.PreToolUse[] | .hooks[].command | select(contains("protect-lockfiles.sh"))] | length' "$SJ")" = "$EXPECTED_DUAL_HOOK_BINDINGS" ] && ok "Claude lockfile保護hookをBash/Editへ配線" || ng "Claude lockfile保護hookの配線漏れ"
MISS=0
for SC in init-agent/init-agent.sh compose-prompt/apply-prompt.sh run-agent/mark-prompt-done.sh e2e/apply-e2e-plan.sh; do
  CMD="bash .claude/skills/$SC"
  jq -e --arg c "$CMD"          '.sandbox.excludedCommands | index($c)' "$SJ" >/dev/null 2>&1 || { ng "excludedCommands に引数なし形が無い: $SC"; MISS=1; }
  jq -e --arg c "$CMD *"        '.sandbox.excludedCommands | index($c)' "$SJ" >/dev/null 2>&1 || { ng "excludedCommands に引数あり形が無い: $SC"; MISS=1; }
  jq -e --arg c "Bash($CMD)"    '.permissions.allow | index($c)' "$SL" >/dev/null 2>&1 || { ng "allow に引数なし形が無い: $SC"; MISS=1; }
  jq -e --arg c "Bash($CMD:*)"  '.permissions.allow | index($c)' "$SL" >/dev/null 2>&1 || { ng "allow に引数あり形が無い: $SC"; MISS=1; }
done
[ "$MISS" = "0" ] && ok "固定スクリプトは引数あり・なし両形で登録済み"

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
