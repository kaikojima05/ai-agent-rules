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
/init-agent codex
```

- **引数あり**: 引数をエージェント種別として使用する（後述の対応表を参照）
- **引数なし**: ユーザーにエージェント種別を確認する

### Step 2: エージェント種別を特定する

引数またはユーザーの回答から、以下の対応表で置換に使用する名前と AGENTS.md が存在するディレクトリ名を決定する:

| 引数 | 置換値（`[agent_name]` に入る値） | ディレクトリ名 |
|------|------------------------------------|---------------|
| `claude` | `claude` | `.claude` |
| `github` | `github` | `.github` |
| `codex` | `codex` | `.codex` |

上記以外の引数が渡された場合は、ユーザーに置換値とディレクトリ名を確認する。

### Step 3: 置換スクリプトを実行する

`[agent_name]` の置換と `[NOTE]: init-agent 対象` の解決は、配置済みの決定的スクリプトに委ねる。Bash の sed / heredoc / インタプリタで手作業でファイルを書き換えてはならない。

```
bash .[agent_name]/skills/init-agent/init-agent.sh <agent>
```

- `<agent>` は Step 2 で特定した種別（`claude` / `github` / `codex`）。呼び出し時は `.[agent_name]` を実際の配置ディレクトリ（例: `.claude`）に読み替える
- スクリプトが自動で行うこと:
  - 配置ツリー配下で `[agent_name]` を含む全ファイルを検出して置換する（`.[agent_name]/...` の dot は placeholder の外なので保持される。`init-agent/` 配下は説明・処理本体のため除外）
  - `require-test.sh` / `allow-coding.sh` の `[NOTE]` ブロックを、種別ごとの確定条件へ畳む（claude/github/codex の条件はスクリプトの `case` を唯一の真実とする）
- 上記3種以外を扱う場合は、スクリプトの `case` に分岐を追加してから実行する

Why: 置換は完全に決定的な処理であり、その都度インタプリタでコードを書き捨てると承認の乱発とツール間の差分の温床になる。レビュー済みの1スクリプトへ固定すれば、一度許可すれば以降は承認なしで再実行できる。

### Step 5: 結果を報告する

置換した `[agent_name]` の値と、解決した `[NOTE]` 箇所をユーザーに報告する。

## 注意事項

- 本リポジトリ（テンプレート元）のファイルは一切変更しない。スクリプトは配置済みツリー（`.claude` / `.codex` / `.github`）のみを対象とする
- `[agent_name]` の置換漏れがないか、処理後に grep で確認すること
  - `init-agent/` 配下は placeholder をあえて残す（スキル自身の説明・処理本体のため）。確認時は `| grep -v /init-agent/` で除外する
  - **確認は必ず明示パスで行う**: `command grep -rn "\[agent_name\]" AGENTS.md .[agent_name] | grep -v /init-agent/` のように
    対象ディレクトリ（`.claude` / `.codex` / `.github` 等）と `AGENTS.md` を直接指定すること
  - bare な `grep -r ... .`（ルートを `.` 指定）を使ってはならない
    - Why: エージェント設定ディレクトリと `AGENTS.md` は通常 `.gitignore` で無視されており、
      Claude Code の `grep` は `ugrep --ignore-files` ラッパーで `.gitignore` を尊重するため、
      ルート起点の再帰検索は対象ツリーを丸ごとスキップし「置換漏れゼロ」と誤検出する
    - 迂回したい場合は `command grep -rn ...`（生の grep）を使う
