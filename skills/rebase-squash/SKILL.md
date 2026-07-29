---
name: rebase-squash
description: "1 ファイル = 1 コミットで積んだ [[agent_name]]: 履歴を、未 push 範囲だけ機能単位に squash する。分類は LLM・履歴操作は決定的スクリプト（temp worktree リプレイ → 二重検証 → swap）。正常系の承認ゲートはグルーピング承認の 1 つだけ"
allowed-tools: Read, Grep, Glob, Bash, Write, AskUserQuestion
disable-model-invocation: true
---

## 目的

「[[agent_name]]: {ファイル名}/{変更内容}」の 1 ファイル = 1 コミット運用で積み上がった細かいコミットを、
レビューに出せる機能単位の履歴へ組み替える。**履歴書き換えの唯一の公認経路**であり、
生の rebase / filter-branch / force push は deny-history-rewrite.sh が deny する。

設計思想（verify-then-swap）: 「どうまとめるか」という曖昧な判断は LLM と人間ゲートが担い、
履歴操作はレビュー済みの `rebase-squash.sh` に閉じ込める。スクリプトは temp worktree で
リプレイを完走させ、「plan が対象範囲を exactly-once で消費」「squash 後の tree が元 HEAD と
同一（diff 空）」の二重検証に合格して初めて本体ブランチを 1 回だけ動かす。
**検証前に本体ブランチと作業ツリーには一切触れない**ため、失敗時は temp が消えるだけで
本体は無傷 — 復元という工程そのものが存在しない。

## 承認ゲートは 1 つだけ

| ゲート | タイミング | 手段 |
|---|---|---|
| **GATE: グルーピング承認** | plan 確定時に 1 回 | ユーザーへの確認（承認 / 調整） |

コンフリクト等で plan を作り直した場合は再度 GATE を通す（新しい plan は新しい契約）。
それ以外でユーザーに確認を求めない（Claude Code では確認に `AskUserQuestion` ツールを使う）。

## 実行フロー

### Step 0: 前提検査（スクリプト）

```
bash [skills_root]/rebase-squash/rebase-squash.sh --check [--base <ref>]
```

- clean tree / merge コミットなし / **範囲の全コミットが全リモート ref から不可視** /
  `[[agent_name]]:` 以外のコミットは境界（それより古い側は対象外）— 判定はすべてスクリプトが機械的に行う
- upstream が無いリポジトリでは `--base` が必須。どこを起点にするかはユーザーに確認する
- `NOTHING-TO-DO` が出たら正直にそう報告して終了する。無理にやることを探さない

### Step 1: 分類（read-only）

`--check` が出力する「コミット + 変更ファイル」一覧（古い順）から機能単位を作る。判断基準:

- api とバリデーションスキーマは同一単位
- コンポーネントは 1 コンポーネントで 1 単位
- マイグレーションファイルとスキーマ変更は同一単位
- ヘルパー関数・定数・変数への置き換えは、置き換え先の変更と同一単位
- テストファイル（`*.test.*`）は対象実装と同一単位
- linter / prettier 対応コミットは、そのファイルが属するグループに入れる
  （グループ内の適用順はスクリプトが元履歴順に再ソートするため、自動的に「そのファイルの
  最後の変更の後」に適用される。特別扱いは不要）
- メッセージと変更ファイルから判断できないコミットは独立グループとして提示し、GATE で人間に決めさせる

**静的交差検査**: 同一ファイルを触る 2 つのグループが元履歴で交差している場合、リプレイが
コンフリクトする可能性がある。plan 提示時にその旨を明記し、必要なら提示前に併合する。

### GATE: グルーピング承認（停止）

「元コミット → グループ → 新 subject」の対応表を提示してユーザーに承認・調整を求める。
subject は「`[[agent_name]]: {機能}/{変更内容(日本語)}`」形式。承認が出るまで実行に進まない。

### Step 2: 実行（スクリプト）

plan を scratchpad に JSON で Write してスクリプトに渡す:

```json
{
  "base": "<--check が出力した BASE の full sha>",
  "groups": [
    { "subject": "[[agent_name]]: 契約一覧API/一覧取得APIとバリデーションスキーマを追加した",
      "commits": ["<sha>", "<sha>"] }
  ]
}
```

```
bash [skills_root]/rebase-squash/rebase-squash.sh <plan.json> [--base <ref>]
```

- groups の並び = squash 後のコミット順。グループ内の commits の並びは無視される
  （スクリプトが元履歴順に再ソートする）
- スクリプトは実行前に plan を再検証する（base 一致 / exactly-once / subject の契約形式 /
  AI 署名不在）。エージェントは git コマンドで履歴に触らない — 触ろうとしても hook が deny する
- **コンフリクトで死んだら**: 本体は無傷。交差していたグループを併合するか、並べ替えを諦めて
  「元履歴で連続している run だけを squash する」縮退 plan に組み直し、GATE からやり直す
- **空グループで死んだら**: revert とその対象が同一グループで相殺されている。plan を組み直す

### Step 3: 報告

squash 後の履歴・元 HEAD の sha・検証結果（tree 一致 / exactly-once）を報告する。

- **push はしない**。squash 後の履歴を最終確認して push するのは人間の仕事
- backup ブランチは残らない。swap の間だけ張る一時的な足場で、成功したらスクリプトが自ら削除する
  （元 HEAD は reflog から辿れる）。`backup/rebase-squash-*` が残っていたら swap が失敗した証拠なので、
  その確認と削除は人間の仕事（エージェントによる削除は deny-history-rewrite.sh が deny する）

## 注意事項

- squash 後の commit は `--no-verify` で作られる。内容は元コミット時点で hook を通過済みの
  内容保存変換であり、配布先の commit hook（フォーマッタ等）が tree を書き換えると
  tree 同一性検証が壊れるため
- author date は失われる（squash とは元々そういう操作）。identity は git config の本人のまま、
  Co-Authored-By 等の AI 署名は入らない — enforce-claude-commit.sh と同じ契約をスクリプトが内蔵する
- commit message は plan の subject 1 行のみで body は付けない。何をまとめたかを元履歴で
  確認したい場合は reflog の元 HEAD を辿る（squash 直後の報告に元 HEAD の sha を出す）
- 本スキルは AGENTS.md「Git 運用」の従属物。規約が変わったら本スキルより規約が優先
