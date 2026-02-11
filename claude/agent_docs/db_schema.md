# DB設計ガイドライン

## ガイドライン

### 全体方針

- **ORM**: Prisma を使用し、データソースは MySQL とする。
- **ビューとテーブルの分離**: 外部DB（働くDB）から同期されるデータは `@@map("〇〇View")` のビューモデルとして参照専用で扱い、アプリケーション固有のデータは通常テーブルで管理する。
- **参照専用の徹底**: ビューモデルに対して Prisma 経由の書き込み処理は実装しない。

### 命名規則

#### モデル名・テーブル名

- **モデル名**: PascalCase の英語名で定義する（例: `Contract`, `CustomerInvoice`）。
- **テーブルマッピング**: MySQL 上のテーブル名と異なる場合は `@@map()` で明示する（例: `@@map("ContractView")`, `@@map("User")`）。

#### フィールド名・カラム名

- **アプリ管理テーブル**: camelCase を使用し、`@map()` は付けない（例: `customerNumber`, `statusId`）。
- **外部DB同期テーブル**: camelCase のフィールド名を定義し、元カラム名を `@map()` でマッピングする（例: `shotNo String @map("shot_no")`, `customerNumber String @map("顧客No")`）。

#### リレーション名

- **基本**: 関連モデルの意味を表す camelCase の英語名にする（例: `contract`, `details`, `status`）。
- **同一モデルへの複数リレーション**: `@relation(name: "...")` で意味を区別する名前を明示する（例: `@relation("ShotInvoiceFullContract")` / `@relation("ShotInvoiceFullDContract")`）。

### 型定義

- **文字列型**: 必ず `@db.VarChar(n)` で最大長を明示する。上限が大きい可変長テキストのみ `@db.Text` を使用する。
- **日付型**: 日付のみは `@db.Date`、日時は `@db.DateTime(0)` または `@db.Timestamp(0)` を指定する。
- **金額**: `Int`（整数）で管理し、税込・税抜・消費税を分けて保持する（例: `amount Int`, `taxableAmount Int`, `tax Int`）。
- **真偽値**: `Boolean` を使用する。NULL を許容する場合は `Boolean?` とする。
- **JSON型**: 構造化データの柔軟な格納には `Json @db.Json` を使用する。ただし、検索・フィルタ対象のフィールドは正規カラムとして定義する。

### 主キー・一意制約

- **外部DB同期テーブル**: 外部DBの業務番号をそのまま `@id` にする（例: `contractNumber String @id @db.VarChar(20)`）。
- **アプリ管理テーブル**: `Int @id @default(autoincrement())` を使用する。
- **マスタ/ステータステーブル**: コード文字列を `@id` にする（例: `id String @id`）。
- **複合主キー**: 明細テーブル等では `@@id([field1, field2])` で定義する。
- **一意制約**: 主キー以外で一意性を保証するフィールドには `@@unique()` を使用する（例: `@@unique([name])`, `@@unique([file_id, file_line_no])`）。

### リレーション設計

- **外部キーの明示**: 外部キーフィールドとリレーションオブジェクトを分けて記述する（例: `contractNumber String?` + `contract Contract? @relation(...)`）。
- **1対多**: 親モデル側に子モデルの配列フィールドを定義する（例: `details CustomerInvoiceDetail[]`）。
- **多対多**: 明示的な中間テーブルで管理する。Prisma の暗黙的多対多は使用しない。
- **Nullable**: 外部キーが任意の場合はリレーションフィールドを Optional（`?`）にする。

### ステータス・マスタ管理

- **ステータステーブルの構成**: 専用モデルで管理し、以下の共通フィールドを持たせる。
  - `id String @id` — ステータスコード
  - `name String @db.VarChar(255)` — 表示名（`@@unique([name])`）
  - `order Int` — 表示順
  - `createdAt DateTime @default(now())`
  - `updatedAt DateTime @updatedAt`
- **種別テーブル**: ステータスと同様の構成とし、複数モデルから参照される場合がある。

### コメント規約

- **フィールドコメント**: 全フィールドに `///`（トリプルスラッシュ）で日本語コメントを付ける（例: `contractNumber String @id /// 契約No`）。
- **モデルコメント**: モデル定義の直前に `///` で業務上の意味を記載する（例: `/// ショット請求完全同期データ`）。
- **非推奨マーク**: 使用を推奨しないフィールドには `@deprecated` をコメント内に明記し、代替フィールドを案内する。

### インデックス設計

- **外部キーへの付与**: 検索・結合に頻繁に使用される外部キーカラムには `@@index()` を付与する。
- **一意制約との兼用**: 複合一意制約で代用できる場合は `@@unique()` で兼ねる。

### 同期メタデータ

- **外部DB同期テーブル**: 同期日時フィールドを持たせる（`sync_at DateTime?` / `sync_reply_at DateTime?`）。
- **アプリ管理テーブル**: `createdAt DateTime @default(now())` と `updatedAt DateTime @updatedAt` を必ず付与する。

## 禁止事項

- **VarChar 未指定**: `String` 型を `@db.VarChar()` や `@db.Text` なしで使用すること。
- **暗黙的多対多**: Prisma の自動中間テーブル機能を使用すること。
- **金額への小数型使用**: `Float` / `Decimal` を金額フィールドに使用すること（整数で管理する）。
- **ビューへの書き込み**: `@@map("〇〇View")` モデルに対して Prisma 経由の作成・更新・削除処理を実装すること。
- **未合意のプレビュー機能**: `previewFeatures` にチーム合意なく機能を追加すること。
- **コメントの省略**: フィールドコメント（`///`）を省略し、業務上の意味が不明なカラムを残すこと。
- **命名規則の逸脱**: モデル名に snake_case を使用したり、アプリ管理テーブルのフィールド名に snake_case を使用すること。
