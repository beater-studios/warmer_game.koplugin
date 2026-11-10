#!/bin/sh
# Every check that runs without KOReader. The CI runs tools/check.sh; the release runs tools/check.sh release,
# which also downloads the sources, builds the data again, fails if the word lists differ from the repository
# and validates the vectors of the three sizes. The package depends on build/, so the release builds it after.
set -eu
cd "$(dirname "$0")/.."
for spec in tests/*_spec.lua; do
    luajit "$spec"
done
luajit tools/check_texts.lua t strings 'strings()'
if [ "${1:-}" = release ]; then
    sources="$(mktemp -d)"
    sh tools/data/fetch_sources.sh "$sources"
    LUAJIT="${LUAJIT:-luajit}" python3 -I tools/data/build_data.py "$sources" build
    rm -rf "$sources"
    # Also catches new files, which git diff leaves out.
    if [ -n "$(git status --porcelain -- data)" ]; then
        git status --short -- data
        echo "data/ differs from what the sources generate." >&2
        exit 1
    fi
    for dims in 100 150 300; do
        luajit tools/validate_data.lua "build/$dims"
    done
else
    luajit tools/validate_data.lua --no-vectors
fi
