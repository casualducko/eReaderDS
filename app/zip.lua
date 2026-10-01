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

-- zlib, to inflate just the start of a compressed entry (a comic page's
-- size is in its first bytes); without it the whole entry is read.
local ffi = require("ffi")
local Z
for _, lib in ipairs({ "z", "libz.so.1", "libz.so" }) do
    local ok, l = pcall(ffi.load, lib)
    if ok then Z = l break end
end
if Z and not pcall(ffi.cdef, [[
    typedef struct zip_z_stream {
        const unsigned char *next_in; unsigned int avail_in; unsigned long total_in;
        unsigned char *next_out; unsigned int avail_out; unsigned long total_out;
        const char *msg; void *state; void *zalloc; void *zfree; void *opaque;
        int data_type; unsigned long adler; unsigned long reserved;
    } zip_z_stream;
    const char *zlibVersion(void);
    int inflateInit2_(zip_z_stream *strm, int windowBits, const char *version, int stream_size);
    int inflate(zip_z_stream *strm, int flush);
    int inflateEnd(zip_z_stream *strm);
]]) then Z = nil end

-- The first n bytes of raw deflate data, or nil.
local function inflate_head(raw, n)
    if not Z then return nil end
    local ok, out = pcall(function()
        local zs = ffi.new("zip_z_stream")
        if Z.inflateInit2_(zs, -15, Z.zlibVersion(), ffi.sizeof("zip_z_stream")) ~= 0 then return nil end
        local buf = ffi.new("unsigned char[?]", n)
        zs.next_in, zs.avail_in = ffi.cast("const unsigned char *", raw), #raw
        zs.next_out, zs.avail_out = buf, n
        local r = Z.inflate(zs, 2)             -- (Z_SYNC_FLUSH: as much as there is)
        local got = n - zs.avail_out
        Z.inflateEnd(zs)
        if r < 0 and r ~= -5 then return nil end      -- (-5: ran out of input, which is expected)
        return ffi.string(buf, got)
    end)
    return ok and out or nil
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
        -- (A damaged entry said to reach past the end of the file is left
        -- out: reading it would ask for gigabytes.)
        if e.offset + e.csize <= size then
            entries[name] = e
            lower[name:lower()] = e
        end
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

-- The first n bytes of an entry, reading little more than that (a comic's
-- page pictures, to read their sizes): a stored one's start, a compressed
-- one's start inflated (the whole entry if zlib isn't there). nil if it
-- isn't there.
function M:read_head(name, n)
    local e = self.entries[name] or self.lower[name:lower()]
    if not e then return nil end
    if e.method ~= 0 and (e.method ~= 8 or not Z) then return self:read(name) end
    local f = self.file
    if not f then return nil end
    f:seek("set", e.offset)
    local hdr = f:read(30)
    if not hdr or #hdr < 30 or hdr:sub(1, 4) ~= "PK\3\4" then return nil end
    f:seek("cur", u16(hdr, 27) + u16(hdr, 29))
    if e.method == 0 then return f:read(math.min(n, e.csize)) or "" end
    -- (Pictures hardly compress, so about as much in as is wanted out.)
    local raw = f:read(math.min(e.csize, n + 1024)) or ""
    local head = inflate_head(raw, math.min(n, e.usize))
    if head then return head end
    return self:read(name)
end

function M:close()
    if self.file then self.file:close(); self.file = nil end
end

return M
