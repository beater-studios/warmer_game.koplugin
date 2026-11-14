# Warmer: design and tools

How the game works inside, for anyone who wants to understand the code or change the data. To install and play, see the [README](../README.md). An original Beater Studios game in the genre of Contexto and Semantle: the player guesses words and sees where each one lands in a ranking of closeness in meaning to the secret word, until they find it. `warmer_game` is the plugin identifier.

## Rules

- The player picks a language (Portuguese, English or Spanish) and plays the daily word or free play.
- Each guess is typed on the game's own keyboard, always at the bottom of the screen, with the word shown on a line above the list. It has no accent keys; Spanish has an Ñ key. Case and accents do not matter, and since the keyboard cannot type them, every reading of what was typed is looked up without accents and the most frequent word wins: "forca" is "força", "rio" is "río", "pais" is "país". A word found exactly as typed with no more frequent accented twin is taken as it is ("news", "mais"), and is never read as a plural.
- A plural counts as its singular, with a notice: "gatos" becomes "gato". When the plain spelling of what was typed is also another word, the more frequent reading wins: "leones" is "león", not "leonés". The rules follow each grammar and are the same in the data generator: in Portuguese `ões`, `ães`, `ãos` to `ão` (also without the tilde: `oes`, `aes`, `aos`), `ns` to `m`, `is` to `l`, `es` only after r, z or s (flores, but leves gives leve) and `s` after a vowel; in English `ies` to `y`, `es` after s, x, z, ch, sh or o, and `s`; in Spanish `ces` to `z`, `es` after a consonant and `s` after a vowel. The singular needs at least 3 letters, so "his" never becomes "hi".
- Words that lose to a more frequent twin cannot be typed: 324 in Portuguese (like "forca") and 164 in Spanish (like "vídeo", since "video" is also a valid spelling and more frequent). They still have a position in the ranking, but are never secret words.
- A word outside the vocabulary is rejected with a notice and does not count. A repeated word does not count either: the list turns to the page where it is and marks it as already sent, until the next guess or hint.
- **Answer:** the position in the ranking, where 1 is the secret word. The position is exact for any word in the vocabulary. The similarity is never shown as a number, since that makes it easy to solve by calculation.
- **Guess list:** sorted by position, with the latest guess highlighted above it and a closeness bar in grayscale. The bar uses a log scale, so close positions stand apart: 1 is full and black, 10 about three quarters, 1000 about a third, the end of the vocabulary empty.
- **Hint:** reveals the word at half the position of the best guess (at least position 2). Every position closer than the best guess is still unknown, so that word is always new. Up to position 1000 it comes from the sorted list of closest words; beyond that, a selection over the scores finds it directly, without sorting thousands of words. With no guesses yet, the hint comes from position 300. With the best guess at position 2 there is no hint left. The word joins the list in italics, marked as a hint, and counts in the result.
- **Give up:** asks for confirmation, reveals the secret word and counts as a loss.
- **Daily word:** comes from the local date and the list of secret words for the language, as in Vocábulo (`secrets[day % total + 1]`, with days counted from 2026-01-01). Everyone using the same language gets the same word, with no internet.
- **Free play:** a word drawn from the same secret list, with no daily limit and no effect on the streak. The draw avoids today's word, the ones for the next 30 days and the last 30 drawn.
- At the end, the Closest Words button lists the secret word and the 100 words closest to it.
- Progress is saved on every guess in `koreader/settings/warmer_game.lua`, with the secret word and the guessed words. Positions are not saved: a game reopened with other data recomputes them. See Saved state.
- **Statistics per language:** daily games, win rate, current and best streak, and average guesses of the wins; free play games and wins. The streak is only recalculated when a game ends and shows as zero if the last game was before yesterday.
- **Share:** a QR code with the daily result without revealing any word: game number, language, dimension count, found or gave up, guesses and hints, and one line per position range (1-100, 101-1000, 1001+) with `■ ▣ □`. Hints and the secret word are left out of the ranges.
- The interface text follows the chosen language. On first launch, the language comes from the KOReader setting.
- Always in portrait, no network, like Vocábulo. Opened in landscape, the screen turns upright and turns back when the game closes, also when opening fails; then the menu shows a message instead of KOReader closing. On devices with a Back button, it goes back one screen and, on the menu, closes the game. When KOReader quits (USB mode on a Kobo, closing the window on a computer) the game closes, except before a power off, which keeps the sleep screen as it is.

## Screens

- **Home:** language, current streak, the daily word (play, continue or see the result), free play, statistics, how to play, about and exit.
- **Game:** a header with Back, the mode and the latest message; Hint and Give Up; the line with the word being typed; the latest guess highlighted; the guess and hint counts; the list sorted by position, paginated; the keyboard at the bottom. On a 600x800 screen the list shows 8 guesses per page.
- **End:** the same screen with Share, Closest Words and Statistics for the daily word, or New Word and Closest Words in free play. When the player gave up, the highlight shows the secret word at position 1.
- **Sleep screen:** if the device sleeps with the game open and the KOReader sleep screen is set to the book cover, `assets/screensaver.png` shows instead. The game wraps KOReader's `Screensaver.setup`: KOReader picks the image as usual, and the game swaps it only when its screen is the topmost full-screen window. Nothing is saved, so closing the game brings back the book cover. Powering off, restarting or any other sleep screen mode are left alone. The image is 1200x1600, twice 600x800, so it stays sharp on larger screens; on 600x800 KOReader halves it.

The game draws its own keyboard instead of using KOReader's input dialog, which covered the list (decision of 2026-11-07, after trying the dialog on the Kindle and comparing three options in the emulator). Each key press refreshes only the line of the typed word; sending a guess refreshes the whole screen. When the game ends the keyboard goes away and the list takes the space.

**Screen updates:** each screen is a kind (`title`, `game`, `closest`, one per page). A change inside the same kind is updated without a flash (`ui`), up to 8 in a row, and the 9th is a full refresh, against ghosting on e-ink. A new kind always flashes, and so do opening a game, the end of a game and waking up. Key presses update only the typed line and stay out of the count. If the guesses cannot be drawn, a short message takes their place and the header, the buttons and the keyboard keep working.

When a game opens, the language data is loaded and the ranking computed, with a short message meanwhile.

## Data

Per language, in `data/<language>/`:

| File | Contents |
|---|---|
| `words.txt` | The vocabulary accepted as guesses, one word per line, in frequency order. |
| `vectors.bin` | `SEMV`, the number of words and of dimensions (little-endian `uint32`), the `int8` matrix (one row per word, in the order of `words.txt`) and one `float32` per word, the inverse of the scale used to quantize it. |
| `secrets.txt` | The secret words, in daily order. |

`words.txt` and `secrets.txt` are text and live in git. `vectors.bin` is generated from the downloaded sources and stays out of git: with three sizes and three languages it would add over 80 MB to the history on every data update. The release builds it again and stops if the regenerated word lists differ from the committed ones, new files included (`git status --porcelain -- data`). The sources are fixed: the word lists are downloaded at pinned commits and every file is checked against `tools/data/sources.sha256` (for FastText, the checksum of the uncompressed first 400,000 lines), so an upstream change stops the download instead of changing the data.

The vectors come from FastText Common Crawl (`cc.<language>.300`), the best in all three languages in a comparison made on 2026-11-07 with NILC (Portuguese), GloVe (English) and SBWCE (Spanish). Each vector is normalized and stored with 1 byte per number plus its scale; in the test, 99 to 100% of the 1000 closest words matched the exact calculation.

**Vocabulary:** common words, without proper names, acronyms, numbers and offensive words, in FastText order, taken from the first 400,000 words of each file and capped at 50,000. The dictionaries are the limit: 38,400 words in Portuguese, 32,036 in English (the Hunspell list has only 38,806 base forms) and 29,020 in Spanish. Each further 50,000 lines would add only 1,000 to 2,000 increasingly rare words. Accepted words are dictionary base forms, so inflections other than plurals ("running", "comí") are not accepted.

In Portuguese the base is the fserb/pt-br lexicon without plurals, because Hunspell stores words like "escola" and "música" as derived from others and they would disappear. Plurals are found by the same rules as in the game, except for the words in `tools/data/not_plural_pt.txt`, which only look like plurals (mais, antes, óculos, parabéns) and stay in the vocabulary. In English and Spanish, the Hunspell base forms from wooorm/dictionaries. Offensive words are filtered by LDNOOBW and the fserb negative list; `tools/data/block_<language>.txt`, when present, adds more, since the vectors bring offensive slang close to common words.

**Secret words:** 750 per language, from the most frequent vocabulary words with at least 3 letters that the keyboard can reach (1,200 candidates in Portuguese and Spanish, 1,400 in English, which has more verb forms and function words at the top). Reviewed words are recorded: approved ones in `tools/data/approved_<language>.txt`, in frequency order, and rejected ones in `tools/data/exclude_<language>.txt`, with the criteria of Vocábulo plus two: no words too vague to find by meaning (thing, way, type) and no generic verbs (make, get, fazer, ter). The criteria: no inflections, participles or adverbs, function words, proper names, demonyms, weekdays, months and numbers, foreign words, obscure terms or heavy topics (violence, death, serious illness, drugs, religion and party politics). The generator keeps the published order, as in Vocábulo: a word that becomes excluded, leaves the vocabulary or can no longer be typed gives its place to a new one, and new words only go to the end. New words only come from the approved list, so a word nobody reviewed never becomes a secret, and every published word is in it: the generator stops if one is missing. A published word stays even when a later filter would leave it out of the candidates, so it can be outside the current candidate window. Once the day number passes the list length, any change of length changes the daily word for everyone, so the generator stops when the length would change and the list is not at least a year longer than today's day number (`ALLOW_LENGTH_CHANGE=1` accepts it). The `candidates` command lists the words of the candidate window that are in neither list, for review.

## Package sizes

Each release publishes the same plugin in three sizes, which differ only in `vectors.bin`:

| Zip | Dimensions | Zip size | Ranking compared with 300 |
|---|---|---|---|
| `warmer_game.koplugin.zip` (recommended) | 150 | about 14 MB | about 83% of the closest words unchanged |
| `warmer_game.koplugin-100d.zip` | 100 | about 10 MB | about 77% unchanged |
| `warmer_game.koplugin-300d.zip` | 300 | about 28 MB | reference |

In the 2026-11-07 test the difference is almost all reordering among equally good words. The 100 and 150 versions are reduced by PCA, centered, from the 300-dimension vectors; the 300 version keeps the original vectors.

All three share the code and the identifier, so only one is installed at a time and switching is installing another on top. The header of `vectors.bin` carries the dimension count; the About screen shows it and the shared result includes it ("Warmer #310 PT · 150"), so players comparing results know whether they played the same ranking.

## Performance

The data are files on disk, read only when a game opens; KOReader only registers the plugin menu at startup. In a game, only the chosen language is in memory: at most about 6 MB with 150 dimensions (4 MB with 100, 12 MB with 300), plus the similarities, one `float` per word. Leaving the game screen releases it. At most two rankings are kept, the daily word's and the free play word's.

Measured on the Kindle on 2026-11-07, with 19,977 Portuguese words and 300 dimensions:

- loading the data: 0.29 s;
- computing the ranking: 0.09 s, and 0.22 s simulating 50,000 words;
- position of a guess: under 1 ms, by counting how many words are above it, without sorting; a restored game computes all its positions in one pass, placing each score among the guessed ones by binary search;
- the closest words: about 0.01 s for 1000, with a heap, kept for later calls;
- memory: about 11 MB.

The list sorted by position is kept until the next guess, since the screen asks for it on every paint and tap. The loading message stays up while the data is read and the ranking computed. The secret word's own score is forced to the top, so quantization can never put another word at position 1. `vectors.bin` is read in 1 MB chunks straight into the FFI buffers, so the file is never held twice in memory, and its size is checked against the header before anything is allocated, so a damaged file shows the missing data message instead of failing. Switching language drops the previous game before loading, so only one vocabulary is in memory.

## Structure

```
warmer_game.koplugin/
  _meta.lua, main.lua     KOReader registration
  warmer_game/
    engine.lua            rules, independent of KOReader
    lexicon.lua           vocabulary and secret words, with the lookup without accents
    vectors.lua           loads vectors.bin and computes the ranking (LuaJIT FFI)
    state.lua             reads back what any version saved, without KOReader
    ui/screen.lua         home, data loading, statistics, help and about
    ui/game_view.lua      game screen and keyboard, drawn directly
    screensaver.lua       game cover on the sleep screen
    portrait.lua          portrait while open, rotation given back on close
    refresh.lua           chooses between updates without a flash and full ones
    calendar.lua          day number, daily word, free play draw and streak
    letters.lua           UTF-8 letters: split, accents and case
    saved_state.lua       defaults, lists and protected restore for saves
  data/
    i18n.lua              text in the three languages
    <language>/           words.txt, secrets.txt, vectors.bin
  assets/screensaver.png  full-screen cover, 1200x1600
  tools/, tests/, docs/   development, outside the published package
```

The game screen is a single widget that draws the header, buttons, highlight, list and pager itself, as in Vocábulo, because dozens of KOReader buttons would weigh on e-ink.

`portrait.lua`, `refresh.lua`, `calendar.lua`, `letters.lua`, `saved_state.lua`, `screensaver.lua` and some files in `tools/` and `.github/workflows/` are shared by the Beater Studios plugins and copied unchanged: each starts with a `Pattern` comment, and a change goes to all plugins at once.

## Saved state

Everything lives in `koreader/settings/warmer_game.lua`, written with `flush` after every guess, hint and give up:

| Key | Contents |
|---|---|
| `lang` | the chosen language |
| `games` | per language, the daily game: `version`, `day`, `secret`, `words`, `hints`, `gave_up`, `finished` |
| `free_games` | per language, the free play game, the same without `day` |
| `stats` | per language, the daily statistics: played, won, streak, best streak, last day, guess and hint totals |
| `free_stats` | per language, free play games and wins |
| `free_recent` | per language, the last 30 free play words |

`warmer_game/state.lua` reads it back field by field: an unknown language or a field of the wrong type gets the default, a game that cannot be read is dropped and the statistics and other games stay, and each entry is read protected, so a damaged save never stops the game from opening. A saved game keeps its secret word, so an update of the secret list does not change a game in progress; guessed words that left the vocabulary are dropped when the game opens, and a secret word that left it starts a new game. A finished daily game stays until the next day, so the home screen shows its result and the word is not played again; a finished free game is replaced when free play opens. `version` goes up only when a field changes meaning; games saved before 0.1.2 have none and count as version 1. `tests/saves/<version>.lua` holds real saves of published versions, and `tests/state_spec.lua` opens each of them.

## Tools

- `tools/data/fetch_sources.sh <empty folder>`: downloads the word lists at pinned commits and the first 400,000 lines of each FastText file, and checks them against `tools/data/sources.sha256`. With another `VECTOR_LINES` the checksums are not checked. The FastText files are sorted by frequency, so the rest is never downloaded.
- `LUAJIT=<luajit> python3 -I tools/data/build_data.py <sources> candidates <folder>`: lists the secret word candidates not yet reviewed. Approved ones go to `approved_<language>.txt`, rejected ones to `exclude_<language>.txt`.
- `tools/data/reachable.lua`: called by the generator, lists the words the keyboard cannot reach, with the game's own lookup, so the rules live in one place.
- `LUAJIT=<luajit> python3 -I tools/data/build_data.py <sources> build`: writes `data/<language>/words.txt` and `secrets.txt`, calls `tools/data/reduce.lua` to write `build/<dimensions>/<language>/vectors.bin` for the three sizes, and copies the recommended size into `data/` for the emulator. Plain Python, no packages.
- `sh tools/check.sh`: every check that runs without KOReader, the same in CI: the tests, `tools/check_texts.lua` and `validate_data.lua --no-vectors`. `sh tools/check.sh release` also downloads the sources, builds the data, fails if `data/` differs from the repository and validates the vectors of the three sizes.
- `luajit tools/validate_data.lua [build/<dimensions>]`: checks the word lists (including that every secret word can be typed) and the vectors of the given size (or of `data/`). With `--no-vectors`, only the lists.
- `luajit tools/check_texts.lua t strings 'strings()'`: the three languages have the same texts and placeholders, no dash or device brand in any text, and every text the code asks for exists.
- `luajit tests/engine_spec.lua`: engine tests (accents, plurals in the three languages, repeats, hints, give up, saving and restoring, daily word, free play draw, streak, shared result).
- `luajit tests/state_spec.lua`: saving and restoring, damaged saves, words that left the vocabulary and the saves of published versions in `tests/saves/`.
- `luajit tests/vectors_spec.lua`: loading of `vectors.bin`, damaged files, the secret word first, the selection used by distant hints against the sorted list, and the one-pass positions against the single ones.
- `sh tools/package.sh`: builds the three zips and their checksums from `build/`, with the steps of `tools/package_lib.sh`. Requires `LICENSE`, `NOTICE` and the cover, and stops if a file the code loads is missing from a package.
- With `KOREADER_DIR` pointing to a desktop KOReader, from the plugin folder:
  - `tools/koreader/run_emulator.sh` opens the game in a window, with the virtual keyboard on.
  - `tools/koreader/check_all_sizes.sh` runs `check_layout.lua` at four screen sizes: all three languages through taps on the game's keyboard, the texts at their longest, the version on the About screen, a game resumed in a new screen, the refresh modes and the Back key.
  - `tools/koreader/run_headless.sh tools/koreader/check_rotation.lua` opens the game with KOReader in landscape and checks portrait, the ignored rotation and the rotation given back, also when opening fails.
  - `tools/koreader/run_headless.sh tools/koreader/fuzz_ui.lua` sends random taps, holds and swipes to the title, the daily word and free play in each language, typing a frequent word one step in four. An error prints the command that repeats it.
  - `tools/koreader/run_headless.sh tools/koreader/check_screensaver.lua` checks when the game cover replaces the sleep screen image.
  - With `OUTPUT_DIR`, the scripts save screenshots; `render_screens.lua` makes the README ones, with a secret word that is not a daily word.
- `KOREADER_DIR=<desktop KOReader> python3 -I tools/make_brand_art.py` draws the icon, the README banner and the GitHub social preview (`docs/social-preview.png`) from the README screenshots, in the same style as the other Beater Studios plugins. Run `render_screens.lua` first. Needs Pillow. With `screensaver` as argument it draws `assets/screensaver.png` instead, in the same style. With `pt <folder>` it draws only the Portuguese banner, `docs/brand/banner_pt.png` (used by `README_pt.md`), and the Portuguese social preview, `docs/social-preview_pt.png`, from screenshots rendered in Portuguese into that folder with `SCREENS_LANGUAGE=pt OUTPUT_DIR=<folder> tools/koreader/run_headless.sh tools/koreader/render_screens.lua`.

The emulator does not show what is specific to e-ink, nor the device speed: the final check is on a real device.

## License

The code is under GPL-3.0, version 3 only. The game data (`data/<language>/`) is adapted from FastText, under CC BY-SA 3.0, and ships as separate data files under that same license, alongside the GPL code rather than merged into it. Credits and the changes made are in `NOTICE`.

## How to release a version

1. Update `version` in `_meta.lua` and add the version section to `CHANGELOG.md`, as `## [1.2.3]`.
2. Run `sh tools/check.sh`, the emulator checks (`check_all_sizes.sh`, `check_rotation.lua`, `fuzz_ui.lua` and `check_screensaver.lua`) and test on a device.
3. If the version changes the save format or the content, save a game with the published version in the emulator and keep it as `tests/saves/<published version>.lua`.
4. Publish the `v1.2.3` release on GitHub, creating the tag with it, after the push. The `release.yml` workflow checks the tag against `_meta.lua`, runs `tools/check.sh release` (tests, texts, the data built again from the sources and compared with the repository, the three sizes validated), builds the packages and attaches every zip in `dist/` with its checksum.
