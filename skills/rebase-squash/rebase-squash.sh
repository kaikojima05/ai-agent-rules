#!/bin/bash
# rebase-squash スキルの決定的実行スクリプト。
# 「[claude]: {ファイル名}/{変更内容}」の 1 ファイル = 1 コミット履歴を、未 push 範囲だけ
# 機能単位の squash 履歴へ組み替える。履歴書き換えの唯一の公認経路
# （生の rebase / filter-branch / force push は deny-history-rewrite.sh が deny する）。
#
# 使い方:
#   rebase-squash.sh --check [--base <ref>]      # 前提検査と対象範囲の報告（履歴を変更しない）
#   rebase-squash.sh <plan.json> [--base <ref>]  # plan に従いリプレイ実行
#
# 安全設計（verify-then-swap）:
#   temp worktree で base から cherry-pick -n によるリプレイを完走させ、
#   「plan が対象範囲を exactly-once で消費」「squash 後の tree が元 HEAD と同一」の
#   二重検証に合格して初めて、本体ブランチを 1 回の reset --hard で切り替える。
#   検証前に本体ブランチと作業ツリーには一切触れないため、失敗時は temp worktree を
#   消すだけでよく、復元パスが存在しない。
# 失敗の扱い: 検査・リプレイ・検証のどこで落ちても ERROR を stderr へ出して exit 1
#   （成功したふりの禁止）。push と backup ブランチの削除は本スクリプトは行わない。
set -u

err() { echo "ERROR: $*" >&2; }
die() { err "$*"; exit 1; }

MODE="" PLAN="" BASE_ARG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --check) MODE=check ;;
    --base) shift; BASE_ARG="${1:?--base には ref が必要}" ;;
    *) [ -n "$PLAN" ] && die "引数が多すぎる: $1"; PLAN="$1"; MODE=run ;;
  esac
  shift
done
[ -n "$MODE" ] || die "usage: rebase-squash.sh --check [--base <ref>] | rebase-squash.sh <plan.json> [--base <ref>]"

command -v jq >/dev/null 2>&1 || die "jq が必要"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "git リポジトリ内で実行すること"
[ "$(git rev-parse --abbrev-ref HEAD)" != "HEAD" ] || die "detached HEAD では実行しない"

# clean tree 前提（untracked は無害なので許容）
git status --porcelain | grep -qv '^??' && \
  die "作業ツリーが dirty。コミットするか退避してから実行すること"

ORIG=$(git rev-parse HEAD)

# base の決定: --base 指定 > @{upstream}。upstream なしで --base も無ければ動かない
if [ -n "$BASE_ARG" ]; then
  BASE=$(git rev-parse --verify "${BASE_ARG}^{commit}" 2>/dev/null) || die "base を解決できない: $BASE_ARG"
else
  BASE=$(git rev-parse --verify '@{upstream}' 2>/dev/null) || die "upstream が無い。--base <ref> で明示すること"
fi
git merge-base --is-ancestor "$BASE" "$ORIG" || die "base($BASE) が HEAD の祖先でない"

[ -z "$(git rev-list --merges "$BASE..$ORIG")" ] || die "範囲に merge コミットがある。本スキルの対象外"

# 「未 push」の判定は upstream 比較では不十分（PR ブランチ等へ push 済みでも @{u}..HEAD に残る）。
# 範囲の全コミットが全リモート追跡 ref から不可視であることを要求する
TOTAL=$(git rev-list --count "$BASE..$ORIG")
INVISIBLE=$(git rev-list --count "$BASE..$ORIG" --not --remotes)
[ "$TOTAL" -eq "$INVISIBLE" ] || \
  die "範囲内にリモートへ push 済みのコミットが $((TOTAL - INVISIBLE)) 件ある。共有履歴は書き換えない"

# [claude]: 以外のコミットは境界: 最新の非 [claude] コミットより古い側は対象から外す
EFFECTIVE_BASE=$BASE
while IFS=$'\t' read -r sha subject; do
  case "$subject" in
    "[claude]: "*) ;;
    *) EFFECTIVE_BASE=$sha ;;
  esac
done < <(git log --reverse --format='%H%x09%s' "$BASE..$ORIG")

COUNT=$(git rev-list --count "$EFFECTIVE_BASE..$ORIG")

if [ "$MODE" = check ]; then
  echo "BASE $EFFECTIVE_BASE"
  echo "HEAD $ORIG"
  echo "COMMITS $COUNT"
  if [ "$COUNT" -lt 2 ]; then
    echo "NOTHING-TO-DO: squash 対象が 2 コミット未満"
    exit 0
  fi
  # 分類の材料: 対象コミット（古い順）と、それぞれの変更ファイル
  while IFS= read -r sha; do
    printf '%s\t%s\n' "$(git log -1 --format=%h "$sha")" "$(git log -1 --format=%s "$sha")"
    git show --name-only --format= "$sha" | sed 's/^/\t/'
  done < <(git rev-list --reverse "$EFFECTIVE_BASE..$ORIG")
  exit 0
fi

# ---- run モード ----
[ "$COUNT" -ge 2 ] || die "squash 対象が 2 コミット未満。やることがない"
[ -f "$PLAN" ] || die "plan ファイルが無い: $PLAN"
jq -e . "$PLAN" >/dev/null 2>&1 || die "plan が JSON として不正: $PLAN"

PLAN_BASE=$(jq -r '.base // empty' "$PLAN")
[ "$PLAN_BASE" = "$EFFECTIVE_BASE" ] || \
  die "plan の base($PLAN_BASE) が現在の対象範囲の base($EFFECTIVE_BASE) と一致しない。plan を作り直すこと"

NGROUPS=$(jq '.groups | length' "$PLAN")
[ "$NGROUPS" -ge 1 ] || die "plan の groups が空"

# 契約検証をスクリプトに内蔵する: enforce-claude-commit.sh はスクリプト内部の commit を
# 見られない(コマンド文字列検査のため)ので、同じ契約をここで自前検査する
while IFS= read -r subj; do
  echo "$subj" | grep -qE '^\[claude\]: [^ /]+/.+' || \
    die "subject が「[claude]: {機能}/{変更内容}」形式でない: $subj"
  echo "$subj" | grep -qiE 'co-authored-by|generated with' && \
    die "subject に AI 署名が含まれる: $subj"
done < <(jq -r '.groups[].subject' "$PLAN")

# exactly-once 検証: plan のコミット集合 = 対象範囲、重複も欠落も許さない
PLAN_SHAS=""
while IFS= read -r s; do
  full=$(git rev-parse --verify "${s}^{commit}" 2>/dev/null) || die "plan に解決できない sha がある: $s"
  PLAN_SHAS="$PLAN_SHAS$full
"
done < <(jq -r '.groups[].commits[]' "$PLAN")
if [ "$(printf '%s' "$PLAN_SHAS" | sort)" != "$(git rev-list "$EFFECTIVE_BASE..$ORIG" | sort)" ]; then
  die "plan のコミット集合が対象範囲と exactly-once で一致しない(欠落・重複・範囲外のいずれか)"
fi

BACKUP="backup/rebase-squash-$(git rev-parse --short=7 "$ORIG")"
git show-ref --verify --quiet "refs/heads/$BACKUP" && \
  die "backup ブランチが既に存在する: ${BACKUP}。前回の残骸の確認と削除は人間の仕事"

WT=$(mktemp -d "${TMPDIR:-/tmp}/rebase-squash.XXXXXX") || die "temp dir を作れない"
cleanup() {
  git worktree remove --force "$WT" >/dev/null 2>&1
  rm -rf "$WT"
}
git worktree add --detach "$WT" "$EFFECTIVE_BASE" >/dev/null 2>&1 || { rm -rf "$WT"; die "temp worktree を作れない"; }

gi=0
while [ "$gi" -lt "$NGROUPS" ]; do
  SUBJECT=$(jq -r ".groups[$gi].subject" "$PLAN")

  # グループ内の適用順は plan を信用せず、元履歴の順序へ再ソートする
  GROUP_RESOLVED=$(jq -r ".groups[$gi].commits[]" "$PLAN" | while IFS= read -r s; do git rev-parse "${s}^{commit}"; done)
  [ -n "$GROUP_RESOLVED" ] || { cleanup; die "group $((gi + 1)) にコミットが無い: $SUBJECT"; }
  GROUP_ORDERED=$(git rev-list --reverse "$EFFECTIVE_BASE..$ORIG" | grep -Fx -f <(printf '%s\n' "$GROUP_RESOLVED"))

  for sha in $GROUP_ORDERED; do
    if ! git -C "$WT" cherry-pick --no-commit "$sha" >/dev/null 2>&1; then
      short=$(git log -1 --format=%h "$sha")
      cleanup
      die "コンフリクト: group $((gi + 1))「${SUBJECT}」の $short を並べ替えて適用できない。グループを併合するか、元履歴で連続する run だけを squash する縮退 plan に組み直すこと(本体ブランチは無傷)"
    fi
  done

  # 相殺で空になったグループは plan の誤り。--allow-empty で誤魔化さない
  if git -C "$WT" diff --cached --quiet; then
    cleanup
    die "group $((gi + 1))「${SUBJECT}」は変更が相殺されて空。revert とその対象は同一グループに入れないこと"
  fi

  # body には元 subject 一覧を機械生成で残す(何をまとめたか履歴から追えるように)。
  # --no-verify: 内容は元コミット時点で hook 通過済みの内容保存変換であり、
  # 配布先の commit hook(フォーマッタ等)が tree を書き換えると検証が壊れるため
  {
    echo "$SUBJECT"
    echo
    echo "Squashed:"
    for sha in $GROUP_ORDERED; do
      echo "- $(git log -1 --format=%s "$sha")"
    done
  } | git -C "$WT" commit --quiet --no-verify -F - || { cleanup; die "commit に失敗: group $((gi + 1))「${SUBJECT}」"; }

  gi=$((gi + 1))
done

NEW_TIP=$(git -C "$WT" rev-parse HEAD)

# 二重検証: これに合格するまで本体ブランチには触れない
git diff --quiet "$ORIG" "$NEW_TIP" || \
  { cleanup; die "検証失敗: squash 後の tree が元 HEAD と一致しない。リプレイのどこかで内容が変わった"; }
NEWCOUNT=$(git rev-list --count "$EFFECTIVE_BASE..$NEW_TIP")
[ "$NEWCOUNT" -eq "$NGROUPS" ] || \
  { cleanup; die "検証失敗: 生成コミット数($NEWCOUNT) が groups($NGROUPS) と一致しない"; }

# verify-then-swap: backup を切ってから、本体を 1 回だけ動かす。
# tree は検証済みで元 HEAD と同一なので、この reset --hard は作業ファイルを 1 byte も変えない
git branch "$BACKUP" "$ORIG" || { cleanup; die "backup ブランチを作れない: $BACKUP"; }
if ! git reset --hard "$NEW_TIP" >/dev/null 2>&1; then
  cleanup
  die "swap(reset --hard) に失敗。ブランチは $BACKUP と reflog から復旧できる"
fi
cleanup

echo "OK: $COUNT commits -> $NGROUPS commits"
echo "backup: $BACKUP (確認後の削除は人間の仕事。エージェントによる削除は hook が deny する)"
echo "検証: tree 一致(元 HEAD と diff 空) / 全コミット exactly-once 消費"
git log --reverse --format='%h%x09%s' "$EFFECTIVE_BASE..HEAD"
