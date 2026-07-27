@AGENTS.md

## 本リポジトリ自体を編集するとき
1. 複数エージェント向け設定の配布テンプレート集。設定の実体を直すときは、ignore された作業用 `.claude/` `.codex/` `.serena/` ではなく、配布物の `claude/` `hooks/` `skills/` `rules/` を編集すること
2. hook・スキル・配布設定（`claude/` `codex/`）を変更したら、必ず `bash tests/verify-all.sh` を実行して全緑（`FAIL=0`）を確認すること
  - 検証範囲: 構文 / 実行ビット / claude・codex 両方の配置シミュレーション（placeholder 置換漏れ・`[NOTE]` 解決）/ hook 全数の deny・ask・棄権 / 出力汚染 / skill-session の発火スコープ / rebase-squash E2E
  - hook やスキルを足したらテストも足す。テストを書き捨てにしない
  - `tests/` は配布対象外（`setup-agent` が配置時に削除する）

