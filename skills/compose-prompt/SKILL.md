---
name: compose-prompt
description: "機能ごとの設計書と実装順の index を対話で組み立て、@.[agent_name]/prompt/ へ反映する"
allowed-tools: Read, Write, Edit, Bash
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

### Step 2: [agent_name]が初期ドラフトを作成する

整理された要件を元に、[agent_name]がプロンプトの初期ドラフトを作成する。この時点では未承認であり、`.[agent_name]/prompt/`へ反映しない。

ドラフトは「後述の構成の一式」を **プロジェクトルートの `draft-prompt/`** に作る（`.prompt.md` + `branch-<機能名>-prompt.md` × N）。
ディレクトリの中身はこの 2 種類だけにすること。メモや作業ファイルを同居させると Step 3 のスクリプトが弾く。

- Why: ユーザーがレビューする対象なので、エディタでそのまま開ける場所に置く。セッションの一時領域（scratchpad / `$TMPDIR`）はパスが不規則でユーザーが確認しづらい
- Why: `.[agent_name]/` は sandbox の denyWrite で保護されておりエージェントは直接書き込めない。`draft-prompt/` は保護対象外なので通常の Write / Edit で往復でき、保護領域への書き込みは Step 3 の固定スクリプト 1 回に集約される
- `draft-prompt/` は Step 3 でスクリプトが畳むまでの一時的な置き場。**コミットしてはならない**（`git add` の対象に含めない。恒久的に無視したいならプロジェクトの `.gitignore` に足すのはユーザーの判断）
- ドラフトの改訂は **Edit** で行う。既存ファイルへの Write（全上書き）は `guard-overwrite.sh` が ask に倒すため、レビュー往復のたびに承認プロンプトが出る（新規作成の Write は素通りするので初回作成はそのままでよい）

### Step 3: DeepSeekへコードベース調査を委任する

各設計書の初期ドラフトを、固定実行器の`research`モードへ1枚ずつ渡す。

```
bash [skills_root]/run-agent/delegate-deepseek.sh research <task-id> draft-prompt/branch-<機能名>-prompt.md
```

- DeepSeekは読み取り専用とし、コード、テスト、設計ドラフトを変更させない
- 調査結果は`file:line`の根拠、不明点、設計リスクとして返させる
- [agent_name]が重要な根拠を実ファイルで再確認する。DeepSeekの自己申告だけで設計へ採用しない
- 調査失敗、予算超過、ZDR対応先なしの場合は理由を報告し、推測で穴埋めしない

調査結果を踏まえて[agent_name]がドラフトを更新する。既存の会話と異なる設計判断が必要なら、[agent_name]だけで決めずユーザーとの相談へ戻る。

### Step 4: ユーザーがドラフトを確認する

ユーザーは設計内容を確認し、必要に応じてフィードバックする。[agent_name]はドラフトを修正し、承認が得られるまで正式な設計へ反映しない。

### Step 5: ドラフト一式を @.[agent_name]/prompt/ へ移す

ユーザーの確認が取れたら、専用スクリプトでドラフトを反映する。**引数は取らない** — 移動元（`draft-prompt/`）・宛先（`.[agent_name]/prompt/`）・受け入れるファイル名（`.prompt.md` と `branch-<機能名>-prompt.md`）がすべてスクリプト内に固定されているため、サンドボックス外実行の事前 allow はこの経路 1 本に限定される。

```
bash [skills_root]/compose-prompt/apply-prompt.sh
```

- スクリプトは反映前に「中身が index と設計書だけか」「index が並べた設計書と実体が 1:1 で対応するか」を検証し、1 つでも外れたら宛先に触れずに終了する
- 全件の反映に成功したら `draft-prompt/` をスクリプトが畳む。ユーザーが `rm` を承認する必要はない
  - Note: 消せるのは固定パスの `draft-prompt/` と、そこにある検証済みの index / 設計書だけ。**引数を受け取らないため削除先を外から動かせず**、`rm` の ask ゲートを迂回する任意ファイル削除の抜け道にならない。この性質を壊すので、後からドラフトのパスを引数で受け取れるようにしてはならない
  - `rmdir` で畳むため、想定外のファイルが残っていればディレクトリは消えずに警告が出る（再帰削除で巻き込むことはない）
- 前タスクの `branch-*-prompt.md` が宛先に残っていた場合は、今回の一式に無いものだけをスクリプトが削除する
  - Why: 残骸があると index と実体が食い違い、run-agent が前タスクの設計書を実装してしまう

- Claude Code では本スクリプトは `settings.json` の `sandbox.excludedCommands` に登録済みのため、そのまま実行すれば最初から sandbox 外で走る（sandbox 内では denyWrite の `.[agent_name]` に阻まれて必ず失敗する）
  - `excludedCommands` と事前 allow はコマンド文字列の照合で決まるため、必ずプロジェクトルートから**上記の 1 行をそのまま単独で**実行すること。以下はいずれも照合を外し、sandbox 内実行の失敗と承認プロンプトを復活させる
    - 絶対パスにする / `./` の有無を変える / `bash` を `sh` に変える — パスは正規化されず、文字列が違えば別のコマンドとして扱われる
    - `cd ... &&` を前置する、`&&` `;` `|` で他のコマンドと繋ぐ — 複合コマンドは区切り文字で分割され、**各サブコマンドが個別に**照合される。繋いだ相手が許可されていなければプロンプトが出る
    - `> log 2>&1` などのリダイレクトを付ける — リダイレクト先の解決可否によってはプロンプトに倒れる
- 「Operation not permitted」で失敗した場合は、まず呼び出しが上記の相対パス形式かを確認し、違っていれば形式を直して再実行する。相対パス形式でも失敗する場合のみ `excludedCommands` 未設定の古い配置と判断し、sandbox を無効化して再実行のうえ `settings.json` の更新をユーザーに案内すること
- Codex では `distributed` permission profile が `.codex` を保護し、`.codex/rules/default.rules` が `bash .agents/skills/compose-prompt/apply-prompt.sh` だけを sandbox 外で allow する。失敗時は迂回せず、project の信頼と rules 配置を確認すること

## 成果物の構成

成果物は「実装順の index 1 枚」と「1 機能 = 1 枚の設計書」で構成する。以下の形式は任意ではなく必須とする。

| ファイル | 役割 |
|---|---|
| `.prompt.md` | 実装順の index。**実装順のリストだけ**を書き、設計の中身は書かない |
| `branch-<機能名>-prompt.md` | 機能 1 つ分の設計書。index に並べた数だけ作る |

- Why: 構成を書き手の裁量に任せると、使用するモデルや reasoning effort によって出力の粒度が大きくブレる。形式を固定し、どのモデルが書いても同じ粒度の設計書になるようにする
- Why: 巨大なタスクでも文章の要約なら数十行に収まってしまい、最終的な実装規模が読めない。設計書の枚数と Changes の行数が、そのままタスク規模の見積もりとして機能するようにする
- Why: 設計書をファイルとして分けることで、run-agent が 1 枚だけ読んで 1 枚だけ実装できる。index のチェックボックスがそのまま進捗になる

### 機能名の付け方

`branch-` 接頭辞のとおり、機能名は **そのまま git のブランチ名に使える ASCII の kebab-case** とする（`user-address-api` など）。
日本語や `_` / 大文字始まりは apply-prompt.sh が弾く。

### 「1 機能」の粒度

設計書 1 枚に収める「1 機能」は rebase-squash スキルの分類基準と揃える（設計書 1 枚 ≒ 1 ブランチ ≒ squash 後の 1 コミット）:

- api とバリデーションスキーマは同一の 1 枚
- コンポーネントは 1 コンポーネントで 1 枚
- マイグレーションファイルとスキーマ変更は同一の 1 枚
- ヘルパー関数・定数への置き換えは、置き換え先の変更と同一の 1 枚
- テスト（`*.test.*`）は対象実装と同一の 1 枚（独立した設計書にしない）

### index（.prompt.md）のテンプレート

実装順に並べたチェックリストのみ。**設計の中身は一切書かない。** 全項目を `- [ ]`（未実装）で作る。

```markdown
# 実装順

- [ ] branch-user-address-api-prompt.md
- [ ] branch-user-address-form-prompt.md
```

- 並び順 = 実装順。依存がある場合は依存される側を先に置く
- `- [ ] <ファイル名>` 以外の形式で書くと apply-prompt.sh が弾く（見出しや説明文の行は自由）
- `[x]` に倒すのは run-agent の仕事。compose-prompt では全件 `[ ]` で出す

### 設計書（branch-<機能名>-prompt.md）のテンプレート

Summary / Changes / 対象ファイル / 参照ルール / 完了条件 のセクションを必ず持つ。

- **Summary**: この機能で何をするかを 1〜2 行で書く
- **Changes**: 具体的な変更内容を、後述の疑似コード形式の文章で書く
- **完了条件**: 各設計書に持たせる（run-agent は 1 枚だけ読んで 1 枚だけ実装するため、1 枚で自己完結させる）

### Changes の書き方

処理の流れをコードの形で書き、中身を日本語の文章で埋める疑似コード形式とする。

1. 予約語・構文キーワード・ライブラリ API 名は英語のまま書く（import / export / function / const / let / if / for / async / await / $transaction / Promise.all など）
  - Why: 実装時に必ずその単語になるものを日本語に翻訳しても情報は増えない。逆に英語のまま残すことで「どの構文・API を使うか」という設計判断が Changes の時点で確定する
2. 分岐・ループは「〜の場合は」と文章で流さず、`if (...) { }` `for (...) { }` の構文で書き、条件と処理内容だけを日本語にする
  - Why: 分岐・ループの数がそのまま Changes の行数に現れることで、実装規模の見積もりが機能する
3. 関数名・引数名・処理の説明は日本語の文章で書く（実装時の英語命名はエージェントに委ねる）
4. エラー処理・副作用（DB 書き込み、メール送信、外部 API 呼び出し等）は省略せず 1 つずつ書く。行数を節約するための要約は禁止する
  - Why: ここで省略した処理は実装時にモデルの裁量で補われ、成果物がブレる

### 記入例

住所変更機能を API とフォームの 2 機能に割った場合、`draft-prompt/` は次の 3 ファイルになる。

**draft-prompt/.prompt.md**

```markdown
# 実装順

- [ ] branch-user-address-api-prompt.md
- [ ] branch-user-address-form-prompt.md
```

**draft-prompt/branch-user-address-api-prompt.md**

````markdown
# 住所変更 API

## Summary

マイページからユーザー自身の住所を変更できる API を追加する。

## Changes

```typescript
// user-address-api.ts
export function ユーザーの住所を変更する関数(ログイン中のユーザーデータ, 変更後の住所) {
  ログインチェックを行う

  for (登録済みの住所 of ユーザーの住所一覧) {
    if (渡された住所と重複している) {
      API エラーを返す
    }
  }

  $transaction {
    User テーブルの address カラムに渡された住所を書き込む
  }

  書き込みが成功したらユーザーのメールアドレスに住所変更完了のメールを送付し、
  クライアント側に 200 を返す
}
```

## 対象ファイル
- @front/features/mypage/resources/user/user-address-api.ts
- @front/features/mypage/resources/user/schema.ts

## 参照ルール
- @.[agent_name]/rules/typescript/api-pattern.md
- @.[agent_name]/rules/typescript/validation-pattern.md

## 完了条件
- Changes に書かれた処理が実装されていること
- 型エラー、フォーマットエラーがないこと
````

**draft-prompt/branch-user-address-form-prompt.md**

````markdown
# 住所変更フォーム

## Summary

マイページに住所変更フォームのコンポーネントを追加する。

## Changes

```typescript
// UserAddressForm.tsx
export function 住所変更フォーム(現在の住所) {
  const 入力中の住所 = フォームの状態として保持する

  送信ボタン押下で住所変更 API を呼び出す

  if (API がエラーを返した) {
    フォーム下部にエラーメッセージを表示する
  }

  成功したら完了トーストを表示する
}
```

## 対象ファイル
- @front/features/mypage/resources/user/components/UserAddressForm.tsx

## 参照ルール
- @.[agent_name]/rules/typescript/ui-pattern.md

## 完了条件
- Changes に書かれた処理が実装されていること
- 型エラー、フォーマットエラーがないこと
````
