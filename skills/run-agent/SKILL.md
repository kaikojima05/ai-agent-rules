---
name: run-agent
description: "@.[agent_name]/prompt/ の設計書を実装順に 1 枚だけ実装する"
allowed-tools: Read, Bash
disable-model-invocation: true
---

## 目的

compose-prompt が作った設計書のうち、**未実装のものを 1 枚だけ**実装する。
「@.[agent_name]/prompt/.prompt.md の内容を実行する」の定型文を省略する。

## 前提: 成果物の構成

compose-prompt が `.[agent_name]/prompt/` に次を置いている（形式の詳細は compose-prompt スキルを参照）:

| ファイル | 役割 |
|---|---|
| `.prompt.md` | 実装順の index。`- [ ] branch-<機能名>-prompt.md` を実装順に並べたもの |
| `branch-<機能名>-prompt.md` | 機能 1 つ分の設計書（Summary / Changes / 対象ファイル / 参照ルール / 完了条件） |

## 実行フロー

### Step 1: スキルを呼び出す

スキルは引数なし

```
/run-agent
```

### Step 2: 実装する設計書を 1 枚特定する

`@.[agent_name]/prompt/.prompt.md` を読み、**最初の `- [ ]`（未実装）の行**を対象とする。

- `- [ ]` が 1 つも無ければ「全設計書が実装済み」と報告して終了する。次のタスクは compose-prompt からやり直す
- `.prompt.md` が存在しない・空の場合は、その旨を伝えて compose-prompt の実行を案内し終了する
- **飛ばさない・選ばない。** 並び順は compose-prompt が依存関係を考慮して決めた実装順であり、エージェントが順序を判断し直してはならない

### Step 3: 設計書 1 枚を実装する

特定した `@.[agent_name]/prompt/branch-<機能名>-prompt.md` だけを読んで実装する。

- **他の設計書は読まない・実装しない**
- コード実装を伴う場合は、直接書かず **tdd-run スキルのフルフロー**（シナリオ → Red → Green → Refactor）で進める
- 調査・ドキュメントなど実装を伴わないタスクは通常通り実行する
- コミットは AGENTS.md「Git 運用」のとおり 1 ファイル = 1 コミットで積む
- 設計書末尾の完了条件を満たすまでを 1 枚の範囲とする

### Step 4: 実装済みとして index に記録する

完了条件を満たしたら、専用スクリプトで index のチェックボックスを `[x]` に倒す。

```
bash [skills_root]/run-agent/mark-prompt-done.sh <機能名>
```

- `<機能名>` は `branch-` と `-prompt.md` を除いた部分（例: `branch-user-address-api-prompt.md` → `user-address-api`）
- `.[agent_name]/` は sandbox の denyWrite で保護されておりエージェントは直接書き込めないため、進捗の記録もこの固定スクリプトに閉じ込める。本スクリプトは対象 1 行のチェックボックスを倒すことしかできず、任意の内容の書き込みもファイルの削除もできない
- 対象が既に `[x]` だった場合はエラーで止まる。**握りつぶして次へ進まない** — 実装対象を取り違えた証拠なので、報告して止まること
- Claude Code では本スクリプトは `settings.json` の `sandbox.excludedCommands` に登録済みのため、そのまま実行すれば最初から sandbox 外で走る
  - `excludedCommands` と事前 allow はコマンド文字列の照合で決まるため、必ずプロジェクトルートから**上記の 1 行をそのまま単独で**実行すること。以下はいずれも照合を外し、sandbox 内実行の失敗と承認プロンプトを復活させる
    - 絶対パスにする / `./` の有無を変える / `bash` を `sh` に変える — パスは正規化されず、文字列が違えば別のコマンドとして扱われる
    - `cd ... &&` を前置する、`&&` `;` `|` で他のコマンドと繋ぐ — 複合コマンドは区切り文字で分割され、**各サブコマンドが個別に**照合される。繋いだ相手が許可されていなければプロンプトが出る
    - `> log 2>&1` などのリダイレクトを付ける — リダイレクト先の解決可否によってはプロンプトに倒れる
  - 「Operation not permitted」で失敗した場合は、まず呼び出しが上記の相対パス形式かを確認し、違っていれば形式を直して再実行する。相対パス形式でも失敗する場合のみ `excludedCommands` 未設定の古い配置と判断し、sandbox を無効化して再実行のうえ `settings.json` の更新をユーザーに案内すること
- Codex では `workspace-write` が `.codex` を保護し、`.codex/rules/default.rules` が `bash .agents/skills/run-agent/mark-prompt-done.sh` だけを sandbox 外で allow する。失敗時は迂回せず、project の信頼と rules 配置を確認すること

### Step 5: 報告して停止する

**設計書 1 枚を終えたら必ずそこで止まる。** 次の `- [ ]` に自動で進んではならない。

報告すること:

- 実装した設計書と、その機能名
- 積んだコミット
- index の残件数（`mark-prompt-done.sh` が `remaining:` として出力する）

- Why: 設計書 1 枚 = 1 ブランチ = 1 PR の単位。次の 1 枚に進む前に、人間がレビューし、必要ならブランチを切り替える余地を残す
- Why: 全設計書を連続実装すると、1 枚目の設計が誤っていた場合に後続すべてが巻き添えになる。1 枚ごとに止めれば、誤りが判明した時点の損害が 1 枚分で収まる
- 続きを実装するときは、ユーザーが改めて `/run-agent` を呼ぶ
