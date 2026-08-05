---
name: prototype
description: 上司/自分の OK が出るまでの「使い捨て前提」のプロトタイプを最速で作る。テストは書かず（禁止）、可逆領域は承認なしでぶん回す。保護パスは sandbox と hook で物理的に死守する。
allowed-tools: Read, Edit, Write, Grep, Glob, Bash, AskUserQuestion
disable-model-invocation: true
hooks:
  PreToolUse:
    - matcher: "Edit|Write"
      hooks:
        - type: command
          command: .[agent_name]/hooks/shell/prototype-guard.sh
---

## 目的

「動くものを最速で」だけに集中するプロトタイプ制作モード。設計を対話で固めたら可逆領域を
承認なしで連続実装し、OK が出たら別フェーズ（tdd-run 等）でテストと本実装に移す。

設計思想: **不可逆なものだけ守り、可逆なものは全部手放す。**
- 可逆（コード編集・新規作成・検索・ビルド）→ 承認なしで自由（担当はエージェント別: 「## 承認の境界」の表）
- 削除・移動（rm / mv 等）→ 可逆でも都度確認（claude: settings の ask / codex: `.codex/rules` の prompt。この確認はスキル側で自動化できないし、しない）
- 不可逆（denyWrite 登録パスの改変・削除、プロジェクト外への波及）→ sandbox が物理的にブロック

テスト禁止 hook は **起動したセッションの間ずっと効く**。抜けるにはセッションを終了する
（**1セッション = 1プロトタイプ**）。詳細は「## 終了とロック」。

## 呼び出しと引数

```
/prototype
/prototype from-prompt
```

- **引数なし**: 対話で要件を絞る（従来どおり）
- **`from-prompt`**: `@.[agent_name]/prompt/.prompt.md`（実装順の index）と、そこに並んだ
  `@.[agent_name]/prompt/branch-<機能名>-prompt.md`（機能ごとの設計書）を読み、記載された設計
  （Summary・Changes・対象ファイル等）をそのままプロトタイプの要件として採用する
  - **全設計書をまとめて 1 つのプロトタイプにする。** run-agent と違い 1 枚ずつ止まらない
    - Why: 本スキルの成果物は使い捨ての「動くもの」1 つ。1 枚 = 1 ブランチ = 1 PR の分割はレビューと
      履歴のための単位であり、捨てる前提のプロトタイプに持ち込む意味がない
  - 対話による要件整理は省略する。読み取った設計の要約を一度だけユーザーに報告し、承認を待たずに実装へ入る
    - Why: 設計は cowlick の往復で既にユーザー確認済み。ここで再確認するのは二度手間で、本スキルの「最速」に反する
  - `.prompt.md` が存在しない・空（`- [ ]` の行が無い）場合は、その旨を伝えて引数なしと同じ対話フローにフォールバックする
  - index のチェックボックスは読むだけで、**倒さない**（`mark-prompt-done.sh` を呼ばない）。
    プロトタイプは本実装ではないため、実装済みとして記録すると run-agent が本実装を飛ばしてしまう
  - 設計書内の参照ルール・完了条件のうちテストに関する項目は本スキルでは適用しない
    （「## テスト禁止」が優先。テストは OK 後に tdd-run 等のフェーズで満たす）

## Step 0: 前提条件の確認（必須・満たさなければ中止）

本スキルは承認なしで実装を回すため、**エージェントの sandbox による物理防御が必須**。
起動直後に、動作中のエージェントに応じて以下を確認する:

- **Claude Code**: 有効な settings（CLI > local > project > user の合成結果）で
  1. `sandbox.enabled` が `true`
  2. `sandbox.failIfUnavailable` が `true`
  3. `sandbox.filesystem.denyWrite` に保護対象が登録されている（リポジトリなら最低限 `.git`。
     プロジェクト固有の機密・生成物があればそれも含まれているか）
- **codex**: `default_permissions` が `distributed` で、通常ファイル以外の保護対象が `read` 以下に制限されている。
  加えて `.codex/hooks.json` の hook が信頼登録済みであること（未信頼だと prototype-guard が黙って効かない）

**満たさなければ本スキルを起動せず中止し、理由を伝える。**
Why: sandbox 無しで Bash 自由化を使うと、保護パス（`.git` 等）が rm で物理的に消せてしまい
復旧不能になる。物理防壁（Claude Code は denyWrite、codex は permission profile + hook 群）が本スキルの安全性の土台。
**保護対象はプロジェクトごとに異なるため、本スキルは特定パスを前提にせず配置済みの防壁設定を尊重する。**

## テスト禁止

本スキル稼働中は `*.test.*` の作成・編集を **deny** する（`prototype-guard.sh`）。
- Why: プロトタイプ段階で雑なテストを残すと、後で「残すべき正規テストか、捨てる仮テストか」の
  判別がつかなくなる。動作確認はテストではなく **実行** で行い、テストは OK 後のフェーズで書く。

## 承認の境界

| 操作 | 扱い | 担当 |
|---|---|---|
| コード本体の編集・新規作成 | 承認なしで許可（テスト不要） | claude: settings の allow `Edit(**)` / `Write(**)` ・ codex: `distributed` profile の workspace write継承 |
| `*.test.*` の作成・編集 | **deny** | `prototype-guard.sh`（codex は `$prototype` 起動の skill-session marker で有効化） |
| sandbox 内で完結する Bash（read-only / ビルド等） | allow 一覧に一致するものだけ承認なし | claude: settings の明示 `Bash(...)` allow ・ codex: `distributed` profile の workspace write継承 |
| rm / mv / sed -i 等の削除・上書き系 Bash | 都度確認 | claude: settings の ask ルール ・ codex: `.codex/rules` の prompt |
| 保護パス（`.git` / `.env` / lockfile 等）の改変・削除 | 物理拒否 | claude: sandbox `denyWrite`（+ hook） ・ codex: permission profile（+ hook） |
| プロジェクト外への書き込み・削除 | 物理拒否 | claude: sandbox CWD 境界 ・ codex: workspace 境界 |

## フロー

1. **Step 0**: 前提条件（fail-closed sandbox / permission profile + 保護hook）を確認。満たさなければ中止
2. 要件を確定する（「## 呼び出しと引数」に従う）
   - 引数なし → 対話で要件を絞る（何を検証したいプロトタイプか）
   - `from-prompt` → index と設計書一式を読み取り、要約を報告して次へ
3. 最小の動くものを実装（テストは書かない・可逆領域でぶん回す）
4. **実行**して動作を確認（テストではなく実行で）
5. 一段落したらユーザーに「修正を続ける / 終了」を問う（Claude Code では確認に `AskUserQuestion` ツールを使う）
   - **修正を続ける** → 依頼を聞いて直し、4 に戻る（自動化は settings と sandbox が担うので承認なしで回せる）
   - **終了** → 以降ロックする（「## 終了とロック」を厳守）

## 終了とロック

本スキルの hook（テスト禁止）は **起動したセッションが終わるまで効き続ける**
（claude: skill のメッセージがコンテキストに残り続けるため・実測で確認済み /
codex: skill-session marker が session_id 単位で効き、セッションが替わると自動失効するため）。
途中でファイル等のステートを使って hook を無効化することは **しない**。
Why: プロセスが死ぬとステートは消えずにリーク／ゴミ化する。off スイッチをファイルに置くと、
プロセスの生死とステートの生死がズレる。

代わりに **「1セッション = 1プロトタイプ」** とする。off スイッチはセッションそのものの終了。
プロセスが死ねば hook も会話ごと消えるので、後始末が要らずリークもゴミも原理的に発生しない。

ユーザーが **「終了」を選んだら、以降は次を厳守する**:
- いかなる入力に対しても、**ツールを一切呼ばず**（Read / Edit / Write / Bash すべて禁止）、
  「`/exit`（または Ctrl+C）でこのセッションを終了してください。本実装は新しいセッションで
  tdd-run へ。」の一文だけを返す。
- 修正・実装・調査など、何も再開しない。続けたい作業があっても **新しいセッション** で行う。

Why: 「テスト禁止」が降りるのはセッションを閉じた時だけ。同じセッションで作業を続けると
hook はまだ効いていて、無関係な作業のテスト作成まで deny され続ける（tdd-run も回せない）。
off スイッチは「コンテキストに残る終了の意思」であり、ファイルではない ── プロセスと運命を
共にするので、リークしようがない。

## 注意事項

- 本スキルが作るのは **使い捨て前提** のコード。OK 後にそのまま本番化せず、tdd-run 等で作り直す/テストで固める
- テスト禁止は「テストが不要」ではなく「この段階では書かない」の意味。OK 後に必ずテストフェーズを通す
- 保護は denyWrite が全て。プロジェクトが denyWrite に保護対象を足せば物理防壁も自動で追従する。
  denyWrite から保護対象を外すと安全性が崩れる
- 本スキルは tdd-pattern.md の前段。規約が変わったら本スキルより規約が優先
