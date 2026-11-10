-- Usage: luajit tools/validate_data.lua [vectors dir | --no-vectors]
-- Checks data/<language>/ and, when given, the vectors of another size in <vectors dir>/<language>/vectors.bin.
-- With --no-vectors only the word lists are checked, as in CI, where the vectors are not built. The texts are
-- checked by tools/check_texts.lua.
package.path = "./?.lua;" .. package.path
local Engine = require("warmer_game/engine")
local Lexicon = require("warmer_game/lexicon")
local Vectors = require("warmer_game/vectors")

local MINIMUM_SECRETS = 365
local MINIMUM_VOCABULARY = 25000
local DIMENSIONS = { [100] = true, [150] = true, [300] = true }
local skip_vectors = arg[1] == "--no-vectors"
local vectors_dir = not skip_vectors and arg[1] or nil
local errors = {}
local function fail(text)
    errors[#errors + 1] = text
end

for _, lang in ipairs(Lexicon.LANGUAGES) do
    local lexicon = Lexicon.load(".", lang)
    if not lexicon then
        fail(lang .. ": words.txt missing")
    else
        if lexicon:size() < MINIMUM_VOCABULARY then
            fail(string.format("%s: only %d words in the vocabulary", lang, lexicon:size()))
        end
        for i, word in ipairs(lexicon.words) do
            if lexicon.index[word] ~= i then fail(lang .. ": repeated word: " .. word) end
            if Engine.clean(word) ~= word or word:find("[%s%d%p]") then fail(lang .. ": word not normalized: " .. word) end
        end
        local secrets = Lexicon.load_secrets(".", lang)
        if #secrets < MINIMUM_SECRETS then
            fail(string.format("%s: only %d secret words", lang, #secrets))
        end
        local seen = {}
        for _, word in ipairs(secrets) do
            if seen[word] then fail(lang .. ": repeated secret word: " .. word) end
            seen[word] = true
            if not lexicon.index[word] then fail(lang .. ": secret word not in the vocabulary: " .. word) end
            if lexicon.index[word] and not lexicon:reachable(word) then fail(lang .. ": secret word cannot be typed on the keyboard: " .. word) end
        end
        local path = skip_vectors and nil or vectors_dir and string.format("%s/%s/vectors.bin", vectors_dir, lang) or string.format("data/%s/vectors.bin", lang)
        local vectors, reason
        if path then
            vectors, reason = Vectors.load(path)
        end
        if skip_vectors then
            print(string.format("%s: %d words, %d secret words", lang, lexicon:size(), #secrets))
        elseif not vectors then
            fail(string.format("%s: %s (%s)", lang, path, reason))
        else
            if vectors.n ~= lexicon:size() then
                fail(string.format("%s: %d vectors for %d words", lang, vectors.n, lexicon:size()))
            end
            if not DIMENSIONS[vectors.d] then
                fail(string.format("%s: unexpected dimension count %d", lang, vectors.d))
            end
            local sample = { secrets[1], secrets[#secrets] }
            for _, word in ipairs(sample) do
                local index = lexicon.index[word]
                if index then
                    local ranker = vectors:ranker(index)
                    if ranker:rank_of(index) ~= 1 then fail(lang .. ": secret word not first in its own ranking: " .. word) end
                    local nearest = ranker:nearest(10)
                    if #nearest ~= 10 then fail(lang .. ": nearest words missing for " .. word) end
                    for position, other in ipairs(nearest) do
                        if ranker:rank_of(other) ~= position + 1 then
                            fail(string.format("%s: rank and nearest disagree for %s at %d", lang, word, position))
                            break
                        end
                    end
                end
            end
            print(string.format("%s: %d words, %d secret words, %d dimensions", lang, lexicon:size(), #secrets, vectors.d))
        end
    end
end

for _, text in ipairs(errors) do
    print("ERROR: " .. text)
end
print(string.format("%d errors", #errors))
os.exit(#errors == 0 and 0 or 1)
