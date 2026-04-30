---
name: init-agent
description: "配置済みのエージェント設定ファイル群の [agent_name] 置換および [NOTE]: init-agent 対象 の解決を行う"
allowed-tools: Read, Grep, Glob, Shell
disable-model-invocation: true
---

## 目的

ユーザーが配置した AGENTS.md と同階層の skills/, hooks/, rules/ に含まれるテンプレート記述を、実際のエージェント種別に合わせて書き換える。

## 実行フロー

### Step 1: スキルを呼び出す

スキルは引数付きで呼び出せる:

```
/init-agent claude
/init-agent github
```

- **引数あり**: 引数をエージェント種別として使用する（後述の対応表を参照）
- **引数なし**: ユーザーにエージェント種別を確認する

### Step 2: エージェント種別を特定する

引数またはユーザーの回答から、以下の対応表で置換に使用する名前と AGENTS.md が存在するディレクトリ名を決定する:

| 引数 | 置換値（`[agent_name]` に入る値） | ディレクトリ名 |
|------|------------------------------------|---------------|
| `claude` | `claude` | `.claude` |
| `github` | `github` | `.github` |

上記以外の引数が渡された場合は、ユーザーに置換値とディレクトリ名を確認する。

### Step 3: `[agent_name]` を置換する

AGENTS.md と同階層の skills/, hooks/, rules/ 内の全ファイルを対象に、`[agent_name]` を Step 2 で決定した置換値（例: `claude`, `github`）に置換する。

テンプレート内では `@.[agent_name]/...` や `./.[agent_name]/...` のように **dot は placeholder の外側** に置く規約とする。dot を含めて置換しないこと。

ただし、frontmatter の `description:` 行のように bare `[agent_name]/...` で書かれている箇所は、テンプレート側のスタイル不統一のため、置換後に手で `.claude/...` のような形へ整形する（または、テンプレート側を `.[agent_name]/...` に統一しておく）。

なお、本ファイル（`init-agent/SKILL.md`）自身は placeholder の概念を説明する文書のため、置換対象から除外すること。

### Step 4: `[NOTE]: init-agent 対象` を解決する

ファイル内に `[NOTE]: init-agent 対象` コメントがある箇所を、エージェント種別に応じて適切な実装に書き換える。

#### hooks/shell/require-test.sh

エージェント種別に応じて条件式を確定させる:

- **claude**: `if [ "$TOOL" = "Edit" ] || [ "$TOOL" = "Write" ] || [ "$TOOL" = "MultiEdit" ]; then`
- **github**: `if [ "$TOOL" = "edit" ] || [ "$TOOL" = "create" ]; then`

`[NOTE]` コメント行と未使用の選択肢コメントは削除し、確定した条件式のみを残す。

### Step 5: 結果を報告する

置換した `[agent_name]` の値と、解決した `[NOTE]` 箇所をユーザーに報告する。

## 注意事項

- 本リポジトリ（テンプレート元）のファイルは一切変更しない
- `[agent_name]` の置換漏れがないか、処理後に grep で確認すること
