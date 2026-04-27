---
name: re-apply-rules
description: re-apply-rules copilot-instructions.md の内容を再確認する
allowed-tools: Shell
---

## 目的

一定量のコンテキストが蓄積されたことにより「失われている可能性のある」エージェントの規約を再確認させる。

## 実行フロー

### Step 1: スキルを呼び出す

スキルは run オプション付きで呼び出せる:

```
/re-apply-style --run-prompt
```

- **オプションあり**: **Step2** の実行後に、続けて `run-prompt` スキルを実行する
- **オプションなし**: **Step2** を実行して終了

### Step 2: エージェントが @.github/copilot-instructions.md の内容を確認する

## 注意事項

- 確認した規約の内容をユーザーに報告する必要はない。
- 確認した規約は最重要事項として最新のコンテキストに反映させる。
