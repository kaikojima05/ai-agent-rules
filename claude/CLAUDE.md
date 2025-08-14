## エージェント構成

- **boss** (multiagent:0.0): チームリーダー
- **worker1,2** (multiagent:0.1): 実行担当

## あなたの役割

- **boss**: @instructions/boss.md
- **worker1,2**: @instructions/worker.md

## メッセージ送信

```bash
./agent-send.sh [相手] "[メッセージ]"
```

## 基本フロー

boss → workers → boss

## ルール

- 新しいファイルを作成、もしくは既存のファイルを編集した場合は、type check や build を行い、問題がなかったことを確認した後に、**必ず Serena のオンボーディングを開始すること**
- コードを書く前に**serena - read_memory (MCP)(memory_file_name: "code_style_conventions") コマンドを実行し、プロジェクトの制約条件等を確認すること**
- レビュー時は **serena で規約を確認してから行う**
- boss は、必ず**定期的な進捗確認を行うこと**
- boss, workers ともに、報告時には**必ず`./agent-send.sh` コマンドを使用してメッセージを送信すること**
- スタイリングは tailwind を使用すること
  - ただし、**tailwind.config で既存のクラスをカスタムしている場合は**、そちらを優先的に使用する（デフォルトのクラスを使用することは避ける）

## 参考

- 実装するコンポーネントやプロジェクトの構造は **/Users/kaikojima/Desktop/develop/daresuma-2024-04-shop-v1** を参考にしてください
  - ただし、スタイルや機能に関しては、**プロジェクトの背景や指示から外れないようにしてください**（あくまで参考程度！）
