#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
for size in "600 800 167" "758 1024 212" "1072 1448 300" "1264 1680 300"; do
    echo "== $size"
    tools/koreader/run_headless.sh tools/koreader/check_layout.lua $size
done
