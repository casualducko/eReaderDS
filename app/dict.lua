-- Dictionaries in StarDict format (the bundled WordNet, plus any in
-- Ebook/Dictionaries). Each dictionary is .ifo (info), .idx (sorted words),
-- optional .syn (other forms) and .dict or .dict.dz (dictzip: gzip in
-- independently compressed chunks, so an entry can be read without
-- unpacking the whole file). Indexes load on first use.
local M = {}

local function read_file(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local d = f:read("*a")
    f:close()
    return d
end

local function u32(s, i)
    local a, b, c, d = s:byte(i, i + 3)
    return ((a * 256 + b) * 256 + c) * 256 + d
end

---------------------------------------------------------------- word lists

-- A sorted word list (.idx or .syn): the raw file plus the start of each
-- word, found once. `tail` is the bytes after each word's terminating zero.
local function word_list(data, tail)
    local starts, ends = {}, {}
    local pos, n = 1, 0
    while pos <= #data do
        local z = data:find("\0", pos, true)
        if not z then break end
        n = n + 1
        starts[n], ends[n] = pos, z - 1
        pos = z + 1 + tail
    end
    return { data = data, starts = starts, ends = ends, n = n, tail = tail }
end

local function word_at(list, i) return list.data:sub(list.starts[i], list.ends[i]) end

-- All entries whose word matches `word` ignoring ASCII case (StarDict sorts
-- that way), exact-case matches first.
local function find_all(list, word)
    local key = word:lower()
    local lo, hi = 1, list.n
    while lo < hi do                              -- first entry >= key
        local mid = math.floor((lo + hi) / 2)
        if word_at(list, mid):lower() < key then lo = mid + 1 else hi = mid end
    end
    local out = {}
    local i = lo
    while i <= list.n and word_at(list, i):lower() == key do
        if word_at(list, i) == word then table.insert(out, 1, i) else out[#out + 1] = i end
        i = i + 1
    end
    return out
end

---------------------------------------------------------------- dictzip

local function open_dictzip(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local head = f:read(12)
    if not head or head:byte(1) ~= 0x1f or head:byte(2) ~= 0x8b then f:close(); return nil end
    local flg = head:byte(4)
    local xlen = head:byte(11) + head:byte(12) * 256
    local extra = (flg % 8 >= 4) and f:read(xlen) or ""
    -- The "RA" subfield: version, chunk length, chunk count, compressed sizes.
    local ra
    local p = 1
    while p + 3 <= #extra do
        local id, len = extra:sub(p, p + 1), extra:byte(p + 2) + extra:byte(p + 3) * 256
        if id == "RA" then ra = extra:sub(p + 4, p + 3 + len) end
        p = p + 4 + len
    end
    if not ra then f:close(); return nil end
    local function le16(i) return ra:byte(i) + ra:byte(i + 1) * 256 end
    local chlen, chcnt = le16(3), le16(5)
    if flg % 16 >= 8 then repeat local c = f:read(1) until not c or c == "\0" end     -- file name
    if flg % 32 >= 16 then repeat local c = f:read(1) until not c or c == "\0" end    -- comment
    if flg % 4 >= 2 then f:read(2) end                                                -- header crc
    local offsets, pos = {}, f:seek()
    for k = 1, chcnt do
        offsets[k] = pos
        pos = pos + le16(7 + (k - 1) * 2)
    end
    offsets[chcnt + 1] = pos
    return { f = f, chlen = chlen, chcnt = chcnt, offsets = offsets, cache = {}, order = {} }
end

local function dz_chunk(dz, k)
    local c = dz.cache[k]
    if c then return c end
    dz.f:seek("set", dz.offsets[k])
    local raw = dz.f:read(dz.offsets[k + 1] - dz.offsets[k]) or ""
    -- Chunks end with a full flush, not the end of a stream: add an empty
    -- final block so the chunk inflates on its own.
    if k < dz.chcnt then raw = raw .. "\3\0" end
    local ok, out = pcall(love.data.decompress, "string", "deflate", raw)
    c = ok and out or ""
    dz.cache[k] = c
    dz.order[#dz.order + 1] = k
    if #dz.order > 8 then dz.cache[table.remove(dz.order, 1)] = nil end
    return c
end

local function dz_read(dz, off, size)
    local first = math.floor(off / dz.chlen) + 1
    local last = math.floor((off + size - 1) / dz.chlen) + 1
    local parts = {}
    for k = first, math.min(last, dz.chcnt) do parts[#parts + 1] = dz_chunk(dz, k) end
    local s = table.concat(parts)
    local start = off - (first - 1) * dz.chlen
    return s:sub(start + 1, start + size)
end

---------------------------------------------------------------- dictionaries

local function load_dict(ifo_path)
    local ifo = read_file(ifo_path)
    if not ifo or not ifo:find("^StarDict's dict ifo file") then return nil end
    local info = {}
    for k, v in ifo:gmatch("([%w_]+)=([^\r\n]*)") do info[k] = v end
    local base = ifo_path:gsub("%.ifo$", "")
    local d = { name = info.bookname or base:match("[^/]+$"), base = base,
        type = info.sametypesequence, loaded = false,
        words = info.wordcount, idxsize = info.idxfilesize }
    return d
end

-- Read the index (and synonyms, and open the definitions) on first lookup.
local function ensure(d)
    if d.loaded then return d.ok end
    d.loaded = true
    local idx = read_file(d.base .. ".idx")
    if not idx then
        -- Some dictionaries ship a gzipped index.
        local gz = read_file(d.base .. ".idx.gz")
        if gz then
            local ok, out = pcall(love.data.decompress, "string", "gzip", gz)
            idx = ok and out or nil
        end
    end
    if not idx then return false end
    d.idx = word_list(idx, 8)
    local syn = read_file(d.base .. ".syn")
    if syn then d.syn = word_list(syn, 4) end
    d.dz = open_dictzip(d.base .. ".dict.dz")
    if not d.dz then
        d.file = io.open(d.base .. ".dict", "rb")
        if not d.file then return false end
    end
    d.ok = true
    return true
end

local function entry_text(d, i)
    local after = d.idx.ends[i] + 2
    local off, size = u32(d.idx.data, after), u32(d.idx.data, after + 4)
    local raw
    if d.dz then raw = dz_read(d.dz, off, size)
    else d.file:seek("set", off); raw = d.file:read(size) or "" end
    local t = d.type
    if not t or t == "" then
        -- Each field starts with its type letter; take the first one.
        t = raw:sub(1, 1)
        raw = raw:sub(2)
        if t:match("%l") then raw = raw:match("^[^%z]*") else raw = raw:sub(5, 4 + u32(raw, 1)) end
    else
        t = t:sub(1, 1)
    end
    return raw, t
end

M.list = nil

-- Find dictionaries: the bundled ones, then Ebook/Dictionaries (any depth up
-- to 3 folders). Yours come first.
function M.scan(dirs)
    local list = {}
    local seen = {}
    for _, dir in ipairs(dirs) do
        local p = io.popen('find -L "' .. dir .. '" -maxdepth 3 -name "*.ifo" 2>/dev/null | sort')
        if p then
            for path in p:lines() do
                if not seen[path] then
                    seen[path] = true
                    local d = load_dict(path)
                    -- The same dictionary copied twice (e.g. a folder inside
                    -- a folder) only counts once.
                    local key = d and (d.name .. "|" .. (d.words or "") .. "|" .. (d.idxsize or ""))
                    if d and not seen[key] then
                        seen[key] = true
                        list[#list + 1] = d
                    end
                end
            end
            p:close()
        end
    end
    M.list = list
    return list
end

---------------------------------------------------------------- lookup

-- Base forms to try for an English word (WordNet's "morphy" rules, plus
-- doubled consonants: "running" -> "run").
local SUFFIXES = {
    { "ies", "y" }, { "ses", "s" }, { "xes", "x" }, { "zes", "z" }, { "ches", "ch" }, { "shes", "sh" },
    { "men", "man" }, { "es", "e" }, { "es", "" }, { "s", "" },
    { "ied", "y" }, { "ed", "e" }, { "ed", "" }, { "ying", "ie" }, { "ing", "e" }, { "ing", "" },
    { "iest", "y" }, { "ier", "y" }, { "est", "e" }, { "est", "" }, { "er", "e" }, { "er", "" },
    { "ly", "" }, { "ily", "y" },
}

local function candidates(word)
    local out, seen = {}, {}
    local function add(w) if w ~= "" and not seen[w] then seen[w] = true; out[#out + 1] = w end end
    add(word)
    add(word:lower())
    local low = word:lower()
    for _, r in ipairs(SUFFIXES) do
        local suf, rep = r[1], r[2]
        if #low > #suf + 1 and low:sub(-#suf) == suf then
            local stem = low:sub(1, -#suf - 1)
            add(stem .. rep)
            -- "stopped" -> "stopp" -> "stop"
            if rep == "" and #stem > 2 and stem:sub(-1) == stem:sub(-2, -2) then add(stem:sub(1, -2)) end
        end
    end
    return out
end

-- Tidy a word taken from the page: curly quotes, surrounding punctuation,
-- possessives.
function M.clean(word)
    word = word:gsub("\226\128\153", "'"):gsub("\226\128\152", "'")         -- ’ ‘
    word = word:gsub("^[%p\226\128\156\157\148\147\194\171\187]+", "")
    word = word:gsub("[%p\226\128\156\157\148\147\194\171\187]+$", "")
    word = word:gsub("'s$", ""):gsub("s'$", "s")
    return word
end

-- Look a word up in every dictionary. Returns a list of
-- { dict = name, word = headword, text = definition, type = "h"|"m"|... }.
function M.lookup(word, only)
    word = M.clean(word)
    if word == "" then return {} end
    local results = {}
    for _, d in ipairs(M.list or {}) do
        if (not only or d.name == only) and ensure(d) then
            -- The word as written (if it's an entry), then its base form
            -- ("running": the adjective, then the verb "run").
            local found, exact_done, base_done = {}, false, false
            for k, w in ipairs(candidates(word)) do
                local is_exact = k <= 2 and w:lower() == word:lower()
                if (is_exact and not exact_done) or (not is_exact and not base_done) then
                    local hits = find_all(d.idx, w)
                    if #hits == 0 and d.syn then
                        for _, si in ipairs(find_all(d.syn, w)) do
                            hits[#hits + 1] = u32(d.syn.data, d.syn.ends[si] + 2) + 1
                        end
                    end
                    if hits[1] then
                        local dup = false
                        for _, f in ipairs(found) do if f == hits[1] then dup = true end end
                        if not dup then found[#found + 1] = hits[1] end
                        if is_exact then exact_done = true else base_done = true end
                    end
                end
                if base_done then break end
            end
            for _, i in ipairs(found) do
                local text, t = entry_text(d, i)
                results[#results + 1] = { dict = d.name, word = word_at(d.idx, i), text = text, type = t }
            end
        end
    end
    return results
end

return M
