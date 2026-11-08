local Engine = {}
Engine.__index = Engine

Engine.HINT_START = 300
Engine.SHARE_RANGES = { 100, 1000 }

local EPOCH_DAY = 20454 -- 2026-01-01

local ACCENTS = {
    ["á"] = "a", ["à"] = "a", ["â"] = "a", ["ã"] = "a", ["ä"] = "a",
    ["é"] = "e", ["ê"] = "e", ["è"] = "e", ["ë"] = "e",
    ["í"] = "i", ["î"] = "i", ["ì"] = "i", ["ï"] = "i",
    ["ó"] = "o", ["ô"] = "o", ["õ"] = "o", ["ò"] = "o", ["ö"] = "o",
    ["ú"] = "u", ["û"] = "u", ["ù"] = "u", ["ü"] = "u",
    ["ç"] = "c", ["ñ"] = "n",
}
local KEPT_LETTERS = { es = { ["ñ"] = true } }
local LOWER = {
    ["Á"] = "á", ["À"] = "à", ["Â"] = "â", ["Ã"] = "ã", ["Ä"] = "ä",
    ["É"] = "é", ["Ê"] = "ê", ["È"] = "è", ["Ë"] = "ë",
    ["Í"] = "í", ["Î"] = "î", ["Ì"] = "ì", ["Ï"] = "ï",
    ["Ó"] = "ó", ["Ô"] = "ô", ["Õ"] = "õ", ["Ò"] = "ò", ["Ö"] = "ö",
    ["Ú"] = "ú", ["Û"] = "û", ["Ù"] = "ù", ["Ü"] = "ü",
    ["Ç"] = "ç", ["Ñ"] = "ñ",
}
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

function Engine.split(word)
    local letters = {}
    for char in word:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        letters[#letters + 1] = char
    end
    return letters
end

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
    if not word:find("[\128-\255]") then
        return word
    end
    local kept = KEPT_LETTERS[lang] or {}
    local out = {}
    for _, char in ipairs(Engine.split(word)) do
        out[#out + 1] = (not kept[char] and ACCENTS[char]) or char
    end
    return table.concat(out)
end

function Engine.lower(text)
    local out = {}
    for _, char in ipairs(Engine.split(text)) do
        out[#out + 1] = LOWER[char] or char:lower()
    end
    return table.concat(out)
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

-- Civil date to day count, so the result does not depend on the time zone or daylight saving.
function Engine.day_number(date)
    local year = date.month <= 2 and date.year - 1 or date.year
    local era = math.floor(year / 400)
    local year_of_era = year - era * 400
    local shifted_month = date.month > 2 and date.month - 3 or date.month + 9
    local day_of_year = math.floor((153 * shifted_month + 2) / 5) + date.day - 1
    local day_of_era = year_of_era * 365 + math.floor(year_of_era / 4) - math.floor(year_of_era / 100) + day_of_year
    return era * 146097 + day_of_era - 719468 - EPOCH_DAY
end

function Engine.today()
    return Engine.day_number(os.date("*t"))
end

function Engine.secret_for_day(secrets, day)
    return secrets[day % #secrets + 1]
end

-- Free play shares the secret list, so it skips the daily words of the coming days and the ones played recently.
function Engine.free_avoided(secrets, today, upcoming_days, recent)
    local avoided = {}
    for day = today, today + upcoming_days do
        avoided[Engine.secret_for_day(secrets, day)] = true
    end
    for _, word in ipairs(recent) do
        avoided[word] = true
    end
    return avoided
end

function Engine.pick_free(secrets, avoided, random)
    local candidates = {}
    for _, word in ipairs(secrets) do
        if not avoided[word] then
            candidates[#candidates + 1] = word
        end
    end
    if #candidates == 0 then
        candidates = secrets
    end
    return candidates[random(#candidates)]
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
    return { played = 0, won = 0, streak = 0, best_streak = 0, last_day = nil, guesses_total = 0, hints_total = 0 }
end

function Engine.record_result(stats, day, won, guesses, hints)
    if stats.last_day == day then
        return stats
    end
    stats.played = stats.played + 1
    if won then
        stats.won = stats.won + 1
        stats.streak = stats.last_day == day - 1 and stats.streak + 1 or 1
        stats.best_streak = math.max(stats.best_streak, stats.streak)
        stats.guesses_total = stats.guesses_total + guesses
        stats.hints_total = stats.hints_total + hints
    else
        stats.streak = 0
    end
    stats.last_day = day
    return stats
end

-- The saved streak only changes when a game ends, so a missed day has to be checked when showing it.
function Engine.current_streak(stats, today)
    if stats.last_day and today - stats.last_day > 1 then
        return 0
    end
    return stats.streak
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
