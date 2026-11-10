#!/bin/sh
# Builds one zip per vector size in dist/, each with its checksum, from build/<dimensions>/<language>/vectors.bin
# made by tools/data/build_data.py. 150 dimensions is the recommended package, without a suffix.
set -eu
. "$(dirname "$0")/package_lib.sh"
package_start "warmer_game"
for dims in 100 150 300; do
    package_stage
    package_add assets data/i18n.lua
    for lang in pt en es; do
        package_add "data/$lang/words.txt" "data/$lang/secrets.txt"
        package_copy "build/$dims/$lang/vectors.bin" "data/$lang/vectors.bin"
    done
    if [ "$dims" = 150 ]; then
        package_zip
    else
        package_zip "warmer_game.koplugin-${dims}d.zip"
    fi
done
