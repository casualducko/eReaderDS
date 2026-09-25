#!/bin/bash
# Render the reader on a computer and save a screenshot of both screens.
#
#   tools/shot.sh OUT.png "action,action,..."
#
# Env: LOVE (path to a LÖVE 11.5 binary), BOOKS (folder of .epub/.txt),
#      DATA (settings/progress folder, default: a temp dir).
# Actions: next prev up down left right confirm back menu toc
#          next_section prev_section, or dpup/dpdown/dpleft/dpright for raw d-pad.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
LOVE="${LOVE:-love}"
DATA="${DATA:-$(mktemp -d)}"
cd "$ROOT/app"
READER_SCALE=0.5 READER_BOOKS="${BOOKS:?set BOOKS to a folder of books}" READER_DATA="$DATA" \
READER_SHOT="$OUT" READER_SCRIPT="${2:-}" "$LOVE" .
