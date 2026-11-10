local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local DataStorage = require("datastorage")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local LuaSettings = require("luasettings")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local logger = require("logger")

local Engine = require("warmer_game/engine")
local GameView = require("warmer_game/ui/game_view")
local Lexicon = require("warmer_game/lexicon")
local Portrait = require("warmer_game/portrait")
local Refresh = require("warmer_game/refresh")
local SavedState = require("warmer_game/saved_state")
local State = require("warmer_game/state")
local Vectors = require("warmer_game/vectors")

local Device_screen = Device.screen

local SERIF = "noto/NotoSerif-Regular.ttf"
local SERIF_BOLD = "noto/NotoSerif-Bold.ttf"
local SERIF_ITALIC = "noto/NotoSerif-Italic.ttf"
local LANGUAGE_NAMES = { pt = "Português", en = "English", es = "Español" }
local RECENT_FREE_WORDS = 30
local UPCOMING_DAILY_WORDS = 30
local CLOSEST_WORDS = 100

local function load_table(path)
    local chunk = assert(loadfile(path))
    setfenv(chunk, {})
    return chunk()
end

local function default_language()
    local code = G_reader_settings and G_reader_settings:readSetting("language") or ""
    local prefix = code:sub(1, 2):lower()
    return LANGUAGE_NAMES[prefix] and prefix or "en"
end

local Screen = InputContainer:extend{
    name = "warmer_game_screen",
    covers_fullscreen = true,
    stop_events_propagation = true,
    plugin_dir = ".",
}

-- The layout only fits portrait.
function Screen:init()
    Portrait.open(self, self.setup)
end

function Screen:setup()
    if Device:hasKeys() then
        self.key_events.Back = { { Device.input.group.Back } }
    end
    -- Screens are rebuilt whole, so up to 8 updates without a flash, then a full one against ghosting.
    self.refresh = Refresh.new(8)
    math.randomseed(os.time())
    self.dimen = Geom:new{ x = 0, y = 0, w = Device_screen:getWidth(), h = Device_screen:getHeight() }
    self.width, self.height = self.dimen.w, self.dimen.h
    self.margin = self:scaled(20)
    self.text_width = self.width - 2 * self.margin
    self.settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/warmer_game.lua")
    self.meta = load_table(self.plugin_dir .. "/_meta.lua")
    self.i18n = load_table(self.plugin_dir .. "/data/i18n.lua")
    local saved = State.load(function(name) return self.settings:readSetting(name) end, logger.warn)
    self.lang = saved.lang or default_language()
    self.games = saved.games
    self.stats = saved.stats
    self.free_games = saved.free_games
    self.free_stats = saved.free_stats
    self.free_recent = saved.free_recent
    self:show_title()
end

-- Shown by the menu when the screen could not open. The texts file may be what failed, so English is the
-- last resort.
function Screen.open_failed_text(plugin_dir)
    local ok, i18n = pcall(load_table, plugin_dir .. "/data/i18n.lua")
    if not ok or type(i18n) ~= "table" then
        return "Warmer could not open. Try restarting KOReader."
    end
    local settings_ok, settings = pcall(LuaSettings.open, LuaSettings, DataStorage:getSettingsDir() .. "/warmer_game.lua")
    local lang = settings_ok and settings:readSetting("lang") or default_language()
    local texts = i18n[lang] or i18n.en
    return texts.open_failed
end

function Screen:scaled(value)
    return Device_screen:scaleBySize(value)
end

function Screen:strings()
    return self.i18n[self.lang]
end

function Screen:save()
    self.settings:saveSetting("lang", self.lang)
    for _, key in ipairs({ "games", "stats", "free_games", "free_stats", "free_recent" }) do
        self.settings:saveSetting(key, self[key])
    end
    self.settings:flush()
end

-- The loading message covers both reading the data and computing the ranking; open_game closes it.
function Screen:show_loading()
    if not self.loading then
        local InfoMessage = require("ui/widget/infomessage")
        self.loading = InfoMessage:new{ text = self:strings().loading }
        UIManager:show(self.loading)
        UIManager:forceRePaint()
    end
end

function Screen:hide_loading()
    if self.loading then
        UIManager:close(self.loading)
        self.loading = nil
    end
end

-- Only the language in play is held in memory, and only while the screen is open.
function Screen:language_data()
    if self.data and self.data.lang == self.lang then
        return self.data
    end
    -- The previous game holds the other language's vocabulary and ranking, so it is dropped before loading.
    self.data, self.engine, self.view = nil, nil, nil
    collectgarbage()
    self:show_loading()
    local lexicon = Lexicon.load(self.plugin_dir, self.lang)
    local vectors = Vectors.load(string.format("%s/data/%s/vectors.bin", self.plugin_dir, self.lang))
    local secrets = {}
    if lexicon then
        -- A secret word missing from the vocabulary would have no vector, so damaged data is filtered here.
        for _, word in ipairs(Lexicon.load_secrets(self.plugin_dir, self.lang)) do
            if lexicon.index[word] then
                secrets[#secrets + 1] = word
            end
        end
    end
    if not lexicon or not vectors or vectors.n ~= lexicon:size() or #secrets == 0 then
        self:hide_loading()
        local InfoMessage = require("ui/widget/infomessage")
        UIManager:show(InfoMessage:new{ text = self:strings().missing_data })
        return nil
    end
    self.data = { lang = self.lang, lexicon = lexicon, vectors = vectors, secrets = secrets, rankers = {} }
    return self.data
end

function Screen:ranker_for(data, secret)
    -- Two rankers at most: the daily word and the free play word.
    if not data.rankers[secret] then
        self:show_loading()
        local count = 0
        for _ in pairs(data.rankers) do count = count + 1 end
        if count >= 2 then
            data.rankers = {}
        end
        data.rankers[secret] = data.vectors:ranker(data.lexicon.index[secret])
    end
    return data.rankers[secret]
end

function Screen:dimensions()
    return self.data and self.data.vectors.d or nil
end

-- kind names the layout: the same kind again is a change inside it and is updated without a flash.
-- content_height is read by tools/koreader/check_layout.lua to catch pages taller than the screen.
function Screen:set_widget(widget, kind, content_height)
    if self[1] then
        self[1]:free()
    end
    self.content_height = content_height or widget:getSize().h
    self[1] = widget
    local mode = self.refresh:mode(kind)
    UIManager:setDirty(self, function()
        return mode, self.dimen
    end)
end

function Screen:set_page(group, kind, content_height)
    self:set_widget(FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        margin = 0,
        width = self.width,
        height = self.height,
        group,
    }, kind, content_height or group:getSize().h)
end

function Screen:centered(widget, height)
    return CenterContainer:new{
        dimen = Geom:new{ w = self.width, h = height or widget:getSize().h },
        widget,
    }
end

function Screen:text_line(text, face, size)
    return TextWidget:new{ text = text, face = Font:getFace(face, size), max_width = self.text_width }
end

function Screen:menu_button(text, callback)
    return Button:new{
        text = text,
        width = self.width - 2 * self:scaled(50),
        padding_v = self:scaled(8),
        radius = self:scaled(8),
        bordersize = self:scaled(2),
        text_font_face = "cfont",
        text_font_size = 19,
        callback = callback,
    }
end

function Screen:option_row(options, selected, on_select)
    local row = HorizontalGroup:new{ align = "center" }
    local gap = self:scaled(6)
    local width = math.floor((self.text_width - (#options - 1) * gap) / #options)
    for i, option in ipairs(options) do
        if i > 1 then
            row[#row + 1] = HorizontalSpan:new{ width = gap }
        end
        local is_selected = option.value == selected
        row[#row + 1] = Button:new{
            text = (is_selected and "• " or "") .. option.label,
            width = width,
            padding_v = self:scaled(7),
            radius = self:scaled(8),
            bordersize = is_selected and self:scaled(3) or self:scaled(1),
            text_font_face = "cfont",
            text_font_bold = is_selected,
            text_font_size = 17,
            callback = function() on_select(option.value) end,
        }
    end
    return row
end

function Screen:saved_daily(day)
    local saved = self.games[self.lang]
    if saved and saved.day == (day or Engine.today()) then
        return saved
    end
end

function Screen:show_title()
    self.mode = "title"
    self.engine, self.view = nil, nil
    local t = self:strings()
    local group = VerticalGroup:new{ align = "center" }
    local function add(widget)
        group[#group + 1] = widget
    end
    local function space(value)
        group[#group + 1] = VerticalSpan:new{ width = self:scaled(value) }
    end

    add(self:centered(self:text_line(t.name, SERIF_BOLD, 36)))
    space(20)
    add(self:centered(self:text_line(t.language, SERIF_ITALIC, 18)))
    space(6)
    local languages = {}
    for i, code in ipairs(Lexicon.LANGUAGES) do
        languages[i] = { value = code, label = LANGUAGE_NAMES[code] }
    end
    add(self:centered(self:option_row(languages, self.lang, function(value)
        self.lang = value
        self:save()
        self:show_title()
    end)))
    space(14)
    local stats = self.stats[self.lang] or Engine.new_stats()
    add(self:centered(self:text_line(string.format(t.streak_line, Engine.current_streak(stats, Engine.today())), SERIF_ITALIC, 17)))
    space(14)
    space(6)

    local saved = self:saved_daily()
    local play_label = t.play
    if saved and saved.finished then
        play_label = t.see_result
    elseif saved and #(saved.words or {}) > 0 then
        play_label = t.resume
    end
    local free_saved = self.free_games[self.lang]
    local free_label = (free_saved and not free_saved.finished and #(free_saved.words or {}) > 0) and t.free_resume or t.free_start
    for _, item in ipairs({
        { play_label, function() self:start_daily() end },
        { free_label, function() self:start_free() end },
        { t.stats, function() self:show_stats(function() self:show_title() end) end },
        { t.help, function() self:show_help() end },
        { t.about, function() self:show_about() end },
        { t.exit, function() UIManager:close(self) end },
    }) do
        add(self:centered(self:menu_button(item[1], item[2])))
        space(8)
    end
    self:set_page(CenterContainer:new{ dimen = Geom:new{ w = self.width, h = self.height }, group }, "title", group:getSize().h)
end

-- The day is kept when coming back from the statistics, even if the date changed meanwhile.
function Screen:start_daily(day)
    local data = self:language_data()
    if not data then
        return
    end
    day = day or Engine.today()
    local saved = self:saved_daily(day)
    -- A saved secret word that left the vocabulary has no vector: the game starts over with today's word.
    if saved and not data.lexicon.index[saved.secret] then
        saved = nil
    end
    local secret = saved and saved.secret or Engine.secret_for_day(data.secrets, day)
    self:open_game{ day = day, secret = secret, saved = saved }
end

function Screen:pick_free_word(data)
    local recent = self.free_recent[self.lang] or {}
    local avoided = Engine.free_avoided(data.secrets, Engine.today(), UPCOMING_DAILY_WORDS, recent)
    local secret = Engine.pick_free(data.secrets, avoided, math.random)
    table.insert(recent, secret)
    while #recent > RECENT_FREE_WORDS do
        table.remove(recent, 1)
    end
    self.free_recent[self.lang] = recent
    return secret
end

function Screen:start_free(new_word)
    local data = self:language_data()
    if not data then
        return
    end
    local saved = self.free_games[self.lang]
    if new_word or not saved or saved.finished or not data.lexicon.index[saved.secret] then
        saved = { version = State.GAME_VERSION, secret = self:pick_free_word(data), words = {}, hints = {} }
        self.free_games[self.lang] = saved
        self:save()
    end
    self:open_game{ secret = saved.secret, saved = saved, free_play = true }
end

function Screen:open_game(opts)
    local data = self.data
    self.mode = "game"
    self.free_play = opts.free_play or false
    self.day = opts.day
    self.engine = Engine.new{
        lexicon = data.lexicon,
        ranker = self:ranker_for(data, opts.secret),
        secret = opts.secret,
        day = opts.day,
    }
    if opts.saved then
        -- A save that does not fit the data any more gives a new game with the same word.
        local restored = SavedState.restore(function(saved)
            self.engine:restore(saved)
            return true
        end, opts.saved, logger.warn)
        if not restored then
            self.engine = Engine.new{ lexicon = data.lexicon, ranker = self.engine.ranker, secret = opts.secret, day = opts.day }
        end
    end
    local t = self:strings()
    self.view = GameView:new{
        engine = self.engine,
        strings = t,
        width = self.width,
        height = self.height,
        free_play = self.free_play,
        title = self.free_play and t.free_play or string.format(t.daily_title, opts.day),
        on_action = function(action) self:on_action(action) end,
    }
    self.view.message = self:status_message()
    self:hide_loading()
    -- Every game opens with a full update, even a new word from the result of the last one.
    self.refresh:reset()
    self:set_widget(self.view, "game")
end

function Screen:status_message()
    local engine, t = self.engine, self:strings()
    if engine:is_won() then
        local guesses, hints = engine:counts()
        if hints > 0 then
            return string.format(t.won_hints, guesses, hints)
        end
        return guesses == 1 and t.won_one or string.format(t.won, guesses)
    elseif engine:is_over() then
        return string.format(t.lost, engine.secret)
    end
    local last = engine:last()
    if last then
        return string.format(t.position, last.word, last.rank)
    end
    return t.start_message
end

-- The guess list and the words closest to the secret one are two kinds, so switching between them flashes.
function Screen:refresh_game(kind)
    local mode = self.refresh:mode(kind or "game")
    UIManager:setDirty(self, function()
        return mode, self.dimen
    end)
end

function Screen:on_action(action)
    local view = self.view
    if action == "back" then
        if view.list_mode == "closest" then
            view:set_list_mode("game")
            self:refresh_game("game")
        else
            self:show_title()
        end
    elseif action == "page" then
        self:refresh_game(view.list_mode)
    elseif action == "type" then
        UIManager:setDirty(self, function()
            return "ui", view:input_rect()
        end)
    elseif action == "submit" then
        local text = view:typed_text()
        if text ~= "" then
            view:clear_typed()
            if self:submit_guess(text) then
                return
            end
            self:refresh_game()
        end
    elseif action == "hint" then
        view.focus = nil
        local entry = self.engine:hint()
        local t = self:strings()
        if entry then
            view.message = string.format(t.hint_given, entry.word, entry.rank)
            view.page = 1
            self:after_move()
        else
            view.message = t.no_hint
            self:refresh_game()
        end
    elseif action == "give_up" then
        local ConfirmBox = require("ui/widget/confirmbox")
        UIManager:show(ConfirmBox:new{
            text = self:strings().give_up_confirm,
            ok_text = self:strings().give_up,
            cancel_text = self:strings().cancel,
            ok_callback = function()
                self.engine:give_up()
                self:after_move()
            end,
        })
    elseif action == "closest" then
        local ranker = self.engine.ranker
        local list = { { word = self.engine.secret, rank = 1 } }
        -- The ranker may already hold a longer list from a hint, so only the first ones are taken.
        local nearest = ranker:nearest(CLOSEST_WORDS)
        for i = 1, math.min(CLOSEST_WORDS, #nearest) do
            list[#list + 1] = { word = self.engine.lexicon.words[nearest[i]], rank = i + 1 }
        end
        view.closest = list
        view:set_list_mode("closest")
        self:refresh_game("closest")
    elseif action == "share" then
        local QRMessage = require("ui/widget/qrmessage")
        UIManager:show(QRMessage:new{ text = self.engine:share_text(self:strings(), self:dimensions()) })
    elseif action == "stats" then
        local day = self.day
        self:show_stats(function() self:start_daily(day) end)
    elseif action == "new_word" then
        self:start_free(true)
    end
end

-- Saves the game, records the result when it ends and repaints.
function Screen:after_move()
    local engine = self.engine
    if self.free_play then
        -- A finished game is only counted once, even if this runs again (a second confirmation on a slow screen).
        local was_finished = self.free_games[self.lang] and self.free_games[self.lang].secret == engine.secret and self.free_games[self.lang].finished
        self.free_games[self.lang] = State.record(engine)
        if engine:is_over() and not was_finished then
            local stats = self.free_stats[self.lang] or { played = 0, won = 0 }
            stats.played = stats.played + 1
            stats.won = stats.won + (engine:is_won() and 1 or 0)
            self.free_stats[self.lang] = stats
        end
    else
        local was_finished = self.games[self.lang] and self.games[self.lang].day == engine.day and self.games[self.lang].finished
        self.games[self.lang] = State.record(engine)
        if engine:is_over() and not was_finished then
            local guesses, hints = engine:counts()
            self.stats[self.lang] = Engine.record_result(self.stats[self.lang] or Engine.new_stats(), engine.day, engine:is_won(), guesses, hints)
        end
    end
    self:save()
    if engine:is_over() then
        self.view.message = self:status_message()
        self.view:relayout()
        self.view.page = 1
        -- The end of a game always flashes; the guesses before it count towards the next full update.
        self.refresh:reset()
        self:refresh_game()
    else
        self:refresh_game()
    end
end

-- Called by the game's keyboard. Returns true when the guess counted.
function Screen:submit_guess(text)
    local t = self:strings()
    local ok, detail, entry_or_plural = self.engine:guess(text)
    local view = self.view
    if ok then
        local entry, plural = detail, entry_or_plural
        if plural then
            view.message = string.format(t.plural, plural, entry.word, entry.rank)
        else
            view.message = string.format(t.position, entry.word, entry.rank)
        end
        view.page = 1
        self:after_move()
    elseif detail == "repeated" then
        -- The list turns to the page of the word already sent and marks it.
        view.message = string.format(t.repeated, entry_or_plural.word, entry_or_plural.rank)
        view:focus_entry(entry_or_plural)
        self:refresh_game()
    elseif detail == "unknown" then
        view.message = string.format(t.unknown, Engine.clean(text))
        self:refresh_game()
    end
    return ok
end

function Screen:show_page(title, items, back)
    self.mode = "page"
    self.page_back = back
    local t = self:strings()
    local group = VerticalGroup:new{ align = "center" }
    group[#group + 1] = self:centered(self:text_line(title, SERIF_BOLD, 26), self:scaled(60))
    for _, item in ipairs(items) do
        local body = VerticalGroup:new{ align = "left" }
        local inner_width = self.text_width - 2 * self:scaled(10) - 2 * self:scaled(2)
        if item.title then
            body[#body + 1] = TextBoxWidget:new{ text = item.title, face = Font:getFace(SERIF_BOLD, 18), width = inner_width }
        end
        if item.meta then
            body[#body + 1] = TextBoxWidget:new{ text = item.meta, face = Font:getFace(SERIF_ITALIC, 14), width = inner_width }
        end
        if item.text then
            body[#body + 1] = TextBoxWidget:new{ text = item.text, face = Font:getFace(SERIF, 16), width = inner_width }
        end
        group[#group + 1] = self:centered(FrameContainer:new{
            width = self.text_width,
            padding = self:scaled(10),
            bordersize = self:scaled(2),
            radius = self:scaled(8),
            background = Blitbuffer.COLOR_WHITE,
            body,
        })
        group[#group + 1] = VerticalSpan:new{ width = self:scaled(8) }
    end
    group[#group + 1] = VerticalSpan:new{ width = self:scaled(6) }
    group[#group + 1] = self:centered(self:menu_button(t.back, back))
    self:set_page(group, "page:" .. title)
end

function Screen:show_help()
    self:show_page(self:strings().help, self:strings().help_items, function() self:show_title() end)
end

local function bare_url(url)
    return (url:gsub("^https?://", ""):gsub("/$", ""))
end

-- The dimension count comes from the installed data, so the About screen tells which package is in use.
function Screen:installed_dimensions()
    local _, dimensions = Vectors.read_header(string.format("%s/data/%s/vectors.bin", self.plugin_dir, self.lang))
    return tonumber(dimensions)
end

function Screen:show_about()
    local t = self:strings()
    local version = string.format(t.version, self.meta.version)
    local dimensions = self:installed_dimensions()
    if dimensions then
        version = version .. " · " .. string.format(t.dimensions, dimensions)
    end
    self:show_page(t.about, {
        {
            title = t.name,
            meta = version,
            text = string.format("%s\n%s\n%s", string.format(t.by, self.meta.author), bare_url(self.meta.website), self.meta.copyright),
        },
        { title = t.source_title, text = bare_url(self.meta.homepage) },
        { title = t.license_title, text = t.license },
        { title = t.sources_title, text = t.sources },
        { title = t.warranty_title, text = t.warranty },
    }, function() self:show_title() end)
end

function Screen:show_stats(back)
    local t = self:strings()
    local stats = self.stats[self.lang] or Engine.new_stats()
    local win_rate = stats.played > 0 and math.floor(stats.won * 100 / stats.played + 0.5) or 0
    local lines = {
        string.format("%s: %d", t.played, stats.played),
        string.format("%s: %d%%", t.win_rate, win_rate),
        string.format("%s: %d", t.streak, Engine.current_streak(stats, Engine.today())),
        string.format("%s: %d", t.best_streak, stats.best_streak),
        string.format("%s: %d", t.average, Engine.average_guesses(stats)),
    }
    local free = self.free_stats[self.lang] or { played = 0, won = 0 }
    self:show_page(t.stats, {
        { title = string.format("%s · %s", t.daily, LANGUAGE_NAMES[self.lang]), text = table.concat(lines, "\n") },
        { title = t.free_play, text = string.format("%s: %d\n%s: %d", t.played, free.played, t.wins, free.won) },
    }, back)
end

Screen.onSetRotationMode = Portrait.ignore_rotation

-- The device Back key goes back one screen, and closes the game from the title screen.
function Screen:onBack()
    if self.mode == "game" then
        self:on_action("back")
    elseif self.mode == "page" then
        self.page_back()
    else
        UIManager:close(self)
    end
    return true
end

-- KOReader sends Close to every window before it quits (USB mode on a Kobo, closing the window on a computer).
function Screen:onClose(arg)
    if not (arg and arg.keep_screensaver) then
        UIManager:close(self)
    end
end

-- The sleep screen covered everything, so the next update clears the ghosting.
function Screen:onResume()
    self.refresh:reset()
end

function Screen:onCloseWidget()
    if self[1] then
        self[1]:free()
        self[1] = nil
    end
    self.data = nil
    self.engine = nil
    collectgarbage()
    Portrait.close(self)
    UIManager:setDirty(nil, "full")
end

return Screen
