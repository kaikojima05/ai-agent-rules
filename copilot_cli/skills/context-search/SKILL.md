---
name: context-search
description: context-dictionary API から過去の知見を検索・取得し、現在の作業に活用する。
allowed-tools: Shell
---

## 目的

過去のセッションで蓄積された知見（発見、判断、解決方法、問題点、注意点）を検索・取得し、現在の作業に活用する。

## 実行フロー

### Step 1: 概要を受け取る

スキルは引数付きで呼び出せる:

```
/context-search 請求明細を正しく表示するために行った対応策
```

- **引数あり**: その内容をそのまま検索の手がかりとして使う。質問はしない。
- **引数なし**: 一言だけ尋ねる → 「過去の記録から何を調べますか？」

### Step 2: エージェントが検索条件を組み立てる

ユーザーの概要から、エージェントが自律的に最適な検索戦略を判断する:

- キーワードを抽出して `q` パラメータや `/api/search?q=` で検索
- 内容から知見タイプを推測して `type` パラメータで絞り込み
  - 「対応策」「解決方法」→ `type=solution`
  - 「判断理由」「なぜ〜にしたか」→ `type=decision`
  - 「仕様」「挙動」→ `type=discovery`
  - 「問題点」「課題」→ `type=issue`
  - 「注意点」「ハマった」→ `type=caveat`
- タグを推測して `tag` パラメータで絞り込み
- 「先週」「先月」等の時間表現があれば `from` / `to` に変換
- 必要に応じて複数回の検索を組み合わせる

エージェントはユーザーに検索条件の確認を取らず、自分の判断で API を叩くこと。

### Step 3: 結果を整理して提示

検索結果をユーザーが読みやすい形式に整理する:

- 各知見の **type**、**日付**、**content** を一覧表示
- decision の場合は **rationale** も表示
- 未解決の **followUps** がある場合は通知する
- 関連する知見 (**relations**) がある場合はリンクを表示
- 結果が多い場合は関連度の高いものを優先して提示する
- 結果が0件の場合は、別のキーワードや type で再検索を試みる

## API 仕様

### 知見一覧取得

- **エンドポイント**: `GET http://localhost:3210/api/insights`

| Param | Type | Default | 説明 |
|---|---|---|---|
| agent | string | - | Agent 名でフィルタ |
| type | string | - | 知見タイプでフィルタ |
| tag | string | - | タグ名でフィルタ |
| repo | string | - | リポジトリ名でフィルタ |
| from | string (ISO 8601) | - | この日時以降 |
| to | string (ISO 8601) | - | この日時以前 |
| q | string | - | content の部分一致検索 |
| limit | number | 20 | 取得件数 |
| offset | number | 0 | スキップ件数 |

### 全文検索

- **エンドポイント**: `GET http://localhost:3210/api/search?q=検索クエリ`
- content に対する全文検索 (MySQL FULLTEXT)
- `type`, `agent` パラメータで追加フィルタ可能

### タグ一覧取得

- **エンドポイント**: `GET http://localhost:3210/api/tags`

### curl の実行例

```bash
# solution タイプの知見を検索
curl -s "http://localhost:3210/api/insights?type=solution&q=請求&limit=10"

# 全文検索
curl -s "http://localhost:3210/api/search?q=認証"

# タグで絞り込み
curl -s "http://localhost:3210/api/insights?tag=billing"

# リポジトリで絞り込み
curl -s "http://localhost:3210/api/insights?repo=billing-service"
```

## 注意事項

- API サーバー (`http://localhost:3210`) が起動していない場合はユーザーに通知すること
- 結果が0件でもすぐ諦めず、キーワードを変えたり type を外して再検索すること
- レスポンスの JSON はそのまま出さず、ユーザーが読みやすい形に整理すること
- **ユーザーへの質問は最初の一言だけ。検索条件はエージェントが自分で判断する**
