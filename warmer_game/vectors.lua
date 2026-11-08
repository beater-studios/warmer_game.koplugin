local ffi = require("ffi")

local Vectors = {}
Vectors.__index = Vectors

local Ranker = {}
Ranker.__index = Ranker

local HEADER_SIZE = 12
local MAXIMUM_DIMENSIONS = 1024
local CHUNK_SIZE = 1024 * 1024
-- Up to this many closest words, a sorted list is built and kept; beyond it a hint picks one word by selection.
local SORTED_LIMIT = 1000

-- vectors.bin: "SEMV", word count and dimensions as little-endian uint32, one int8 row per word, then one float32 per word.
local function parse_header(header)
    if not header or #header < HEADER_SIZE or header:sub(1, 4) ~= "SEMV" then
        return nil
    end
    local b = { header:byte(5, 12) }
    local n = b[1] + b[2] * 256 + b[3] * 65536 + b[4] * 16777216
    local d = b[5] + b[6] * 256 + b[7] * 65536 + b[8] * 16777216
    if n < 2 or d < 1 or d > MAXIMUM_DIMENSIONS then
        return nil
    end
    return n, d
end

function Vectors.read_header(path)
    local file = io.open(path, "rb")
    if not file then
        return nil, "missing"
    end
    local n, d = parse_header(file:read(HEADER_SIZE))
    file:close()
    if not n then
        return nil, "format"
    end
    return n, d
end

-- Reads straight into the FFI buffer in chunks, so the file is never held twice in memory.
local function read_into(file, buffer, size)
    local offset = 0
    while offset < size do
        local chunk = file:read(math.min(CHUNK_SIZE, size - offset))
        if not chunk or #chunk == 0 then
            return false
        end
        ffi.copy(buffer + offset, chunk, #chunk)
        offset = offset + #chunk
    end
    return true
end

function Vectors.load(path)
    local file = io.open(path, "rb")
    if not file then
        return nil, "missing"
    end
    local n, d = parse_header(file:read(HEADER_SIZE))
    local file_size = file:seek("end")
    -- The size is checked before allocating, so a damaged header cannot ask for a huge buffer.
    if not n or file_size ~= HEADER_SIZE + n * d + n * 4 then
        file:close()
        return nil, "format"
    end
    file:seek("set", HEADER_SIZE)
    local matrix = ffi.new("int8_t[?]", n * d)
    local inverse = ffi.new("float[?]", n)
    local ok = read_into(file, ffi.cast("uint8_t*", matrix), n * d) and read_into(file, ffi.cast("uint8_t*", inverse), n * 4)
    file:close()
    if not ok then
        return nil, "format"
    end
    return setmetatable({ n = n, d = d, matrix = matrix, inverse = inverse }, Vectors)
end

-- Word indices are 1-based, like the vocabulary; rows are 0-based.
function Vectors:ranker(secret_index)
    local n, d = self.n, self.d
    assert(secret_index and secret_index >= 1 and secret_index <= n, "secret word outside the vectors")
    local matrix, inverse = self.matrix, self.inverse
    local scores = ffi.new("float[?]", n)
    local target = matrix + (secret_index - 1) * d
    for row = 0, n - 1 do
        local values = matrix + row * d
        local sum = 0
        for k = 0, d - 1 do
            sum = sum + target[k] * values[k]
        end
        scores[row] = sum * inverse[row]
    end
    -- Quantization could let a near-duplicate tie with the secret word, so the secret is forced to the top.
    scores[secret_index - 1] = math.huge
    return setmetatable({ scores = scores, total = n, secret_index = secret_index, top = {} }, Ranker)
end

function Ranker:rank_of(index)
    if index == self.secret_index then
        return 1
    end
    local scores, n = self.scores, self.total
    local score = scores[index - 1]
    local above = 0
    for row = 0, n - 1 do
        if scores[row] > score then
            above = above + 1
        end
    end
    return above + 1
end

-- Positions of several words in one pass over the scores: each score is placed among the sorted scores of the
-- asked words by binary search, and the counts above each one are summed from the top.
function Ranker:ranks(indices)
    local k = #indices
    local result = {}
    if k == 0 then
        return result
    end
    local scores = self.scores
    local asked = {}
    for i, index in ipairs(indices) do
        asked[i] = { scores[index - 1], index }
    end
    table.sort(asked, function(a, b) return a[1] < b[1] end)
    local values = ffi.new("float[?]", k)
    for i = 1, k do
        values[i - 1] = asked[i][1]
    end
    local bump = ffi.new("int32_t[?]", k + 1)
    for row = 0, self.total - 1 do
        local score = scores[row]
        local low, high = 0, k
        while low < high do
            local middle = math.floor((low + high) / 2)
            if values[middle] < score then low = middle + 1 else high = middle end
        end
        bump[low] = bump[low] + 1
    end
    local above = 0
    for i = k, 1, -1 do
        above = above + bump[i]
        local index = asked[i][2]
        result[index] = index == self.secret_index and 1 or above + 1
    end
    return result
end

-- The k closest words after the secret one, in order, kept for later calls.
function Ranker:nearest(k)
    k = math.min(k, self.total - 1)
    if #self.top >= k then
        return self.top
    end
    local scores, skip = self.scores, self.secret_index - 1
    local heap_score = ffi.new("float[?]", k)
    local heap_row = ffi.new("int32_t[?]", k)
    local size = 0
    local function sift_down(pos)
        while true do
            local left, right, smallest = 2 * pos + 1, 2 * pos + 2, pos
            if left < size and heap_score[left] < heap_score[smallest] then smallest = left end
            if right < size and heap_score[right] < heap_score[smallest] then smallest = right end
            if smallest == pos then return end
            heap_score[pos], heap_score[smallest] = heap_score[smallest], heap_score[pos]
            heap_row[pos], heap_row[smallest] = heap_row[smallest], heap_row[pos]
            pos = smallest
        end
    end
    for row = 0, self.total - 1 do
        if row ~= skip then
            local score = scores[row]
            if size < k then
                heap_score[size], heap_row[size] = score, row
                size = size + 1
                if size == k then
                    for pos = math.floor(k / 2) - 1, 0, -1 do sift_down(pos) end
                end
            elseif score > heap_score[0] then
                heap_score[0], heap_row[0] = score, row
                sift_down(0)
            end
        end
    end
    local list = {}
    for i = 0, size - 1 do
        list[#list + 1] = { heap_score[i], heap_row[i] + 1 }
    end
    table.sort(list, function(a, b) return a[1] > b[1] end)
    local top = {}
    for i, item in ipairs(list) do
        top[i] = item[2]
    end
    self.top = top
    return top
end

-- The row with the k-th highest score (k starting at 1), by quickselect over a copy of the scores.
function Ranker:select(k)
    local n = self.total
    local values = ffi.new("float[?]", n)
    local rows = ffi.new("int32_t[?]", n)
    for i = 0, n - 1 do
        values[i], rows[i] = self.scores[i], i
    end
    local target = k - 1
    local low, high = 0, n - 1
    while low < high do
        local pivot = values[math.floor((low + high) / 2)]
        local i, j = low, high
        while i <= j do
            while values[i] > pivot do i = i + 1 end
            while values[j] < pivot do j = j - 1 end
            if i <= j then
                values[i], values[j] = values[j], values[i]
                rows[i], rows[j] = rows[j], rows[i]
                i, j = i + 1, j - 1
            end
        end
        if target <= j then
            high = j
        elseif target >= i then
            low = i
        else
            break
        end
    end
    return rows[target] + 1
end

function Ranker:index_at(position)
    if position <= 1 then
        return self.secret_index
    end
    if position - 1 <= #self.top or position - 1 <= SORTED_LIMIT then
        return self:nearest(position - 1)[position - 1]
    end
    return self:select(position)
end

return Vectors
