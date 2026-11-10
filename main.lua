local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")

local GameScreensaver = require("warmer_game/screensaver")
local Screen = require("warmer_game/ui/screen")

local PLUGIN_DIR = debug.getinfo(1, "S").source:gsub("^@", ""):match("(.*)/") or "."

GameScreensaver.install(PLUGIN_DIR, "warmer_game")

local WarmerGame = WidgetContainer:extend{
    name = "warmer_game",
    is_doc_only = false,
}

function WarmerGame:init()
    self.ui.menu:registerToMainMenu(self)
end

function WarmerGame:addToMainMenu(menu_items)
    menu_items.warmer_game = {
        text = self.fullname,
        sorting_hint = "tools",
        callback = function()
            -- An error leaving the menu callback would bring KOReader down.
            local ok, screen = pcall(Screen.new, Screen, { plugin_dir = PLUGIN_DIR })
            if ok then
                UIManager:show(screen)
            else
                logger.warn("warmer_game: could not open", screen)
                UIManager:show(InfoMessage:new{ text = Screen.open_failed_text(PLUGIN_DIR) })
            end
        end,
    }
end

return WarmerGame
