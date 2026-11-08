#!/bin/sh
# Downloads the sources at fixed commits and checks them against tools/data/sources.sha256, so a release always
# rebuilds the same data. The FastText files are checked by the checksum of their uncompressed first lines.
set -eu
dest="${1:?usage: fetch_sources.sh <empty folder for the sources>}"
lines="${VECTOR_LINES:-400000}"
sums="$(cd "$(dirname "$0")" && pwd)/sources.sha256"
mkdir -p "$dest"
if [ -n "$(ls -A "$dest")" ]; then
    echo "the folder must be empty: $dest" >&2
    exit 1
fi
expected() {
    awk -v name="$1" '$2 == name { print $1 }' "$sums"
}
check() {
    if [ "$lines" != 400000 ]; then
        return
    fi
    if [ "$2" != "$(expected "$1")" ]; then
        echo "checksum mismatch: $1 (the source changed; update the commit or sources.sha256 on purpose)" >&2
        exit 1
    fi
}
fetch() {
    curl -fsSL --max-time 120 -o "$dest/$2" "$1"
    check "$2" "$(shasum -a 256 "$dest/$2" | cut -d' ' -f1)"
    echo "downloaded: $2"
}
fserb=https://raw.githubusercontent.com/fserb/pt-br/93ba2a6f3b2f85262fba72df09d448c6bb2fa50a
ldnoobw=https://raw.githubusercontent.com/LDNOOBW/List-of-Dirty-Naughty-Obscene-and-Otherwise-Bad-Words/5faf2ba42d7b1c0977169ec3611df25a3c08eb13
wooorm=https://raw.githubusercontent.com/wooorm/dictionaries/8cfea406b505e4d7df52d5a19bce525df98c54ab
fetch "$fserb/lexico" pt_lexicon
fetch "$fserb/listas/negativas" pt_negative
for lang in en es pt; do
    fetch "$ldnoobw/$lang" "${lang}_blocklist"
    fetch "$wooorm/dictionaries/$lang/index.dic" "${lang}_stems.dic"
done
# The FastText files are sorted by frequency, so the first lines are enough and the rest is never downloaded.
for lang in en es pt; do
    curl -fsSL "https://dl.fbaipublicfiles.com/fasttext/vectors-crawl/cc.$lang.300.vec.gz" 2>/dev/null \
        | gunzip -c 2>/dev/null | head -n "$((lines + 1))" | gzip -1 > "$dest/cc.$lang.300.head.vec.gz" || true
    count=$(gunzip -c "$dest/cc.$lang.300.head.vec.gz" | wc -l | tr -d ' ')
    if [ "$count" -lt "$((lines + 1))" ]; then
        echo "incomplete download: cc.$lang ($count lines)" >&2
        exit 1
    fi
    check "cc.$lang.300.head.vec" "$(gunzip -c "$dest/cc.$lang.300.head.vec.gz" | shasum -a 256 | cut -d' ' -f1)"
    echo "downloaded: cc.$lang.300.head.vec.gz ($lines words)"
done
