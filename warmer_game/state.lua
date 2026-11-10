-- Reads back what any version saved in koreader/settings/warmer_game.lua, without KOReader, so the tests
-- load real saves of older versions. Games, statistics and choices are checked field by field: a game that
-- cannot be read is dropped, and the statistics and the other games stay.
local Engine = require("warmer_game/engine")
local Lexicon = require("warmer_game/lexicon")
local SavedState = require("warmer_game/saved_state")

local State = {}

-- Goes up only when a saved field changes meaning. Games saved before 0.1.2 have no version and the same
-- format, so they count as version 1.
State.GAME_VERSION = 1

local STATS = Engine.new_stats()
local FREE_STATS = { played = 0, won = 0 }

local function is_day(value)
    return type(value) == "number" and value % 1 == 0
end

-- A saved game with every part checked, or nil when it cannot be played. Words are kept as saved: the ones
-- that left the vocabulary are dropped when the game opens, and a secret word that left it gives a new game.
function State.game(saved, daily)
    if type(saved) ~= "table" or (saved.version or 1) ~= State.GAME_VERSION then
        return nil
    end
    if type(saved.secret) ~= "string" or saved.secret == "" then
        return nil
    end
    if daily and not is_day(saved.day) then
        return nil
    end
    if saved.words ~= nil and type(saved.words) ~= "table" then
        return nil
    end
    local words, hints = {}, {}
    local saved_hints = type(saved.hints) == "table" and saved.hints or {}
    for i, word in ipairs(SavedState.list(saved.words or {})) do
        if type(word) ~= "string" then
            return nil
        end
        words[#words + 1] = word
        hints[#hints + 1] = saved_hints[i] == true
    end
    return {
        version = State.GAME_VERSION,
        day = daily and saved.day or nil,
        secret = saved.secret,
        words = words,
        hints = hints,
        gave_up = saved.gave_up == true,
        finished = saved.finished == true,
    }
end

local function stats_of(saved)
    local stats = SavedState.with_defaults(saved, STATS)
    if not is_day(stats.last_day) then
        stats.last_day = nil
    end
    return stats
end

local function recent_of(saved)
    return SavedState.known(saved, function(word) return type(word) == "string" end)
end

-- Each entry of a saved map by language, through read(value), keeping the ones that give something back.
-- read runs protected, so one broken entry never stops the opening.
local function by_language(saved, read, warn)
    local out = {}
    if type(saved) ~= "table" then
        return out
    end
    for _, lang in ipairs(Lexicon.LANGUAGES) do
        if saved[lang] ~= nil then
            out[lang] = SavedState.restore(read, saved[lang], warn)
        end
    end
    return out
end

-- read(name) gives a saved setting (settings:readSetting); warn reports a dropped game (logger.warn).
function State.load(read, warn)
    return {
        lang = SavedState.one_of(read("lang"), Lexicon.LANGUAGES),
        games = by_language(read("games"), function(data) return State.game(data, true) end, warn),
        stats = by_language(read("stats"), stats_of, warn),
        free_games = by_language(read("free_games"), function(data) return State.game(data, false) end, warn),
        free_stats = by_language(read("free_stats"), function(data) return SavedState.with_defaults(data, FREE_STATS) end, warn),
        free_recent = by_language(read("free_recent"), recent_of, warn),
    }
end

-- What goes into the save for the game in play. serialize builds new tables, so the engine never changes a
-- saved one.
function State.record(engine)
    local record = engine:serialize()
    record.version = State.GAME_VERSION
    return record
end

return State
