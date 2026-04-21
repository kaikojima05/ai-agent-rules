# API の追加・編集ルール

## 実装方針
1. 可読性を優先し、宣言的な書き方を選ぶこと
   - 例: reduce() ではなく filter().map() を使う
   - Why: reduce() はループ中のアキュムレータの状態把握が難しく、レビュー負荷が高い
   - ただし、パフォーマンスが計測上ボトルネックになっている箇所には適用しない
2. update（upsert）や delete を行う際は、Prisma の $transaction を使用すること
   - interactive transaction（コールバック形式）を基本とする
   - Why: 部分的な書き込みによるデータ不整合を防ぐため
3. 日付順のソートは昇順（古い順）をデフォルトとすること
   - Why: 時系列データは古い→新しいが自然な並びであり、UI 側で reverse する方が意図が明確になるため
   - UI の要件で降順が必要な場合は、API の引数で制御する

## 命名ルール
- copilot-instructions.md の命名規則に準拠
- @front/features/mypage/resources/ 内の関数名は [resource名]〇〇 とする
  - 例: billPaymentTermUpdate, contractFindMany

## DB クエリのアンチパターン
1. DB から取得したデータを filter() している場合は、WHERE 句で絞れないか検討すること
   a. WHERE 句で絞れる場合 → クエリを修正する
   b. 複雑なクエリが必要な場合 → filter() を維持してよいが、コメントで理由を残す
   c. 判断に迷う場合 → PR レビューで相談する（AI の場合はユーザーに確認を取る）
   d. そもそもクエリが複雑になりすぎる場合は、テーブル設計の見直しを検討する
