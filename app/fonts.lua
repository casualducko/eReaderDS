-- Finds reading fonts (bundled + user folders) and groups them into families
-- with regular / italic / bold / bold-italic faces.
local M = {}

local BUNDLED_DIR = "fonts"   -- inside the LÖVE source
M.DEFAULT = "Gentium Book Plus"

-- Bundled fonts in menu order: serifs, then sans-serifs, then accessibility.
local ORDER = {
    "Gentium Book Plus", "Literata", "Charis SIL", "Source Serif 4", "Crimson Text", "Bitter",
    "Atkinson Hyperlegible Next", "Inter", "Lexend",
    "OpenDyslexic",
}
local RANK = {}
for i, name in ipairs(ORDER) do RANK[name] = i end

-- Fonts that were renamed or replaced between versions.
local ALIASES = { ["Atkinson Hyperlegible"] = "Atkinson Hyperlegible Next" }

local function user_dirs()
    local env = os.getenv("READER_FONTS")
    local dirs = {}
    if env then
        for d in env:gmatch("[^:]+") do dirs[#dirs + 1] = d end
    else
        dirs = { "/mnt/mmc/Ebook/Fonts", "/mnt/sdcard/Ebook/Fonts", "/mnt/vendor/bin/ebook/resources/fonts" }
    end
    return dirs
end

---------------------------------------------------------------- font name table

local function u16(s, i) local a, b = s:byte(i, i + 1); return a * 256 + b end
local function u32(s, i)
    local a, b, c, d = s:byte(i, i + 3)
    return ((a * 256 + b) * 256 + c) * 256 + d
end

local function utf16be(s)
    local out = {}
    for i = 1, #s - 1, 2 do
        local c = u16(s, i)
        if c < 0x80 then out[#out + 1] = string.char(c)
        elseif c < 0x800 then out[#out + 1] = string.char(0xC0 + math.floor(c / 64), 0x80 + c % 64)
        elseif c < 0xD800 or c > 0xDFFF then
            out[#out + 1] = string.char(0xE0 + math.floor(c / 4096), 0x80 + math.floor(c / 64) % 64, 0x80 + c % 64)
        end
    end
    return table.concat(out)
end

-- Reads family / subfamily names from a TrueType/OpenType file.
-- read(offset, length) returns bytes (offset 0-based).
local function parse_names(read)
    local head = read(0, 12)
    if not head or #head < 12 then return nil end
    local base = 0
    if head:sub(1, 4) == "ttcf" then       -- collection: use the first font
        base = u32(head, 9)
        head = read(base, 12)
        if not head or #head < 12 then return nil end
    end
    local n = u16(head, 5)
    local dir = read(base + 12, n * 16)
    if not dir or #dir < n * 16 then return nil end
    local off, len
    for k = 0, n - 1 do
        if dir:sub(k * 16 + 1, k * 16 + 4) == "name" then
            off, len = u32(dir, k * 16 + 9), u32(dir, k * 16 + 13)
        end
    end
    if not off then return nil end
    local t = read(off, len)
    if not t or #t < 6 then return nil end
    local count, strings = u16(t, 3), u16(t, 5)
    local names = {}
    for k = 0, count - 1 do
        local r = 7 + k * 12
        if r + 11 > #t then break end
        local platform, lang, id = u16(t, r), u16(t, r + 4), u16(t, r + 6)
        local l, o = u16(t, r + 8), u16(t, r + 10)
        if id == 1 or id == 2 or id == 16 or id == 17 then
            local raw = t:sub(strings + o + 1, strings + o + l)
            local s
            if platform == 3 or platform == 0 then s = utf16be(raw)
            elseif platform == 1 then s = raw end
            -- Prefer English (Windows 0x409 / Mac 0), otherwise keep the first seen.
            local english = (platform == 3 and lang == 0x409) or (platform == 1 and lang == 0)
            if s and s ~= "" and (english or not names[id]) then names[id] = s end
        end
    end
    local family = names[16] or names[1]
    local sub = names[17] or names[2]
    if not family then return nil end
    return family, sub or "Regular"
end

local function names_from_path(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local ok, fam, sub = pcall(parse_names, function(o, l)
        f:seek("set", o); return f:read(l)
    end)
    f:close()
    if ok then return fam, sub end
end

local function names_from_bundle(path)
    local data = love.filesystem.read(path)
    if not data then return nil end
    local ok, fam, sub = pcall(parse_names, function(o, l) return data:sub(o + 1, o + l) end)
    if ok then return fam, sub end
end

-- Fallback: "Family-BoldItalic.ttf" -> "Family", "BoldItalic"
local function names_from_filename(file)
    local base = file:gsub("%.[^.]+$", "")
    local fam, sub = base:match("^(.-)[%-_ ]+(%a+)$")
    if fam and sub:lower():find("^[%a]*$") and (sub:lower():find("bold") or sub:lower():find("italic")
        or sub:lower():find("oblique") or sub:lower():find("regular") or sub:lower():find("light")
        or sub:lower():find("medium") or sub:lower():find("book")) then
        return fam, sub
    end
    return base, "Regular"
end

---------------------------------------------------------------- styles

local function classify(sub)
    local s = sub:lower():gsub("[%s%-_]", "")
    local italic = s:find("italic") or s:find("oblique") or s:find("^it$")
    local weight
    if s:find("semibold") or s:find("demibold") then weight = 600
    elseif s:find("extrabold") or s:find("ultrabold") then weight = 800
    elseif s:find("black") or s:find("heavy") then weight = 900
    elseif s:find("bold") then weight = 700
    elseif s:find("medium") then weight = 500
    elseif s:find("extralight") or s:find("ultralight") then weight = 200
    elseif s:find("thin") or s:find("hairline") then weight = 100
    elseif s:find("light") then weight = 300
    else weight = 400 end
    return weight, italic and true or false
end

-- Pick the face closest to the wanted weight with the wanted slant.
local function pick(faces, weight, italic)
    local best, best_score
    for _, f in ipairs(faces) do
        local score = math.abs(f.weight - weight) + (f.italic == italic and 0 or 1000)
        -- For bold, prefer heavier over lighter when equally far.
        if weight >= 700 and f.weight < weight then score = score + 1 end
        if not best_score or score < best_score then best, best_score = f, score end
    end
    return best
end

---------------------------------------------------------------- scanning

local families, by_name

local function add_face(path, bundled, fam, sub)
    local weight, italic = classify(sub)
    local key = fam:lower()
    local f = by_name[key]
    if not f then
        f = { name = fam, faces = {}, bundled = bundled }
        by_name[key] = f
        families[#families + 1] = f
    end
    f.faces[#f.faces + 1] = { path = path, bundled = bundled, weight = weight, italic = italic }
end

local function is_font(name)
    local ext = (name:match("%.([^.]+)$") or ""):lower()
    return (ext == "ttf" or ext == "otf" or ext == "ttc") and not name:match("^%._")
end

function M.scan()
    families, by_name = {}, {}
    for _, file in ipairs(love.filesystem.getDirectoryItems(BUNDLED_DIR)) do
        if is_font(file) then
            local p = BUNDLED_DIR .. "/" .. file
            local fam, sub = names_from_bundle(p)
            if not fam then fam, sub = names_from_filename(file) end
            add_face(p, true, fam, sub)
        end
    end
    for _, dir in ipairs(user_dirs()) do
        local ls = io.popen('ls -1 "' .. dir .. '" 2>/dev/null')
        if ls then
            for file in ls:lines() do
                if is_font(file) then
                    local p = dir .. "/" .. file
                    local fam, sub = names_from_path(p)
                    if not fam then fam, sub = names_from_filename(file) end
                    add_face(p, false, fam, sub)
                end
            end
            ls:close()
        end
    end
    -- Bundled fonts in their curated order, then user fonts alphabetically.
    table.sort(families, function(a, b)
        local ra = a.bundled and (RANK[a.name] or 99) or 1000
        local rb = b.bundled and (RANK[b.name] or 99) or 1000
        if ra ~= rb then return ra < rb end
        return a.name:lower() < b.name:lower()
    end)
    for _, f in ipairs(families) do
        f.r = pick(f.faces, 400, false)
        f.i = pick(f.faces, 400, true)
        f.b = pick(f.faces, 700, false)
        f.bi = pick(f.faces, 700, true)
        local desc = {}
        for _, face in ipairs(f.faces) do desc[#desc + 1] = face.weight .. (face.italic and "i" or "") end
        print(string.format("[fonts] %s (%s)%s", f.name, table.concat(desc, " "), f.bundled and "" or " user"))
    end
    return families
end

function M.list()
    if not families then M.scan() end
    return families
end

function M.find(name)
    name = ALIASES[name] or name
    for _, f in ipairs(M.list()) do
        if f.name == name then return f end
    end
    return M.list()[1]
end

---------------------------------------------------------------- loading

local filedata = {}

local function new_font(face, size)
    if face.bundled then return love.graphics.newFont(face.path, size) end
    local fd = filedata[face.path]
    if not fd then
        local f = assert(io.open(face.path, "rb"))
        local data = f:read("*a")
        f:close()
        fd = love.filesystem.newFileData(data, face.path:match("[^/]+$"))
        filedata[face.path] = fd
    end
    return love.graphics.newFont(love.font.newRasterizer(fd, size))
end

-- Returns fonts {r, i, b, bi, h} for a family at a size, falling back to the
-- default family if anything fails to load.
function M.load(name, size)
    local fam = M.find(name)
    local function load_family(f)
        return {
            r = new_font(f.r, size),
            i = new_font(f.i, size),
            b = new_font(f.b, size),
            bi = new_font(f.bi, size),
            h = new_font(f.b, math.floor(size * 1.45)),
        }
    end
    local ok, res = pcall(load_family, fam)
    if ok then return res, fam.name end
    print("[fonts] failed to load " .. fam.name .. ": " .. tostring(res))
    local def = M.find(M.DEFAULT)
    ok, res = pcall(load_family, def)
    if ok then return res, def.name end
    local f = love.graphics.newFont(size)
    return { r = f, i = f, b = f, bi = f, h = love.graphics.newFont(math.floor(size * 1.45)) }, "Default"
end

return M
