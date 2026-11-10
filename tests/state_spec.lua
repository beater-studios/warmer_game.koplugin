package.path = "./?.lua;" .. package.path
local Engine = require("warmer_game/engine")
local Lexicon = require("warmer_game/lexicon")
local SavedState = require("warmer_game/saved_state")
local State = require("warmer_game/state")

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
    else
        failed = failed + 1
        print("FAILED: " .. name .. "\n  " .. tostring(err))
    end
end
local function eq(actual, expected)
    if actual ~= expected then
        error(string.format("expected %s, got %s", tostring(expected), tostring(actual)), 2)
    end
end
local function load(saved)
    local warnings = {}
    local state = State.load(function(name) return saved[name] end, function(text) warnings[#warnings + 1] = text end)
    return state, warnings
end

-- Positions follow the vocabulary order, with the secret word first: enough to restore without vectors.
local function ranker_for(lexicon, secret)
    local secret_index = lexicon.index[secret]
    local function rank_of(_, index)
        if index == secret_index then return 1 end
        return index < secret_index and index + 1 or index
    end
    return {
        total = lexicon:size(),
        rank_of = rank_of,
        index_at = function(_, position)
            if position == 1 then return secret_index end
            return position - 1 < secret_index and position - 1 or position
        end,
    }
end
local function engine_for(lexicon, record)
    local engine = Engine.new{ lexicon = lexicon, ranker = ranker_for(lexicon, record.secret), secret = record.secret, day = record.day }
    engine:restore(record)
    return engine
end

local WORDS = { "casa", "lar", "país", "pais", "café", "chá", "animal", "pão", "papel", "mar", "rio", "lago", "sol", "lua" }
local small = Lexicon.from_list(WORDS, "pt")

test("a game comes back the same after saving", function()
    local engine = engine_for(small, { secret = "mar", day = 312 })
    engine:guess("casas")
    engine:guess("pais")
    engine:hint()
    engine:guess("cafe")
    local saved = { games = { pt = SavedState.copy(State.record(engine)) }, lang = "pt" }
    local state = load(saved)
    local again = engine_for(small, state.games.pt)
    eq(#again.guesses, #engine.guesses)
    for i, entry in ipairs(engine.guesses) do
        eq(again.guesses[i].word, entry.word)
        eq(again.guesses[i].hint, entry.hint)
        eq(again.guesses[i].rank, entry.rank)
    end
    eq(again.day, 312)
    eq(select(1, again:counts()), 3)
    again:guess("mar")
    eq(again:is_won(), true)
end)

test("saving does not share tables with the engine", function()
    local engine = engine_for(small, { secret = "mar", day = 1 })
    engine:guess("casa")
    local record = State.record(engine)
    engine:guess("lar")
    eq(#record.words, 1)
    eq(record.version, State.GAME_VERSION)
end)

test("words that left the vocabulary are dropped and the game opens", function()
    local state = load({ games = { pt = { day = 5, secret = "mar", words = { "casa", "gone", "rio" }, hints = { false, false, true } } } })
    local engine = engine_for(small, state.games.pt)
    eq(#engine.guesses, 2)
    eq(engine.guesses[2].word, "rio")
    eq(engine.guesses[2].hint, true)
end)

test("a broken game is dropped and the rest stays", function()
    local state, warnings = load({
        lang = "en",
        games = {
            pt = { day = 5, secret = "mar", words = 5 },
            en = { day = "yesterday", secret = "sea", words = {} },
            es = { day = 5, secret = "mar", words = { "agua", 7 } },
        },
        stats = { pt = { played = 4, won = 3, streak = 2, best_streak = 2, last_day = 300 } },
        free_games = { pt = "broken", en = { secret = "sea", words = { "lake" } } },
        free_recent = { pt = { "casa", 3, "lar" } },
    })
    eq(state.lang, "en")
    eq(state.games.pt, nil)
    eq(state.games.en, nil)
    eq(state.games.es, nil)
    eq(state.stats.pt.played, 4)
    eq(state.stats.pt.guesses_total, 0)
    eq(state.free_games.pt, nil)
    eq(state.free_games.en.secret, "sea")
    eq(state.free_recent.pt[2], "lar")
    eq(#warnings, 0)
end)

test("a reader that fails on one entry only loses that entry", function()
    local state, warnings = load({ stats = { pt = setmetatable({}, { __index = function() error("planted") end }), en = { played = 1 } } })
    eq(state.stats.pt, nil)
    eq(state.stats.en.played, 1)
    eq(#warnings, 1)
end)

test("unknown languages and choices fall back", function()
    local state = load({ lang = "fr", games = { fr = { day = 1, secret = "mer", words = {} } }, stats = { pt = { played = "many", last_day = 1.5 } } })
    eq(state.lang, nil)
    eq(state.games.fr, nil)
    eq(state.stats.pt.played, 0)
    eq(state.stats.pt.last_day, nil)
end)

test("saves of every published version open", function()
    local lexicons = {}
    local function lexicon(lang)
        lexicons[lang] = lexicons[lang] or Lexicon.load(".", lang)
        return lexicons[lang]
    end
    local pipe = io.popen("ls tests/saves")
    local count = 0
    for name in pipe:lines() do
        local saved = dofile("tests/saves/" .. name)
        local state, warnings = load(saved)
        eq(#warnings, 0)
        for _, map in ipairs({ { state.games, saved.games }, { state.free_games, saved.free_games } }) do
            for lang, raw in pairs(map[2] or {}) do
                local record = map[1][lang]
                assert(record, name .. ": game dropped in " .. lang)
                eq(record.version, State.GAME_VERSION)
                local engine = engine_for(lexicon(lang), record)
                eq(#engine.guesses, #raw.words)
                eq(engine:is_over(), raw.finished)
            end
        end
        for lang, raw in pairs(saved.stats or {}) do
            eq(state.stats[lang].played, raw.played)
            eq(state.stats[lang].guesses_total, raw.guesses_total)
        end
        eq(state.lang, saved.lang)
        count = count + 1
    end
    pipe:close()
    assert(count > 0, "no saves in tests/saves")
end)

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
