-- Backups: everything eReaderDS keeps in a zip, and back again (Settings →
-- Back Up & Restore). Used on the backup thread (backupworker.lua), and by
-- the app to measure what a backup would hold.
--
-- What's in the books folder goes in by its place in that folder (so a
-- backup from the stock firmware restores on ROCKNIX or GammaOS, whose books
-- folders are elsewhere): the data folder (.ereaderds: settings, progress,
-- bookmarks, highlights, themes, logins), and for a whole backup the books,
-- fonts, dictionaries and highlight files too. The data files name books by
-- their full paths; in a backup the books folder's path is written as
-- {BOOKS}, and put back as the new one when it's restored.
--
-- Zips are written by hand: stored (books are zips already) or deflated
-- (the data files), with UTF-8 names, and big files copied a piece at a
-- time with a data descriptor, so nothing large is ever held in memory.
local M = {}
local ffi = require("ffi")
local bit = require("bit")

M.MANIFEST = "eReaderDS-backup.txt"
M.TOKEN = "{BOOKS}"

-- Folders and files through the C library (no shell on Android).
for _, decl in ipairs({
    "int mkdir(const char *path, unsigned int mode);",
    "typedef struct bk_DIR bk_DIR;",
    "struct bk_dirent { uint64_t d_ino; int64_t d_off; unsigned short d_reclen; unsigned char d_type; char d_name[256]; };",
    "bk_DIR *opendir(const char *name);",
    "struct bk_dirent *readdir(bk_DIR *dir);",
    "int closedir(bk_DIR *dir);",
}) do pcall(ffi.cdef, decl) end
local C = ffi.C

local function list(dir)
    local out = {}
    local ok, d = pcall(C.opendir, dir)
    if not ok or d == nil then return out end
    while true do
        local e = C.readdir(d)
        if e == nil then break end
        local name = ffi.string(e.d_name)
        if name ~= "." and name ~= ".." then
            local is_dir = e.d_type == 4
            if e.d_type == 0 then                       -- (unknown: try opening it as a folder)
                local sub = C.opendir(dir .. "/" .. name)
                is_dir = sub ~= nil
                if is_dir then C.closedir(sub) end
            end
            out[#out + 1] = { name = name, dir = is_dir }
        end
    end
    C.closedir(d)
    return out
end

function M.mkdir_p(path)
    local p = ""
    for part in path:gmatch("[^/]+") do
        p = p .. "/" .. part
        pcall(C.mkdir, p, tonumber("775", 8))
    end
end

local function size_of(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local n = f:seek("end")
    f:close()
    return n
end

-- Data files worth keeping: text and JSON at the top of the data folder (not
-- crash notes, temporary or hidden files, or the certificates it fetches).
local function data_file(name)
    if name:match("^%.") or name:match("%.tmp$") or name:match("%.part$") or name:match("^crash") then return false end
    return name:match("%.txt$") or name:match("%.json$")
end

-- What a backup holds: { { path, name (in the zip), size, data = true for
-- the data files } }, and the total size. whole: books, fonts and the rest
-- of the books folder too (not hidden folders, Backups, or unfinished files).
function M.collect(root, data_dir, whole)
    local files, total = {}, 0
    for _, e in ipairs(list(data_dir)) do
        if not e.dir and data_file(e.name) then
            local p = data_dir .. "/" .. e.name
            local n = size_of(p) or 0
            files[#files + 1] = { path = p, name = ".ereaderds/" .. e.name, size = n, data = true }
            total = total + n
        end
    end
    if whole then
        local function walk(dir, rel, depth)
            for _, e in ipairs(list(dir)) do
                local r = rel == "" and e.name or (rel .. "/" .. e.name)
                if e.name:match("^%.") or e.name:match("%.part$") then
                    -- hidden (the data folder is above) or unfinished
                elseif e.dir then
                    if depth > 0 and not (rel == "" and e.name == "Backups") then walk(dir .. "/" .. e.name, r, depth - 1) end
                else
                    local n = size_of(dir .. "/" .. e.name) or 0
                    files[#files + 1] = { path = dir .. "/" .. e.name, name = r, size = n }
                    total = total + n
                end
            end
        end
        walk(root, "", 8)
    end
    return files, total
end

---------------------------------------------------------------- CRC32

local z
for _, lib in ipairs({ "z", "libz.so.1", "libz.so" }) do
    local ok, l = pcall(ffi.load, lib)
    if ok then z = l break end
end
if z then pcall(ffi.cdef, "unsigned long crc32(unsigned long crc, const char *buf, unsigned int len);") end
local TABLE
local function crc32(crc, s)
    if z then return tonumber(z.crc32(crc, s, #s)) end
    if not TABLE then
        TABLE = {}
        for i = 0, 255 do
            local c = i
            for _ = 1, 8 do c = bit.band(c, 1) ~= 0 and bit.bxor(0xEDB88320, bit.rshift(c, 1)) or bit.rshift(c, 1) end
            TABLE[i] = c
        end
    end
    local c = bit.bnot(crc)
    for i = 1, #s do c = bit.bxor(TABLE[bit.band(bit.bxor(c, s:byte(i)), 0xFF)], bit.rshift(c, 8)) end
    return bit.bnot(c) % 4294967296
end

---------------------------------------------------------------- writing

local function u16(n) return string.char(n % 256, math.floor(n / 256) % 256) end
local function u32(n) return u16(n % 65536) .. u16(math.floor(n / 65536) % 65536) end

-- The time as MS-DOS has it in a zip.
local function dos_time(t)
    local d = os.date("*t", t)
    return u16(d.hour * 2048 + d.min * 32 + math.floor(d.sec / 2)),
        u16(math.max(0, d.year - 1980) * 512 + d.month * 32 + d.day)
end

local CHUNK = 256 * 1024

-- Write a zip of files (from M.collect) plus the manifest text to out; the
-- data files' text has the books folder's path made into {BOOKS}.
-- progress(done_bytes, total_bytes) now and then. True, or nil and why.
function M.write(out, files, manifest, root, progress)
    local part = out .. ".part"
    local f = io.open(part, "wb")
    if not f then return nil, "couldn't write the backup (is the SD card full?)" end
    local central, offset, done, total = {}, 0, 0, 0
    for _, e in ipairs(files) do total = total + e.size end
    if total > 3.9 * 1024 ^ 3 then f:close(); os.remove(part); return nil, "it's too big for one backup (4 GB)" end
    local tm, dt = dos_time(os.time())
    local ok_all = true
    local function put(s) if not f:write(s) then ok_all = false end end

    local function add_whole(name, data)
        -- A small file, deflated (or stored when that's no smaller).
        local crc = crc32(0, data)
        local method, body = 0, data
        local okc, packed = pcall(love.data.compress, "string", "deflate", data)
        if okc and packed and #packed < #data then method, body = 8, packed end
        local head = "PK\3\4" .. u16(20) .. u16(0x0800) .. u16(method) .. tm .. dt
            .. u32(crc) .. u32(#body) .. u32(#data) .. u16(#name) .. u16(0)
        put(head .. name)
        put(body)
        central[#central + 1] = { name = name, method = method, crc = crc, csize = #body, usize = #data,
            offset = offset, flags = 0x0800 }
        offset = offset + #head + #name + #body
    end

    local function add_stream(name, path, size)
        -- A big one, stored, a piece at a time; its CRC and sizes follow it
        -- (bit 3), so it never has to be read twice or held whole.
        local src = io.open(path, "rb")
        if not src then return end                       -- (gone meanwhile: left out)
        local head = "PK\3\4" .. u16(20) .. u16(0x0808) .. u16(0) .. tm .. dt
            .. u32(0) .. u32(0) .. u32(0) .. u16(#name) .. u16(0)
        put(head .. name)
        local crc, n = 0, 0
        while true do
            local chunk = src:read(CHUNK)
            if not chunk then break end
            crc = crc32(crc, chunk)
            put(chunk)
            n = n + #chunk
            done = done + #chunk
            if progress then progress(done, total) end
        end
        src:close()
        put("PK\7\8" .. u32(crc) .. u32(n) .. u32(n))
        central[#central + 1] = { name = name, method = 0, crc = crc, csize = n, usize = n, offset = offset, flags = 0x0808 }
        offset = offset + #head + #name + n + 16
    end

    add_whole(M.MANIFEST, manifest)
    local prefix = root .. "/"
    for _, e in ipairs(files) do
        if not ok_all then break end
        if e.data then
            local src = io.open(e.path, "rb")
            if src then
                local text = src:read("*a") or ""
                src:close()
                -- (Plain replace: the path's characters aren't patterns.)
                local parts, i = {}, 1
                while true do
                    local a, b = text:find(prefix, i, true)
                    if not a then parts[#parts + 1] = text:sub(i) break end
                    parts[#parts + 1] = text:sub(i, a - 1) .. M.TOKEN .. "/"
                    i = b + 1
                end
                add_whole(e.name, table.concat(parts))
                done = done + e.size
            end
        else
            add_stream(e.name, e.path, e.size)
        end
    end
    -- The directory at the end.
    local cd_start, cd = offset, {}
    for _, c in ipairs(central) do
        cd[#cd + 1] = "PK\1\2" .. u16(20) .. u16(20) .. u16(c.flags) .. u16(c.method) .. tm .. dt
            .. u32(c.crc) .. u32(c.csize) .. u32(c.usize) .. u16(#c.name) .. u16(0) .. u16(0)
            .. u16(0) .. u16(0) .. u32(0) .. u32(c.offset) .. c.name
    end
    local cds = table.concat(cd)
    put(cds)
    put("PK\5\6" .. u16(0) .. u16(0) .. u16(#central) .. u16(#central) .. u32(#cds) .. u32(cd_start) .. u16(0))
    if not f:close() then ok_all = false end
    if not ok_all then os.remove(part); return nil, "couldn't write the backup (is the SD card full?)" end
    os.remove(out)
    if not os.rename(part, out) then os.remove(part); return nil, "couldn't save the backup" end
    return true
end

-- The copies made by themselves before a restore or a reset
-- ("eReaderDS-before-…zip") beyond the newest `keep` are deleted, so they
-- don't pile up. Your own backups are never touched.
-- (spare: the one being restored, which is never deleted.)
function M.prune(dir, keep, spare)
    local found = {}
    for _, e in ipairs(list(dir)) do
        local stamp = not e.dir and e.name:match("^eReaderDS%-before%-%a+%-(%d+%-%d+%-%d+%-%d+)%.zip$")
        if stamp and dir .. "/" .. e.name ~= spare then found[#found + 1] = { name = e.name, stamp = stamp } end
    end
    table.sort(found, function(a, b) return a.stamp > b.stamp end)
    for i = keep + 1, #found do os.remove(dir .. "/" .. found[i].name) end
end

---------------------------------------------------------------- restoring

-- The manifest's fields ("key=value" lines) of a backup, or nil if it isn't one.
function M.manifest(path)
    local ok, zf = pcall(require("zip").open, path)
    if not ok or not zf then return nil end
    local text = zf:read(M.MANIFEST)
    -- (How many books it has a place in: to tell backups apart.)
    local progress = text and zf:read(".ereaderds/progress.txt") or ""
    zf:close()
    if not text then return nil end
    local t = {}
    for k, v in text:gmatch("([%w_]+)=([^\n]*)") do t[k] = v end
    local n = 0
    for _ in progress:gmatch("[^\n]+") do n = n + 1 end
    t.places = n
    return t
end

-- Put a backup's files back: everything but the data files into root by
-- its place there (a book already there at the same size isn't copied
-- again; one that can't be written, such as a name this card can't hold, is
-- skipped and counted), then the data files into data_dir (with {BOOKS} made
-- the books folder, root, again), all at once: each written beside its old
-- one first, so a failure leaves the settings as they were. Data files the
-- backup doesn't have are removed (they become the backup's). This device's
-- own ids (for sync and Calibre) are kept, so a backup from another device
-- doesn't make two of the same. progress(done, total).
-- True and how many books were skipped, or nil and why.
local function safe_name(name)
    if name:match("^/") then return false end
    for part in (name .. "/"):gmatch("([^/]*)/") do
        if part == "" or part == ".." or part == "." then return false end
    end
    return true
end

local function read_file(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

local LOGINS = { ["opds.txt"] = true, ["calibre.json"] = true }

function M.restore(path, root, data_dir, progress)
    local ok, zf = pcall(require("zip").open, path)
    if not ok or not zf then return nil, "couldn't read the backup" end
    if not zf.entries[M.MANIFEST] then zf:close(); return nil, "that isn't an eReaderDS backup" end
    local total, done, skipped = 0, 0, 0
    local data = {}
    for name, e in pairs(zf.entries) do
        if name ~= M.MANIFEST and not name:match("/$") then
            -- (Never outside the books folder: no ".." parts, no absolute names.)
            if not safe_name(name) then zf:close(); return nil, "the backup has a bad file name" end
            total = total + e.usize
            local data_name = name:match("^%.ereaderds/([^/]+)$")
            if data_name and data_file(data_name) then data[#data + 1] = { name = name, data_name = data_name } end
        end
    end
    local function fail(why) zf:close(); return nil, why end
    -- The books (and the rest of the books folder).
    for name, e in pairs(zf.entries) do
        if name ~= M.MANIFEST and not name:match("/$") and not name:match("^%.") then
            local dest, start = root .. "/" .. name, done
            if size_of(dest) ~= e.usize then
                M.mkdir_p(dest:match("^(.*)/"))
                local f = io.open(dest .. ".part", "wb")
                local wrote = f ~= nil
                if f and e.method == 0 then
                    -- Stored: copied a piece at a time.
                    local src = zf.file
                    src:seek("set", e.offset)
                    local hdr = src:read(30)
                    if not hdr or hdr:sub(1, 4) ~= "PK\3\4" then f:close(); os.remove(dest .. ".part"); return fail("the backup is damaged") end
                    src:seek("cur", hdr:byte(27) + hdr:byte(28) * 256 + hdr:byte(29) + hdr:byte(30) * 256)
                    local left = e.csize
                    while left > 0 do
                        local chunk = src:read(math.min(CHUNK, left))
                        if not chunk or #chunk == 0 then wrote = false break end
                        if not f:write(chunk) then wrote = false break end
                        left = left - #chunk
                        done = done + #chunk
                        if progress then progress(done, total) end
                    end
                elseif f then
                    local d = zf:read(name)
                    if not d or not f:write(d) then wrote = false end
                end
                if f and not f:close() then wrote = false end
                if wrote then
                    os.remove(dest)
                    wrote = os.rename(dest .. ".part", dest)
                end
                if not wrote then
                    os.remove(dest .. ".part")
                    skipped = skipped + 1
                    print("[backup] couldn't restore " .. name)
                end
            end
            done = start + e.usize
            if progress then progress(done, total) end
        end
    end
    -- The data files: each written as .tmp first; only when all are there do
    -- they replace the old ones.
    M.mkdir_p(data_dir)
    local mine = {
        -- (Only an id there is: after a reset there's none yet, and the
        -- backup's, from this device, is the one to have.)
        ["settings.txt"] = { "\nkosync_device=[^\n]+", read_file(data_dir .. "/settings.txt") },
        ["calibre.json"] = { '"uuid"%s*:%s*"[^"]+"', read_file(data_dir .. "/calibre.json") },
    }
    local written, from_backup = {}, {}
    local function undo() for _, n in ipairs(written) do os.remove(data_dir .. "/" .. n .. ".tmp") end end
    for _, d in ipairs(data) do
        local text = zf:read(d.name)
        if not text then undo(); return fail("couldn't read " .. d.name .. " from the backup") end
        local parts, i = {}, 1
        while true do
            local a, b = text:find(M.TOKEN .. "/", i, true)
            if not a then parts[#parts + 1] = text:sub(i) break end
            parts[#parts + 1] = text:sub(i, a - 1) .. root .. "/"
            i = b + 1
        end
        text = table.concat(parts)
        local keep = mine[d.data_name]
        local own = keep and keep[2] and ("\n" .. keep[2]):match(keep[1])
        if own then
            local n
            text, n = ("\n" .. text):gsub(keep[1], function() return own end, 1)
            text = text:sub(2)
            if n == 0 and d.data_name == "settings.txt" then text = text:gsub("([^\n])$", "%1\n") .. own:sub(2) .. "\n" end
        end
        local f = io.open(data_dir .. "/" .. d.data_name .. ".tmp", "wb")
        if not f then undo(); return fail("couldn't write the settings") end
        written[#written + 1] = d.data_name
        local w = f:write(text)
        if not (f:close() and w) then undo(); return fail("couldn't write the settings (is the SD card full?)") end
        from_backup[d.data_name] = true
    end
    zf:close()
    for _, e in ipairs(list(data_dir)) do
        -- (Not logins the backup hasn't any of: the question doesn't say they go.)
        if not e.dir and data_file(e.name) and not from_backup[e.name] and not LOGINS[e.name] then
            os.remove(data_dir .. "/" .. e.name)
        end
    end
    for _, n in ipairs(written) do
        local p = data_dir .. "/" .. n
        if not os.rename(p .. ".tmp", p) then
            os.remove(p)
            if not os.rename(p .. ".tmp", p) then return nil, "couldn't save " .. n end
        end
    end
    return true, skipped
end

return M
