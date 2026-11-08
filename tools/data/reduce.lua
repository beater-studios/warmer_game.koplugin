-- Usage: luajit reduce.lua <matrix.f32> <build dir> <language>
-- Reads the normalized 300-dimension vectors and writes build/<dims>/<language>/vectors.bin for each size.
local ffi = require("ffi")

local input, build_dir, lang = arg[1], arg[2], arg[3]
local REDUCED = { 100, 150 }

local f = assert(io.open(input, "rb"))
local blob = f:read("*a")
f:close()
local header = ffi.new("uint32_t[2]")
ffi.copy(header, blob, 8)
local n, d = tonumber(header[0]), tonumber(header[1])
local x = ffi.new("float[?]", n * d)
ffi.copy(x, ffi.cast("const char*", blob) + 8, n * d * 4)
blob = nil

local function write_vectors(dims, row_of)
    local dir = string.format("%s/%d/%s", build_dir, dims, lang)
    os.execute(string.format("mkdir -p '%s'", dir))
    local out = assert(io.open(dir .. "/vectors.bin", "wb"))
    out:write("SEMV", ffi.string(ffi.new("uint32_t[2]", n, dims), 8))
    local row = ffi.new("double[?]", dims)
    local quantized = ffi.new("int8_t[?]", dims)
    local inverse = ffi.new("float[?]", n)
    for i = 0, n - 1 do
        row_of(i, row)
        local norm, peak = 0, 0
        for k = 0, dims - 1 do norm = norm + row[k] * row[k] end
        norm = math.sqrt(norm)
        if norm == 0 then norm = 1 end
        for k = 0, dims - 1 do
            row[k] = row[k] / norm
            if math.abs(row[k]) > peak then peak = math.abs(row[k]) end
        end
        if peak == 0 then peak = 1 end
        local scale = 127 / peak
        for k = 0, dims - 1 do
            local value = row[k] * scale
            quantized[k] = value >= 0 and math.floor(value + 0.5) or -math.floor(-value + 0.5)
        end
        inverse[i] = 1 / scale
        out:write(ffi.string(quantized, dims))
    end
    out:write(ffi.string(inverse, n * 4))
    out:close()
end

write_vectors(d, function(i, row)
    for k = 0, d - 1 do row[k] = x[i * d + k] end
end)

local mean = ffi.new("double[?]", d)
for i = 0, n - 1 do
    for k = 0, d - 1 do mean[k] = mean[k] + x[i * d + k] end
end
for k = 0, d - 1 do mean[k] = mean[k] / n end

local a = ffi.new("double[?]", d * d)
local centered = ffi.new("double[?]", d)
for i = 0, n - 1 do
    for k = 0, d - 1 do centered[k] = x[i * d + k] - mean[k] end
    for p = 0, d - 1 do
        local cp, base = centered[p], p * d
        for q = p, d - 1 do a[base + q] = a[base + q] + cp * centered[q] end
    end
end
for p = 0, d - 1 do
    for q = p, d - 1 do
        a[p * d + q] = a[p * d + q] / n
        a[q * d + p] = a[p * d + q]
    end
end

-- Cyclic Jacobi: the eigenvectors of the covariance end up in the columns of v.
local v = ffi.new("double[?]", d * d)
for p = 0, d - 1 do v[p * d + p] = 1 end
for _ = 1, 30 do
    local off = 0
    for p = 0, d - 1 do
        for q = p + 1, d - 1 do off = off + a[p * d + q] ^ 2 end
    end
    if off < 1e-22 then break end
    for p = 0, d - 2 do
        for q = p + 1, d - 1 do
            local apq = a[p * d + q]
            if math.abs(apq) > 1e-30 then
                local theta = (a[q * d + q] - a[p * d + p]) / (2 * apq)
                local t = (theta >= 0 and 1 or -1) / (math.abs(theta) + math.sqrt(theta * theta + 1))
                local c = 1 / math.sqrt(t * t + 1)
                local s = t * c
                for k = 0, d - 1 do
                    local akp, akq = a[k * d + p], a[k * d + q]
                    a[k * d + p], a[k * d + q] = c * akp - s * akq, s * akp + c * akq
                end
                for k = 0, d - 1 do
                    local apk, aqk = a[p * d + k], a[q * d + k]
                    a[p * d + k], a[q * d + k] = c * apk - s * aqk, s * apk + c * aqk
                end
                for k = 0, d - 1 do
                    local vkp, vkq = v[k * d + p], v[k * d + q]
                    v[k * d + p], v[k * d + q] = c * vkp - s * vkq, s * vkp + c * vkq
                end
            end
        end
    end
end

local order = {}
for k = 0, d - 1 do order[#order + 1] = k end
table.sort(order, function(i, j) return a[i * d + i] > a[j * d + j] end)

for _, dims in ipairs(REDUCED) do
    write_vectors(dims, function(i, row)
        for k = 0, d - 1 do centered[k] = x[i * d + k] - mean[k] end
        for r = 0, dims - 1 do
            local col, s = order[r + 1], 0
            for j = 0, d - 1 do s = s + centered[j] * v[j * d + col] end
            row[r] = s
        end
    end)
end
