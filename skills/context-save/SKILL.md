---
name: context-save
description: セッションで得た知見を context-dictionary API に登録する。
allowed-tools: Shell
disable-model-invocation: true
---

## 目的

セッション中に得られた知見（発見した事実、設計判断、解決方法、構造的問題、注意点）を context-dictionary API に記録し、将来の参照に備える。

## 実行フロー

### Step 1: 概要を受け取る

スキルは引数付きで呼び出せる:

```
/context-save 今回発生していた問題の原因と解決方法
```

- **引数あり**: その内容をそのまま概要として使う。質問はしない。
- **引数なし**: 一言だけ尋ねる → 「今回のセッションで記録しておきたいことはありますか？」

### Step 2: エージェントが知見を組み立てる

ユーザーの概要と、**現在のセッションの文脈**（会話履歴、編集したファイル、実行したコマンド等）から、エージェントが自律的に知見を構成する。

1件のセッションから複数の知見が抽出される場合は、**それぞれ個別の Insight として登録する**。

各 Insight に設定するフィールド:

- **type**: 内容に応じて以下から選択
  - `discovery` — わかった事実・外部サービスの仕様
  - `decision` — 設計判断（rationale 必須）
  - `solution` — 問題に対する解決方法
  - `issue` — 構造的問題・後で対処すべきこと
  - `caveat` — 注意点・ハマりどころ
- **content**: 知見の概要。1-2文で簡潔に書く
- **detail**: 概要だけでは伝わらない詳細（手順、コード、背景説明等）。solution や discovery で長くなる場合に使う
- **rationale**: decision の場合は判断理由を書く
- **tags**: 内容に適したタグを自動で付与
- **repo / branch**: 現在の repo 名と branch 名を自動取得
- **followUps**: 未完了・要対応の事項があれば設定

### Step 3: 確認して送信

組み立てた内容を簡潔に提示する:

> 以下の知見を登録します。よろしいですか？
>
> 1. [discovery] Stripe API は webhook の再送を最大3日間行う  #stripe #webhook
> 2. [solution] N+1 問題を include で解消  #performance #prisma
> 3. [issue] 認証ミドルウェアの責務が肥大化  #auth #tech-debt

ユーザーが OK したら送信する。複数件ある場合は bulk API を使う。

## API 仕様

- **単件登録**: `POST http://localhost:3210/api/insights`
- **一括登録**: `POST http://localhost:3210/api/insights/bulk`
- **Content-Type**: `application/json`

### リクエストボディ

| Field | Type | Required | 説明 |
|---|---|---|---|
| type | string | Yes | `discovery`, `decision`, `solution`, `issue`, `caveat` |
| content | string | Yes | 知見の概要 |
| detail | string | No | 詳細な説明・手順・コード等 |
| rationale | string | No | 判断理由・背景 (decision では必須) |
| agent | string (max 50) | Yes | `copilot-cli` 固定 |
| repo | string (max 200) | No | リポジトリ名 |
| branch | string (max 200) | No | ブランチ名 |
| sessionId | string (max 100) | No | セッション識別ID |
| tags | string[] | No | タグ名のリスト |
| followUps | string[] | No | フォローアップ項目のリスト |
| relations | object[] | No | `{targetId, type}` 関連知見へのリンク |

### curl の実行例

```bash
# 単件登録
curl -s -X POST http://localhost:3210/api/insights \
  -H 'Content-Type: application/json' \
  -d '{
    "type": "discovery",
    "content": "Stripe API は webhook の再送を最大3日間行う",
    "agent": "copilot-cli",
    "repo": "billing-service",
    "branch": "feat/stripe-webhook",
    "tags": ["stripe", "webhook"]
  }'

# 一括登録
curl -s -X POST http://localhost:3210/api/insights/bulk \
  -H 'Content-Type: application/json' \
  -d '[
    {"type": "solution", "content": "...", "agent": "copilot-cli", "tags": ["perf"]},
    {"type": "issue", "content": "...", "agent": "copilot-cli", "tags": ["tech-debt"]}
  ]'
```

## 注意事項

- `agent` フィールドは必ず `copilot-cli` を設定すること
- API サーバー (`http://localhost:3210`) が起動していない場合はユーザーに通知すること
- content は具体的に書くこと。「問題を解決した」のような曖昧な記述は避ける
- 1セッションから複数の知見が出る場合はそれぞれ独立した Insight として登録する
- **ユーザーへの質問は最初の一言だけ。詳細はエージェントがセッション文脈から自分で組み立てる**
