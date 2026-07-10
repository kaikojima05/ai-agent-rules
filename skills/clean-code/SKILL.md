---
name: clean-code
description: 実装完了後にフォーマッタおよびリンターを実行し、コード品質とスタイルを修正する。 
allowed-tools: Read, Grep, Glob, Shell
disable-model-invocation: true
---

## 目的

未ステージング・ステージング済みのファイルに対して、コードの品質維持およびプロジェクトのスタイルガイドへの準拠を目的として、自動整形（Format）と静的解析（Lint）を実行します。

## ガイドライン

### 実行方法（共通）

1. `package.json` の scripts に該当タスク（`format` / `lint` / `typecheck` 等）があれば **script 経由**（`yarn <script>`）を最優先で使うこと
2. script が無い場合のみ、下記の `node_modules/.bin/<tool>` を直接実行すること
3. **`npx` での起動は禁止**（未導入だと registry へ取りに行くため hook が deny する。`tdd-pattern.md` の test script 規約と同根）
4. ツールが未導入（`node_modules/.bin` に無い）場合は install せず、ユーザーに相談すること（install 系も deny される）

### コード整形

プロジェクトの構成を確認し、以下のいずれかの設定ファイルに基づいて整形を実行すること。

- **Prettier**: `.prettierrc` (または関連設定ファイル) を検知した場合
  - 設定ファイルが存在するディレクトリにて `node_modules/.bin/prettier --write .` を実行する。
- **Biome**: `biome.json` を検知した場合
  - 設定ファイルが存在するディレクトリにて `node_modules/.bin/biome format --write .` を実行する。

### 静的解析・修正

プロジェクトの構成を確認し、以下のいずれかの設定ファイルに基づいて修正を実行すること。

- **ESLint**: `.eslintrc.js` または `.eslintrc.json` を検知した場合
  - 設定ファイルが存在するディレクトリにて `node_modules/.bin/eslint . --fix` を実行する。
- **Biome**: `biome.json` を検知した場合
  - 設定ファイルが存在するディレクトリにて `node_modules/.bin/biome lint --apply .` を実行する。
- **typecheck**: `tsconfig.json` を検知した場合
  - ESLint or Biome の設定ファイルが存在しなかった場合は、tsconfig.json が存在するディレクトリにて `node_modules/.bin/tsc --noEmit` を実行する。

### DBスキーマの整形

- **Prisma**: `prisma/schema.prisma` を検知した場合
  - 設定ファイルが存在するディレクトリにて `node_modules/.bin/prisma format` を実行する。

## 注意事項
- 実行前に必ず設定ファイルの有無を確認し、プロジェクトに最適なツールを選択すること。
- エラーが発生した場合は、メッセージを確認し、必要に応じて手動修正またはタスクの再試行を検討すること。
- コード整形と静的解析の対象は、`git status` で確認できる未ステージング・ステージング済みのファイルに限定すること。
