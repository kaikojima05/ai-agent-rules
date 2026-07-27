---
name: init-agent
description: "配置済みのエージェント設定ファイル群の placeholder（[agent_name] / [skills_root]）置換および [NOTE]: init-agent 対象 の解決を行う"
allowed-tools: Read, Grep, Glob, Bash
disable-model-invocation: true
---

## 目的

ユーザーが配置した AGENTS.md・設定ディレクトリ・skills ツリーに含まれるテンプレート記述を、実際のエージェント種別に合わせて書き換える。

## 実行フロー

### Step 1: スキルを呼び出す

スキルは引数付きで呼び出せる:

```
/init-agent claude
/init-agent codex
```

- **引数あり**: 引数をエージェント種別として使用する（後述の対応表を参照）
- **引数なし**: ユーザーにエージェント種別を確認する

### Step 2: エージェント種別を特定する

引数またはユーザーの回答から、以下の対応表で置換値と配置先を決定する:

| 引数 | 置換値（`[agent_name]`） | 設定ディレクトリ | skills 配置先（`[skills_root]`） |
|------|--------------------------|------------------|----------------------------------|
| `claude` | `claude` | `.claude` | `.claude/skills` |
| `codex` | `codex` | `.codex` | `.agents/skills` |

- codex の skills 配置先が `.agents/skills` なのは codex 側の探索仕様（リポジトリ内は `.agents/skills` しか読まない）による。hooks / rules / prompt は `.codex/` 配下に置く
- 上記以外の引数が渡された場合は、ユーザーに置換値と配置先を確認する

### Step 3: 置換スクリプトを実行する

`[agent_name]` / `[skills_root]` の置換と `[NOTE]: init-agent 対象` の解決は、配置済みの決定的スクリプトに委ねる。Bash の sed / heredoc / インタプリタで手作業でファイルを書き換えてはならない。

```
bash [skills_root]/init-agent/init-agent.sh <agent>
```

- `<agent>` は Step 2 で特定した種別（`claude` / `codex`）。呼び出し時は `[skills_root]` を上表の実際の配置先（例: `.claude/skills`）に読み替える
- スクリプトが自動で行うこと:
  - 設定ディレクトリ・`AGENTS.md`・skills ツリー（codex は `.agents/`）配下で `[agent_name]` / `[skills_root]` を含む全ファイルを検出して置換する（`.[agent_name]/...` の dot は placeholder の外なので保持される。`init-agent/` 配下は説明・処理本体のため除外）
  - `require-test.sh` の `[NOTE]` ブロックを、種別ごとの確定条件へ畳む（claude/codex の条件はスクリプトの `case` を唯一の真実とする）
- 上記3種以外を扱う場合は、スクリプトの `case` に分岐を追加してから実行する
- Claude Code では本スクリプトは `settings.json` の `sandbox.excludedCommands` に登録済みのため、そのまま実行すれば最初から sandbox 外で走る（permission は `settings.local.json` の事前 allow が担保するため承認プロンプトは出ない）
  - Why: 対象ツリー（`.claude/` 等）は sandbox の denyWrite で保護されており、sandbox 内での実行は必ず「Operation not permitted」で失敗する。失敗→sandbox 外で再実行という二度手間を踏まないための除外設定である
  - `excludedCommands` と事前 allow はコマンド文字列の前方一致で照合されるため、必ずプロジェクトルートから上記の相対パス形式で呼ぶこと。絶対パスや `cd` 連結で呼ぶとどちらにも一致せず、sandbox 内実行の失敗と承認プロンプトが復活する
  - 「Operation not permitted」で失敗した場合は、まず呼び出しが上記の相対パス形式かを確認し、違っていれば形式を直して再実行する。相対パス形式でも失敗する場合のみ `excludedCommands` 未設定の古い配置と判断し、sandbox を無効化して再実行のうえ `settings.json` の更新をユーザーに案内すること
- Codex では `workspace-write` が `.codex` / `.agents` を read-only にするため、配布済みの `.codex/rules/default.rules` が上記の正確なコマンドだけを sandbox 外で allow する
  - project が trusted でないと project-local rules 自体が読み込まれない。未信頼または rules 未配置で失敗した場合は迂回せず、project の信頼と配布ファイルを確認する
  - 引数やスクリプトパスを変えると限定 allow に一致しない。`bash .agents/skills/init-agent/init-agent.sh codex` の形を維持する

Why: 置換は完全に決定的な処理であり、その都度インタプリタでコードを書き捨てると承認の乱発とツール間の差分の温床になる。レビュー済みの1スクリプトへ固定すれば、一度許可すれば以降は承認なしで再実行できる。

### Step 4: 結果を報告する

置換した `[agent_name]` / `[skills_root]` の値と、解決した `[NOTE]` 箇所をユーザーに報告する。

## 注意事項

- 本リポジトリ（テンプレート元）のファイルは一切変更しない。スクリプトは配置済みツリー（`.claude` / `.codex` / `.agents` / `AGENTS.md`）のみを対象とする
- placeholder の置換漏れがないか、処理後に grep で確認すること
  - `init-agent/` 配下は placeholder をあえて残す（スキル自身の説明・処理本体のため）。確認時は `| grep -v /init-agent/` で除外する
  - **確認は必ず明示パスで行う**: `command grep -rnE "\[agent_name\]|\[skills_root\]" AGENTS.md .[agent_name] .agents 2>/dev/null | grep -v /init-agent/` のように
    対象ディレクトリ（`.claude` / `.codex`、codex 配置なら `.agents` も）と `AGENTS.md` を直接指定すること
  - bare な `grep -r ... .`（ルートを `.` 指定）を使ってはならない
    - Why: エージェント設定ディレクトリと `AGENTS.md` は通常 `.gitignore` で無視されており、
      Claude Code の `grep` は `ugrep --ignore-files` ラッパーで `.gitignore` を尊重するため、
      ルート起点の再帰検索は対象ツリーを丸ごとスキップし「置換漏れゼロ」と誤検出する
    - 迂回したい場合は `command grep -rn ...`（生の grep）を使う
