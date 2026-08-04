---
name: meeting
description: "ユーザーの要件を受け取り、design-preflight、compose-prompt、ponytail を必要に応じて呼び分け、ユーザーにはコードベースから決められない事項だけを尋ねながら、要件監査から最小設計の承認・正式反映までを統括する"
allowed-tools:
  - Skill(design-preflight)
  - Skill(compose-prompt *)
  - Skill(ponytail)
  - AskUserQuestion
disable-model-invocation: true
---

## 目的

設計 workflow の単一入口になる。
ユーザーには要件と必要な判断だけを求め、内部 skill の選択、再実行、調査担当 model、phase 管理はエージェントが引き受ける。

## 内部構成

基本順序は次とする:

```
design-preflight → compose-prompt draft → ponytail → ユーザー承認 → compose-prompt apply
```

- **design-preflight**: 要件の穴、既存機能との衝突、副作用、未決定事項を読み取り専用で洗い出す
- **compose-prompt draft**: 確定した要件から未承認の設計ドラフトを作り、下位モデルのコードベース調査を反映する
- **ponytail**: ドラフトから不要な機能、重複実装、不要な依存、過剰な表現を削る
- **compose-prompt apply**: 最終承認済みのドラフトだけを正式反映する

後段で前提が崩れた場合は、影響する phase まで戻す。

## 対話の原則

- skill 名、呼び出し順、task-id、調査担当 model をユーザーへ選ばせない
- 目的、業務要件、受け入れる副作用など、ユーザーにしか決められない事項だけを質問する
- コードベースから判定できることは質問せず、対応する内部 skill の調査へ回す
- 質問は一度に一つだけ行い、回答の影響を評価してから次へ進む
- 既に確定した内容を聞き直さない
- 内部 skill が返した複数の論点をそのまま一括提示せず、影響の大きい未決定事項から扱う
- phase 遷移を長々と実況せず、判断が必要な理由、選択肢、挙動差、推奨だけを示す
- 各 skill の禁止事項と承認境界を引き継ぎ、wrapper を迂回路にしない

## 会話内の状態

ファイルへ進行状態を書かず、現在の会話で次を管理する:

- 要件 revision: 目的、対象範囲、既存機能との関係、受け入れた副作用
- draft revision: compose-prompt が最後に作成・更新したドラフト
- ponytail revision: ponytail が最後に確認した draft revision
- 最終承認: ユーザーが承認した ponytail revision

古い revision の調査結果、単純化結果、承認を新しい revision に流用しない。

## 実行フロー

### Step 1: 要件を受け取る

引数があれば要件として使う。引数がなければ直前の会話から対象を抽出する。対象が複数あり一意に決められない場合だけ質問する。

最初から完全な仕様を聞き出そうとしない。コードベース調査で消える質問までユーザーへ投げない。

### Step 2: design-preflight を収束させる

同じ要件 revision について有効な結果がなければ design-preflight を実行する。

design-preflight が未決定事項を返した場合は、最も影響の大きい一件だけをユーザーへ質問する。回答を新しい制約として design-preflight を再実行し、新しい穴や矛盾がないか確認する。重大な未決定事項がなくなるまで compose-prompt へ進まない。

### Step 3: compose-prompt draft を実行する

design-preflight の確定要件、受け入れた副作用、未確認事項、コード根拠を入力として、compose-prompt の `draft` mode を実行する。

- 要件の前提が崩れた場合は Step 2 へ戻す
- 設計上の判断が必要なら、一件だけユーザーへ質問して `draft` mode を再実行する
- `draft_ready` が返るまで ponytail へ進まない

### Step 4: ponytail を収束させる

現在の draft revision に ponytail を実行する。

- 挙動を変えない単純化はドラフトへ反映させる
- 機能、公開契約、data、security、互換性を変える候補は、一件だけユーザーへ質問する
- 回答で目的または対象範囲が変われば Step 2 へ戻す
- 回答で設計または完了条件が変われば Step 3 へ戻す
- ponytail が新しい実装要素を加えた場合は Step 3 のコードベース調査からやり直す

未決定事項がなく、ponytail revision が現在の draft revision と一致するまで最終承認へ進まない。

### Step 5: 最終承認を得る

現在のドラフト一式と次をユーザーへ示す:

- 確定した設計の範囲
- design-preflight で受け入れた副作用
- ponytail で省略または再利用へ置き換えた項目
- 未確認のまま残すとユーザーが明示した事項

ユーザーが現在の ponytail revision を承認するまで正式反映しない。フィードバックがあれば影響範囲に応じて Step 2、3、4 のいずれかへ戻す。

### Step 6: compose-prompt apply を実行する

最終承認後だけ compose-prompt の `apply` mode を実行する。`apply` mode が確認する draft revision と、ユーザーが承認した ponytail revision が一致しなければ反映させない。

完了時は、ユーザーが行った重要な判断、ponytail で省略した事項、正式反映した設計書を報告する。内部の全 tool call や調査ログは列挙しない。

## 失敗時の扱い

- 下位モデルへの調査委任が失敗した場合は、失敗した調査範囲を示し、推測で先へ進まない
- 内部 skill が見つからない、ドラフトが壊れている、固定反映に失敗した場合は、その phase で停止する
- ユーザーが未確認事項を明示的に受け入れた場合だけ、制約として保持して続行する
