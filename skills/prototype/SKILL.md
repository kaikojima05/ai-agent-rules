---
name: prototype
description: 上司/自分の OK が出るまでの「使い捨て前提」のプロトタイプを最速で作る。テストは書かず（禁止）、可逆領域は承認なしでぶん回す。denyWrite 登録パスは sandbox で物理的に死守する。
allowed-tools: Read, Edit, Write, Grep, Glob, Shell, AskUserQuestion
disable-model-invocation: true
hooks:
  PreToolUse:
    - matcher: "Edit|Write"
      hooks:
        - type: command
          command: .claude/hooks/shell/prototype-guard.sh
    - matcher: "Bash"
      hooks:
        - type: command
          command: .claude/hooks/shell/allow-prototype-bash.sh
---

## 目的

「動くものを最速で」だけに集中するプロトタイプ制作モード。設計を対話で固めたら可逆領域を
承認なしで連続実装し、OK が出たら別フェーズ（tdd-run 等）でテストと本実装に移す。

設計思想: **不可逆なものだけ守り、可逆なものは全部手放す。**
- 可逆（コード編集・新規作成・denyWrite 対象外の rm/mv・検索・ビルド）→ 承認なしで自由
- 不可逆（denyWrite 登録パスの改変・削除、プロジェクト外への波及）→ sandbox が物理的にブロック

## Step 0: 前提条件の確認（必須・満たさなければ中止）

本スキルは Bash を広く自動許可するため、**sandbox による物理防御が必須**。
起動直後に、有効な settings（CLI > local > project > user の合成結果）に対し以下を確認する:

1. `sandbox.enabled` が `true`
2. `sandbox.filesystem.denyWrite` に保護対象が登録されている（リポジトリなら最低限 `.git`。
   プロジェクト固有の機密・生成物があればそれも含まれているか）

**満たさなければ本スキルを起動せず中止し、理由を伝える。**
Why: sandbox 無しで Bash 自由化を使うと、denyWrite 登録パス（`.git` 等）が rm で物理的に消せてしまい
復旧不能になる。denyWrite（OS 境界）が保護対象の唯一の物理防壁であり、本スキルの安全性の土台。
**保護対象はプロジェクトごとに異なるため、本スキルは特定パスを前提にせず denyWrite の中身を尊重する。**

## テスト禁止

本スキル稼働中は `*.test.*` の作成・編集を **deny** する（`prototype-guard.sh`）。
- Why: プロトタイプ段階で雑なテストを残すと、後で「残すべき正規テストか、捨てる仮テストか」の
  判別がつかなくなる。動作確認はテストではなく **実行** で行い、テストは OK 後のフェーズで書く。

## 承認の境界

| 操作 | 扱い | 担当 |
|---|---|---|
| コード本体の編集・新規作成 | 承認なしで許可（テスト不要） | `prototype-guard.sh` |
| `*.test.*` の作成・編集 | **deny** | `prototype-guard.sh` |
| 可逆な Bash（read-only / ビルド / denyWrite 対象外の rm・mv） | 承認なしで許可 | `allow-prototype-bash.sh` |
| denyWrite 登録パスに触れる Bash | ask（自動許可しない・denyWrite を動的に参照） | `allow-prototype-bash.sh` |
| denyWrite 登録パスの実際の改変・削除 | 物理拒否 | sandbox `denyWrite` |
| プロジェクト外への書き込み・削除 | 物理拒否 | sandbox CWD 境界 |

## フロー

1. **Step 0**: 前提条件（sandbox + denyWrite）を確認。満たさなければ中止
2. 対話で要件を絞る（何を検証したいプロトタイプか）
3. 最小の動くものを実装（テストは書かない・可逆領域でぶん回す）
4. **実行**して動作を確認（テストではなく実行で）
5. OK が出たら完了。後続フェーズ（tdd-run でテスト化 → 本実装）へ引き継ぐ

## 注意事項

- 本スキルが作るのは **使い捨て前提** のコード。OK 後にそのまま本番化せず、tdd-run 等で作り直す/テストで固める
- テスト禁止は「テストが不要」ではなく「この段階では書かない」の意味。OK 後に必ずテストフェーズを通す
- 保護は denyWrite が全て。`allow-prototype-bash.sh` は特定パスをハードコードせず denyWrite を動的に読むので、
  プロジェクトが denyWrite に保護対象を足せば backstop も自動で追従する。denyWrite から保護対象を外すと安全性が崩れる
- 本スキルは tdd-pattern.md の前段。規約が変わったら本スキルより規約が優先
