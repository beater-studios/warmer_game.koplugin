local plugin_dir = assert(os.getenv("PLUGIN_DIR"))
local out_dir = assert(os.getenv("OUTPUT_DIR"))

require("setupkoenv")
local DataStorage = require("datastorage")
G_defaults = require("luadefaults"):open()
G_reader_settings = require("luasettings"):open(DataStorage:getDataDir() .. "/settings.reader.lua")
G_reader_settings:saveSetting("language", "pt_BR")
package.path = plugin_dir .. "/?.lua;" .. package.path

local Device = require("device")
local Screen = Device.screen
require("document/canvascontext"):init(Device)
local UIManager = require("ui/uimanager")
UIManager:init()
local Engine = require("warmer_game/engine")
local GameScreen = require("warmer_game/ui/screen")
local Lexicon = require("warmer_game/lexicon")
local TextWidget = require("ui/widget/textwidget")

local problems = 0
local function problem(text)
    problems = problems + 1
    print("PROBLEM: " .. text)
end
local function shot(name)
    UIManager:forceRePaint()
    Screen.bb:writePNG(out_dir .. "/" .. name .. ".png")
end
local function check_height(game, name)
    if game.content_height > Screen:getHeight() then
        problem("page taller than the screen in " .. name .. ": " .. game.content_height)
    end
end
local function check_rects(rects, name)
    for _, r in ipairs(rects) do
        if r.x < 0 or r.y < 0 or r.x + r.w > Screen:getWidth() or r.y + r.h > Screen:getHeight() then
            problem(name .. " off screen: " .. tostring(r.id))
        end
    end
end
local function tap(game, rect)
    game.view:onTap(nil, { pos = { x = rect.x + math.floor(rect.w / 2), y = rect.y + math.floor(rect.h / 2) } })
end
local function action(game, id)
    for _, rect in ipairs(game.view.actions) do
        if rect.id == id then
            tap(game, rect)
            return true
        end
    end
    problem("missing button " .. id)
end
local function key(game, id)
    for _, k in ipairs(game.view.keys) do
        if k.id == id then return k end
    end
    problem("missing key " .. id .. " in " .. game.lang)
end
-- Types on the game's keyboard; accents are left out, as a player would.
local function type_word(game, word)
    for _, letter in ipairs(Engine.split(Engine.plain(word, game.lang))) do
        tap(game, key(game, letter))
    end
end
local function send(game, word)
    type_word(game, word)
    tap(game, key(game, "submit"))
end
local function top_widget()
    return UIManager._window_stack[#UIManager._window_stack].widget
end
local function text_fits(text, face, width, label)
    local widget = TextWidget:new{ text = text, face = face }
    if widget:getSize().w > width then
        problem("text does not fit in " .. label .. ": " .. text)
    end
    widget:free()
end

local game = GameScreen:new{ plugin_dir = plugin_dir }
UIManager:show(game)
check_height(game, "title")
shot("title")

for _, lang in ipairs(Lexicon.LANGUAGES) do
    game.lang = lang
    game.games, game.stats, game.free_games, game.free_stats, game.free_recent = {}, {}, {}, {}, {}
    game:show_title()
    check_height(game, "title " .. lang)
    game:start_daily()
    local view = game.view
    if not view then
        problem("daily game did not open in " .. lang)
    else
        local t = game:strings()
        if not view:keyboard_visible() then problem("keyboard not shown in " .. lang) end
        check_rects(view.actions, lang)
        check_rects(view.keys, lang .. " keyboard")
        check_rects(view.pager_buttons, lang .. " pager")
        check_rects({ view.back_rect }, lang .. " back button")
        if view.pager_y + view.pager_h > Screen:getHeight() - view.keyboard_h then problem("pager overlaps the keyboard in " .. lang) end
        if view.rows_per_page < 5 then problem("only " .. view.rows_per_page .. " rows per page in " .. lang) end
        local message_width = view.width - Screen:scaleBySize(12)
        for _, text in ipairs({
            t.start_message,
            string.format(t.plural, "rendimientos", "rendimiento", 28999),
            string.format(t.repeated, "responsabilidade", 12345),
            string.format(t.hint_given, "responsabilidade", 12345),
            string.format(t.won, 123),
            t.won_one,
            string.format(t.won_hints, 123, 12),
            string.format(t.lost, "responsabilidade"),
            string.format(t.unknown, "responsabilidades"),
        }) do
            text_fits(text, view.message_face, message_width, lang .. " header")
        end
        text_fits(string.format(t.daily_title, 1234), view.title_face, view.width - 2 * (view.back_rect.x + view.back_rect.w + Screen:scaleBySize(6)), lang .. " title")

        local data = game.data
        local secret = game.engine.secret
        local guesses = {}
        for _, word in ipairs(data.secrets) do
            if word ~= secret then guesses[#guesses + 1] = word end
            if #guesses == 24 then break end
        end
        type_word(game, guesses[1])
        if view:typed_text() ~= Engine.plain(guesses[1], lang) then problem("typing failed in " .. lang .. ": " .. view:typed_text()) end
        if lang == "pt" then shot("typing_pt") end
        tap(game, key(game, "backspace"))
        if #Engine.split(view:typed_text()) ~= #Engine.split(Engine.plain(guesses[1], lang)) - 1 then problem("backspace failed in " .. lang) end
        view:clear_typed()
        for i, word in ipairs(guesses) do
            send(game, word)
            if #game.engine.guesses ~= i then problem("guess did not count in " .. lang .. ": " .. word) end
        end
        if view:typed_text() ~= "" then problem("typed word not cleared in " .. lang) end
        send(game, "qwzxq")
        if #game.engine.guesses ~= #guesses then problem("unknown word counted in " .. lang) end
        if view.message ~= string.format(t.unknown, "qwzxq") then problem("unknown word message missing in " .. lang) end

        -- A word sent again turns the list to its page and marks it.
        local sorted = game.engine:sorted()
        local last_entry = sorted[#sorted]
        send(game, last_entry.word)
        if #game.engine.guesses ~= #guesses then problem("repeated word counted in " .. lang) end
        if view.focus ~= last_entry.index or view.page ~= view:page_count() then problem("repeated word not shown in " .. lang) end
        if lang == "pt" then shot("repeated_pt") end
        tap(game, view.pager_buttons[1])

        local before = #game.engine.guesses
        action(game, "hint")
        if #game.engine.guesses ~= before + 1 or not game.engine:last().hint then problem("hint did not work in " .. lang) end
        if view.focus then problem("hint did not clear the repeated word mark in " .. lang) end
        if view:page_count() < 2 then problem("no second page in " .. lang) end
        tap(game, view.pager_buttons[2])
        if view.page ~= 2 then problem("next page did not work in " .. lang) end
        shot("game_page2_" .. lang)
        tap(game, view.pager_buttons[1])
        if view.page ~= 1 then problem("previous page did not work in " .. lang) end
        shot("game_" .. lang)

        action(game, "give_up")
        local confirm = top_widget()
        if not confirm.ok_callback then problem("give up did not ask in " .. lang) else
            confirm.ok_callback()
            UIManager:close(confirm)
        end
        if not game.engine:is_over() or game.engine:is_won() then problem("give up did not end the game in " .. lang) end
        if view:keyboard_visible() then problem("keyboard still shown after the end in " .. lang) end
        if not game.stats[lang] or game.stats[lang].played ~= 1 then problem("daily result not recorded in " .. lang) end
        check_rects(view.actions, lang .. " result")
        shot("result_" .. lang)
        action(game, "closest")
        if view.list_mode ~= "closest" or #view.closest ~= 101 then problem("closest words missing in " .. lang) end
        if view.closest[1].word ~= secret or view.closest[2].rank ~= 2 then problem("closest list starts wrong in " .. lang) end
        shot("closest_" .. lang)
        tap(game, view.back_rect)
        if view.list_mode ~= "game" or game.mode ~= "game" then problem("back from closest words failed in " .. lang) end
        action(game, "share")
        local qr = top_widget()
        if qr == game then problem("share did not open in " .. lang) else UIManager:close(qr) end

        game:show_title()
        game:start_daily()
        if not game.engine:is_over() or #game.engine.guesses ~= before + 1 then problem("finished daily game not restored in " .. lang) end

        game:show_title()
        check_height(game, "title after a game " .. lang)
        game:start_free()
        if not game.free_play or game.engine:is_over() then problem("free play did not start in " .. lang) end
        if game.engine.secret == Engine.secret_for_day(data.secrets, Engine.today()) then problem("free play drew today's word in " .. lang) end
        local first_free = game.engine.secret
        send(game, guesses[2] ~= first_free and guesses[2] or guesses[3])
        game:show_title()
        game:start_free()
        if game.engine.secret ~= first_free or #game.engine.guesses ~= 1 then problem("free play not restored in " .. lang) end
        send(game, first_free)
        if not game.engine:is_won() then problem("free play not won in " .. lang) end
        if game.free_stats[lang].won ~= 1 then problem("free play result not recorded in " .. lang) end
        if game.stats[lang].played ~= 1 then problem("free play changed the daily stats in " .. lang) end
        shot("free_won_" .. lang)
        action(game, "new_word")
        if game.engine:is_over() or game.engine.secret == first_free then problem("new word did not draw another in " .. lang) end
        local free_played = game.free_stats[lang].played
        send(game, game.engine.secret)
        if game.view.message ~= t.won_one then problem("first guess win message wrong in " .. lang .. ": " .. tostring(game.view.message)) end
        if game.free_stats[lang].played ~= free_played + 1 then problem("first guess win not recorded in " .. lang) end
        game:after_move()
        if game.free_stats[lang].played ~= free_played + 1 then problem("finished free game counted twice in " .. lang) end
        game:start_free(true)
        action(game, "hint")
        send(game, guesses[4] ~= game.engine.secret and guesses[4] or guesses[5])
        game:show_title()
        game:start_free()
        if #game.engine.guesses ~= 2 then problem("free game with a hint not restored in " .. lang) end
        for _, entry in ipairs(game.engine.guesses) do
            if entry.rank ~= game.engine.ranker:rank_of(entry.index) then problem("restored position wrong in " .. lang .. ": " .. entry.word) end
        end
        if game.loading then problem("loading message left open in " .. lang) end
        send(game, game.engine.secret)
        local won_guesses, won_hints = game.engine:counts()
        if game.view.message ~= string.format(t.won_hints, won_guesses, won_hints) then problem("win with hints message wrong in " .. lang .. ": " .. tostring(game.view.message)) end

        game:show_stats(function() end)
        check_height(game, "statistics " .. lang)
        shot("stats_" .. lang)
        game:show_help()
        check_height(game, "help " .. lang)
        shot("help_" .. lang)
        game:show_about()
        check_height(game, "about " .. lang)
        shot("about_" .. lang)
    end
end

game.lang = "es"
game:save()
UIManager:close(game)
local reopened = GameScreen:new{ plugin_dir = plugin_dir }
if reopened.lang ~= "es" then problem("language not saved") end

-- The About screen shows the version from _meta.lua, in every language.
local meta = dofile(plugin_dir .. "/_meta.lua")
local real_show_page = GameScreen.show_page
for _, lang in ipairs(Lexicon.LANGUAGES) do
    local shown
    GameScreen.show_page = function(screen, title, items, back)
        shown = items
        return real_show_page(screen, title, items, back)
    end
    reopened.lang = lang
    reopened:show_about()
    GameScreen.show_page = real_show_page
    local found = false
    for _, item in ipairs(shown or {}) do
        if (item.meta or ""):find(meta.version, 1, true) then found = true end
    end
    if not found then problem("version missing on the About screen in " .. lang) end
end

-- A daily game in progress comes back in a new screen opened with the same settings.
UIManager:show(reopened)
reopened.lang = "pt"
reopened.games = {}
reopened:start_daily()
local first_guess
for _, word in ipairs(reopened.data.secrets) do
    if word ~= reopened.engine.secret then first_guess = word break end
end
send(reopened, first_guess)
local daily_secret = reopened.engine.secret
UIManager:close(reopened)
local resumed = GameScreen:new{ plugin_dir = plugin_dir }
UIManager:show(resumed)
if resumed.lang ~= "pt" then problem("language did not come back in a new screen") end
resumed:start_daily()
if #resumed.engine.guesses ~= 1 or resumed.engine.guesses[1].word ~= first_guess or resumed.engine.secret ~= daily_secret then
    problem("daily game in progress did not come back in a new screen")
end

-- Refresh modes: a new layout flashes, a change inside it does not, the 9th change in a row flashes, and the
-- end of a game and the switch to the closest words flash. Key presses update only the typed line.
local real_set_dirty = UIManager.setDirty
local log = {}
UIManager.setDirty = function(_, widget, refresh)
    if widget == resumed then
        log[#log + 1] = type(refresh) == "function" and (refresh()) or refresh
    end
end
local function modes(fn)
    log = {}
    fn()
    return table.concat(log, ",")
end
local function expect(name, actual, wanted)
    if actual ~= wanted then problem(string.format("refresh in %s: %s, expected %s", name, actual, wanted)) end
end
resumed.games = {}
resumed:show_help()
expect("title", modes(function() resumed:show_title() end), "full")
local changes = {}
for i = 1, 9 do changes[i] = modes(function() resumed:show_title() end) end
expect("option changes", table.concat(changes, ","), "ui,ui,ui,ui,ui,ui,ui,ui,full")
expect("opening a game", modes(function() resumed:start_daily() end), "full")
local wrong = {}
for _, word in ipairs(resumed.data.secrets) do
    if word ~= resumed.engine.secret and #Engine.split(word) <= 6 then wrong[#wrong + 1] = word end
    if #wrong == 2 then break end
end
local keys = string.rep("ui,", #Engine.split(Engine.plain(wrong[1], "pt")))
expect("typing and sending", modes(function() send(resumed, wrong[1]) end), keys .. "ui")
expect("hint", modes(function() action(resumed, "hint") end), "ui")
expect("giving up", modes(function()
    action(resumed, "give_up")
    local confirm = top_widget()
    confirm.ok_callback()
    UIManager:close(confirm)
end), "full")
expect("closest words", modes(function() action(resumed, "closest") end), "full")
expect("back from the closest words", modes(function() tap(resumed, resumed.view.back_rect) end), "full")
expect("page", modes(function() resumed:show_about() end), "full")
UIManager.setDirty = real_set_dirty
UIManager:close(resumed)

-- Back goes back one screen and closes from the title; KOReader's Close closes, except before a shutdown.
local back = GameScreen:new{ plugin_dir = plugin_dir }
UIManager:show(back)
back:start_daily()
back:onBack()
if back.mode ~= "title" or not UIManager:isWidgetShown(back) then problem("Back in a game did not go to the title") end
back:show_help()
back:onBack()
if back.mode ~= "title" then problem("Back on the help page did not go to the title") end
back:onClose({ keep_screensaver = true })
if not UIManager:isWidgetShown(back) then problem("Close before a shutdown closed the window") end
back:onBack()
if UIManager:isWidgetShown(back) then problem("Back on the title did not close the game") end
local closing = GameScreen:new{ plugin_dir = plugin_dir }
UIManager:show(closing)
closing:start_daily()
closing:onClose()
if UIManager:isWidgetShown(closing) then problem("KOReader's Close did not close the window") end

-- A failing paint of the guesses leaves the header and the keyboard working.
local broken = GameScreen:new{ plugin_dir = plugin_dir }
UIManager:show(broken)
broken:start_daily()
local real_paint = broken.view.paint_guesses
broken.view.paint_guesses = function() error("planted failure") end
local paint_ok = pcall(function() broken:paintTo(Screen.bb, 0, 0) end)
if not paint_ok then problem("a failing paint of the guesses broke the screen") end
broken.view.paint_guesses = real_paint
tap(broken, broken.view.back_rect)
if broken.mode ~= "title" then problem("Back did not work after a failing paint") end
UIManager:close(broken)

print("problems: " .. problems)
os.exit(problems == 0 and 0 or 1)
