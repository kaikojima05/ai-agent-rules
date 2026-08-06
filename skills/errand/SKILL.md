---
name: errand
description: "ユーザーが $errand を明示して、既存パターンへ収まる小さく一意な本体コード修正を設計書なしで DeepSeek へ委任したいときだけ使う。新機能設計、要件判断、設定・schema・依存関係の変更には使わない。"
allowed-tools: Read, Edit, Write, Grep, Glob, Bash
disable-model-invocation: true
---

## 目的

設計書を作る価値がないほど小さく、依頼と既存の契約から変更内容・対象本体コード・完了条件を一意に確定できる実装だけを委任する。上位モデルは要件の縮約、許可パスの決定、候補パッチの採否、検証、Gitを担当する。DeepSeekは隔離 worktree で本体コードの候補パッチだけを作る。

## 起動境界

ユーザーが明示的に errand を呼んだ場合だけ使う。通常の自然言語依頼から自動起動してはならない。meeting / cowlick / ponytail は呼ばない。

次のいずれかなら、変更せず理由を報告して停止する。meeting を自動で起動してはならない。

- 要件、公開挙動、対象パス、完了条件のいずれかを一意に決められない
- 新しい API、認可境界、DB、migration、schema、設定、依存関係、CI、スキル、Git 管理ファイルを変更する
- 新しいテストシナリオまたは既存テストの意味変更が必要になる
- 許可する本体コードに未コミット変更がある

## 実行手順

1. ユーザーの依頼だけから、変更後の公開挙動、完了条件、候補となる本体コードを短く固定する。上の停止条件に当たるなら停止する。
2. 既存の実装挙動を調査する必要がある場合は、上位モデルが Read / Grep / Glob / 検索コマンドで調べず、DeepSeek の survey mode を先に実行する。

   ~~~bash
   bash [skills_root]/conductor/delegate-deepseek.sh survey <task-id> <調査指示>
   ~~~

   結果ディレクトリの result.json、opencode.jsonl、candidate.patch を読み、根拠と未確認事項だけを受け取る。DeepSeek が失敗・中断・根拠不足なら上位モデルが自力調査へ切り替えず停止する。
3. 依頼と survey 結果だけから、変更内容、守る既存パターン、完了条件を含む短い実装指示を作る。対象は追跡済みで clean な本体コードだけにする。テスト、Markdown、設定、schema、migration、lockfile、環境変数、Git 管理ファイルを許可対象にしてはならない。
4. 固定実行器へ実装を委任する。

   ~~~bash
   bash [skills_root]/conductor/delegate-deepseek.sh errand <task-id> <短い実装指示> -- <許可する本体コード>
   ~~~

   DeepSeek にテスト、設定、Git、設計資産を変更させない。task-id は lowercase kebab-case とし、同じ task-id を再利用しない。
5. result.json、opencode.jsonl、candidate.patch を読み、候補パッチを確認する。許可パス外の変更、曖昧さの握り潰し、ハードコード、既存契約との不一致があればパッチ全体を拒否する。
6. 採用した候補だけを反映し、対象の既存テスト、型検査、lint、回帰確認を実行する。追跡対象は 1 ファイルずつコミットする。必要なテストシナリオが増えた場合は変更を進めず停止する。

## 完了報告

依頼、DeepSeek の survey / errand task-id、許可パス、候補パッチの採否、実行した検証、コミットを簡潔に報告して停止する。
