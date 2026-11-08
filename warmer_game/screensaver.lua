local Screensaver = require("ui/screensaver")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")

local SCREEN_NAME = "warmer_game_screen"

local GameScreensaver = {}

local function game_on_top()
    for widget in UIManager:topdown_widgets_iter() do
        if widget.covers_fullscreen then
            return widget.name == SCREEN_NAME
        end
    end
    return false
end

-- KOReader chooses the book cover first; the game only swaps it while it is the screen being shown, so closing the game restores the default behavior.
local function apply(saver, event, image_file)
    if event ~= nil or not saver.ui or G_reader_settings:readSetting("screensaver_type") ~= "cover" then
        return
    end
    if not game_on_top() or lfs.attributes(image_file, "mode") ~= "file" then
        return
    end
    if saver.image then
        saver.image:free()
    end
    saver.image = nil
    saver.image_file = image_file
    saver.screensaver_type = "cover"
end

function GameScreensaver.install(plugin_dir)
    GameScreensaver.image_file = plugin_dir .. "/assets/screensaver.png"
    if Screensaver._warmer_game_original_setup then
        return
    end
    local original_setup = Screensaver.setup
    Screensaver._warmer_game_original_setup = original_setup
    Screensaver.setup = function(saver, event, ...)
        original_setup(saver, event, ...)
        local ok, err = pcall(apply, saver, event, GameScreensaver.image_file)
        if not ok then
            logger.warn("Warmer: screensaver cover failed", err)
        end
    end
end

return GameScreensaver
