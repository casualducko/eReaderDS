-- Settings and reading progress, stored as small text files in READER_DATA
-- (Ebook/.ereaderds on the device, outside the app folder so updates keep them).
local M = {}
local Android = require("android")

local DEFAULTS = {
    font = "Crimson Pro", font_size = 40, spacing = 0.85, margins = 1, vmargins = 2, justify = true,
    hyphenate = false, -- English books only (the patterns are US English)
    lib_sort = "recent", -- library order: "recent" | "title" | "author" | "series" | "progress"
    dict = "all",      -- dictionary for look-ups: "all" or a dictionary's name
    theme = "Sepia", chrome = true, orient = "left", anim = "flip",
    tap = "next",      -- what a tap on the touchscreen does while reading: "menu" | "next"
    -- status bar
    sb_title = "both", sb_pages = "left", sb_percent = true,
    sb_bar = "chapter", sb_bar_size = 2, sb_battery = true,
    sb_show = true, sb_clock = "12", tz = "Device clock",
    sb_time = "chapter", -- time left in the chapter: "chapter" | "off"
    read_cps = 20,     -- learned reading speed, characters per second (~250 words/min to start)
    -- Backlight in percent; -1 = leave the system setting alone. ROCKNIX's
    -- panels are dimmer at the same level, so its launcher asks for more.
    brightness = tonumber(os.getenv("READER_DEFAULT_BRIGHTNESS") or "") or (Android.active and -1 or 50),
    extra_dim = 0,     -- 0-3: dark layer over the page, dimmer than the backlight allows
    seen_version = "", -- the version last run: after an update, "what's new" is offered once
    update_notices = true, -- check for a newer version on launch and say so
    night_theme = "off", -- a theme used automatically at night ("off" or a theme's name)
    hidden_themes = "", -- built-in themes left out of the lists, by name: "Dracula,Nord"
    hl_color = "yellow", -- highlights: "yellow" | "green" | "blue" | "pink" | "subtle" (the selection colour)
    hl_bright = false,   -- highlights on a dark theme: bright, with dark text (else muted, the text light)
    comic_tip = false,   -- the magnifier's been pointed out (the first comic opened)
    dim_pictures = true, -- pictures in books drawn darker on a dark theme
    night_from = 21,   -- ... from this hour (0-23, the device's clock)
    night_to = 7,      -- ... until this one
    skip_version = "", -- a version the reader chose to skip (not mentioned again)
    lid = "sleep",     -- closing the lid: "sleep" (suspend) or "screen" (screens off only)
    lib_hide_finished = false, -- My Books leaves out the books marked finished
    idle_min = 10,     -- left alone this many minutes, the screens dim, then turn off (0 = never)
    -- KOReader sync (kosync.lua): the account (the key is the password's MD5,
    -- as KOReader keeps it), the server ("crosspoint", "koreader" or "custom":
    -- kosync_custom's address), how books are matched (CrossPoint's server
    -- goes with file names, KOReader's with file contents, as they default),
    -- sending the book's details, and this device's id there.
    kosync_user = "", kosync_key = "", kosync_server = "crosspoint", kosync_custom = "",
    kosync_custom_name = "",   -- your own server's name (empty: its address)
    kosync_match = "filename", kosync_meta = false, kosync_device = "",
    kosync_auto = "ask",       -- automatic sync: "off", "ask" (when opening a book) or "on"
}

local function data_dir()
    local d = os.getenv("READER_DATA")
    if not d then d = Android.active and Android.DATA or (love.filesystem.getSource() .. "/data") end
    Android.mkdir(d)
    return d
end

local DIR
local function path(name)
    DIR = DIR or data_dir()
    return DIR .. "/" .. name
end

local last_written = {}          -- file -> text, to skip writes that change nothing

-- Making sure a file is really on the card before it replaces the old one
-- (fsync): without it, a sudden power-off right after a save could leave
-- the renamed file empty on the SD card (FAT keeps no order between the
-- two). Linux and Android only (through the C library).
local fsync_file
if jit.os == "Linux" then
    local ok_ffi, ffi = pcall(require, "ffi")
    if ok_ffi then
        for _, decl in ipairs({ "int open(const char *path, int flags);", "int close(int fd);", "int fsync(int fd);" }) do
            pcall(ffi.cdef, decl)
        end
        fsync_file = function(path)
            local fd = ffi.C.open(path, 0)          -- (O_RDONLY: enough to flush it)
            if fd < 0 then return end
            ffi.C.fsync(fd)
            ffi.C.close(fd)
        end
    end
end
-- Files written on nearly every page turn: flushed at most every 30 s (and
-- by Store.flush on quitting, closing the lid and the screens going off),
-- so turning pages doesn't wait on the card.
local OFTEN = { ["progress.txt"] = true, ["last.txt"] = true, ["opened.txt"] = true }
local last_fsync = {}

-- While a backup is being restored (and until eReaderDS closes after it),
-- nothing is written: the app's own saves would put the old settings back.
M.frozen = false

local function write_atomic(file, text)
    if M.frozen then return true end
    if last_written[file] == nil then
        -- First write of this file this session: if it already says this,
        -- there's nothing to do (reopening a book rewrote several files).
        local cur = io.open(file, "rb")
        last_written[file] = cur and cur:read("*a") or false
        if cur then cur:close() end
    end
    if last_written[file] == text then return true end
    local tmp = file .. ".tmp"
    local f = io.open(tmp, "wb")
    if not f then return false end
    -- A full card shows up at close (when the data is really written), and
    -- a short file mustn't replace a good one.
    local ok = f:write(text)
    ok = f:close() and ok
    if ok then
        local chk = io.open(tmp, "rb")
        ok = chk and chk:seek("end") == #text
        if chk then chk:close() end
    end
    if not ok then os.remove(tmp); return false end
    if fsync_file then
        local base, now = file:match("([^/]+)$"), os.time()
        if not OFTEN[base] or now - (last_fsync[base] or 0) >= 30 then
            last_fsync[base] = now
            pcall(fsync_file, tmp)
        end
    end
    -- rename() replaces the old file in one step, so a power cut leaves either
    -- the old file or the new one. (Remove first only if a rename over an
    -- existing file isn't allowed.)
    local renamed = os.rename(tmp, file)
    if not renamed then
        os.remove(file)
        renamed = os.rename(tmp, file)
    end
    -- Remember it only once it's really on the card, so a failed write is
    -- retried next time.
    if renamed then last_written[file] = text end
    return renamed
end

-- A file's lines without a Windows line ending (a file edited on a PC).
local function lines(f)
    return function()
        local l = f:read("*l")
        return l and (l:gsub("\r$", ""))
    end
end

-- A fraction as stored: 0..1 (never -0.0000 or nan, which wouldn't read back).
local function frac(x)
    x = tonumber(x) or 0
    if x ~= x then return 0 end
    return math.max(0, math.min(1, x))
end

local function read_kv(file)
    local t = {}
    local f = io.open(file, "rb")
    if not f then return t end
    for line in lines(f) do
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
    elseif Android.active then
        dirs = { Android.BOOKS }
    else
        dirs = { "/mnt/mmc/Ebook", "/mnt/sdcard/Ebook", "/mnt/mmc/Books" }
    end
    return dirs
end

function M.data_path(name) return path(name) end

-- The data folder itself (no trailing slash).
function M.data_dir() return (path(""):gsub("/$", "")) end

-- Themes the reader made (Settings → Themes → Custom): themes.txt, one per
-- line, "name <tab> text colour <tab> page colour", each "brightness:warmth:tint".
function M.load_themes()
    local out = {}
    local f = io.open(path("themes.txt"), "rb")
    if not f then return out end
    for line in lines(f) do
        local name, fg, bg = line:match("^([^\t]+)\t([%d,/:%-]+)\t([%d,/:%-]+)$")
        if name then out[#out + 1] = { name = name, fg = fg, bg = bg } end
    end
    f:close()
    return out
end

function M.save_themes(list)
    local out = {}
    for _, t in ipairs(list) do out[#out + 1] = t.name .. "\t" .. t.fg .. "\t" .. t.bg end
    write_atomic(path("themes.txt"), table.concat(out, "\n") .. (#out > 0 and "\n" or ""))
end

-- The books folder as people see it, for messages: "Ebook" (on the stock
-- firmware's SD card, /mnt/mmc/Ebook) or "roms/ebook" (ROCKNIX,
-- /storage/roms/ebook). Returns the name and where it is (or nil).
function M.books_folder()
    local d = M.book_dirs()[1] or "/mnt/mmc/Ebook"
    if Android.active and d == Android.BOOKS then return "Ebook", "on the handheld's storage" end
    local rel = d:match("^/storage/(.+)$")
    if rel then return rel, nil end
    rel = d:match("^/mnt/mmc/(.+)$") or d:match("^/mnt/sdcard/(.+)$")
    if rel then return rel, "on your SD card" end
    return d, nil
end

-- Where downloaded books go: the first book folder that exists.
local download_dir
function M.download_dir()
    if download_dir then return download_dir end
    download_dir = M.find_download_dir()
    return download_dir
end

function M.find_download_dir()
    local dirs = M.book_dirs()
    for _, d in ipairs(dirs) do
        if Android.is_dir(d) then return d end
    end
    Android.mkdir(dirs[1])
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
    -- Values edited by hand (or from older versions) that aren't valid fall
    -- back to the default.
    local ENUMS = {
        lib_sort = { recent = true, title = true, author = true, series = true, progress = true },
        lid = { sleep = true, screen = true },
        tap = { next = true, menu = true },
        anim = { flip = true, fade = true, off = true },
        hl_color = { yellow = true, green = true, blue = true, pink = true, subtle = true },
        kosync_match = { binary = true, filename = true },
        kosync_auto = { off = true, ask = true, on = true },
    }
    for k, allowed in pairs(ENUMS) do
        if allowed and not allowed[s[k]] then s[k] = DEFAULTS[k] end
    end
    -- Numbers edited by hand: real numbers (not nan or inf) in a sensible
    -- range, or the default (a text size of 0 couldn't even start).
    local RANGES = { font_size = { 18, 64 }, spacing = { 0.5, 2.5 }, extra_dim = { 0, 3 }, brightness = { -1, 100 },
        idle_min = { 0, 1440 }, night_from = { 0, 23 }, night_to = { 0, 23 }, margins = { 1, 3 }, vmargins = { 1, 4 },
        read_cps = { 1, 200 } }
    for k, r in pairs(RANGES) do
        local v = s[k]
        if type(v) ~= "number" or v ~= v or v < r[1] or v > r[2] then s[k] = DEFAULTS[k] end
    end
    -- Settings saved by a version from before seen_version (v0.3.10 and
    -- older): that's an update, not a new install, so "what's new" is offered.
    if raw.seen_version == nil and next(raw) then s.seen_version = "older" end
    s.read_cps = math.max(3, math.min(80, s.read_cps))
    s.night_from, s.night_to = math.floor(s.night_from) % 24, math.floor(s.night_to) % 24
    -- The old default "UTC" meant "the device's time as it is".
    if s.tz == "UTC" then s.tz = "Device clock" end
    -- "left": turned counter-clockwise (buttons on the right, the usual);
    -- "right": turned the other way round (Settings → Reading & Device → Hold it).
    if s.orient ~= "right" then s.orient = "left" end
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
        for line in lines(f) do
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
        out[#out + 1] = string.format("%s\t%d\t%d\t%.4f", k, v.ch, v.off, frac(v.pct))
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
        for line in lines(f) do
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
            out[#out + 1] = string.format("%s\t%d\t%d\t%.4f\t%s\t%s", k, b.ch, b.off, frac(b.pct),
                clean(b.title), clean(b.snippet))
        end
    end
    write_atomic(path("bookmarks.txt"), table.concat(out, "\n") .. (#out > 0 and "\n" or ""))
end

-- highlights.txt: one line per highlight:
-- path \t chapter \t start offset \t end offset \t fraction \t chapter title \t the words
-- [\t colour \t note] (colour: "" for the Settings one; the note's line breaks
-- as \n, its backslashes \\). Lines without the last two are from before
-- there were colours and notes.
local highlights
local function load_highlights()
    if highlights then return highlights end
    highlights = {}
    local f = io.open(path("highlights.txt"), "rb")
    if f then
        for line in lines(f) do
            local p, ch, s, e, pct, title, text, colour, note =
                line:match("^(.-)\t(%d+)\t(%d+)\t(%d+)\t([%d%.]+)\t([^\t]*)\t([^\t]*)\t(%a*)\t(.*)$")
            if not p then
                p, ch, s, e, pct, title, text = line:match("^(.-)\t(%d+)\t(%d+)\t(%d+)\t([%d%.]+)\t(.-)\t(.*)$")
            end
            if p then
                local list = highlights[p] or {}
                if note and note ~= "" then
                    note = note:gsub("\\(.)", function(c) return c == "n" and "\n" or c end)
                else
                    note = nil
                end
                list[#list + 1] = { ch = tonumber(ch), s = tonumber(s), e = tonumber(e), pct = tonumber(pct),
                    title = title, text = text, color = (colour or "") ~= "" and colour or nil, note = note }
                highlights[p] = list
            end
        end
        f:close()
    end
    return highlights
end

-- The book's highlights, in reading order.
function M.get_highlights(p)
    return load_highlights()[p] or {}
end

function M.set_highlights(p, list)
    local all = load_highlights()
    table.sort(list, function(a, b) return a.ch < b.ch or (a.ch == b.ch and a.s < b.s) end)
    all[p] = #list > 0 and list or nil
    local keys = {}
    for k in pairs(all) do keys[#keys + 1] = k end
    table.sort(keys)
    local out = {}
    local function clean(t) return ((t or ""):gsub("[\t\r\n]", " ")) end
    for _, k in ipairs(keys) do
        for _, h in ipairs(all[k]) do
            local note = (h.note or ""):gsub("\\", "\\\\"):gsub("\r?\n", "\\n"):gsub("[\t\r]", " ")
            out[#out + 1] = string.format("%s\t%d\t%d\t%d\t%.4f\t%s\t%s\t%s\t%s", k, h.ch, h.s, h.e, frac(h.pct),
                clean(h.title), clean(h.text), h.color or "", note)
        end
    end
    write_atomic(path("highlights.txt"), table.concat(out, "\n") .. (#out > 0 and "\n" or ""))
end

function M.get_last()
    local f = io.open(path("last.txt"), "rb")
    if not f then return nil end
    local p = f:read("*l")
    f:close()
    return p ~= "" and p or nil
end

function M.set_last(p) write_atomic(path("last.txt"), p .. "\n") end

-- comics.txt: the reading direction chosen for a comic, where it isn't the
-- one its ComicInfo.xml gives: path \t rtl | ltr.
local comics
local function load_comics()
    if comics then return comics end
    comics = {}
    local f = io.open(path("comics.txt"), "rb")
    if f then
        for line in lines(f) do
            local p, d = line:match("^(.-)\t(%a+)$")
            if p and (d == "rtl" or d == "ltr") then comics[p] = d end
        end
        f:close()
    end
    return comics
end

-- "rtl", "ltr", or nil (as the comic says).
function M.get_comic_dir(p) return load_comics()[p] end

function M.set_comic_dir(p, d)
    load_comics()[p] = d
    local out = {}
    for k, v in pairs(comics) do out[#out + 1] = k .. "\t" .. v end
    table.sort(out)
    write_atomic(path("comics.txt"), table.concat(out, "\n") .. (#out > 0 and "\n" or ""))
end

-- opened.txt: when each book was last opened: path \t unix time.
local opened
local function load_opened()
    if opened then return opened end
    opened = {}
    local f = io.open(path("opened.txt"), "rb")
    if f then
        for line in lines(f) do
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

-- library.txt: the title and author inside each EPUB, read once for the
-- library list: path \t size \t title \t author \t author's sort name \t
-- series \t number in the series. An entry is used while the file keeps its
-- size; one with no title is a book that couldn't be read (its file name is
-- used). Lines from before series were kept are read again.
local meta
local function load_meta()
    if meta then return meta end
    meta = {}
    local f = io.open(path("library.txt"), "rb")
    if f then
        for line in lines(f) do
            local p, size, t, a, so, se, ix = line:match("^(.-)\t(%-?%d+)\t(.-)\t(.-)\t(.-)\t(.-)\t(.-)$")
            if p then
                meta[p] = { size = tonumber(size), title = t ~= "" and t or nil, author = a, sort = so ~= "" and so or nil,
                    series = se ~= "" and se or nil, index = tonumber(ix) }
            end
        end
        f:close()
    end
    return meta
end

function M.get_meta(p, size)
    local m = load_meta()[p]
    if m and (not size or m.size == size) then return m end
end

function M.set_meta(p, size, m)
    load_meta()[p] = { size = size or -1, title = m.title, author = m.author or "", sort = m.sort,
        series = m.series, index = m.index }
end

-- Written after a scan, keeping only the books still there (keep: path -> true).
function M.save_meta(keep)
    local out = {}
    local function clean(v) return ((v or ""):gsub("[\t\r\n]", " ")) end
    for p, m in pairs(load_meta()) do
        if not keep or keep[p] then
            out[#out + 1] = table.concat({ p, tostring(m.size or -1), clean(m.title), clean(m.author), clean(m.sort),
                clean(m.series), m.index and tostring(m.index) or "" }, "\t")
        end
    end
    table.sort(out)
    write_atomic(path("library.txt"), table.concat(out, "\n") .. (#out > 0 and "\n" or ""))
end

-- finished.txt: books marked finished (by reaching the end, or by hand):
-- path \t unix time.
local finished
local function load_finished()
    if finished then return finished end
    finished = {}
    local f = io.open(path("finished.txt"), "rb")
    if f then
        for line in lines(f) do
            local p, t = line:match("^(.-)\t(%d+)$")
            if p then finished[p] = tonumber(t) end
        end
        f:close()
    end
    return finished
end

-- When the book was finished, or nil.
function M.get_finished(p) return load_finished()[p] end

function M.set_finished(p, on)
    load_finished()[p] = on and os.time() or nil
    local out = {}
    for q, t in pairs(load_finished()) do out[#out + 1] = q .. "\t" .. t end
    table.sort(out)
    write_atomic(path("finished.txt"), table.concat(out, "\n") .. (#out > 0 and "\n" or ""))
end

-- sync-seen.txt: for KOReader sync, the server's timestamp for each book's
-- place that this device has already dealt with (gone to, stayed, or sent),
-- per account: account \t path \t timestamp. Kept across restarts, so an
-- old place from another device isn't offered again.
local seen
local function load_seen()
    if seen then return seen end
    seen = {}
    local f = io.open(path("sync-seen.txt"), "rb")
    if f then
        for line in lines(f) do
            local a, p, t = line:match("^(.-)\t(.-)\t(.+)$")
            if a then seen[a .. "\t" .. p] = t end
        end
        f:close()
    end
    return seen
end

function M.get_sync_seen(account, p) return load_seen()[account .. "\t" .. p] end

-- ts nil: forget it. account alone (p nil): forget that account's.
function M.set_sync_seen(account, p, ts)
    local all = load_seen()
    if p then
        local key = account .. "\t" .. p
        ts = ts ~= nil and tostring(ts) or nil
        if all[key] == ts then return end
        all[key] = ts
    else
        for k in pairs(all) do if k:sub(1, #account + 1) == account .. "\t" then all[k] = nil end end
    end
    local out = {}
    for k, t in pairs(all) do out[#out + 1] = k .. "\t" .. t end
    table.sort(out)
    write_atomic(path("sync-seen.txt"), table.concat(out, "\n") .. (#out > 0 and "\n" or ""))
end

-- Forget a deleted book: its progress, bookmarks and "last opened".
function M.forget(p)
    load_progress()[p] = nil
    write_progress()
    M.set_bookmarks(p, {})
    if load_highlights()[p] then M.set_highlights(p, {}) end
    if load_opened()[p] then load_opened()[p] = nil; write_opened() end
    if load_finished()[p] then M.set_finished(p, false) end
    if M.get_last() == p then
        os.remove(path("last.txt"))
        last_written[path("last.txt")] = nil
    end
end

-- (Not on Android, where it's slow, flushing the whole storage, and closing
-- the app waited on it; the files are already written.)
function M.flush() if not Android.active then os.execute("sync") end end

return M
