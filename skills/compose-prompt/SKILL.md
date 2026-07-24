---
name: compose-prompt
description: "@.[agent_name]/prompt/.prompt.md の内容を更新する"
allowed-tools: Shell
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
bash .[agent_name]/skills/compose-prompt/apply-prompt.sh <ドラフトのパス>
```

- Claude Code では本スクリプトは `settings.json` の `sandbox.excludedCommands` に登録済みのため、そのまま実行すれば最初から sandbox 外で走る（sandbox 内では denyWrite の `.[agent_name]` に阻まれて必ず失敗する）
- それでも「Operation not permitted」で失敗した場合は `excludedCommands` 未設定の古い配置なので、sandbox を無効化して再実行し、`settings.json` の更新をユーザーに案内すること

## .prompt.md の基本構成

基本構成通りにプロンプトを構築する必要はないが、下記のルールは遵守すること。

1. セクション毎に詳細を分ける
2. 対象ファイル、参照ルール、完了条件の三つのセクションは必ず記載する

```markdown
## 概要
- 「ご利用料金の内訳」セクションに表示する特別値引きが「なんの値引きか」を表示する

## 問題
顧客請求（CustomerInvoice）の明細（detail）には、値引きされた場合に項目名が一律 "特別値引き" として登録されてしまっているため、これを NebikiMasterFull, NebikiMasterFullDetail から取得した値引きの種別と紐づけることができない。
紐付けのための再設計や中間テーブルの提案もしたが、先方が使用している顧客管理システムの仕様上できないと言われてしまった。
その為、力技で解決するしかない。

## 対応策
### 前提
- 値引きマスタの明細（NebikimasterFullDetail）には、付与された値引きが「いつ使用される（された）」かを表す `target_month` という項目がある
- 付与された値引きは、明細の上から順に使用されていく
- NebikiMasterFullDetail に登録されたレコードは下記のようになっている
```sql
INSERT INTO `NebikiMasterFullDetail` (`detail_key`, `contract_no`, `d_contract_no`, `target_month`, `sales_amount`, `taxable_amount`, `tax_exempt_amount`, `detail_added_at`, `discount_reconciled_at`, `is_reconciled`, `discount_or_additional_invoice_no`, `target_customer_invoice_no`, `is_discount_applied`, `discount_category`, `discount_no`)
VALUES
	('Ug000000003-1', 'C000000003', '', '2026/03', -2500, -2500, 0, '2026-04-01 15:00:00', NULL, NULL, 'zy000000005', '', NULL, '紹介割', 'Ug000000003'),
	('Ug000000003-2', 'C000000004', '', '2026/03', -750, -750, 0, '2026-04-04 15:00:00', NULL, NULL, 'zy000000006', '', NULL, '特別値引き', 'Ug000000003'),
	('Ug000000003-3', 'C000000003', '', '2026/04', 3250, 3250, 0, '2026-04-09 15:00:00', '2026-04-09 15:00:00', 1, '', '', 1, '', 'Ug000000003');
```
- 上記の構造でわかる通り、付与された値引きと使用された値引きは別のレコードとして管理されている

### 実装
- [] NebikiMasterFullDetail の `target_month` と顧客請求の請求月を比較して、どの値引きが使用されたかを特定する
  - [] 顧客請求の明細に値引きが含まれているかどうかは、tilte が "特別値引き" もしくは taxableAmount が負の値であるか 
- [] 値引きが含まれている顧客請求の明細は、NebikiMasterFullDetail から、対象の顧客請求Noを持つレコードを抽出する
- [] 抽出したレコードの中から、請求月と `target_month` が一致するレコードを特定する
- [] （ここがキモ！）複数件ある場合は、顧客請求の明細に記録された値引きの金額分を NebikiMasterFullDetail のレコードを上から順に消化していき、差分が発生した段階で、そのレコードの値引きがまだ未消化とし（例を下に記述）、消化された値引きを "ご利用料金の内訳" セクションに表示する

### 例
1. 顧客請求の明細に -6,000 がある
2. NebikiMasterFullDetail に登録された値引きが、上から-2,500（紹介割1）、-2,500（紹介割2）、-2,500（紹介割3）、-1,000（損失手当） の4件あるとする
3. 上から順に消化していくと、-2,500、-2,500、-1,000 まで消化した段階で顧客請求との差分が0となり、紹介割3が-1500、損失手当の-1,000が未消化となる
4. その為、顧客請求の明細には、紹介割1、紹介割2、紹介割3（1,000円分のみ）が適用されたことを表示し、紹介割3の-1,000円と損失手当は適用されなかったことを表示する

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
