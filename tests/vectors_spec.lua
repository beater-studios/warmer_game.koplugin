package.path = "./?.lua;" .. package.path
local ffi = require("ffi")
local Vectors = require("warmer_game/vectors")

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

local function uint32(value)
    return string.char(value % 256, math.floor(value / 256) % 256, math.floor(value / 65536) % 256, math.floor(value / 16777216) % 256)
end

local paths = {}
local function write_file(content)
    local path = os.tmpname()
    paths[#paths + 1] = path
    local file = assert(io.open(path, "wb"))
    file:write(content)
    file:close()
    return path
end

-- Random vectors with a fixed seed; each row gets its own scale, as in the real files.
local function sample(n, d)
    math.randomseed(42)
    local rows, scales = {}, {}
    for i = 1, n * d do
        rows[i] = string.char(math.random(0, 255))
    end
    local inverse = ffi.new("float[?]", n)
    for i = 0, n - 1 do
        inverse[i] = 1 / math.random(100, 127)
    end
    return "SEMV" .. uint32(n) .. uint32(d) .. table.concat(rows) .. ffi.string(inverse, n * 4)
end

test("load and read_header agree on a valid file", function()
    local path = write_file(sample(60, 16))
    local vectors = assert(Vectors.load(path))
    eq(vectors.n, 60)
    eq(vectors.d, 16)
    local n, d = Vectors.read_header(path)
    eq(n, 60)
    eq(d, 16)
end)

test("damaged files are rejected without errors", function()
    local valid = sample(60, 16)
    eq(select(2, Vectors.load("/nonexistent/vectors.bin")), "missing")
    eq(select(2, Vectors.load(write_file(valid:sub(1, -10)))), "format")
    eq(select(2, Vectors.load(write_file("XXXX" .. valid:sub(5)))), "format")
    eq(select(2, Vectors.load(write_file("SEMV" .. uint32(4294967295) .. uint32(300) .. "abc"))), "format")
    eq(select(2, Vectors.load(write_file("SEMV" .. uint32(10) .. uint32(5000) .. "abc"))), "format")
    eq(select(2, Vectors.load(write_file("SEMV"))), "format")
    eq(select(2, Vectors.read_header(write_file("SEMV12"))), "format")
end)

test("the secret word is first and positions match the nearest list", function()
    local vectors = assert(Vectors.load(write_file(sample(60, 16))))
    local ranker = vectors:ranker(7)
    eq(ranker:rank_of(7), 1)
    local nearest = ranker:nearest(10)
    eq(#nearest, 10)
    for position, index in ipairs(nearest) do
        eq(ranker:rank_of(index), position + 1)
    end
end)

test("selection finds the same word as the sorted list at every position", function()
    local vectors = assert(Vectors.load(write_file(sample(200, 24))))
    local ranker = vectors:ranker(13)
    local sorted = vectors:ranker(13):nearest(199)
    for position = 1, 200 do
        local expected = position == 1 and 13 or sorted[position - 1]
        eq(ranker:select(position), expected)
    end
    eq(ranker:index_at(150), sorted[149])
end)

test("ranks computes in one pass the same positions as rank_of", function()
    local vectors = assert(Vectors.load(write_file(sample(200, 24))))
    local ranker = vectors:ranker(13)
    local indices = { 13, 1, 200, 57, 99, 140, 2 }
    local ranks = ranker:ranks(indices)
    for _, index in ipairs(indices) do
        eq(ranks[index], ranker:rank_of(index))
    end
    eq(next(ranker:ranks({})), nil)
end)

test("a secret index outside the vectors raises a clear error", function()
    local vectors = assert(Vectors.load(write_file(sample(60, 16))))
    local ok, err = pcall(vectors.ranker, vectors, nil)
    eq(ok, false)
    eq(tostring(err):find("secret word outside the vectors", 1, true) ~= nil, true)
end)

for _, path in ipairs(paths) do
    os.remove(path)
end
print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
