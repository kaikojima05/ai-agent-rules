#!/bin/bash
# hook 全数テスト。claude 配置を解決済みのツリー(.claude/hooks/shell)に対して
# Claude Code スキーマの入力を食わせ、deny / ask / 棄権(出力なし) を検証する。
# 単体では動かない: verify-all.sh が配置シミュレーションを作ってからコピーして実行する。
#   実行は `bash tests/verify-all.sh`
H="$(cd "$(dirname "$0")" && pwd)/.claude/hooks/shell"
PASS=0; FAIL=0

# hook にJSON入力を与えて stdout を返すヘルパー関数
run() { echo "$2" | bash "$H/$1"; }

# 実行結果が期待(deny/ask/empty)と一致するか判定して集計する関数
check() { # name expect(deny|ask|empty) hook json
  OUT=$(run "$3" "$4")
  # deny/ask は「stdout 全体が決定 JSON としてパース可能」まで検査する（出力汚染の検出）
  case "$2" in
    deny)  [ "$(echo "$OUT" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null)" = "deny" ] ;;
    ask)   [ "$(echo "$OUT" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null)" = "ask" ] ;;
    empty) [ -z "$OUT" ] ;;
  esac
  if [ $? -eq 0 ]; then PASS=$((PASS+1)); echo "ok   $1"
  else FAIL=$((FAIL+1)); echo "FAIL $1 -> [$OUT]"; fi
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

# --- deny-history-rewrite ---
check "history-rewrite: git rebase は deny"   deny  deny-history-rewrite.sh '{"tool_name":"Bash","tool_input":{"command":"git rebase -i HEAD~3"}}'
check "history-rewrite: force push は deny"   deny  deny-history-rewrite.sh '{"tool_name":"Bash","tool_input":{"command":"git push -f origin master"}}'
check "history-rewrite: git commit は棄権"    empty deny-history-rewrite.sh '{"tool_name":"Bash","tool_input":{"command":"git commit -m msg"}}'

# --- deny-inline-eval ---
check "inline-eval: python3 -c は deny"       deny  deny-inline-eval.sh '{"tool_name":"Bash","tool_input":{"command":"python3 -c import_os"}}'
check "inline-eval: node -e は deny"          deny  deny-inline-eval.sh '{"tool_name":"Bash","tool_input":{"command":"node -e code"}}'
check "inline-eval: python3 foo.py は棄権"    empty deny-inline-eval.sh '{"tool_name":"Bash","tool_input":{"command":"python3 foo.py"}}'

# --- deny-registry-fetch ---
check "registry-fetch: npx は deny"           deny  deny-registry-fetch.sh '{"tool_name":"Bash","tool_input":{"command":"npx create-app"}}'
check "registry-fetch: npm install は deny"   deny  deny-registry-fetch.sh '{"tool_name":"Bash","tool_input":{"command":"npm install left-pad"}}'
check "registry-fetch: yarn build は棄権"     empty deny-registry-fetch.sh '{"tool_name":"Bash","tool_input":{"command":"yarn build"}}'

# --- enforce-claude-commit ---
check "claude-commit: git add -A は deny"     deny  enforce-claude-commit.sh '{"tool_name":"Bash","tool_input":{"command":"git add -A"}}'
check "claude-commit: 契約形式コミットは棄権" empty enforce-claude-commit.sh '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"[claude]: foo.ts/バグを直した\""}}'
check "claude-commit: 形式違反は deny"        deny  enforce-claude-commit.sh '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"fix bug\""}}'
check "claude-commit: amend は deny"          deny  enforce-claude-commit.sh '{"tool_name":"Bash","tool_input":{"command":"git commit --amend -m \"[claude]: a/b\""}}'

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

# --- hook-io フェイルクローズ(未実装エージェント = claude/codex 以外) ---
sed 's/^HOOK_AGENT="claude"/HOOK_AGENT="github"/' "$H/hook-io.sh" > "$H/hook-io.sh.codex" && mv "$H/hook-io.sh.codex" "$H/hook-io.sh.bak-claude" 2>/dev/null
mv "$H/hook-io.sh" "$H/hook-io.sh.orig" && mv "$H/hook-io.sh.bak-claude" "$H/hook-io.sh"
OUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"git rebase"}}' | bash "$H/deny-history-rewrite.sh"); RC=$?
mv "$H/hook-io.sh.orig" "$H/hook-io.sh"
if [ -z "$OUT" ] && [ "$RC" -ne 0 ]; then PASS=$((PASS+1)); echo "ok   hook-io: 未実装エージェントは無出力+非ゼロ終了"
else FAIL=$((FAIL+1)); echo "FAIL hook-io: 未実装エージェント rc=$RC out=[$OUT]"; fi

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
