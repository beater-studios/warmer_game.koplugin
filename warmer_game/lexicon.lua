local Engine = require("warmer_game/engine")

local Lexicon = {}
Lexicon.__index = Lexicon

Lexicon.LANGUAGES = { "pt", "en", "es" }

local function read_lines(path)
    local file = io.open(path, "r")
    if not file then
        return nil
    end
    local lines = {}
    for line in file:lines() do
        if line ~= "" then
            lines[#lines + 1] = line
        end
    end
    file:close()
    return lines
end

-- Words come in frequency order, so the plain lookup keeps the most frequent of words that differ only by accents.
function Lexicon.from_list(words, lang)
    local index, plain_index = {}, {}
    for i, word in ipairs(words) do
        index[word] = i
        local key = Engine.plain(word, lang)
        if not plain_index[key] then
            plain_index[key] = i
        end
    end
    return setmetatable({ lang = lang, words = words, index = index, plain_index = plain_index }, Lexicon)
end

function Lexicon.load(plugin_dir, lang)
    local words = read_lines(string.format("%s/data/%s/words.txt", plugin_dir, lang))
    if not words then
        return nil
    end
    return Lexicon.from_list(words, lang)
end

function Lexicon.load_secrets(plugin_dir, lang)
    return read_lines(string.format("%s/data/%s/secrets.txt", plugin_dir, lang)) or {}
end

-- Accents are ignored and the most frequent word wins, since the game's keyboard cannot type them:
-- of "força" and "forca", only the first one is reachable.
function Lexicon:find(word)
    return self.plain_index[Engine.plain(word, self.lang)]
end

-- A word the keyboard can reach: typing it without accents leads back to it.
function Lexicon:reachable(word)
    return self.words[(Engine.resolve(self, Engine.plain(word, self.lang)))] == word
end

function Lexicon:size()
    return #self.words
end

return Lexicon
