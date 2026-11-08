"""Builds the game data from the downloaded sources and the reviewed exclusion lists.

Usage:
    build_data.py <sources> candidates <output dir>   writes the secret word candidates not reviewed yet
    build_data.py <sources> build                     writes data/ and the vectors for each size in build/
"""
import array
import gzip
import math
import os
import random
import shutil
import struct
import subprocess
import sys
import unicodedata

TOOLS = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(TOOLS, "..", "..")
DATA = os.path.join(ROOT, "data")
BUILD = os.path.join(ROOT, "build")
LANGUAGES = ("pt", "en", "es")
KEPT_LETTERS = {"pt": "", "en": "", "es": "ñ"}
VOCABULARY_SIZE = 50000
MINIMUM_VOCABULARY = 25000
CANDIDATES_PER_LANGUAGE = {"pt": 1200, "en": 1400, "es": 1200}
SECRETS_PER_LANGUAGE = 750
MINIMUM_SECRETS = 365
MINIMUM_SECRET_LENGTH = 3
SOURCE_DIMENSIONS = 300
RECOMMENDED_DIMENSIONS = 150
VOWELS = set("aeiouáéíóúâêôãõ")
MINIMUM_SINGULAR_LETTERS = 3
# Same rules as warmer_game/engine.lua. The third item limits a rule to singulars with that ending.
PT_PLURAL_RULES = (
    ("ões", "ão", None), ("ães", "ão", None), ("ãos", "ão", None), ("ns", "m", None), ("is", "l", None),
    ("es", "", ("r", "z", "s")), ("s", "", "vowel"),
)


def plain(word, lang):
    letters = []
    for char in word:
        if char in KEPT_LETTERS[lang]:
            letters.append(char)
        else:
            letters.extend(c for c in unicodedata.normalize("NFD", char) if not unicodedata.combining(c))
    return "".join(letters)


def read_lines(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        return [line.strip() for line in f if line.strip()]


def read_optional(path):
    return read_lines(path) if os.path.exists(path) else []


def write_lines(path, lines):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")


def ends_as(singular, after):
    if after is None:
        return True
    if after == "vowel":
        return singular[-1:] in VOWELS
    return singular.endswith(after)


def pt_singulars(word):
    found = []
    for suffix, ending, after in PT_PLURAL_RULES:
        if word.endswith(suffix) and len(word) > len(suffix):
            singular = word[: -len(suffix)] + ending
            if len(singular) >= MINIMUM_SINGULAR_LETTERS and ends_as(singular, after):
                found.append(singular)
    return found


def is_pt_plural(word, lexicon, not_plural):
    return word not in not_plural and any(s in lexicon for s in pt_singulars(word))


def read_stems(sources, lang):
    stems = set()
    for line in read_lines(os.path.join(sources, lang + "_stems.dic"))[1:]:
        stem = line.split("/")[0].split("\t")[0].strip()
        if stem and stem == stem.lower():
            stems.add(stem)
    return stems


def accepted_words(sources, lang):
    if lang == "pt":
        # The Hunspell stems miss common nouns that the dictionary derives from verbs or masculine forms
        # (escola, livro, música), so the lexicon is the base and only plurals are removed.
        lexicon = set(read_lines(os.path.join(sources, "pt_lexicon")))
        # Words that only look like plurals ("mais" is not the plural of "mal") stay in the vocabulary.
        not_plural = set(read_optional(os.path.join(TOOLS, "not_plural_pt.txt")))
        return {w for w in lexicon if not is_pt_plural(w, lexicon, not_plural)}
    return read_stems(sources, lang)


def blocked_keys(sources, lang):
    lists = [os.path.join(sources, lang + "_blocklist"), os.path.join(TOOLS, "block_%s.txt" % lang)]
    if lang == "pt":
        lists.append(os.path.join(sources, "pt_negative"))
    return {plain(w.lower(), lang) for path in lists for w in read_optional(path)}


def iter_vectors(sources, lang):
    with gzip.open(os.path.join(sources, "cc.%s.300.head.vec.gz" % lang), "rt", encoding="utf-8", errors="ignore") as f:
        f.readline()
        for line in f:
            parts = line.rstrip().split(" ")
            if len(parts) == SOURCE_DIMENSIONS + 1:
                yield parts[0], parts[1:]


def load_vocabulary(sources, lang):
    accepted = accepted_words(sources, lang)
    blocked = blocked_keys(sources, lang)
    words, vectors, seen = [], [], set()
    for word, raw in iter_vectors(sources, lang):
        if word in seen or not word.isalpha() or word != word.lower() or len(word) < 2:
            continue
        if word not in accepted or plain(word, lang) in blocked:
            continue
        values = [float(x) for x in raw]
        norm = math.sqrt(sum(x * x for x in values)) or 1.0
        seen.add(word)
        words.append(word)
        vectors.append(array.array("f", (x / norm for x in values)))
        if len(words) == VOCABULARY_SIZE:
            break
    return words, vectors


def secret_candidates(words, lang):
    return [w for w in words if len(w) >= MINIMUM_SECRET_LENGTH][:CANDIDATES_PER_LANGUAGE[lang]]


def read_excluded(lang):
    return set(read_optional(os.path.join(TOOLS, "exclude_%s.txt" % lang)))


def read_approved(lang):
    return read_optional(os.path.join(TOOLS, "approved_%s.txt" % lang))


def unreachable_words(words, lang):
    """Words the game's keyboard cannot reach, asked to the game's own lookup so the rules live in one place."""
    luajit = os.environ.get("LUAJIT", "luajit")
    os.makedirs(BUILD, exist_ok=True)
    path = os.path.join(BUILD, "%s_words.txt" % lang)
    write_lines(path, words)
    result = subprocess.run([luajit, os.path.join(TOOLS, "reachable.lua"), path, lang],
                            check=True, capture_output=True, text=True)
    os.remove(path)
    return set(result.stdout.split())


def stable_secrets(published, approved, excluded, usable, seed):
    """Keeps the published order, so the daily word does not change for anyone.

    A published word that is now excluded or no longer usable (left the vocabulary or cannot be typed) gives its
    place to a new word. New words only go to the end of the list, up to SECRETS_PER_LANGUAGE. New words only come
    from the approved list, so a word that never went through review cannot become a secret.
    """
    removed = [w in excluded or w not in usable for w in published]
    published_set = set(published)
    fresh = [w for w in approved if w not in excluded and w not in published_set and w in usable]
    slots = sum(removed) + max(0, SECRETS_PER_LANGUAGE - len(published))
    new = fresh[:slots]
    random.Random(seed).shuffle(new)
    secrets, shifted = [], False
    for word, is_removed in zip(published, removed):
        if not is_removed:
            secrets.append(word)
        elif new:
            secrets.append(new.pop(0))
        else:
            shifted = True
    secrets.extend(new[:max(0, SECRETS_PER_LANGUAGE - len(secrets))])
    return secrets, shifted


def write_matrix(path, vectors):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(struct.pack("<II", len(vectors), SOURCE_DIMENSIONS))
        for v in vectors:
            f.write(v.tobytes())


def candidates(sources, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    for lang in LANGUAGES:
        words, _ = load_vocabulary(sources, lang)
        excluded = read_excluded(lang)
        known = set(read_approved(lang)) | excluded
        unreachable = unreachable_words(words, lang)
        # After review, approved words go to approved_<language>.txt and rejected ones to exclude_<language>.txt.
        pending = [w for w in secret_candidates(words, lang) if w not in known and w not in unreachable]
        write_lines(os.path.join(out_dir, "%s.txt" % lang), pending)
        print("%s: %d words in the vocabulary, %d candidates to review" % (lang, len(words), len(pending)))


def build(sources):
    luajit = os.environ.get("LUAJIT", "luajit")
    failed = False
    for lang in LANGUAGES:
        words, vectors = load_vocabulary(sources, lang)
        excluded = read_excluded(lang)
        secrets_path = os.path.join(DATA, lang, "secrets.txt")
        published = read_optional(secrets_path)
        usable = set(words) - unreachable_words(words, lang)
        secrets, shifted = stable_secrets(published, read_approved(lang), excluded, usable, "warmer-" + lang)
        if shifted:
            print("  %s: removed words without a replacement, the daily word changes from them on" % lang)
        write_lines(os.path.join(DATA, lang, "words.txt"), words)
        write_lines(secrets_path, secrets)
        matrix = os.path.join(BUILD, "%s_%d.f32" % (lang, SOURCE_DIMENSIONS))
        write_matrix(matrix, vectors)
        subprocess.run([luajit, os.path.join(TOOLS, "reduce.lua"), matrix, BUILD, lang], check=True)
        shutil.copyfile(os.path.join(BUILD, str(RECOMMENDED_DIMENSIONS), lang, "vectors.bin"),
                        os.path.join(DATA, lang, "vectors.bin"))
        os.remove(matrix)
        print("%s: %d words in the vocabulary, %d secret words" % (lang, len(words), len(secrets)))
        if len(words) < MINIMUM_VOCABULARY:
            print("  vocabulary below %d: download more lines with VECTOR_LINES" % MINIMUM_VOCABULARY)
            failed = True
        if len(secrets) < MINIMUM_SECRETS:
            print("  too few secret words: the minimum is %d" % MINIMUM_SECRETS)
            failed = True
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    if sys.argv[2] == "candidates":
        candidates(sys.argv[1], sys.argv[3])
    else:
        build(sys.argv[1])
