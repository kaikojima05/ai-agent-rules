---
name: context-update
description: context-dictionary API に登録済みの知見を更新・follow-up を管理する。
allowed-tools: Shell
disable-model-invocation: true
---

## 目的

過去に登録した知見（Insight）の内容修正・タグ変更・follow-up の追加や解決など、既存データの更新操作を行う。

## 実行フロー

### Step 1: 概要を受け取る

スキルは引数付きで呼び出せる:

```
/context-update ID:3 の detail を追記したい
/context-update ID:2 に follow-up を追加
/context-update ID:1 の follow-up を解決済みにする
```

- **引数あり**: その内容から対象と操作を判断する。
- **引数なし**: 一言だけ尋ねる → 「どの知見をどう更新しますか？」

### Step 2: 対象の特定

更新対象の Insight ID が不明な場合、エージェントが自律的に検索して特定する:

1. ユーザーの説明からキーワードを抽出
2. `GET /api/insights` や `GET /api/search` で候補を検索
3. 候補を提示して確認を取る（候補が1件なら確認不要）

ID が明示されている場合は `GET /api/insights/:id` で現在の状態を取得する。

### Step 3: 操作の実行

操作の種類に応じて以下を実行する:

#### 知見の更新

対象の Insight を取得し、現在の状態をユーザーに提示した上で変更内容を確認する:

> ID:3 の知見を以下のように更新します。よろしいですか？
>
> **content**: （変更なし）
> **detail**: 「〜〜〜」を追記
> **tags**: billing, discount → billing, discount, **refactoring**（追加）

ユーザーが OK したら `PATCH /api/insights/:id` で更新する。

#### follow-up の追加

対象の Insight に follow-up を追加する:

> ID:2 に以下の follow-up を追加します。よろしいですか？
>
> - [ ] テストケースを追加する

ユーザーが OK したら `POST /api/insights/:id/follow-ups` で追加する。

#### follow-up の解決

対象の Insight の follow-up 一覧を表示し、解決する項目を確認する:

> ID:1 の follow-up:
>
> 1. [  ] リファクタリングする（follow-up ID: 5）
> 2. [x] ドキュメントを更新する（follow-up ID: 6）
>
> どれを解決済みにしますか？

ユーザーが指定したら `PATCH /api/follow-ups/:id` で `resolved: true` に更新する。
未解決に戻す場合は `resolved: false` を送信する。

## API 仕様

### 知見の更新

- **エンドポイント**: `PATCH http://localhost:3210/api/insights/:id`
- **Content-Type**: `application/json`

すべてのフィールドは任意（partial update）:

| Field | Type | 説明 |
|---|---|---|
| type | string | `discovery`, `decision`, `solution`, `issue`, `caveat` |
| content | string | 知見の概要 |
| detail | string | 詳細な説明・手順・コード等 |
| rationale | string | 判断理由・背景 |
| agent | string (max 50) | Agent 名 |
| repo | string (max 200) | リポジトリ名 |
| branch | string (max 200) | ブランチ名 |
| tags | string[] | タグ名のリスト（**全置換**: 既存タグを削除して再設定） |
| addTags | string[] | 既存タグを保持したまま追加 |
| removeTags | string[] | 指定したタグだけ削除 |
| relations | object[] | `{targetId, type}` のリスト（**全置換**: 既存 relation を削除して再設定） |
| addRelations | object[] | `{targetId, type}` 既存 relation を保持したまま追加 |
| removeRelations | object[] | `{targetId, type}` 指定した relation だけ削除 |

**使い分け**:
- `tags` / `relations` を指定すると既存のものが全削除されて再作成される（全置換）
- `addTags` / `removeTags` / `addRelations` / `removeRelations` を使えば差分操作が可能
- `tags` と `addTags`/`removeTags` の同時指定は不可（`tags` が優先される）

### follow-up の追加

- **エンドポイント**: `POST http://localhost:3210/api/insights/:id/follow-ups`
- **Content-Type**: `application/json`

| Field | Type | Required | 説明 |
|---|---|---|---|
| content | string | Yes | follow-up の内容 |

### follow-up の解決/未解決

- **エンドポイント**: `PATCH http://localhost:3210/api/follow-ups/:id`
- **Content-Type**: `application/json`

| Field | Type | Required | 説明 |
|---|---|---|---|
| resolved | boolean | Yes | `true` で解決済み、`false` で未解決に戻す |

### 参照用 API

| 用途 | エンドポイント |
|---|---|
| 知見の取得 | `GET http://localhost:3210/api/insights/:id` |
| 知見の検索 | `GET http://localhost:3210/api/insights?q=キーワード` |
| 全文検索 | `GET http://localhost:3210/api/search?q=キーワード` |
| タグ一覧 | `GET http://localhost:3210/api/tags` |

### curl の実行例

```bash
# 知見の内容を更新
curl -s -X PATCH http://localhost:3210/api/insights/3 \
  -H 'Content-Type: application/json' \
  -d '{
    "detail": "更新後の詳細説明"
  }'

# タグを追加（既存を保持）
curl -s -X PATCH http://localhost:3210/api/insights/3 \
  -H 'Content-Type: application/json' \
  -d '{
    "addTags": ["refactoring"]
  }'

# タグを削除
curl -s -X PATCH http://localhost:3210/api/insights/3 \
  -H 'Content-Type: application/json' \
  -d '{
    "removeTags": ["discount"]
  }'

# タグを全置換
curl -s -X PATCH http://localhost:3210/api/insights/3 \
  -H 'Content-Type: application/json' \
  -d '{
    "tags": ["billing", "discount", "refactoring"]
  }'

# follow-up を追加
curl -s -X POST http://localhost:3210/api/insights/2/follow-ups \
  -H 'Content-Type: application/json' \
  -d '{"content": "テストケースを追加する"}'

# follow-up を解決済みにする
curl -s -X PATCH http://localhost:3210/api/follow-ups/5 \
  -H 'Content-Type: application/json' \
  -d '{"resolved": true}'
```

## 注意事項

- `tags` と `relations` は partial update ではなく**全置換**される。既存の値を保持したい場合は、先に `GET` で取得してマージすること
- API サーバー (`http://localhost:3210`) が起動していない場合はユーザーに通知すること
- 更新前に必ず現在の状態を取得して、ユーザーに変更差分を提示すること
- **ユーザーへの質問は最小限にする。対象の特定に必要な場合のみ質問する**
