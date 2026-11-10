-- Pattern "letters". This file is copied unchanged into every
-- plugin that needs it, as <id>/letters.lua: change the pattern first, then copy it again.
--
-- UTF-8 letters for Portuguese, English and Spanish texts: Lua counts and cuts bytes, and string.upper and
-- string.lower leave accented letters as they are. Expects valid UTF-8 in composed form (NFC); Letters.nfc
-- turns decomposed text into it. On invalid UTF-8, split, count and cut still agree: a stray byte stays with
-- the character before it.
local Letters = {}

local PLAIN = {}
for plain, chars in pairs({
    a = "áàâãä", e = "éèêë", i = "íìîï", o = "óòôõö", u = "úùûü", c = "ç", n = "ñ",
    A = "ÁÀÂÃÄ", E = "ÉÈÊË", I = "ÍÌÎÏ", O = "ÓÒÔÕÖ", U = "ÚÙÛÜ", C = "Ç", N = "Ñ",
}) do
    for char in chars:gmatch("\195[\128-\191]") do
        PLAIN[char] = plain
    end
end

-- The characters of the text, in order.
function Letters.split(text)
    local list = {}
    for char in text:gmatch("[^\128-\191][\128-\191]*") do
        list[#list + 1] = char
    end
    return list
end

-- How many characters the text has (# counts bytes, and an accented letter has two).
function Letters.count(text)
    return select(2, text:gsub("[^\128-\191]", ""))
end

-- The first n characters, never cutting a letter in half.
function Letters.cut(text, n)
    local count = 0
    for pos in text:gmatch("()[^\128-\191]") do
        count = count + 1
        if count > n then
            return text:sub(1, pos - 1)
        end
    end
    return text
end

-- The same Latin-1 letter in the other case ("ñ" and "Ñ"), or nil.
local function other_case(char)
    local byte = char:byte(2)
    if byte >= 128 and byte <= 158 and byte ~= 151 then
        return "\195" .. string.char(byte + 32)
    elseif byte >= 160 and byte <= 190 and byte ~= 183 then
        return "\195" .. string.char(byte - 32)
    end
end

-- Without accents and cedilla, keeping the case: "Ação" is "Acao". kept is an optional set of characters
-- that stay as they are, such as { ["ñ"] = true } for Spanish; a kept letter is kept in both cases.
function Letters.plain(text, kept)
    if not text:find("[\128-\255]") then
        return text
    end
    return (text:gsub("\195[\128-\191]", function(char)
        if kept and (kept[char] or kept[other_case(char) or ""]) then
            return char
        end
        return PLAIN[char] or char
    end))
end

-- Lowercase, accented letters included: "AÇÃO" is "ação". The Latin-1 capitals sit 32 code points below
-- their lowercase letters, except × and ÷.
function Letters.lower(text)
    return (text:lower():gsub("\195([\128-\158])", function(byte)
        if byte ~= "\151" then
            return "\195" .. string.char(byte:byte() + 32)
        end
    end))
end

-- Uppercase, accented letters included: "ação" is "AÇÃO". ÿ has no capital in Latin-1 and stays.
function Letters.upper(text)
    return (text:upper():gsub("\195([\160-\190])", function(byte)
        if byte ~= "\183" then
            return "\195" .. string.char(byte:byte() - 32)
        end
    end))
end

-- Whether the text is valid UTF-8 (no stray, overlong or surrogate sequences).
function Letters.is_valid(text)
    local i, n = 1, #text
    while i <= n do
        local b = text:byte(i)
        local size, low, high = 1, 128, 191
        if b >= 194 and b <= 223 then
            size = 2
        elseif b >= 224 and b <= 239 then
            size = 3
            if b == 224 then low = 160 elseif b == 237 then high = 159 end
        elseif b >= 240 and b <= 244 then
            size = 4
            if b == 240 then low = 144 elseif b == 244 then high = 143 end
        elseif b >= 128 then
            return false
        end
        for k = 1, size - 1 do
            local c = text:byte(i + k)
            if not c or c < (k == 1 and low or 128) or c > (k == 1 and high or 191) then
                return false
            end
        end
        i = i + size
    end
    return true
end

-- The text in composed form (NFC): a letter typed or saved as a base letter plus a combining accent, as in
-- file names made on a Mac, becomes the single accented letter the functions above know. Uses KOReader's
-- utf8proc; without it (plain LuaJIT in the tests) or on invalid UTF-8, the text comes back as it is
-- (utf8proc crashes the process on invalid UTF-8, so it is never given any).
local utf8proc
function Letters.nfc(text)
    if not text:find("[\128-\255]") or not Letters.is_valid(text) then
        return text
    end
    if utf8proc == nil then
        local ok, module = pcall(require, "ffi/utf8proc")
        utf8proc = ok and module or false
    end
    if not utf8proc then
        return text
    end
    local ok, result = pcall(utf8proc.normalize_NFC, text)
    return ok and result or text
end

return Letters
