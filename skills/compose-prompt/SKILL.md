---
name: compose-prompt
description: "@.[agent_name]/prompt/.prompt.md の内容を更新する"
allowed-tools: Bash
disable-model-invocation: true
---

## 目的

これまでの会話から判断した修正や追加のタスクを、ユーザーとエージェントが対話しながらプロンプトとしてまとめる。

## 実行フロー

### Step 1: スキルを呼び出す

スキルは引数付きで呼び出せる:

```
/compose-prompt トークンに認証情報を追加する
```

- **引数あり**: 引数に渡された概要を中心にプロンプトを構築する →  ユーザーと対話しながら要件を整理してプロンプトを構築する。
- **引数なし**: エージェントが会話の中から自律的にプロンプトの概要を抽出 → 方向性が間違っていないかユーザーに確認する → ユーザーと対話しながら要件を整理してプロンプトを構築する。

### Step 2: エージェントがドラフトを作成し、ユーザーが確認する

整理された要件を元に、エージェントがプロンプトのドラフトを作成する。ユーザーは内容を確認してフィードバックを行い、必要に応じてエージェントがドラフトを修正する。

ドラフトは必ずセッションの一時領域（scratchpad / `$TMPDIR`）に置くこと。リポジトリ内に置くことは禁止する。

- Why: `.[agent_name]/` は sandbox の denyWrite で保護されており、エージェントは直接書き込めない。レビューの往復はドラフト上で完結させ、保護領域への書き込みは Step 3 の固定スクリプト 1 回に集約する
- Why: 一時領域のドラフトはセッション終了で消えるため後始末が不要。リポジトリ内に置くと git status を汚し、削除には ask ゲートの `rm` が必要になって承認プロンプトが復活してしまう
- Note: 反映後のドラフト削除を apply-prompt.sh に持たせてはならない。事前 allow されたスクリプトに引数ファイルの削除機能を足すと、`rm` の ask ゲートを迂回する任意ファイル削除の抜け道になる

### Step 3: ドラフトを @.[agent_name]/prompt/.prompt.md に反映する

ユーザーの確認が取れたら、専用スクリプトでドラフトを反映する。宛先はスクリプト内で `.prompt.md` に固定されているため、サンドボックス外実行の事前 allow はこの 1 ファイルへの書き込みに限定される。

```
bash [skills_root]/compose-prompt/apply-prompt.sh <ドラフトのパス>
```

- Claude Code では本スクリプトは `settings.json` の `sandbox.excludedCommands` に登録済みのため、そのまま実行すれば最初から sandbox 外で走る（sandbox 内では denyWrite の `.[agent_name]` に阻まれて必ず失敗する）
  - `excludedCommands` と事前 allow はコマンド文字列の前方一致で照合されるため、必ずプロジェクトルートから上記の相対パス形式で呼ぶこと。絶対パスや `cd` 連結で呼ぶとどちらにも一致せず、sandbox 内実行の失敗と承認プロンプトが復活する
- 「Operation not permitted」で失敗した場合は、まず呼び出しが上記の相対パス形式かを確認し、違っていれば形式を直して再実行する。相対パス形式でも失敗する場合のみ `excludedCommands` 未設定の古い配置と判断し、sandbox を無効化して再実行のうえ `settings.json` の更新をユーザーに案内すること
- Codex では `workspace-write` が `.codex` を保護し、`.codex/rules/default.rules` が `bash .agents/skills/compose-prompt/apply-prompt.sh <ドラフト>` だけを sandbox 外で allow する。失敗時は迂回せず、project の信頼と rules 配置を確認すること

## .prompt.md の基本構成

基本構成通りにプロンプトを構築する必要はないが、下記のルールは遵守すること。

1. セクション毎に詳細を分ける
2. 対象ファイル、参照ルール、完了条件の三つのセクションは必ず記載する

```markdown
## 概要
- 「ご利用料金の内訳」セクションに表示する特別値引きが「なんの値引きか」を表示する

## 問題
- 明細の値引き項目名が一律 "特別値引き" で登録されており、値引きマスタの種別と紐づけられない

## 対応策
- [ ] 値引きマスタ明細から、対象の請求 No と請求月（`target_month`）が一致するレコードを特定する
- [ ] 複数件ある場合は、明細の値引き金額を上から順に消化し、消化された値引きだけを内訳に表示する

## 対象ファイル
- @front/features/mypage/resources/bill/bill-api.ts
- @front/features/mypage/resources/bill/components/BillCustomerInvoiceDetails.tsx

## 参照ルール
- @.[agent_name]/rules/typescript/api-pattern.md
- @.[agent_name]/rules/typescript/tdd-pattern.md
- @.[agent_name]/rules/typescript/ui-pattern.md

## 完了条件
- 要件を満たしていること
- 型エラー、フォーマットエラーがないこと
```
