-- Minimal read-only ZIP reader (stored + deflate), enough for EPUB files.
local M = {}
M.__index = M

local function u16(s, i) local a, b = s:byte(i, i + 1); return a + b * 256 end
local function u32(s, i)
    local a, b, c, d = s:byte(i, i + 3)
    return a + b * 256 + c * 65536 + d * 16777216
end

local function inflate(data)
    if love and love.data then
        return love.data.decompress("string", "deflate", data)
    end
    error("no inflate available")
end

function M.open(path)
    local f, err = io.open(path, "rb")
    if not f then return nil, err end
    local data = f:read("*a")
    f:close()

    -- End of central directory record: scan backwards (comment may follow it).
    local eocd
    for i = #data - 21, math.max(1, #data - 65557), -1 do
        if data:byte(i) == 0x50 and data:sub(i, i + 3) == "PK\5\6" then eocd = i; break end
    end
    if not eocd then return nil, "not a zip file" end

    local count = u16(data, eocd + 10)
    local pos = u32(data, eocd + 16) + 1
    local entries, lower = {}, {}
    for _ = 1, count do
        if data:sub(pos, pos + 3) ~= "PK\1\2" then break end
        local method = u16(data, pos + 10)
        local csize = u32(data, pos + 20)
        local usize = u32(data, pos + 24)
        local nlen, xlen, clen = u16(data, pos + 28), u16(data, pos + 30), u16(data, pos + 32)
        local offset = u32(data, pos + 42)
        local name = data:sub(pos + 46, pos + 45 + nlen)
        local e = { name = name, method = method, csize = csize, usize = usize, offset = offset }
        entries[name] = e
        lower[name:lower()] = e
        pos = pos + 46 + nlen + xlen + clen
    end
    return setmetatable({ data = data, entries = entries, lower = lower }, M)
end

function M:has(name)
    return self.entries[name] ~= nil or self.lower[name:lower()] ~= nil
end

function M:read(name)
    local e = self.entries[name] or self.lower[name:lower()]
    if not e then return nil, "missing " .. name end
    local d = self.data
    local p = e.offset + 1
    if d:sub(p, p + 3) ~= "PK\3\4" then return nil, "bad local header" end
    local start = p + 30 + u16(d, p + 26) + u16(d, p + 28)
    local raw = d:sub(start, start + e.csize - 1)
    if e.method == 0 then return raw end
    if e.method == 8 then
        local ok, out = pcall(inflate, raw)
        if ok then return out end
        return nil, out
    end
    return nil, "unsupported compression " .. e.method
end

return M
