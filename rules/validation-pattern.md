# schema.ts の編集ルール

## スキーマ定義ツールの選定
1. 新しくスキーマを定義するときは **yup** を使用すること
   - zod で定義済みの既存スキーマを編集する場合はそのまま zod を使用してよい

## nullable 必須フィールドのユーティリティ
1. 以下の条件を **すべて** 満たすフィールドには、自前でスキーマを書かず
   `@front/modules/yup/utils.ts`（または `@front/modules/zod/utils.ts`）のユーティリティを使うこと
   a. 入力（選択）が必須である
   b. placeholder を設定する
   c. 初期値が null である
   - Why: 「未選択状態（null）→ placeholder 表示 → 送信時に必須バリデーション」
     というパターンを統一的に扱うため
   - 主なユーティリティ: requiredNullableString, requiredNullableNumber,
     requiredNullableEnum, requiredNullableDate
