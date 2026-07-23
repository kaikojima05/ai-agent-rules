#!/bin/bash
# apply-prompt: compose-prompt で作成したドラフトを .[agent_name]/prompt/.prompt.md へ反映する。
# .[agent_name]/ は sandbox の denyWrite で保護されており、エージェントは直接書き込めない。
# 宛先を本スクリプト内に固定することで、サンドボックス外書き込みの事前 allow を
# 「.prompt.md 1 ファイルへの cp」だけに絞る（cp 自体を allow すると何でも上書きできてしまう）。
# 使い方: bash apply-prompt.sh <ドラフトのパス>
# 失敗の扱い: ドラフト不在・宛先が symlink・cp 失敗はすべて exit 1（握りつぶし禁止）。
set -u

SRC="${1:?usage: apply-prompt.sh <draft.md>}"
DEST_DIR=".[agent_name]/prompt"
DEST="$DEST_DIR/.prompt.md"

[ -f "$SRC" ] || { echo "ERROR: draft not found: $SRC" >&2; exit 1; }

# 宛先側が symlink だと cp がリンク先を上書きし「宛先固定」の前提が崩れるため拒否する
[ -L "$DEST_DIR" ] && { echo "ERROR: dest dir is a symlink: $DEST_DIR" >&2; exit 1; }
[ -L "$DEST" ] && { echo "ERROR: dest is a symlink: $DEST" >&2; exit 1; }

mkdir -p "$DEST_DIR" || { echo "ERROR: cannot create dir: $DEST_DIR" >&2; exit 1; }

if cp -- "$SRC" "$DEST"; then
  echo "applied: $SRC -> $DEST"
else
  echo "ERROR: copy failed: $SRC -> $DEST" >&2
  exit 1
fi
