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
│   ├── compose-prompt/     # 対話でプロンプトを組み立てて .prompt.md へ反映
│   ├── run-agent/          # .prompt.md の内容を実行
│   ├── tdd-run/            # TDD サイクルを 2 ゲートで自動連続実行
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
├── prompt/             # .prompt.md の配置先シード（compose-prompt / run-agent が使用）
├── e2e/                # .e2e.md の配置先シード（e2e スキルが使用）
├── claude/             # Claude Code 用の設定（settings.json, CLAUDE.md 等）
├── codex/              # Codex 用の設定（config.toml, hooks.json, rules/）
└── tests/              # テンプレート自体の回帰テスト（配布対象外）
```

## 使い方

1. このリポジトリの `AGENTS.md` / `rules/` / `skills/` / `hooks/` / `prompt/` / `e2e/` を、対象プロジェクトの該当パスにコピーする。
   - claude: すべて `.claude/` 配下（skills は `.claude/skills/`）
   - codex: hooks / rules / prompt / e2e は `.codex/` 配下、**skills だけは `.agents/skills/`**（codex はリポジトリ内の skills をそこからしか読まない）
2. 対象エージェントに応じて `init-agent` スキルを実行し、placeholder（`[agent_name]` / `[skills_root]`）および `[NOTE]: init-agent 対象` を解決する。

   ```
   # claude
   /init-agent claude

   # codex（スキルは $ メンションで呼び出す）
   $init-agent codex
   ```

3. 必要に応じて各エージェント固有の設定（`claude/settings.json`, `codex/config.toml` 等）を配置する。

## 注意

- 本リポジトリはテンプレートなので、`init-agent` 実行時にここのファイルを書き換えてはいけない。コピー先で置換する。
- placeholder の dot は placeholder の外側に置く規約（例: `.[agent_name]/...`）。置換漏れは grep で確認する。
- Claude Code は `AGENTS.md` を自動読み込みしない（`CLAUDE.md` のみ）。そのため `claude/CLAUDE.md`（中身は `@AGENTS.md`）を配置時にプロジェクトルートへ展開して読ませる。codex は `AGENTS.md` を直読みするため不要。
- codex の hook（`.codex/hooks.json`）は**配置しただけでは実行されない**。hook は信頼登録制（`~/.codex/config.toml` の `hooks.state` に hash 登録）で、未信頼のまま `codex exec` を使うと**黙ってスキップされる**。初回に対話セッションを開いて信頼を承認すること（検証用の一時迂回フラグは `--dangerously-bypass-hook-trust`）。

## 承認の挙動

このテンプレートを適用すると、エージェントの操作は次のように振り分けられる。

| やろうとすること | どうなる |
|---|---|
| ファイルを読む・探す（`ls` `cat` `grep`） | ✅ 自動 |
| 通常ファイルを書き換える（コード・テスト・ドキュメント） | ✅ 自動 |
| 自分の localhost サーバーを叩く（`curl` 等） | ✅ 自動 |
| 依存を触る（`package.json` / lockfile） | 🙋 確認 |
| CI/CD・インフラを触る（`.github/workflows` `Dockerfile` `*.tf`） | 🙋 確認 |
| DB の不可逆変更（`migrations/` `schema.prisma`） | 🙋 確認 |
| 復元できない全上書き（未コミット差分あり / git 管理外） | 🙋 確認 |
| ファイルを消す（`rm`）・シェルで上書きする（`sed -i` 等） | 🙋 確認 |
| 外部のサーバーにデータを送る | 🙋 確認 |
| 契約に従うコミット（`[<エージェント名>]: {ファイル名}/{内容}`・1 ファイル単位） | ✅ 自動 |
| `tdd-run` 中にテストの無い ts/js コードを書く | 🚫 禁止 |
| `.env` / `.git/` / `.claude/` を書き換える | 🚫 禁止 |
| 契約に反するコミット（prefix 無し・`-a` 一括・AI 署名・`--amend`） | 🚫 禁止 |
| `git push`、依存の install / add | 🚫 禁止 |

挙動を決めている実体（想定外の動きをしたらここを見る）:

- 許可 / 確認 / 禁止の名簿（コマンドと書き込みパスのリスク分類） → `claude/settings.local.json`
- テストの有無でコード書き込みを判定（`tdd-run` 稼働中のみ deny） → `hooks/shell/require-test.sh`（claude: tdd-run の frontmatter hooks で起動 / codex: 常時配線 + `skill-session.sh` の marker で tdd-run 稼働中のみ執行）
- 復元できない全上書きだけ確認に通す → `hooks/shell/guard-overwrite.sh`
- 機密ファイル（`.env` / `.env.*`）の書き込み・削除の封じ込め → `hooks/shell/protect-env.sh`（claude は denyWrite との二重層、codex では唯一の per-path 防壁）
- コミット契約（`[<エージェント名>]:` 形式・1 ファイル単位・AI 署名禁止）の執行 → `hooks/shell/enforce-claude-commit.sh`
- 書き込み先・通信先の封じ込め → `claude/settings.json`（sandbox）

## テスト

テンプレート自体の回帰テスト。**hook・スキル・配布設定を変更したら必ず実行する。**

```
bash tests/verify-all.sh
```

- `tests/verify-all.sh` — 統合スイート。一時ディレクトリに claude / codex の配置を再現し、`init-agent` の placeholder 置換・`[NOTE]` 解決を実行したうえで全 hook を検証する。最後に `PASS=n FAIL=0` を出す
- `tests/run-tests.sh` — hook 全数の deny / ask / 棄権テスト（`verify-all.sh` から呼ばれる。単体では動かない）
- 検証範囲: 構文 / 実行ビット / 配置シミュレーション（claude・codex）/ placeholder 置換漏れ / hook の決定 JSON が汚染されていないこと / `skill-session` の発火スコープ / `rebase-squash` の E2E（squash・tree 同一性・不正 plan の拒否・境界判定）
- 前提: `jq` と `git`。作業ファイルは一時ディレクトリに作られリポジトリを汚さない
- `tests/` は配布対象外（`setup-agent` が配置時に削除する）
