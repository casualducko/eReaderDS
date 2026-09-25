-- Settings and reading progress, stored as small text files next to the app.
local M = {}

local DEFAULTS = {
    font = "Gentium Book Plus", font_size = 32, spacing = 1.15, margins = 2, justify = true,
    theme = 1, chrome = true, orient = "left", anim = "flip",
    brightness = -1,   -- percent; -1 = leave the system setting alone
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

local function write_atomic(file, text)
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
    if s.orient ~= "left" and s.orient ~= "right" then s.orient = "left" end
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

function M.set_progress(p, ch, off, pct)
    local all = load_progress()
    all[p] = { ch = ch, off = off, pct = pct }
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

function M.get_last()
    local f = io.open(path("last.txt"), "rb")
    if not f then return nil end
    local p = f:read("*l")
    f:close()
    return p ~= "" and p or nil
end

function M.set_last(p) write_atomic(path("last.txt"), p .. "\n") end

function M.flush() os.execute("sync") end

return M
