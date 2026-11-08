#!/bin/sh
# Builds the three package sizes from build/<dimensions>/<language>/vectors.bin, made by tools/data/build_data.py.
set -eu
cd "$(dirname "$0")/.."
name=warmer_game.koplugin
recommended=150
for file in LICENSE NOTICE; do
    if [ ! -f "$file" ]; then
        echo "$file not found: the package cannot be built without it." >&2
        exit 1
    fi
done
rm -rf dist
mkdir -p dist
for dims in 100 150 300; do
    for lang in pt en es; do
        if [ ! -f "build/$dims/$lang/vectors.bin" ]; then
            echo "build/$dims/$lang/vectors.bin not found: run tools/data/build_data.py first." >&2
            exit 1
        fi
    done
    stage="dist/stage-$dims/$name"
    mkdir -p "$stage/data"
    cp -R _meta.lua main.lua LICENSE NOTICE warmer_game assets "$stage/"
    cp data/i18n.lua "$stage/data/"
    for lang in pt en es; do
        mkdir -p "$stage/data/$lang"
        cp data/$lang/words.txt data/$lang/secrets.txt "$stage/data/$lang/"
        cp "build/$dims/$lang/vectors.bin" "$stage/data/$lang/"
    done
    find "dist/stage-$dims" \( -name '._*' -o -name '.DS_Store' \) -delete
    if [ "$dims" = "$recommended" ]; then
        zip_name="$name.zip"
    else
        zip_name="$name-${dims}d.zip"
    fi
    (cd "dist/stage-$dims" && zip -qrX "../$zip_name" "$name")
    rm -rf "dist/stage-$dims"
    (cd dist && shasum -a 256 "$zip_name" > "$zip_name.sha256")
    echo "Package built: dist/$zip_name"
done
