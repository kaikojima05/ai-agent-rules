---
name: run-prompt
description: [agent_name]/prompt/.prompt.md の内容を実行する
allowed-tools: Shell
disable-model-invocation: true
---

## 目的

「@.[agent_name]/prompt/.prompt.md の内容を実行する」の定型文を省略する。

## 実行フロー

### Step 1: スキルを呼び出す

スキルは引数なし

```
/run-prompt
```

### Step 2: エージェントが @.[agent_name]/prompt/.prompt.md の内容を確認・実行する
