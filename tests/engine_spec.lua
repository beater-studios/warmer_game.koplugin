package.path = "./?.lua;" .. package.path
local Engine = require("warmer_game/engine")
local Lexicon = require("warmer_game/lexicon")

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
    else
        failed = failed + 1
        print("FAILED: " .. name .. "\n  " .. tostring(err))
    end
end
local function eq(actual, expected)
    if actual ~= expected then
        error(string.format("expected %s, got %s", tostring(expected), tostring(actual)), 2)
    end
end

-- The ranking follows the order of the list: the secret word first, then the others as listed.
local function fake_ranker(lexicon, order)
    local rank, at = {}, {}
    for position, word in ipairs(order) do
        local index = assert(lexicon.index[word], word)
        rank[index] = position
        at[position] = index
    end
    return {
        total = #order,
        rank_of = function(_, index) return rank[index] end,
        index_at = function(_, position) return at[position] end,
    }
end

local WORDS = { "casa", "lar", "país", "pais", "café", "chá", "animal", "pão", "papel", "mar", "rio", "lago", "sol", "lua" }
local ORDER = { "casa", "lar", "café", "chá", "pão", "pais", "país", "animal", "papel", "mar", "rio", "lago", "sol", "lua" }

local function game(secret, order)
    local lexicon = Lexicon.from_list(WORDS, "pt")
    return Engine.new{ lexicon = lexicon, ranker = fake_ranker(lexicon, order or ORDER), secret = secret or "casa", day = 310 }
end

test("plain removes accents and keeps ñ in Spanish", function()
    eq(Engine.plain("café", "pt"), "cafe")
    eq(Engine.plain("año", "es"), "año")
    eq(Engine.plain("ação", "pt"), "acao")
end)

test("clean trims and lowers, including accented capitals", function()
    eq(Engine.clean("  CAFÉ "), "café")
    eq(Engine.clean("Ação"), "ação")
end)

test("guess finds words without accents", function()
    local g = game()
    local ok, entry = g:guess("cafe")
    eq(ok, true)
    eq(entry.word, "café")
    eq(entry.rank, 3)
end)

test("without accents the most frequent spelling wins", function()
    local g = game()
    local _, entry = g:guess("pais")
    eq(entry.word, "país")
    local _, other = g:guess("país")
    eq(other, "repeated")
end)

test("plural counts as singular", function()
    local g = game()
    local ok, entry, plural = g:guess("animais")
    eq(ok, true)
    eq(entry.word, "animal")
    eq(plural, "animais")
    ok, entry = g:guess("pães")
    eq(ok, true)
    eq(entry.word, "pão")
    ok, entry = g:guess("papéis")
    eq(ok, true)
    eq(entry.word, "papel")
end)

local function resolved(words, lang, input)
    local index = Engine.resolve(Lexicon.from_list(words, lang), input)
    return index and words[index] or nil
end

test("the keyboard reaches the accented word over a rarer unaccented twin", function()
    eq(resolved({ "força", "forca" }, "pt", "forca"), "força")
    eq(resolved({ "río", "rio" }, "es", "rio"), "río")
    local lexicon = Lexicon.from_list({ "força", "forca" }, "pt")
    eq(lexicon:reachable("força"), true)
    eq(lexicon:reachable("forca"), false)
end)

test("a plural reading wins over a rarer word with the same plain spelling", function()
    eq(resolved({ "león", "leonés" }, "es", "leones"), "león")
    eq(resolved({ "país", "pai", "pais" }, "pt", "pais"), "país")
end)

test("a word found exactly as typed is not read as a plural", function()
    eq(resolved({ "new", "news" }, "en", "news"), "news")
end)

test("Portuguese plurals in -ões, -ães and -ãos work without the tilde", function()
    eq(resolved({ "coração" }, "pt", "coracoes"), "coração")
    eq(resolved({ "pão" }, "pt", "paes"), "pão")
    eq(resolved({ "irmão" }, "pt", "irmaos"), "irmão")
    eq(resolved({ "papel" }, "pt", "papeis"), "papel")
    eq(resolved({ "mês" }, "pt", "meses"), "mês")
end)

test("a word in the vocabulary wins over a plural reading", function()
    eq(resolved({ "mal", "mais" }, "pt", "mais"), "mais")
end)

test("Portuguese plurals follow the singular ending", function()
    eq(resolved({ "lev", "leve" }, "pt", "leves"), "leve")
    eq(resolved({ "flor", "flore" }, "pt", "flores"), "flor")
    eq(resolved({ "luz" }, "pt", "luzes"), "luz")
    eq(resolved({ "jardim" }, "pt", "jardins"), "jardim")
    eq(resolved({ "nó" }, "pt", "nós"), nil)
end)

test("English plurals, and no singular shorter than 3 letters", function()
    eq(resolved({ "dog" }, "en", "dogs"), "dog")
    eq(resolved({ "box" }, "en", "boxes"), "box")
    eq(resolved({ "city" }, "en", "cities"), "city")
    eq(resolved({ "hi" }, "en", "his"), nil)
end)

test("Spanish plurals follow the singular ending", function()
    eq(resolved({ "árbol" }, "es", "árboles"), "árbol")
    eq(resolved({ "casa" }, "es", "casas"), "casa")
    eq(resolved({ "luz" }, "es", "luces"), "luz")
    eq(resolved({ "cas" }, "es", "cases"), "cas")
end)

test("unknown and empty words are rejected and not counted", function()
    local g = game()
    local ok, reason = g:guess("xyz")
    eq(ok, false)
    eq(reason, "unknown")
    ok, reason = g:guess("   ")
    eq(reason, "empty")
    ok, reason = g:guess("casa 2")
    eq(reason, "unknown")
    eq(#g.guesses, 0)
end)

test("a repeated word shows the previous entry and does not count", function()
    local g = game()
    g:guess("mar")
    local ok, reason, entry = g:guess("MAR")
    eq(ok, false)
    eq(reason, "repeated")
    eq(entry.rank, 10)
    eq(#g.guesses, 1)
end)

test("finding the secret word wins and ends the game", function()
    local g = game()
    g:guess("mar")
    local ok, entry = g:guess("casa")
    eq(ok, true)
    eq(entry.rank, 1)
    eq(g:is_won(), true)
    eq(g:is_over(), true)
    local again = g:guess("rio")
    eq(again, false)
end)

test("sorted lists by position, then by order", function()
    local g = game()
    g:guess("mar")
    g:guess("lar")
    g:guess("rio")
    local list = g:sorted()
    eq(list[1].word, "lar")
    eq(list[2].word, "mar")
    eq(list[3].word, "rio")
    eq(g:last().word, "rio")
end)

test("hint without guesses starts at position 300, capped by the vocabulary", function()
    local g = game()
    local entry = g:hint()
    -- 14 words: best becomes 14, target 7.
    eq(entry.rank, 7)
    eq(entry.hint, true)
end)

test("hint goes halfway to the secret and never reveals it", function()
    local g = game()
    g:guess("mar")
    eq(g:hint().rank, 5)
    eq(g:hint().rank, 2)
    local entry, reason = g:hint()
    eq(entry, nil)
    eq(reason, "none")
    eq(g:is_won(), false)
end)

test("hint with the best guess at position 3 gives position 2", function()
    local g = game()
    g:guess("café")
    eq(g:hint().rank, 2)
    eq(select(2, g:hint()), "none")
end)

test("give up ends the game without winning", function()
    local g = game()
    g:guess("mar")
    g:give_up()
    eq(g:is_over(), true)
    eq(g:is_won(), false)
    eq(select(2, g:guess("lar")), "over")
end)

test("counts separate guesses and hints", function()
    local g = game()
    g:guess("mar")
    g:hint()
    g:guess("lago")
    local guesses, hints = g:counts()
    eq(guesses, 2)
    eq(hints, 1)
end)

test("serialize and restore keep words, hints and give up", function()
    local g = game()
    g:guess("mar")
    g:hint()
    g:give_up()
    local saved = g:serialize()
    eq(saved.finished, true)
    local restored = game()
    restored:restore(saved)
    eq(#restored.guesses, 2)
    eq(restored.guesses[2].hint, true)
    eq(restored.gave_up, true)
end)

test("restore recomputes positions with other data", function()
    local g = game()
    g:guess("mar")
    local other = { "casa", "mar", "lar", "café", "chá", "pão", "pais", "país", "animal", "papel", "rio", "lago", "sol", "lua" }
    local restored = game("casa", other)
    restored:restore(g:serialize())
    eq(restored.guesses[1].rank, 2)
end)

test("sorted is cached until the next guess", function()
    local g = game()
    g:guess("mar")
    local first = g:sorted()
    eq(g:sorted(), first)
    g:guess("lar")
    eq(g:sorted() ~= first, true)
    eq(g:sorted()[1].word, "lar")
end)

test("restore skips words missing from the vocabulary", function()
    local restored = game()
    restored:restore({ words = { "mar", "inexistente" }, hints = { false, false } })
    eq(#restored.guesses, 1)
end)

test("closeness is 1 at the secret and falls on a log scale", function()
    eq(Engine.closeness(1, 30000), 1)
    eq(Engine.closeness(30000, 30000), 0)
    local ten, thousand = Engine.closeness(10, 30000), Engine.closeness(1000, 30000)
    assert(ten > 0.7 and ten < 0.8, ten)
    assert(thousand > 0.3 and thousand < 0.4, thousand)
end)

test("day number and daily word", function()
    eq(Engine.day_number({ year = 2026, month = 1, day = 1 }), 0)
    eq(Engine.day_number({ year = 2026, month = 11, day = 7 }), 310)
    eq(Engine.day_number({ year = 2028, month = 3, day = 1 }), 790)
    local secrets = { "a", "b", "c" }
    eq(Engine.secret_for_day(secrets, 0), "a")
    eq(Engine.secret_for_day(secrets, 4), "b")
end)

test("free play avoids upcoming daily words and recent ones", function()
    local secrets = { "a", "b", "c", "d", "e" }
    local avoided = Engine.free_avoided(secrets, 0, 2, { "e" })
    eq(avoided.a and avoided.b and avoided.c and avoided.e, true)
    eq(avoided.d, nil)
    eq(Engine.pick_free(secrets, avoided, function(n) return n end), "d")
    local everything = { a = true, b = true, c = true, d = true, e = true }
    eq(Engine.pick_free(secrets, everything, function() return 1 end), "a")
end)

test("streak counts consecutive days and resets", function()
    local stats = Engine.new_stats()
    Engine.record_result(stats, 10, true, 20, 1)
    Engine.record_result(stats, 11, true, 30, 0)
    eq(stats.streak, 2)
    eq(Engine.average_guesses(stats), 25)
    Engine.record_result(stats, 11, true, 5, 0)
    eq(stats.played, 2)
    Engine.record_result(stats, 13, false, 40, 2)
    eq(stats.streak, 0)
    eq(stats.best_streak, 2)
    eq(Engine.current_streak({ streak = 3, last_day = 10 }, 12), 0)
    eq(Engine.current_streak({ streak = 3, last_day = 10 }, 11), 3)
end)

test("shared result shows counts and ranges without words", function()
    local g = game()
    g:guess("mar")
    g:hint()
    g:guess("lar")
    g:guess("casa")
    local strings = { share_title = "Warmer", share_found = "Found", share_gave_up = "Gave up", share_counts = "Guesses: %d · Hints: %d" }
    local text = g:share_text(strings, 150)
    eq(text:find("Warmer #310 PT · 150", 1, true) ~= nil, true)
    eq(text:find("Guesses: 3 · Hints: 1", 1, true) ~= nil, true)
    eq(text:find("1-100 ■■ 2", 1, true) ~= nil, true)
    eq(text:find("mar", 1, true), nil)
    eq(text:find("casa", 1, true), nil)
end)

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
