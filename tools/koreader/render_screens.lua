-- Renders the README screenshots with a free play game whose secret word is not a daily word.
local plugin_dir = assert(os.getenv("PLUGIN_DIR"))
local out_dir = assert(os.getenv("OUTPUT_DIR"))

require("setupkoenv")
local DataStorage = require("datastorage")
G_defaults = require("luadefaults"):open()
G_reader_settings = require("luasettings"):open(DataStorage:getDataDir() .. "/settings.reader.lua")
G_reader_settings:saveSetting("language", "en_US")
package.path = plugin_dir .. "/?.lua;" .. package.path

local Device = require("device")
local Screen = Device.screen
require("document/canvascontext"):init(Device)
local UIManager = require("ui/uimanager")
UIManager:init()
local GameScreen = require("warmer_game/ui/screen")

local SECRET = "guitar"
local GUESSES = { "house", "song", "wood", "sound", "drum", "music", "string", "band", "dance", "radio", "concert" }

local function shot(name)
    UIManager:forceRePaint()
    local path = out_dir .. "/" .. name .. ".png"
    Screen.bb:writePNG(path)
    print("saved: " .. path)
end

local game = GameScreen:new{ plugin_dir = plugin_dir }
UIManager:show(game)
shot("title")
local data = game:language_data()
for _, word in ipairs(data.secrets) do
    assert(word ~= SECRET, "the screenshot word must not be a daily word")
end
game.free_games.en = { secret = SECRET, words = {}, hints = {} }
game:start_free()
for _, word in ipairs(GUESSES) do
    game.engine:guess(word)
end
game.engine:hint()
game.view.message = game:status_message()
shot("game")
game.engine:guess(SECRET)
game:after_move()
game:on_action("closest")
shot("closest")
game:show_help()
shot("help")
os.exit(0)
