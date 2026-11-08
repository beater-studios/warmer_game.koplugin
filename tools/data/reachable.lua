-- Usage: luajit tools/data/reachable.lua <words.txt> <language>
-- Prints the words that the game's keyboard cannot reach (typed without accents they lead to another word),
-- using the game's own lookup, so the data generator never picks such a word as a secret.
local root = arg[0]:match("(.*)/tools/data/[^/]+$") or "."
package.path = root .. "/?.lua;" .. package.path
local Lexicon = require("warmer_game/lexicon")

local words = {}
for line in io.lines(arg[1]) do
    if line ~= "" then
        words[#words + 1] = line
    end
end
local lexicon = Lexicon.from_list(words, arg[2])
for _, word in ipairs(words) do
    if not lexicon:reachable(word) then
        print(word)
    end
end
