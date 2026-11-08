<p align="center">
  <img src="docs/brand/banner.png" alt="Warmer: find the secret word by its meaning">
</p>

<p align="center">
  <strong>Find the secret word by its meaning. A word guessing game for KOReader, in Portuguese, English and Spanish.</strong>
</p>

<p align="center">
  <a href="https://github.com/beater-studios/warmer_game.koplugin/releases/latest"><img src="https://img.shields.io/github/v/release/beater-studios/warmer_game.koplugin?style=flat-square&color=111111&label=release" alt="Latest release"></a>
  <a href="https://github.com/beater-studios/warmer_game.koplugin/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/beater-studios/warmer_game.koplugin/ci.yml?branch=main&style=flat-square&label=tests" alt="Tests"></a>
  <a href="https://koreader.rocks"><img src="https://img.shields.io/badge/KOReader-2026.07-111111?style=flat-square" alt="Built for KOReader 2026.07"></a>
  <img src="https://img.shields.io/badge/languages-EN%20%C2%B7%20PT%20%C2%B7%20ES-111111?style=flat-square" alt="English, Portuguese and Spanish">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--3.0-111111?style=flat-square" alt="License: GPL-3.0"></a>
</p>

<p align="center">
  <a href="#what-it-does">What it does</a> ·
  <a href="#installation">Installation</a> ·
  <a href="#how-it-works">How it works</a> ·
  <a href="#development">Development</a> ·
  <a href="README_pt.md">Leia em português</a>
</p>

## What it does

<table>
  <tr>
    <td width="25%" align="center"><img src="docs/screenshots/title.png" alt="Title screen with language, streak and menu"><br><sub><b>Home</b></sub></td>
    <td width="25%" align="center"><img src="docs/screenshots/game.png" alt="A game with guesses sorted by position, closeness bars and the keyboard"><br><sub><b>Guessing</b></sub></td>
    <td width="25%" align="center"><img src="docs/screenshots/closest.png" alt="The words closest to the secret word after finding it"><br><sub><b>Closest words</b></sub></td>
    <td width="25%" align="center"><img src="docs/screenshots/help.png" alt="How to play"><br><sub><b>How to play</b></sub></td>
  </tr>
</table>

Each guess gets a position in a ranking of closeness in meaning to the secret word, which is position 1. If the secret word is "guitar", "banjo" lands at position 10 and "house" near 8,000: keep guessing until you find it. The same genre as Contexto and Semantle, made for e-ink.

- **Word of the day:** everyone playing the same language gets the same word, with no internet needed.
- **Free play:** random words, with no daily limit and no effect on your streak.
- **Closeness bars:** every guess shows its position and a bar on a log scale, so the close ones stand apart. The list is sorted by position, with your latest guess on top.
- **Its own keyboard:** always on screen, with no pop-up covering the list. Accents are optional and plurals count as their singular. A word sent again is shown where it already is in the list.
- **Hints:** a hint reveals a word halfway between your best guess and the secret word.
- **Give up:** reveals the secret word. At the end, see the 100 words closest to it.
- **Three languages:** Portuguese, English and Spanish, each with its own words. The interface follows the language you pick.
- **Statistics:** streak, wins and average guesses by language.
- **Sharing:** the daily result becomes a QR code that shows how close your guesses got, without revealing any word.
- **Sleep screen:** if the device sleeps with the game open, it shows the Warmer cover instead of the book cover. This applies when the KOReader sleep screen is set to show the book cover.
- **No internet:** it works offline and collects no data. Progress is saved after every guess.

## Installation

Each release has three packages. They play the same game and differ only in the size of the meaning data:

| Package | Size | |
|---|---|---|
| `warmer_game.koplugin.zip` | about 14 MB | **Recommended.** |
| `warmer_game.koplugin-100d.zip` | about 10 MB | Lighter. Close words come in a slightly different order. |
| `warmer_game.koplugin-300d.zip` | about 28 MB | Full data, the reference ranking. |

1. Download one of them from the [latest release](https://github.com/beater-studios/warmer_game.koplugin/releases/latest).
2. Extract it into `koreader/plugins/`, so that `koreader/plugins/warmer_game.koplugin/main.lua` exists.
3. Restart KOReader. The game is in the Tools menu, as **Warmer**.

To switch packages, extract another one over the same folder. Games in progress keep going, with positions recomputed. The About screen shows which data is installed, and the shared result includes it, so you know whether you are comparing the same ranking.

Progress is stored in `koreader/settings/warmer_game.lua`. To uninstall, delete the plugin folder and, if you wish, that file.

## How it works

Every word in the game is a list of numbers, a word vector, learned from how the word is used in billions of sentences. Words used in similar contexts get similar numbers. When a game starts, Warmer compares the secret word with every word it knows, on the device, and sorts them: that order is the ranking.

<details>
<summary><b>The data and the device</b></summary>

<br>

- **Vectors:** FastText vectors from Meta, trained on Common Crawl and Wikipedia, reduced to 100, 150 or 300 numbers per word and stored with 1 byte each.
- **Vocabulary:** about 38,000 words in Portuguese, 32,000 in English and 29,000 in Spanish, all dictionary base forms, without proper names or offensive words.
- **Secret words:** 750 per language, common words reviewed one by one, so a little over two years without repeating the word of the day.
- **On a Kindle:** opening a game takes under a second, and a guess under a millisecond. Only the language in play is in memory, a few megabytes, released when you leave the game.
- **Offline:** nothing is downloaded or sent. The data comes inside the package.

The rules, the data pipeline and the measurements are in [docs/design.md](docs/design.md).

</details>

## Compatibility

- Made for KOReader 2026.07 and for touchscreens, always in portrait. It was developed for a 10th generation basic Kindle (firmware 5.18.1).
- Layout checked in the emulator at 600x800, 758x1024, 1072x1448 and 1264x1680.
- Uses only what comes with KOReader, with nothing else to install.

## Development

With [LuaJIT](https://luajit.org) installed, from the repository root:

```sh
luajit tools/validate_data.lua --no-vectors
luajit tests/engine_spec.lua
luajit tests/vectors_spec.lua
```

The meaning data is not in the repository: `tools/data/fetch_sources.sh` downloads the sources at pinned versions and `tools/data/build_data.py` builds them. The rules, the data, the remaining tools and the release process are described in [docs/design.md](docs/design.md). To suggest removing a word, open an issue. Contributions are accepted under the project's license.

## License

The code is under [GPL-3.0](LICENSE), version 3 only. You may use, study, modify and redistribute it, keeping it open under the same license.

The game data is adapted from the FastText word vectors by Meta and is distributed under CC BY-SA 3.0. This license grants no rights to the names "Warmer" and "Beater Studios". See [NOTICE](NOTICE).

---

<p align="center">
  <sub>Made by <a href="https://beaterstudios.com/">Beater Studios</a></sub>
</p>
