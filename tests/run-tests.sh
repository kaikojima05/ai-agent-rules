#!/bin/bash
# hook 全数テスト。claude 配置を解決済みのツリー(.claude/hooks/shell)に対して
# Claude Code スキーマの入力を食わせ、deny / ask / 棄権(出力なし) を検証する。
# 単体では動かない: verify-all.sh が配置シミュレーションを作ってからコピーして実行する。
#   実行は `bash tests/verify-all.sh`
H="$(cd "$(dirname "$0")" && pwd)/.claude/hooks/shell"
PASS=0; FAIL=0

# hook にJSON入力を与えて stdout を返すヘルパー関数
run() { echo "$2" | bash "$H/$1"; }

matches_expected() { # expect(deny|ask|empty) output
  case "$1" in
    deny)  [ "$(echo "$2" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null)" = "deny" ] ;;
    ask)   [ "$(echo "$2" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null)" = "ask" ] ;;
    empty) [ -z "$2" ] ;;
  esac
}

# 実行結果が期待(deny/ask/empty)と一致するか判定して集計する関数
check() { # name expect(deny|ask|empty) hook json
  OUT=$(run "$3" "$4")
  # deny/ask は「stdout 全体が決定 JSON としてパース可能」まで検査する（出力汚染の検出）
  if matches_expected "$2" "$OUT"; then PASS=$((PASS+1)); echo "ok   $1"
  else FAIL=$((FAIL+1)); echo "FAIL $1 -> [$OUT]"; fi
}

check_bash_group() { # name expect hook command...
  GROUP_NAME=$1
  EXPECTED=$2
  HOOK=$3
  shift 3
  GROUP_FAILURES=
  for COMMAND in "$@"; do
    INPUT=$(jq -cn --arg command "$COMMAND" '{tool_name:"Bash",tool_input:{command:$command}}')
    OUT=$(run "$HOOK" "$INPUT")
    if ! matches_expected "$EXPECTED" "$OUT"; then
      GROUP_FAILURES="${GROUP_FAILURES}\ncommand=[$COMMAND] output=[$OUT]"
    fi
  done
  if [ -z "$GROUP_FAILURES" ]; then PASS=$((PASS+1)); echo "ok   $GROUP_NAME"
  else FAIL=$((FAIL+1)); printf 'FAIL %s%b\n' "$GROUP_NAME" "$GROUP_FAILURES"; fi
}

check_rewrite() { # name expected-command hook json
  OUT=$(run "$3" "$4")
  ACTUAL_DECISION=$(echo "$OUT" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null)
  ACTUAL_COMMAND=$(echo "$OUT" | jq -r '.hookSpecificOutput.updatedInput.command' 2>/dev/null)
  if [ "$ACTUAL_DECISION" = "allow" ] && [ "$ACTUAL_COMMAND" = "$2" ]; then
    PASS=$((PASS+1)); echo "ok   $1"
  else
    FAIL=$((FAIL+1)); echo "FAIL $1 -> decision=[$ACTUAL_DECISION] command=[$ACTUAL_COMMAND]"
  fi
}

check_bash_rewrite() { # name expected-command hook command
  INPUT=$(jq -cn --arg command "$4" '{tool_name:"Bash",tool_input:{command:$command}}')
  check_rewrite "$1" "$2" "$3" "$INPUT"
}

# --- require-test ---
mkdir -p src && rm -f src/foo.ts src/foo.test.ts src/bar.tsx
check "require-test: テスト無し ts は deny"   deny  require-test.sh '{"tool_name":"Edit","tool_input":{"file_path":"'$PWD'/src/foo.ts"}}'
touch src/foo.test.ts
check "require-test: テスト有り ts は棄権"    empty require-test.sh '{"tool_name":"Edit","tool_input":{"file_path":"'$PWD'/src/foo.ts"}}'
check "require-test: tsx は棄権"              empty require-test.sh '{"tool_name":"Edit","tool_input":{"file_path":"'$PWD'/src/bar.tsx"}}'
check "require-test: Bash は棄権"             empty require-test.sh '{"tool_name":"Bash","tool_input":{"command":"ls"}}'

# --- protect-git-dir ---
check "protect-git-dir: rm .git は deny"      deny  protect-git-dir.sh '{"tool_name":"Bash","tool_input":{"command":"rm -rf .git"}}'
check "protect-git-dir: Edit .git/config は deny" deny protect-git-dir.sh '{"tool_name":"Edit","tool_input":{"file_path":".git/config"}}'
check "protect-git-dir: 通常 Edit は棄権"     empty protect-git-dir.sh '{"tool_name":"Edit","tool_input":{"file_path":"src/a.ts"}}'
check "protect-git-dir: git status は棄権"    empty protect-git-dir.sh '{"tool_name":"Bash","tool_input":{"command":"git status"}}'

# --- protect-agent-config ---
check "agent-config: Edit .claude は deny"    deny  protect-agent-config.sh '{"tool_name":"Edit","tool_input":{"file_path":".claude/settings.json"}}'
check "agent-config: Edit .agents は deny"    deny  protect-agent-config.sh '{"tool_name":"Edit","tool_input":{"file_path":".agents/skills/foo/SKILL.md"}}'
check "agent-config: rm .claude は deny"      deny  protect-agent-config.sh '{"tool_name":"Bash","tool_input":{"command":"rm -rf .claude"}}'
check "agent-config: 設定読み取りは棄権"      empty protect-agent-config.sh '{"tool_name":"Bash","tool_input":{"command":"cat .claude/settings.json"}}'
check "agent-config: 設定script起動は棄権"    empty protect-agent-config.sh '{"tool_name":"Bash","tool_input":{"command":"bash .claude/skills/init-agent/init-agent.sh claude"}}'

# --- deny-history-rewrite ---
check "history-rewrite: git rebase は deny"   deny  deny-history-rewrite.sh '{"tool_name":"Bash","tool_input":{"command":"git rebase -i HEAD~3"}}'
check "history-rewrite: force push は deny"   deny  deny-history-rewrite.sh '{"tool_name":"Bash","tool_input":{"command":"git push -f origin master"}}'
check "history-rewrite: git commit は棄権"    empty deny-history-rewrite.sh '{"tool_name":"Bash","tool_input":{"command":"git commit -m msg"}}'

# --- deny-inline-eval ---
check "inline-eval: python3 -c は deny"       deny  deny-inline-eval.sh '{"tool_name":"Bash","tool_input":{"command":"python3 -c import_os"}}'
check "inline-eval: node -e は deny"          deny  deny-inline-eval.sh '{"tool_name":"Bash","tool_input":{"command":"node -e code"}}'
check "inline-eval: python3 foo.py は棄権"    empty deny-inline-eval.sh '{"tool_name":"Bash","tool_input":{"command":"python3 foo.py"}}'

# --- normalize-readonly-search ---
check_bash_rewrite "readonly-search: rg stderr破棄をoptionへ正規化" \
  "rg --no-messages -n 'foo|bar' front --glob '!generated/**'" \
  normalize-readonly-search.sh \
  "rg -n 'foo|bar' front --glob '!generated/**' 2>/dev/null"
check_bash_rewrite "readonly-search: findのstderr破棄を許可" \
  "find .codex/tmp/deepseek -maxdepth 2 -type f -print 2>/dev/null" \
  normalize-readonly-search.sh \
  "find .codex/tmp/deepseek -maxdepth 2 -type f -print 2>/dev/null"
check_bash_rewrite "readonly-search: stdoutのdev null破棄を許可" \
  "nl -ba src/foo.ts >/dev/null" \
  normalize-readonly-search.sh \
  "nl -ba src/foo.ts > /dev/null"
check_bash_group "readonly-search: 単一コマンドを誤拒否しない" empty normalize-readonly-search.sh \
  "rg 'foo|bar' src" \
  "find src -maxdepth 2 -type f -print" \
  "cat src/foo.ts" \
  "nl -ba src/foo.ts" \
  "sort src/files.txt" \
  "sed -n '1,240p' src/foo.ts" \
  'echo "$VALUE" 2>&1'
check_bash_group "readonly-search: 複合shellを分割要求で拒否" deny normalize-readonly-search.sh \
  "rg --files src | sort" \
  "find src -type f -print 2>/dev/null | sort" \
  "rg foo; rm target 2>/dev/null" \
  "rg foo 2>/dev/null | tee result.txt" \
  'rg $(danger) 2>/dev/null' \
  $'pwd\nls' \
  "zsh -lc 'pwd; ls'" \
  "/bin/zsh -lc 'pwd; ls'" \
  "env bash -c 'pwd; ls'" \
  "/usr/bin/env zsh -lc 'pwd; ls'" \
  "bash --noprofile -c 'pwd; ls'" \
  "sleep 1 & echo done" \
  'for f in a.ts b.ts; do if test -f "$f"; then sed -n '\''1,240p'\'' "$f"; fi; done; rg --files src | rg '\''smtp|s3'\'''
check_bash_group "readonly-search: 危険な読み取りoptionを拒否" deny normalize-readonly-search.sh \
  "find tmp -type f -delete" \
  "/usr/bin/find tmp -type f -delete" \
  "find tmp -type f -delete 2>/dev/null | sort" \
  'find tmp "-de""lete"' \
  "find tmp -type f -exec rm {} +" \
  "find tmp -type f -fprint result.txt" \
  "sort -o result.txt source.txt" \
  "sort -oresult.txt source.txt" \
  "sort --output=result.txt source.txt" \
  "sort --compress-program=gzip source.txt" \
  "rg --pre preprocess.sh pattern src" \
  "rg --pre=preprocess.sh pattern src" \
  "git diff --output=result.patch" \
  "git show --output=result.txt HEAD"
check_bash_group "readonly-search: 通常fileへのredirectはpermission層へ委任" empty normalize-readonly-search.sh \
  "cat src/foo.ts > result.txt" \
  "rg foo > result.txt 2>/dev/null"

# --- deny-registry-fetch ---
check "registry-fetch: npx は deny"           deny  deny-registry-fetch.sh '{"tool_name":"Bash","tool_input":{"command":"npx create-app"}}'
check "registry-fetch: npm install は deny"   deny  deny-registry-fetch.sh '{"tool_name":"Bash","tool_input":{"command":"npm install left-pad"}}'
check "registry-fetch: yarn build は棄権"     empty deny-registry-fetch.sh '{"tool_name":"Bash","tool_input":{"command":"yarn build"}}'

# --- enforce-agent-commit ---
check "agent-commit: git add -A は deny"       deny  enforce-agent-commit.sh '{"tool_name":"Bash","tool_input":{"command":"git add -A"}}'
check_bash_group "agent-commit: 強制stage は deny" deny enforce-agent-commit.sh \
  "git add -f ignored.test.ts" \
  "git add --force ignored.test.ts" \
  "git add ignored.test.ts -f"
check "agent-commit: plain push は deny"       deny  enforce-agent-commit.sh '{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}'
check "agent-commit: cherry-pick は deny"      deny  enforce-agent-commit.sh '{"tool_name":"Bash","tool_input":{"command":"git cherry-pick abc123"}}'
mkdir -p commit-fixture
cd commit-fixture
git init -q
git config user.email tester@example.com
git config user.name tester
printf 'foo\n' > foo.ts
git add foo.ts
check "agent-commit: 契約形式コミットは棄権" empty enforce-agent-commit.sh '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"[claude]: foo.ts/バグを直した\""}}'
check "agent-commit: ファイル名不一致は deny" deny  enforce-agent-commit.sh '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"[claude]: bar.ts/バグを直した\""}}'
check "agent-commit: 英語だけの変更内容は deny" deny  enforce-agent-commit.sh '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"[claude]: foo.ts/fix bug\""}}'
check "agent-commit: 形式違反は deny"          deny  enforce-agent-commit.sh '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"fix bug\""}}'
check "agent-commit: amend は deny"            deny  enforce-agent-commit.sh '{"tool_name":"Bash","tool_input":{"command":"git commit --amend -m \"[claude]: foo.ts/修正した\""}}'
printf 'bar\n' > bar.ts
git add bar.ts
check "agent-commit: 複数stageは deny"          deny  enforce-agent-commit.sh '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"[claude]: foo.ts/バグを直した\""}}'
cd ..

# --- guard-overwrite ---
echo x > untracked.txt
check "guard-overwrite: git 管理外の上書きは ask" ask guard-overwrite.sh '{"tool_name":"Write","tool_input":{"file_path":"'$PWD'/untracked.txt"}}'
check "guard-overwrite: 新規作成は棄権"       empty guard-overwrite.sh '{"tool_name":"Write","tool_input":{"file_path":"'$PWD'/nonexistent.txt"}}'

# --- prototype-guard ---
check "prototype-guard: テストファイルは deny" deny prototype-guard.sh '{"tool_name":"Write","tool_input":{"file_path":"src/foo.test.ts"}}'
check "prototype-guard: 通常ファイルは棄権"   empty prototype-guard.sh '{"tool_name":"Write","tool_input":{"file_path":"src/foo.ts"}}'

# --- protect-env ---
check "protect-env: Edit .env は deny"        deny  protect-env.sh '{"tool_name":"Edit","tool_input":{"file_path":".env"}}'
check "protect-env: Edit .env.local は deny"  deny  protect-env.sh '{"tool_name":"Edit","tool_input":{"file_path":"config/.env.local"}}'
check "protect-env: Edit env.ts は棄権"       empty protect-env.sh '{"tool_name":"Edit","tool_input":{"file_path":"src/env.ts"}}'
check "protect-env: rm .env は deny"          deny  protect-env.sh '{"tool_name":"Bash","tool_input":{"command":"rm .env"}}'
check "protect-env: リダイレクト書き込みは deny" deny protect-env.sh '{"tool_name":"Bash","tool_input":{"command":"echo A=1 > .env"}}'
check "protect-env: cat .env は棄権"          empty protect-env.sh '{"tool_name":"Bash","tool_input":{"command":"cat .env"}}'

# --- protect-lockfiles ---
check "protect-lockfiles: Edit yarn.lock は deny" deny protect-lockfiles.sh '{"tool_name":"Edit","tool_input":{"file_path":"yarn.lock"}}'
check "protect-lockfiles: Bash 上書きは deny" deny protect-lockfiles.sh '{"tool_name":"Bash","tool_input":{"command":"echo x > package-lock.json"}}'
check "protect-lockfiles: 読み取りは棄権" empty protect-lockfiles.sh '{"tool_name":"Bash","tool_input":{"command":"cat pnpm-lock.yaml"}}'

# --- hook-io フェイルクローズ(未実装エージェント = claude/codex 以外) ---
# 契約: exit 1 は PreToolUse で non-blocking error 扱い = fail-open になるため、
#       PreToolUse には deny 決定 JSON + exit 0 で止める。PreToolUse 以外のイベントは
#       exit 0 の stdout がプロンプトへ注入されるため JSON を出さず棄権する。
#       例外は init-agent.sh の 1 コマンドのみ（placeholder を解決する初期化自身を止めない）。
sed 's/^HOOK_AGENT="claude"/HOOK_AGENT="github"/' "$H/hook-io.sh" > "$H/hook-io.sh.github"
mv "$H/hook-io.sh" "$H/hook-io.sh.orig" && mv "$H/hook-io.sh.github" "$H/hook-io.sh"

OUT=$(echo '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git rebase"}}' | bash "$H/deny-history-rewrite.sh"); RC=$?
if [ "$RC" -eq 0 ] && [ "$(echo "$OUT" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null)" = "deny" ]; then
  PASS=$((PASS+1)); echo "ok   hook-io: 未実装エージェントは deny JSON + exit 0"
else FAIL=$((FAIL+1)); echo "FAIL hook-io: 未実装エージェント rc=$RC out=[$OUT]"; fi

OUT=$(echo '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"bash ./skills/init-agent/init-agent.sh codex"}}' | bash "$H/deny-history-rewrite.sh"); RC=$?
if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then PASS=$((PASS+1)); echo "ok   hook-io: 未実装でも init-agent.sh は棄権"
else FAIL=$((FAIL+1)); echo "FAIL hook-io: init-agent 例外 rc=$RC out=[$OUT]"; fi

OUT=$(echo '{"hook_event_name":"UserPromptSubmit","prompt":"git rebase して"}' | bash "$H/deny-history-rewrite.sh"); RC=$?
if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then PASS=$((PASS+1)); echo "ok   hook-io: PreToolUse 以外は JSON を出さず棄権"
else FAIL=$((FAIL+1)); echo "FAIL hook-io: 非 PreToolUse rc=$RC out=[$OUT]"; fi

mv "$H/hook-io.sh.orig" "$H/hook-io.sh"

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
