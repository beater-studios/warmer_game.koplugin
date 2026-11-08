local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local TextWidget = require("ui/widget/textwidget")

local Engine = require("warmer_game/engine")

local Screen = Device.screen

local SERIF = "noto/NotoSerif-Regular.ttf"
local SERIF_BOLD = "noto/NotoSerif-Bold.ttf"
local SERIF_ITALIC = "noto/NotoSerif-Italic.ttf"
local KEY_ROWS = {
    default = { "qwertyuiop", "asdfghjkl", "zxcvbnm" },
    es = { "qwertyuiop", "asdfghjklñ", "zxcvbnm" },
}
local BACKSPACE = "backspace"
local SUBMIT = "submit"
local MAXIMUM_LETTERS = 24

local GameView = InputContainer:extend{
    name = "warmer_game_view",
    engine = nil,
    strings = nil,
    width = nil,
    height = nil,
    title = nil,
    message = nil,
    free_play = false,
    -- "game" lists the guesses; "closest" lists the words closest to the secret one.
    list_mode = "game",
    closest = nil,
    page = 1,
    -- Index of a word sent again, marked in the list until the next guess.
    focus = nil,
    on_action = nil,
}

function GameView:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
    self.typed = {}
    self.ges_events = {
        Tap = { GestureRange:new{ ges = "tap", range = self.dimen } },
    }
    self:compute_layout()
end

function GameView:getSize()
    return self.dimen
end

local function s(value)
    return Screen:scaleBySize(value)
end

function GameView:compute_layout()
    local W, H = self.width, self.height
    local margin = s(10)
    self.margin = margin
    self.header_h = s(66)
    self.title_face = Font:getFace(SERIF_BOLD, 19)
    self.message_face = Font:getFace(SERIF_ITALIC, 16)
    self.button_face = Font:getFace(SERIF_BOLD, 17)
    self.back_face = Font:getFace(SERIF_BOLD, 15)
    self.word_face = Font:getFace(SERIF, 18)
    self.word_bold_face = Font:getFace(SERIF_BOLD, 18)
    self.hint_face = Font:getFace(SERIF_ITALIC, 18)
    self.small_face = Font:getFace(SERIF_ITALIC, 14)
    self.rank_face = Font:getFace(SERIF_BOLD, 16)

    local back_h = s(44)
    self.back_rect = { id = "back", label = "‹ " .. self.strings.back, x = margin, y = math.floor((self.header_h - back_h) / 2), w = s(92), h = back_h }

    self.input_face = Font:getFace(SERIF_BOLD, 22)
    self.button_h = s(46)
    self.row_h = s(38)
    self.pager_h = s(48)

    local rows = KEY_ROWS[self.engine.lang] or KEY_ROWS.default
    local key_gap = s(4)
    local key_w = math.floor((W - 2 * margin - 9 * key_gap) / 10)
    local key_h = s(46)
    self.key_face = Font:getFace(SERIF_BOLD, 19)
    self.action_key_face = Font:getFace(SERIF_BOLD, 14)
    self.keyboard_h = 3 * key_h + 2 * key_gap + s(12)
    local keyboard_y = H - self.keyboard_h
    self.keys = {}
    local y = keyboard_y + s(6)
    for row_index, row in ipairs(rows) do
        local letters = Engine.split(row)
        local total = #letters * key_w + (#letters - 1) * key_gap
        local action_w = 0
        if row_index == 3 then
            action_w = math.floor(key_w * 1.5)
            total = total + 2 * (action_w + key_gap)
        end
        local x = math.floor((W - total) / 2)
        if row_index == 3 then
            self.keys[#self.keys + 1] = { id = SUBMIT, label = self.strings.submit, x = x, y = y, w = action_w, h = key_h, action = true }
            x = x + action_w + key_gap
        end
        for _, letter in ipairs(letters) do
            self.keys[#self.keys + 1] = { id = letter, label = letter == "ñ" and "Ñ" or letter:upper(), x = x, y = y, w = key_w, h = key_h }
            x = x + key_w + key_gap
        end
        if row_index == 3 then
            self.keys[#self.keys + 1] = { id = BACKSPACE, label = "←", x = x, y = y, w = action_w, h = key_h, action = true }
        end
        y = y + key_h + key_gap
    end
    self:relayout()
end

function GameView:keyboard_visible()
    return self.list_mode == "game" and not self.engine:is_over()
end

function GameView:focus_entry(entry)
    self.focus = entry.index
    for position, other in ipairs(self:entries()) do
        if other.index == entry.index then
            self.page = math.floor((position - 1) / self.rows_per_page) + 1
            return
        end
    end
end

-- With the keyboard on screen, the typed word sits under the buttons and the list shrinks above the keyboard.
function GameView:relayout()
    local W, H, margin = self.width, self.height, self.margin
    local keyboard = self:keyboard_visible()
    self.actions_y = self.header_h + s(8)
    local y = self.actions_y + self.button_h + s(8)
    if keyboard then
        self.input_y, self.input_h = y, s(48)
        y = y + self.input_h + s(6)
    end
    self.last_y = y
    self.last_h = keyboard and s(44) or s(50)
    self.counts_y = self.last_y + self.last_h + s(4)
    self.counts_h = s(22)
    self.list_y = self.counts_y + self.counts_h + s(2)
    local bottom = keyboard and (H - self.keyboard_h) or H
    self.pager_y = bottom - self.pager_h - s(6)
    self.rows_per_page = math.max(1, math.floor((self.pager_y - s(4) - self.list_y) / self.row_h))
    local pager_button_w = s(70)
    self.pager_buttons = {
        { id = "previous", label = "‹", x = margin, y = self.pager_y, w = pager_button_w, h = self.pager_h },
        { id = "next", label = "›", x = W - margin - pager_button_w, y = self.pager_y, w = pager_button_w, h = self.pager_h },
    }
    self:layout_actions()
end

-- Rect of the typed word, in screen coordinates, so each key press refreshes only that line.
function GameView:input_rect()
    return Geom:new{ x = self.dimen.x, y = self.dimen.y + self.input_y, w = self.width, h = self.input_h }
end

function GameView:typed_text()
    return table.concat(self.typed)
end

function GameView:clear_typed()
    self.typed = {}
end

function GameView:layout_actions()
    local W, margin, gap = self.width, self.margin, s(8)
    local t = self.strings
    local specs
    if self.list_mode == "closest" then
        specs = {}
    elseif not self.engine:is_over() then
        specs = { { "hint", t.hint, 1 }, { "give_up", t.give_up, 1 } }
    elseif self.free_play then
        specs = { { "new_word", t.new_word, 1 }, { "closest", t.closest, 1 } }
    else
        specs = { { "share", t.share, 1 }, { "closest", t.closest, 1 }, { "stats", t.stats, 1 } }
    end
    local weights = 0
    for _, spec in ipairs(specs) do weights = weights + spec[3] end
    local available = W - 2 * margin - (#specs - 1) * gap
    local x = margin
    self.actions = {}
    for i, spec in ipairs(specs) do
        local w = i == #specs and (W - margin - x) or math.floor(available * spec[3] / weights)
        self.actions[#self.actions + 1] = { id = spec[1], label = spec[2], x = x, y = self.actions_y, w = w, h = self.button_h }
        x = x + w + gap
    end
end

function GameView:set_list_mode(mode)
    self.list_mode = mode
    self.page = 1
    self:relayout()
end

function GameView:entries()
    if self.list_mode == "closest" then
        return self.closest or {}
    end
    return self.engine:sorted()
end

function GameView:page_count()
    return math.max(1, math.ceil(#self:entries() / self.rows_per_page))
end

local function paint_centered(bb, widget, x, y, w, h)
    local size = widget:getSize()
    widget:paintTo(bb, x + math.floor((w - size.w) / 2), y + math.floor((h - size.h) / 2))
end

function GameView:draw_text(bb, text, face, x, y, w, h, align, color)
    local widget = TextWidget:new{ text = text, face = face, fgcolor = color or Blitbuffer.COLOR_BLACK, max_width = w }
    local size = widget:getSize()
    local px = self.dimen.x + x
    if align == "right" then
        px = px + w - size.w
    elseif align ~= "left" then
        px = px + math.floor((w - size.w) / 2)
    end
    widget:paintTo(bb, px, self.dimen.y + y + math.floor((h - size.h) / 2))
    widget:free()
end

function GameView:paint_button(bb, rect, border)
    local x, y = self.dimen.x + rect.x, self.dimen.y + rect.y
    bb:paintRect(x, y, rect.w, rect.h, Blitbuffer.COLOR_WHITE)
    bb:paintBorder(x, y, rect.w, rect.h, border or s(2), Blitbuffer.COLOR_BLACK)
    self:draw_text(bb, rect.label, self.button_face, rect.x + s(4), rect.y, rect.w - s(8), rect.h)
end

function GameView:paint_header(bb)
    local back = self.back_rect
    local x, y = self.dimen.x + back.x, self.dimen.y + back.y
    bb:paintRect(x, y, back.w, back.h, Blitbuffer.COLOR_WHITE)
    bb:paintBorder(x, y, back.w, back.h, s(2), Blitbuffer.COLOR_BLACK)
    self:draw_text(bb, back.label, self.back_face, back.x + s(4), back.y, back.w - s(8), back.h)
    local text_x = back.x + back.w + s(6)
    local text_w = self.width - 2 * text_x
    self:draw_text(bb, self.title or "", self.title_face, text_x, s(8), text_w, s(30))
    if self.message then
        self:draw_text(bb, self.message, self.message_face, s(6), s(38), self.width - s(12), s(26))
    end
    bb:paintRect(self.dimen.x, self.dimen.y + self.header_h - s(1), self.width, s(1), Blitbuffer.COLOR_BLACK)
end

-- The bar is drawn in grayscale: an outline, filled in proportion to how close the word is.
function GameView:paint_bar(bb, x, y, w, h, rank)
    local total = self.engine.ranker.total
    local px, py = self.dimen.x + x, self.dimen.y + y
    bb:paintBorder(px, py, w, h, s(1), Blitbuffer.COLOR_DARK_GRAY)
    local fill = math.floor((w - 2 * s(1)) * Engine.closeness(rank, total) + 0.5)
    if fill > 0 then
        local color = rank == 1 and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_GRAY_5
        bb:paintRect(px + s(1), py + s(1), fill, h - 2 * s(1), color)
    end
end

function GameView:paint_entry(bb, entry, y, h, highlight, focused)
    local margin = self.margin
    local W = self.width
    local rank_w = s(70)
    local bar_w = math.floor(W * 0.32)
    local bar_x = W - margin - s(10) - rank_w - s(10) - bar_w
    local word_x = margin + s(10)
    local word_w = bar_x - s(10) - word_x
    if highlight or focused then
        bb:paintBorder(self.dimen.x + margin, self.dimen.y + y, W - 2 * margin, h, s(3), Blitbuffer.COLOR_BLACK)
    end
    local face = entry.hint and self.hint_face or ((highlight or entry.rank == 1) and self.word_bold_face or self.word_face)
    local label = entry.word
    if focused then
        label = string.format("%s (%s)", entry.word, self.strings.already_mark)
        face = self.word_bold_face
    elseif entry.hint then
        label = string.format("%s (%s)", entry.word, self.strings.hint_mark)
    end
    self:draw_text(bb, label, face, word_x, y, word_w, h, "left")
    local bar_h = math.floor(h * 0.4)
    self:paint_bar(bb, bar_x, y + math.floor((h - bar_h) / 2), bar_w, bar_h, entry.rank)
    self:draw_text(bb, tostring(entry.rank), self.rank_face, W - margin - s(10) - rank_w, y, rank_w, h, "right")
end

function GameView:paint_list(bb)
    local entries = self:entries()
    local pages = self:page_count()
    if self.page > pages then
        self.page = pages
    end
    local first = (self.page - 1) * self.rows_per_page + 1
    local y = self.list_y
    for i = first, math.min(#entries, first + self.rows_per_page - 1) do
        self:paint_entry(bb, entries[i], y, self.row_h, false, self.focus ~= nil and entries[i].index == self.focus)
        bb:paintRect(self.dimen.x + self.margin, self.dimen.y + y + self.row_h - 1, self.width - 2 * self.margin, 1, Blitbuffer.COLOR_LIGHT_GRAY)
        y = y + self.row_h
    end
    if pages > 1 then
        for _, button in ipairs(self.pager_buttons) do
            self:paint_button(bb, button)
        end
        local middle_x = self.pager_buttons[1].x + self.pager_buttons[1].w
        self:draw_text(bb, string.format(self.strings.page, self.page, pages), self.small_face,
            middle_x, self.pager_y, self.pager_buttons[2].x - middle_x, self.pager_h)
    end
end

function GameView:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    bb:paintRect(x, y, self.width, self.height, Blitbuffer.COLOR_WHITE)
    self:paint_header(bb)
    for _, action in ipairs(self.actions) do
        self:paint_button(bb, action)
    end
    if self.list_mode == "closest" then
        self:draw_text(bb, string.format(self.strings.closest_title, self.engine.secret), self.title_face,
            self.margin, self.last_y, self.width - 2 * self.margin, self.last_h)
    else
        local last = self.engine:last()
        if self.engine.gave_up then
            last = { word = self.engine.secret, rank = 1 }
        end
        if last then
            self:paint_entry(bb, last, self.last_y, self.last_h, true)
        end
        local guesses, hints = self.engine:counts()
        self:draw_text(bb, string.format(self.strings.counts, guesses, hints), self.small_face,
            self.margin, self.counts_y, self.width - 2 * self.margin, self.counts_h)
    end
    self:paint_list(bb)
    if self:keyboard_visible() then
        self:paint_input(bb)
        self:paint_keyboard(bb)
    end
end

function GameView:paint_input(bb)
    local margin = self.margin
    local x, y = self.dimen.x + margin, self.dimen.y + self.input_y
    local w = self.width - 2 * margin
    bb:paintRect(x, y, w, self.input_h, Blitbuffer.COLOR_WHITE)
    bb:paintBorder(x, y, w, self.input_h, s(2), Blitbuffer.COLOR_BLACK)
    local typed = self:typed_text()
    if typed == "" then
        self:draw_text(bb, self.strings.type_word, self.message_face, margin + s(12), self.input_y, w - s(24), self.input_h, "left", Blitbuffer.COLOR_DARK_GRAY)
    else
        self:draw_text(bb, typed .. "_", self.input_face, margin + s(12), self.input_y, w - s(24), self.input_h, "left")
    end
end

function GameView:paint_keyboard(bb)
    local keyboard_y = self.height - self.keyboard_h
    bb:paintRect(self.dimen.x, self.dimen.y + keyboard_y, self.width, s(1), Blitbuffer.COLOR_BLACK)
    for _, key in ipairs(self.keys) do
        local x, y = self.dimen.x + key.x, self.dimen.y + key.y
        bb:paintRect(x, y, key.w, key.h, Blitbuffer.COLOR_WHITE)
        bb:paintBorder(x, y, key.w, key.h, s(1), Blitbuffer.COLOR_BLACK)
        self:draw_text(bb, key.label, key.action and self.action_key_face or self.key_face, key.x + s(2), key.y, key.w - s(4), key.h)
    end
end

local function hit(rects, x, y)
    for _, rect in ipairs(rects) do
        if x >= rect.x and x < rect.x + rect.w and y >= rect.y and y < rect.y + rect.h then
            return rect
        end
    end
end

function GameView:onTap(_, ges)
    local x, y = ges.pos.x - self.dimen.x, ges.pos.y - self.dimen.y
    local target = hit({ self.back_rect }, x, y) or hit(self.actions, x, y)
    if not target and self:keyboard_visible() then
        local key = hit(self.keys, x, y)
        if key then
            if key.id == SUBMIT then
                self.focus = nil
                self.on_action("submit")
            elseif key.id == BACKSPACE then
                if #self.typed > 0 then
                    self.typed[#self.typed] = nil
                    self.on_action("type")
                end
            elseif #self.typed < MAXIMUM_LETTERS then
                self.typed[#self.typed + 1] = key.id
                self.on_action("type")
            end
            return true
        end
    end
    if not target and self:page_count() > 1 then
        target = hit(self.pager_buttons, x, y)
    end
    if not target then
        return true
    end
    if target.id == "previous" or target.id == "next" then
        local page = self.page + (target.id == "next" and 1 or -1)
        if page >= 1 and page <= self:page_count() then
            self.page = page
            self.on_action("page")
        end
    else
        self.on_action(target.id)
    end
    return true
end

return GameView
