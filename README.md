# ai-agent-rules

複数の AI コーディングエージェント（Claude Code / Codex 等）に対して、共通の規約・スキル・フックを横断的に適用するためのテンプレート集。

## 目的

エージェントごとに設定ファイルや配置ディレクトリ（`.claude/`, `.codex/` …）が分かれていても、開発上守らせたいルールは同じであることが多い。本リポジトリは次の点を狙う。

- **規約の一元管理**: コーディング規約やパターン集を `AGENTS.md` と `rules/` に集約し、どのエージェントから参照しても同じ振る舞いになるようにする。
- **エージェント間の差分を placeholder で吸収**: テンプレートでは `[agent_name]`（エージェント名）と `[skills_root]`（skills 配置先）を使って書いておき、`init-agent` スキルで対象エージェントに合わせて実体化する。hook の入出力スキーマ差分は `hooks/shell/hook-io.sh` が吸収する。
- **必要な統制をフックで強制**: 編集系ツール呼び出しの前にテストの存在を要求するなど、人間側の運用に頼らない仕組みを置く。

## 構成

```
ai-agent-rules/
├── AGENTS.md           # エージェントが従う最上位の規約
├── rules/              # AGENTS.md から分離したパターン別の規約
│   └── typescript/         # TypeScript プロジェクト固有のルール
├── skills/             # スキル（スラッシュコマンド相当）の定義
│   ├── init-agent/         # placeholder（[agent_name] / [skills_root]）と [NOTE] の解決
│   ├── compose-prompt/     # 対話で機能ごとの設計書を組み立てて prompt/ へ反映
│   ├── run-agent/          # 設計書1枚を選び、DeepSeek実装を統括して停止
│   ├── tdd-run/            # シナリオ承認後、テスト・委任実装・レビューを連続実行
│   ├── prototype/          # 使い捨て前提のプロトタイプを sandbox 防御の上で回す
│   ├── rebase-squash/      # 1 ファイル = 1 コミット履歴を機能単位に squash
│   ├── rule-audit/         # 差分と規約の突き合わせ
│   ├── interview/          # 設計意図の深掘り対話
│   ├── clean-code/         # フォーマッタ・リンターの一括適用
│   ├── context-save/       # 知見の登録（context-dictionary API）
│   ├── context-search/     # 知見の検索
│   ├── context-update/     # 知見の更新
│   └── e2e/                # chrome-devtools-mcp による E2E テスト
├── hooks/
│   └── shell/              # PreToolUse hook 本体（hook-io.sh がスキーマ差分を吸収）
├── prompt/             # 実装順 index（.prompt.md）と設計書の配置先シード（compose-prompt / run-agent が使用）
├── e2e/                # .e2e.md の配置先シード（e2e スキルが使用）
├── claude/             # Claude Code 用の設定（settings.json, CLAUDE.md 等）
├── codex/              # Codex 用の設定（config.toml, hooks.json, rules/）
└── tests/              # テンプレート自体の回帰テスト（配布対象外）
```

## 使い方

### Codex への配置

Codex 0.138.0 以上を前提とする。次の対応を崩さずに配置する。共通の Markdown 規約と execpolicy は、拡張子が異なるため `.codex/rules/` で共存できる。

| 配布元 | 配置先 |
|---|---|
| `AGENTS.md` | `<repo>/AGENTS.md` |
| `codex/config.toml` | `<repo>/.codex/config.toml` |
| `codex/hooks.json` | `<repo>/.codex/hooks.json` |
| `codex/.gitignore` | `<repo>/.codex/.gitignore` |
| `codex/rules/default.rules` | `<repo>/.codex/rules/default.rules` |
| `hooks/` | `<repo>/.codex/hooks/` |
| `rules/` | `<repo>/.codex/rules/` |
| `prompt/` | `<repo>/.codex/prompt/` |
| `e2e/` | `<repo>/.codex/e2e/` |
| `skills/` | `<repo>/.agents/skills/` |

配置後は次の順序で有効化する。

1. Codex の対話セッションを対象リポジトリで開き、project を trusted にする。未信頼では project-local の config / hooks / rules がすべて無視される。
2. `$init-agent codex` を実行し、placeholder（`[agent_name]` / `[skills_root]`）と `[NOTE]: init-agent 対象` を解決する。配布rulesは正確な init-agent コマンドだけをsandbox外でallowする。
3. `/hooks` を開き、**init-agent 実行後の現在のhook定義**をレビューして信頼する。hookは内容変更でhashが変わるたび再レビューが必要になる。
4. Codexを再起動し、config / rules / hooks / skillsを新しいセッションで読み直す。

### Claude Code への配置

Claude Code は次の対応で配置する。MCP の共有設定だけは `.claude/` 配下ではなく、project root の `.mcp.json` に置く。

| 配布元 | 配置先 |
|---|---|
| `AGENTS.md` | `<repo>/AGENTS.md` |
| `claude/CLAUDE.md` | `<repo>/CLAUDE.md` |
| `claude/.mcp.json` | `<repo>/.mcp.json` |
| `claude/settings.json` | `<repo>/.claude/settings.json` |
| `claude/settings.local.json` | `<repo>/.claude/settings.local.json` |
| `claude/.gitignore` | `<repo>/.claude/.gitignore` |
| `hooks/` | `<repo>/.claude/hooks/` |
| `rules/` | `<repo>/.claude/rules/` |
| `prompt/` | `<repo>/.claude/prompt/` |
| `e2e/` | `<repo>/.claude/e2e/` |
| `skills/` | `<repo>/.claude/skills/` |

配置後に project を trust し、`.mcp.json` の Serena を承認してから `/init-agent claude` を実行する。

対象エージェントに応じた呼び出し形式:

```
# claude
/init-agent claude

# codex
$init-agent codex
```

### DeepSeekへの実装委任

`compose-prompt`と`run-agent`は、OpenCode + OpenRouter + DeepSeekを調査・本体実装に利用できる。委任時はOpenRouterの`~deepseek/deepseek-v4-flash-latest`エイリアスで最新のDeepSeek V4 Flashへ追従し、reasoning effortを`high`に固定する。CodexまたはClaude Codeが設計、テスト、レビュー、Gitを担当し、DeepSeekには読み取り調査または許可された本体コードの編集だけを委任する。

事前にOpenCodeをインストールし、専用のOpenRouter API keyを環境変数へ設定する。

```bash
export OPENROUTER_API_KEY="..."
```

API keyには40 USD以下の月次またはリセットなしhard limitを設定する。固定実行器は使用量38 USDで新規実行を止め、各リクエストでもZDRと学習利用拒否を強制する。キーはリポジトリへ保存しない。

通常はスクリプトを直接操作せず、`compose-prompt`または`run-agent`から呼ぶ。実行器は隔離worktreeで候補パッチを作り、テスト、設計、設定、Git、外部plugin、shellをDeepSeekへ許可しない。

テストの穴をDeepSeekが見つけた場合は、変更せず`[agent_name]`へ相談する。承認済みシナリオから一意に解決できない場合だけ、ユーザーへシナリオ承認を求め直す。

## 注意

- 本リポジトリはテンプレートなので、`init-agent` 実行時にここのファイルを書き換えてはいけない。コピー先で置換する。
- placeholder の dot は placeholder の外側に置く規約（例: `.[agent_name]/...`）。置換漏れは grep で確認する。
- Claude Code は `AGENTS.md` を自動読み込みしない（`CLAUDE.md` のみ）。そのため `claude/CLAUDE.md`（中身は `@AGENTS.md`）を配置時にプロジェクトルートへ展開して読ませる。codex は `AGENTS.md` を直読みするため不要。
- Codex は `distributed` permission profile で通常の workspace 書き込みを許可し、`.git` / `.codex` / `.agents` とレビュー対象パスを保護する。設定更新は配布rulesが限定allowする固定スクリプトだけを使い、汎用の `cp` / `sed` に例外を与えない。
- Codex の hook は**配置しただけでは実行されない**。`/hooks` で現在の定義をレビューして信頼すること。未信頼のhookはスキップされる（検証用の一時迂回フラグは `--dangerously-bypass-hook-trust`）。

## 承認の挙動

両エージェントで共通化している主な挙動:

| やろうとすること | どうなる |
|---|---|
| ファイルを読む・探す（`ls` `cat` `grep`） | ✅ 自動 |
| 通常ファイルを書き換える（コード・テスト・ドキュメント） | ✅ 自動 |
| `package.json` / CI / migration / Prisma / Docker / Terraform を書き換える | 🙋 確認 |
| ファイルを消す（`rm`）・シェルで上書きする（`sed -i` 等） | 🙋 確認 |
| localhost を含むサーバーへ HTTP request を送る | 🙋 sandbox 外で確認 |
| 契約に従うコミット（stage 1件・対象名一致・日本語の変更内容） | ✅ 自動 |
| `tdd-run` 中にテストの無い ts/js コードを書く | 🚫 禁止 |
| `.env` / lockfile / `.git/` / エージェント設定を直接書き換える | 🚫 禁止 |
| 契約に反するコミット（複数stage・対象名不一致・日本語なし・AI署名・`--amend`） | 🚫 禁止 |
| `git push` / `git cherry-pick`、依存の install / add | 🚫 禁止 |

エージェント実装上の差分:

| 操作 | Claude Code | Codex |
|---|---|---|
| localhost を含むHTTP request | sandbox外承認 | permission profileのnetwork無効化によりsandbox外承認 |
| `package.json` / CI / migration 等のpath単位確認 | settingsのaskで強制 | permission profileでreadへ降格し書き込み時に承認 |
| 既存ファイルの全面Write | `guard-overwrite.sh`でask | `apply_patch`は部分差分。opaque shellはrulesでprompt |
| 設定・skillの更新 | sandbox除外済み固定スクリプト | rulesでallowした固定スクリプト |
| MCPの未登録tool | Claudeの既定確認 | `default_tools_approval_mode = "prompt"` |

挙動を決めている実体（想定外の動きをしたらここを見る）:

- 許可 / 確認 / 禁止の名簿（コマンドと書き込みパスのリスク分類） → `claude/settings.local.json`
- Codex のpermission profile / network / MCP承認 / hook有効化 → `codex/config.toml`
- Codex のコマンド単位の許可 / 確認 / 禁止 → `codex/rules/default.rules`
- Codex のhookイベントと実行timeout → `codex/hooks.json`
- テストの有無でコード書き込みを判定（`tdd-run` 稼働中のみ deny） → `hooks/shell/require-test.sh`（claude: tdd-run の frontmatter hooks で起動 / codex: 常時配線 + `skill-session.sh` の marker で tdd-run 稼働中のみ執行）
- 復元できない全上書きだけ確認に通す（Claude Code） → `hooks/shell/guard-overwrite.sh`
- `.claude` / `.codex` / `.agents` の自己改変防止 → `hooks/shell/protect-agent-config.sh`
- 機密ファイル（`.env` / `.env.*`）の書き込み・削除の封じ込め → `hooks/shell/protect-env.sh`（sandbox / permission profile との二重層）
- lockfile の編集ツール・Bash直接変更を拒否 → `hooks/shell/protect-lockfiles.sh`（permission設定との二重層）
- コミット契約（stage厳密1件・対象ファイル名一致・日本語・AI署名禁止）の執行 → `hooks/shell/enforce-agent-commit.sh`

## テスト

テンプレート自体の回帰テスト。**hook・スキル・配布設定を変更したら必ず実行する。**

```
bash tests/verify-all.sh
```

- `tests/verify-all.sh` — 統合スイート。一時ディレクトリに claude / codex の配置を再現し、`init-agent` の placeholder 置換・`[NOTE]` 解決を実行したうえで全 hook を検証する。最後に `PASS=n FAIL=0` を出す
- `tests/run-tests.sh` — hook 全数の deny / ask / 棄権テスト（`verify-all.sh` から呼ばれる。単体では動かない）
- 検証範囲: 構文 / 実行ビット / 配置シミュレーション（claude・codex）/ 権限パスマトリクス / MCP version・tool承認 / Codex config strict読込 / execpolicy判定 / commit契約 / hook参照先・timeout / placeholder置換漏れ / hook決定JSON / `skill-session`の発火スコープ / 固定宛先スクリプト / `rebase-squash` E2E
- 前提: `jq` と `git`。Codex CLI があれば 0.138.0 以上であることと config / rules の実機検査を行い、無い環境ではその部分だけskipする
- 作業ファイルは一時ディレクトリに作られ、終了時に削除される。`tests/` 自体は配布対象外
