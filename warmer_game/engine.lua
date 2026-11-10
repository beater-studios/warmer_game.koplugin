local Calendar = require("warmer_game/calendar")
local Letters = require("warmer_game/letters")

local Engine = {}
Engine.__index = Engine

Engine.HINT_START = 300
Engine.SHARE_RANGES = { 100, 1000 }

local KEPT_LETTERS = { es = { ["ñ"] = true } }
-- Same rules as tools/data/build_data.py, so a plural typed by the player finds the singular kept in the vocabulary.
-- "after" limits a rule to singulars with that ending, as in each grammar: flores from flor, but leves from leve.
local VOWELS = { a = true, e = true, i = true, o = true, u = true, ["á"] = true, ["é"] = true, ["í"] = true, ["ó"] = true,
    ["ú"] = true, ["â"] = true, ["ê"] = true, ["ô"] = true, ["ã"] = true, ["õ"] = true }
local PLURALS = {
    pt = {
        { "ões", "ão" }, { "ães", "ão" }, { "ãos", "ão" },
        -- The game's keyboard has no accents, so the same plurals are also read without the tilde.
        { "oes", "ao" }, { "aes", "ao" }, { "aos", "ao" },
        { "ns", "m" }, { "is", "l" },
        { "es", "", after = { "r", "z", "s" } }, { "s", "", after = "vowel" },
    },
    en = { { "ies", "y" }, { "es", "", after = { "s", "x", "z", "ch", "sh", "o" } }, { "s", "" } },
    es = { { "ces", "z" }, { "es", "", after = "consonant" }, { "s", "", after = "vowel" } },
}
local MINIMUM_SINGULAR_LETTERS = 3

Engine.split = Letters.split
Engine.lower = Letters.lower
Engine.upper = Letters.upper

local function ends_as(singular, after)
    if not after then
        return true
    end
    local letters = Engine.split(singular)
    local last = letters[#letters]
    if after == "vowel" then
        return VOWELS[last] == true
    elseif after == "consonant" then
        return last ~= nil and not VOWELS[last]
    end
    for _, ending in ipairs(after) do
        if singular:sub(-#ending) == ending then
            return true
        end
    end
    return false
end

-- The singulars a word could come from, in rule order. "mais" still yields "mal": the generator keeps such
-- words in the vocabulary (tools/data/not_plural_pt.txt), so the exact match is found first.
function Engine.singulars(word, lang)
    local found = {}
    for _, rule in ipairs(PLURALS[lang] or {}) do
        local suffix, ending = rule[1], rule[2]
        if #word > #suffix and word:sub(-#suffix) == suffix then
            local singular = word:sub(1, -#suffix - 1) .. ending
            if #Engine.split(singular) >= MINIMUM_SINGULAR_LETTERS and ends_as(singular, rule.after) then
                found[#found + 1] = singular
            end
        end
    end
    return found
end

function Engine.plain(word, lang)
    return Letters.plain(word, KEPT_LETTERS[lang])
end

function Engine.clean(input)
    return Engine.lower((input or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Returns the vocabulary index for what the player typed, and the typed word when it was read as a plural.
-- The keyboard has no accents, so every reading of the word (as typed, or as the singular of a plural) is looked
-- up without accents and the most frequent match wins: "forca" is "força", "leones" is "león", "pais" is "país".
function Engine.resolve(lexicon, input)
    local word = Engine.clean(input)
    if word == "" then
        return nil, "empty"
    end
    if word:find("[%s%d%p]") then
        return nil, "unknown"
    end
    -- A word found exactly as typed, with no more frequent accented twin, is never read as a plural ("news").
    local exact = lexicon.index[word]
    if exact and (word:find("[\128-\255]") or lexicon:find(word) == exact) then
        return exact
    end
    local best, plural = lexicon:find(word), nil
    for _, singular in ipairs(Engine.singulars(word, lexicon.lang)) do
        local index = lexicon:find(singular)
        if index and (not best or index < best) then
            best, plural = index, word
        end
    end
    if best then
        return best, plural
    end
    return nil, "unknown"
end

Engine.day_number = Calendar.day_number
Engine.secret_for_day = Calendar.of_day
Engine.current_streak = Calendar.current_streak

-- Read at call time, so tests and screenshots can fix the day by replacing Engine.today.
function Engine.today()
    return Calendar.today()
end

-- Free play shares the secret list, so it skips the daily words of the coming days and the ones played recently.
function Engine.free_avoided(secrets, today, upcoming_days, recent)
    return Calendar.avoided(secrets, today, upcoming_days, recent)
end

function Engine.pick_free(secrets, avoided, random)
    return Calendar.pick_free(secrets, avoided, random)
end

-- 1 for the secret word, 0 for the last word of the vocabulary, on a log scale to spread the close positions.
function Engine.closeness(rank, total)
    if rank <= 1 then
        return 1
    end
    local value = 1 - math.log(rank) / math.log(math.max(total, 2))
    return math.max(0, math.min(1, value))
end

function Engine.new(opts)
    local self = setmetatable({
        lang = opts.lexicon.lang,
        day = opts.day,
        secret = opts.secret,
        lexicon = opts.lexicon,
        ranker = opts.ranker,
        guesses = {},
        by_index = {},
        gave_up = false,
    }, Engine)
    self.secret_index = assert(opts.lexicon.index[opts.secret], "secret word not in the vocabulary")
    return self
end

function Engine:add(index, hint, rank)
    self.sorted_cache = nil
    local entry = {
        word = self.lexicon.words[index],
        index = index,
        rank = rank or self.ranker:rank_of(index),
        hint = hint or false,
        order = #self.guesses + 1,
    }
    self.guesses[#self.guesses + 1] = entry
    self.by_index[index] = entry
    return entry
end

function Engine:is_won()
    return self.by_index[self.secret_index] ~= nil
end

function Engine:is_over()
    return self.gave_up or self:is_won()
end

function Engine:guess(input)
    if self:is_over() then
        return false, "over"
    end
    local index, detail = Engine.resolve(self.lexicon, input)
    if not index then
        return false, detail
    end
    local existing = self.by_index[index]
    if existing then
        return false, "repeated", existing
    end
    return true, self:add(index, false), detail
end

function Engine:best_rank()
    local best
    for _, entry in ipairs(self.guesses) do
        if not best or entry.rank < best then
            best = entry.rank
        end
    end
    return best
end

-- Halfway between the best guess and the secret word, never the secret word itself. Every position closer
-- than the best guess is still unknown, so the target position is always free.
function Engine:hint()
    if self:is_over() then
        return nil, "over"
    end
    local best = math.min(self:best_rank() or 2 * Engine.HINT_START, self.ranker.total)
    if best <= 2 then
        return nil, "none"
    end
    return self:add(self.ranker:index_at(math.max(2, math.floor(best / 2))), true)
end

function Engine:give_up()
    if not self:is_over() then
        self.gave_up = true
    end
end

function Engine:counts()
    local guesses, hints = 0, 0
    for _, entry in ipairs(self.guesses) do
        if entry.hint then
            hints = hints + 1
        else
            guesses = guesses + 1
        end
    end
    return guesses, hints
end

-- Kept until the next guess, since the screen asks for it on every paint and tap.
function Engine:sorted()
    if self.sorted_cache then
        return self.sorted_cache
    end
    local list = {}
    for i, entry in ipairs(self.guesses) do
        list[i] = entry
    end
    table.sort(list, function(a, b)
        if a.rank ~= b.rank then
            return a.rank < b.rank
        end
        return a.order < b.order
    end)
    self.sorted_cache = list
    return list
end

function Engine:last()
    return self.guesses[#self.guesses]
end

-- Words are saved instead of positions, so a game reopened with other data recomputes them.
function Engine:serialize()
    local words, hints = {}, {}
    for i, entry in ipairs(self.guesses) do
        words[i] = entry.word
        hints[i] = entry.hint
    end
    return { day = self.day, secret = self.secret, words = words, hints = hints, gave_up = self.gave_up, finished = self:is_over() }
end

-- The positions of all saved words are computed in one pass when the ranker can, instead of one scan per word.
function Engine:restore(saved)
    local indices, hints = {}, {}
    local seen = {}
    for i, word in ipairs(saved.words or {}) do
        local index = self.lexicon.index[word]
        if index and not seen[index] then
            seen[index] = true
            indices[#indices + 1] = index
            hints[#hints + 1] = saved.hints and saved.hints[i] or false
        end
    end
    local ranks = self.ranker.ranks and self.ranker:ranks(indices) or {}
    for i, index in ipairs(indices) do
        self:add(index, hints[i], ranks[index])
    end
    self.gave_up = saved.gave_up or false
end

function Engine.new_stats()
    local stats = Calendar.new_stats()
    stats.guesses_total, stats.hints_total = 0, 0
    return stats
end

-- Each day is recorded once, and the guess and hint totals only grow when it was.
function Engine.record_result(stats, day, won, guesses, hints)
    if Calendar.record(stats, day, won) and won then
        stats.guesses_total = stats.guesses_total + guesses
        stats.hints_total = stats.hints_total + hints
    end
    return stats
end

function Engine.average_guesses(stats)
    if stats.won == 0 then
        return 0
    end
    return math.floor(stats.guesses_total / stats.won + 0.5)
end

-- The shared result tells how close the guesses got without revealing any word.
function Engine:share_text(strings, dimensions)
    local guesses, hints = self:counts()
    local lines = {
        string.format("%s #%d %s · %d", strings.share_title, self.day or 0, self.lang:upper(), dimensions),
        self:is_won() and strings.share_found or strings.share_gave_up,
        string.format(strings.share_counts, guesses, hints),
    }
    local low, high = Engine.SHARE_RANGES[1], Engine.SHARE_RANGES[2]
    local counts = { 0, 0, 0 }
    for _, entry in ipairs(self.guesses) do
        if entry.index ~= self.secret_index and not entry.hint then
            local bucket = entry.rank <= low and 1 or (entry.rank <= high and 2 or 3)
            counts[bucket] = counts[bucket] + 1
        end
    end
    local marks = { "■", "▣", "□" }
    local labels = { string.format("1-%d", low), string.format("%d-%d", low + 1, high), string.format("%d+", high + 1) }
    for i = 1, 3 do
        local parts = { labels[i] }
        if counts[i] > 0 then
            parts[#parts + 1] = string.rep(marks[i], math.min(counts[i], 15))
        end
        parts[#parts + 1] = tostring(counts[i])
        lines[#lines + 1] = table.concat(parts, " ")
    end
    return table.concat(lines, "\n")
end

return Engine
