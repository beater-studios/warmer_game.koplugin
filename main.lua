local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local GameScreensaver = require("warmer_game/screensaver")
local Screen = require("warmer_game/ui/screen")

local PLUGIN_DIR = debug.getinfo(1, "S").source:gsub("^@", ""):match("(.*)/") or "."

GameScreensaver.install(PLUGIN_DIR)

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
            UIManager:show(Screen:new{ plugin_dir = PLUGIN_DIR })
        end,
    }
end

return WarmerGame
