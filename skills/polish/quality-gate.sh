#!/bin/bash
# polish 完了の receipt を記録・検証する固定実行器。
# receipt は一時領域に置き、設計書の index や作業ツリーを汚さない。
set -u

MODE="${1:-}"
FEATURE="${2:-}"
FEATURE_RE='^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$'

die() { echo "ERROR: $1" >&2; exit 1; }

[ "$#" -eq 2 ] || die "usage: quality-gate.sh <record|verify> <機能名>"
[[ "$FEATURE" =~ $FEATURE_RE ]] || die "invalid 機能名: $FEATURE (ASCII kebab-case only)"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "git リポジトリ内で実行すること"

REPOSITORY=$(git rev-parse --show-toplevel)
REPOSITORY_KEY=$(printf '%s' "$REPOSITORY" | cksum | awk '{ print $1 }')
RECEIPT_DIR="${TMPDIR:-/tmp}/polish-quality-gate/$REPOSITORY_KEY"
RECEIPT="$RECEIPT_DIR/$FEATURE"

case "$MODE" in
  record)
    git diff --quiet || die "未ステージングの追跡対象変更がある。polish後の変更を検証・コミットしてから記録すること"
    git diff --cached --quiet || die "stage済み変更がある。polish後の変更をコミットしてから記録すること"
    mkdir -p "$RECEIPT_DIR" || die "quality gate receipt用の一時ディレクトリを作れない"
    HEAD=$(git rev-parse HEAD)
    printf '%s\n%s\n' "$REPOSITORY" "$HEAD" > "$RECEIPT" || die "quality gate receiptを記録できない"
    echo "recorded: $FEATURE $HEAD"
    ;;
  verify)
    [ -f "$RECEIPT" ] || die "polish品質ゲートのreceiptが無い: $FEATURE"
    EXPECTED_REPOSITORY=$(sed -n '1p' "$RECEIPT")
    EXPECTED_HEAD=$(sed -n '2p' "$RECEIPT")
    [ "$EXPECTED_REPOSITORY" = "$REPOSITORY" ] || die "quality gate receiptのリポジトリが一致しない"
    [ "$EXPECTED_HEAD" = "$(git rev-parse HEAD)" ] || die "polish後にHEADが変わった。品質ゲートを再実行して記録し直すこと"
    git diff --quiet || die "receipt記録後に未ステージングの追跡対象変更がある"
    git diff --cached --quiet || die "receipt記録後にstage済み変更がある"
    ;;
  *)
    die "mode は record または verify に限定する"
    ;;
esac
