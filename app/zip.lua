-- Minimal read-only ZIP reader (stored + deflate), enough for EPUB files.
-- Reads only the central directory up front, then each file on request by
-- seeking, so opening a large book (or previewing its cover) stays fast.
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
    local size = f:seek("end")

    -- End of central directory record: in the last 64 KB (a comment may follow it).
    local tail_len = math.min(size, 65557)
    f:seek("set", size - tail_len)
    local tail = f:read(tail_len) or ""
    local eocd
    for i = #tail - 21, 1, -1 do
        if tail:byte(i) == 0x50 and tail:sub(i, i + 3) == "PK\5\6" then eocd = i; break end
    end
    if not eocd then f:close(); return nil, "not a zip file" end

    local count = u16(tail, eocd + 10)
    local cd_size, cd_off = u32(tail, eocd + 12), u32(tail, eocd + 16)
    if cd_off + cd_size > size then f:close(); return nil, "damaged zip file" end
    f:seek("set", cd_off)
    local cd = f:read(cd_size) or ""
    local entries, lower = {}, {}
    local pos = 1
    for _ = 1, count do
        -- (A directory cut short ends the list rather than failing.)
        if pos + 45 > #cd or cd:sub(pos, pos + 3) ~= "PK\1\2" then break end
        local nlen, xlen, clen = u16(cd, pos + 28), u16(cd, pos + 30), u16(cd, pos + 32)
        local name = cd:sub(pos + 46, pos + 45 + nlen)
        local e = { method = u16(cd, pos + 10), csize = u32(cd, pos + 20),
            usize = u32(cd, pos + 24), offset = u32(cd, pos + 42) }
        entries[name] = e
        lower[name:lower()] = e
        pos = pos + 46 + nlen + xlen + clen
    end
    return setmetatable({ file = f, entries = entries, lower = lower }, M)
end

function M:read(name)
    local e = self.entries[name] or self.lower[name:lower()]
    if not e then return nil, "missing " .. name end
    local f = self.file
    if not f then return nil, "closed" end
    f:seek("set", e.offset)
    local hdr = f:read(30)
    if not hdr or #hdr < 30 or hdr:sub(1, 4) ~= "PK\3\4" then return nil, "bad local header" end
    f:seek("cur", u16(hdr, 27) + u16(hdr, 29))
    local raw = e.csize > 0 and f:read(e.csize) or ""
    if e.method == 0 then return raw end
    if e.method == 8 then
        local ok, out = pcall(inflate, raw)
        if ok then return out end
        return nil, out
    end
    return nil, "unsupported compression " .. e.method
end

function M:close()
    if self.file then self.file:close(); self.file = nil end
end

return M
