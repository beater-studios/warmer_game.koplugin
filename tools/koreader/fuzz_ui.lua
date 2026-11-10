-- Random touches through the real screens: the title, the word of the day and free play, in each language. In
-- a game, one step in four types a word drawn from the 3000 most frequent ones (now and then the secret word)
-- on the game keyboard and sends it, so games reach their end; the other steps are random touches.
-- Run: KOREADER_DIR=<desktop KOReader> tools/koreader/run_headless.sh tools/koreader/fuzz_ui.lua
local Fuzz = dofile(os.getenv("PLUGIN_DIR") .. "/tools/koreader/fuzz.lua")
local DataStorage = require("datastorage")
local UIManager = require("ui/uimanager")
local Engine = require("warmer_game/engine")
local GameScreen = require("warmer_game/ui/screen")
local GameView = require("warmer_game/ui/game_view")
local Lexicon = require("warmer_game/lexicon")
local SavedState = require("warmer_game/saved_state")

local FREQUENT_WORDS = 3000

-- A fixed day, so a run repeats the same word of the day whatever the date.
Engine.today = function() return 312 end

local settings_file = DataStorage:getSettingsDir() .. "/warmer_game.lua"
local taps, modes = 0, {}
local real_tap = GameView.onTap
GameView.onTap = function(...)
    taps = taps + 1
    return real_tap(...)
end

local screen = GameScreen:new{ plugin_dir = Fuzz.plugin_dir }
local fuzz = Fuzz.new{ screen = screen }

-- Every run starts from no saved state and the same free play draws.
local function fresh_screen(f, lang)
    if UIManager:isWidgetShown(f.screen) then
        UIManager:close(f.screen)
    end
    SavedState.remove_file(settings_file)
    local new = GameScreen:new{ plugin_dir = Fuzz.plugin_dir }
    math.randomseed(f.seed)
    new.lang = lang
    new:save()
    UIManager:show(new)
    return new
end

local function tap_rect(f, rect)
    f:tap(rect.x + math.floor(rect.w / 2), rect.y + math.floor(rect.h / 2))
end

local function key_rect(view, id)
    for _, key in ipairs(view.keys) do
        if key.id == id then return key end
    end
end

local function game_step(f)
    local game = f.screen
    modes[game.mode .. (game.view and game.view.list_mode == "closest" and " closest" or "")] = true
    if game.mode == "game" and game.view:keyboard_visible() and f.random(1, 4) == 1 then
        local words = game.data.lexicon.words
        local word = f.random(1, 10) == 1 and game.engine.secret or words[f.random(1, math.min(FREQUENT_WORDS, #words))]
        for _, letter in ipairs(Engine.split(Engine.plain(word, game.lang))) do
            local key = key_rect(game.view, letter)
            if key then tap_rect(f, key) end
        end
        tap_rect(f, key_rect(game.view, "submit"))
    else
        f:touch()
    end
end

local function left_game(f)
    return f.screen.mode ~= "game"
end

for _, lang in ipairs(Lexicon.LANGUAGES) do
    fuzz:run{
        label = "title " .. lang,
        setup = function(f)
            local new = fresh_screen(f, lang)
            new:show_title()
            return new
        end,
        step = function(f)
            modes[f.screen.mode] = true
            f:touch()
        end,
    }
end
for _, lang in ipairs(Lexicon.LANGUAGES) do
    fuzz:run{
        label = "daily " .. lang,
        setup = function(f)
            local new = fresh_screen(f, lang)
            new:start_daily()
            return new
        end,
        again = left_game,
        step = game_step,
    }
end
for _, lang in ipairs(Lexicon.LANGUAGES) do
    fuzz:run{
        label = "free " .. lang,
        setup = function(f)
            local new = fresh_screen(f, lang)
            new:start_free()
            return new
        end,
        again = left_game,
        step = game_step,
    }
end

local visited = {}
for mode in pairs(modes) do visited[#visited + 1] = mode end
table.sort(visited)
print(string.format("%d taps reached the game view; screens visited: %s", taps, table.concat(visited, ", ")))
fuzz:finish()
