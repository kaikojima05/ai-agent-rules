# ai-agent-rules

複数の AI コーディングエージェント（Claude Code / Codex / GitHub Copilot 等）に対して、共通の規約・スキル・フックを横断的に適用するためのテンプレート集。

## 目的

エージェントごとに設定ファイルや配置ディレクトリ（`.claude/`, `.codex/`, `.github/` …）が分かれていても、開発上守らせたいルールは同じであることが多い。本リポジトリは次の点を狙う。

- **規約の一元管理**: コーディング規約やパターン集を `AGENTS.md` と `rules/` に集約し、どのエージェントから参照しても同じ振る舞いになるようにする。
- **エージェント間の差分を placeholder で吸収**: テンプレートでは `[agent_name]` を使って書いておき、`init-agent` スキルで対象エージェントに合わせて実体化する。
- **必要な統制をフックで強制**: 編集系ツール呼び出しの前にテストの存在を要求するなど、人間側の運用に頼らない仕組みを置く。

## 構成

```
ai-agent-rules/
├── AGENTS.md           # エージェントが従う最上位の規約
├── rules/              # AGENTS.md から分離したパターン別の規約
│   ├── api-pattern.md
│   ├── db-pattern.md
│   ├── function-pattern.md
│   ├── tdd-pattern.md
│   ├── ui-pattern.md
│   └── validation-pattern.md
├── skills/             # スキル（スラッシュコマンド相当）の定義
│   ├── init-agent/         # [agent_name] と [NOTE] をエージェント種別に応じて解決
│   ├── re-apply-guideline/ # コンテキスト肥大時に AGENTS.md を再確認させる
│   ├── compose-prompt/     # 対話を通じてプロンプトを組み立てる
│   ├── run-agent/          # 構築済みプロンプトに従ってエージェントが作業を実行
│   ├── interview/          # 設計・実装の意図を問いかけ、検討漏れに気づかせる対話
│   ├── clean-code/         # 変更コードのレビューと修正
│   ├── context-save/       # コンテキスト保存
│   ├── context-search/     # コンテキスト検索
│   ├── context-update/     # コンテキスト更新
│   └── e2e/                # E2E テスト関連
├── hooks/              # フック設定
│   ├── pre-coding.json     # 編集前フックのテンプレート
│   └── shell/              # フックから呼ばれるシェルスクリプト
├── claude/             # Claude Code 用の設定（settings.json 等）
├── codex/              # Codex 用の設定（config.toml 等）
└── copilot/            # GitHub Copilot 用の設定置き場
```

## 使い方

1. このリポジトリの `AGENTS.md` / `rules/` / `skills/` / `hooks/` を、対象プロジェクトの該当パス（`.claude/`, `.codex/`, `.github/` 等）にコピーする。
2. 対象エージェントに応じて `init-agent` スキルを実行し、テンプレート中の `[agent_name]` および `[NOTE]: init-agent 対象` を解決する。

   ```
   # cluade, codex
   /init-agent claude
   /init-agent github

   # codex
   $init-agent codex
   ```

3. 必要に応じて各エージェント固有の設定（`claude/settings.json`, `codex/config.toml` 等）を配置する。

## 注意

- 本リポジトリはテンプレートなので、`init-agent` 実行時にここのファイルを書き換えてはいけない。コピー先で置換する。
- `[agent_name]` の dot は placeholder の外側に置く規約（例: `.[agent_name]/...`）。置換漏れは grep で確認する。
