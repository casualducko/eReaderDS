-- Settings and reading progress, stored as small text files in READER_DATA
-- (Ebook/.ereaderds on the device, outside the app folder so updates keep them).
local M = {}

local DEFAULTS = {
    font = "Gentium Book Plus", font_size = 32, spacing = 1.15, margins = 2, vmargins = 2, justify = true,
    hyphenate = false, -- English books only (the patterns are US English)
    lib_sort = "recent", -- library order: "recent" | "title" | "author" | "progress"
    dict = "all",      -- dictionary for look-ups: "all" or a dictionary's name
    theme = "Paper", chrome = true, orient = "left", anim = "flip",
    tap = "next",      -- what a tap on the touchscreen does while reading: "menu" | "next"
    -- status bar
    sb_title = "both", sb_pages = "left", sb_percent = true,
    sb_bar = "chapter", sb_bar_size = 2, sb_battery = true,
    sb_show = true, sb_clock = "off", tz = "UTC",
    sb_time = "both",
    read_cps = 20,     -- learned reading speed, characters per second (~250 words/min to start)
    brightness = -1,   -- percent; -1 = leave the system setting alone
    extra_dim = 0,
    lid = "sleep",     -- closing the lid: "sleep" (suspend) or "screen" (screens off only)     -- 0-3: dark layer over the page, dimmer than the backlight allows
}

local function data_dir()
    local d = os.getenv("READER_DATA")
    if not d then d = love.filesystem.getSource() .. "/data" end
    os.execute('mkdir -p "' .. d .. '"')
    return d
end

local DIR
local function path(name)
    DIR = DIR or data_dir()
    return DIR .. "/" .. name
end

local last_written = {}          -- file -> text, to skip writes that change nothing

local function write_atomic(file, text)
    if last_written[file] == text then return true end
    last_written[file] = text
    local tmp = file .. ".tmp"
    local f = io.open(tmp, "wb")
    if not f then return false end
    f:write(text)
    f:close()
    os.remove(file)
    return os.rename(tmp, file)
end

local function read_kv(file)
    local t = {}
    local f = io.open(file, "rb")
    if not f then return t end
    for line in f:lines() do
        local k, v = line:match("^([%w_]+)=(.*)$")
        if k then t[k] = v end
    end
    f:close()
    return t
end

function M.book_dirs()
    local env = os.getenv("READER_BOOKS")
    local dirs = {}
    if env then
        for d in env:gmatch("[^:]+") do dirs[#dirs + 1] = d end
    else
        dirs = { "/mnt/mmc/Ebook", "/mnt/sdcard/Ebook", "/mnt/mmc/Books" }
    end
    return dirs
end

function M.data_path(name) return path(name) end

-- Where downloaded books go: the first book folder that exists.
function M.download_dir()
    local dirs = M.book_dirs()
    for _, d in ipairs(dirs) do
        local r = os.execute('[ -d "' .. d .. '" ]')
        if r == 0 or r == true then return d end
    end
    os.execute('mkdir -p "' .. dirs[1] .. '"')
    return dirs[1]
end

function M.load_settings()
    local raw = read_kv(path("settings.txt"))
    local s = {}
    for k, def in pairs(DEFAULTS) do
        local v = raw[k]
        if v == nil then s[k] = def
        elseif type(def) == "number" then s[k] = tonumber(v) or def
        elseif type(def) == "boolean" then s[k] = v == "true"
        else s[k] = v end
    end
    -- The flipped grip was removed (the buttons end up under the wrong hand), so
    -- anyone who had it set goes back to the normal one.
    s.orient = "left"
    return s
end

function M.save_settings(s)
    local keys = {}
    for k in pairs(DEFAULTS) do keys[#keys + 1] = k end
    table.sort(keys)
    local out = {}
    for _, k in ipairs(keys) do out[#out + 1] = k .. "=" .. tostring(s[k]) end
    write_atomic(path("settings.txt"), table.concat(out, "\n") .. "\n")
end

-- progress.txt: one line per book: path \t chapter \t offset \t fraction
local progress
local function load_progress()
    if progress then return progress end
    progress = {}
    local f = io.open(path("progress.txt"), "rb")
    if f then
        for line in f:lines() do
            local p, ch, off, pct = line:match("^(.-)\t(%d+)\t(%d+)\t([%d%.]+)$")
            if p then progress[p] = { ch = tonumber(ch), off = tonumber(off), pct = tonumber(pct) } end
        end
        f:close()
    end
    return progress
end

function M.get_progress(p) return load_progress()[p] end

local function write_progress()
    local all = load_progress()
    local keys = {}
    for k in pairs(all) do keys[#keys + 1] = k end
    table.sort(keys)
    local out = {}
    for _, k in ipairs(keys) do
        local v = all[k]
        out[#out + 1] = string.format("%s\t%d\t%d\t%.4f", k, v.ch, v.off, v.pct)
    end
    write_atomic(path("progress.txt"), table.concat(out, "\n") .. "\n")
end

function M.set_progress(p, ch, off, pct)
    load_progress()[p] = { ch = ch, off = off, pct = pct }
    write_progress()
end

-- bookmarks.txt: one line per bookmark:
-- path \t chapter \t offset \t fraction \t chapter title \t first words of the page
local bookmarks
local function load_bookmarks()
    if bookmarks then return bookmarks end
    bookmarks = {}
    local f = io.open(path("bookmarks.txt"), "rb")
    if f then
        for line in f:lines() do
            local p, ch, off, pct, title, snippet = line:match("^(.-)\t(%d+)\t(%d+)\t([%d%.]+)\t(.-)\t(.*)$")
            if p then
                local list = bookmarks[p] or {}
                list[#list + 1] = { ch = tonumber(ch), off = tonumber(off), pct = tonumber(pct),
                    title = title, snippet = snippet }
                bookmarks[p] = list
            end
        end
        f:close()
    end
    return bookmarks
end

-- The book's bookmarks, in reading order.
function M.get_bookmarks(p)
    return load_bookmarks()[p] or {}
end

function M.set_bookmarks(p, list)
    local all = load_bookmarks()
    table.sort(list, function(a, b) return a.ch < b.ch or (a.ch == b.ch and a.off < b.off) end)
    all[p] = #list > 0 and list or nil
    local keys = {}
    for k in pairs(all) do keys[#keys + 1] = k end
    table.sort(keys)
    local out = {}
    local function clean(t) return ((t or ""):gsub("[\t\r\n]", " ")) end
    for _, k in ipairs(keys) do
        for _, b in ipairs(all[k]) do
            out[#out + 1] = string.format("%s\t%d\t%d\t%.4f\t%s\t%s", k, b.ch, b.off, b.pct,
                clean(b.title), clean(b.snippet))
        end
    end
    write_atomic(path("bookmarks.txt"), table.concat(out, "\n") .. (#out > 0 and "\n" or ""))
end

function M.get_last()
    local f = io.open(path("last.txt"), "rb")
    if not f then return nil end
    local p = f:read("*l")
    f:close()
    return p ~= "" and p or nil
end

function M.set_last(p) write_atomic(path("last.txt"), p .. "\n") end

-- opened.txt: when each book was last opened: path \t unix time.
local opened
local function load_opened()
    if opened then return opened end
    opened = {}
    local f = io.open(path("opened.txt"), "rb")
    if f then
        for line in f:lines() do
            local p, t = line:match("^(.-)\t(%d+)$")
            if p then opened[p] = tonumber(t) end
        end
        f:close()
    else
        -- First run with this file: the book open last counts as most recent.
        local last = M.get_last()
        if last then opened[last] = os.time() end
    end
    return opened
end

local function write_opened()
    local out = {}
    for p, t in pairs(load_opened()) do out[#out + 1] = p .. "\t" .. t end
    table.sort(out)
    write_atomic(path("opened.txt"), table.concat(out, "\n") .. (#out > 0 and "\n" or ""))
end

function M.get_opened(p) return load_opened()[p] end

function M.set_opened(p)
    load_opened()[p] = os.time()
    write_opened()
end

-- Forget a deleted book: its progress, bookmarks and "last opened".
function M.forget(p)
    load_progress()[p] = nil
    write_progress()
    M.set_bookmarks(p, {})
    if load_opened()[p] then load_opened()[p] = nil; write_opened() end
    if M.get_last() == p then
        os.remove(path("last.txt"))
        last_written[path("last.txt")] = nil
    end
end

function M.flush() os.execute("sync") end

return M
