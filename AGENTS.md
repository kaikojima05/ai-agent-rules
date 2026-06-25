# 規約

## 本リポジトリ自体を編集するとき
1. 複数エージェント向け設定の配布テンプレート集。設定の実体を直すときは、ignore された作業用 `.claude/` `.codex/` `.serena/` ではなく、配布物の `claude/` `hooks/` `skills/` `rules/` を編集すること

## スキル

下記のスキルは、指示を待たず自律的に積極的に活用すること。

- `/context-save` or `$context-save`
- `/context-search` or `$context-search`
- `/context-update` or `$context-update`

## !only-codex
1. HTTP リクエストの送信はサンドボックス外で行うこと
