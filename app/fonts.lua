-- Finds reading fonts (bundled + user folders) and groups them into families
-- with regular / italic / bold / bold-italic faces.
local M = {}

local BUNDLED_DIR = "fonts"   -- inside the LÖVE source
M.DEFAULT = "Crimson Pro"            -- new readers' font, and the fallback
M.FALLBACK = "Gentium Book Plus"      -- for characters a font doesn't have

-- Serif or sans-serif, for the font list's filter. The bundled ones are
-- known; for your own, the font's PANOSE class if it has one, then its name,
-- and otherwise serif (most reading fonts are).
local SANS = { ["Andika"] = true, ["Atkinson Hyperlegible Next"] = true, ["Inter"] = true,
    ["Lexend"] = true, ["OpenDyslexic"] = true }
local SANS_NAMES = { "sans", "grotesk", "grotesque", "gothic", "helvetica", "arial", "roboto", "lato",
    "montserrat", "nunito", "poppins", "verdana", "tahoma", "futura", "ubuntu", "dyslex", "hyperlegible" }
function M.kind(f)
    if f.bundled then return SANS[f.name] and "sans" or "serif" end
    if f.panose then return f.panose end
    local n = f.name:lower()
    if n:find("serif") and not n:find("sans") then return "serif" end
    for _, w in ipairs(SANS_NAMES) do
        if n:find(w, 1, true) then return "sans" end
    end
    return "serif"
end

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

-- The folder downloaded fonts go in: the first fonts folder (created if
-- need be), e.g. Ebook/Fonts or roms/ebook/Fonts.
function M.user_dir()
    local d = user_dirs()[1]
    if d then require("android").mkdir(d) end
    return d
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
    local head = read(0, 16)
    if not head or #head < 12 then return nil end
    local base = 0
    if head:sub(1, 4) == "ttcf" then       -- collection: use the first font
        if #head < 16 then return nil end
        base = u32(head, 13)                -- (after tag, version, count: the first offset)
        head = read(base, 12)
        if not head or #head < 12 then return nil end
    end
    local n = u16(head, 5)
    local dir = read(base + 12, n * 16)
    if not dir or #dir < n * 16 then return nil end
    local off, len, os2
    for k = 0, n - 1 do
        local tag = dir:sub(k * 16 + 1, k * 16 + 4)
        if tag == "name" then
            off, len = u32(dir, k * 16 + 9), u32(dir, k * 16 + 13)
        elseif tag == "OS/2" then
            os2 = u32(dir, k * 16 + 9)
        end
    end
    if not off then return nil end
    -- PANOSE (in OS/2): for Latin text faces, serif styles 2-10 are serifs and
    -- 11-13 sans-serifs. Often left blank (0).
    local kind
    local pan = os2 and read(os2 + 32, 2)
    if pan and #pan == 2 and pan:byte(1) == 2 then
        local st = pan:byte(2)
        kind = (st >= 2 and st <= 10 and "serif") or (st >= 11 and st <= 13 and "sans") or nil
    end
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
    return family, sub or "Regular", kind
end

local function names_from_path(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local ok, fam, sub, kind = pcall(parse_names, function(o, l)
        f:seek("set", o); return f:read(l)
    end)
    f:close()
    if ok then return fam, sub, kind end
end

-- Only the few KB of tables needed, not the whole file (reading all the
-- bundled fonts in full took over a second at startup).
local function names_from_bundle(path)
    local f = love.filesystem.newFile(path)
    if not f:open("r") then return nil end
    local ok, fam, sub = pcall(parse_names, function(o, l)
        if not f:seek(o) then return nil end
        return (f:read(l))
    end)
    f:close()
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
-- Caches of loaded font files and name previews (see below); M.scan clears
-- them, since fonts may have been added or removed.
local filedata, filedata_order, previews, preview_order = {}, {}, {}, {}

local function release_previews()
    for _, f in pairs(previews) do if f then f:release() end end
    previews, preview_order = {}, {}
end

local function add_face(path, bundled, fam, sub, kind)
    local weight, italic = classify(sub)
    local key = fam:lower()
    local f = by_name[key]
    if not f then
        f = { name = fam, faces = {}, bundled = bundled }
        by_name[key] = f
        families[#families + 1] = f
    end
    f.panose = f.panose or kind
    f.faces[#f.faces + 1] = { path = path, bundled = bundled, weight = weight, italic = italic }
end

local function is_font(name)
    local ext = (name:match("%.([^.]+)$") or ""):lower()
    return (ext == "ttf" or ext == "otf" or ext == "ttc") and not name:match("^%._")
end

-- The bundled fonts' names, read from each file once per version and kept
-- in LÖVE's save folder: reading ~70 fonts' name tables took a good part of
-- a second at every start on Android.
local CACHE = "fonts-bundled.txt"
local function bundle_cache()
    local key = "v" .. require("version")
    local ok, text = pcall(love.filesystem.read, CACHE)
    local names = {}
    if ok and text and text:sub(1, #key + 1) == key .. "\n" then
        for file, fam, sub in text:gmatch("([^\t\n]+)\t([^\t\n]+)\t([^\t\n]*)\n") do
            names[file] = { fam, sub }
        end
    end
    return names, key
end

function M.scan()
    families, by_name = {}, {}
    release_previews()
    filedata, filedata_order = {}, {}
    local cached, key = bundle_cache()
    local out, missed = { key }, false
    for _, file in ipairs(love.filesystem.getDirectoryItems(BUNDLED_DIR)) do
        if is_font(file) then
            local p = BUNDLED_DIR .. "/" .. file
            local fam, sub
            if cached[file] then
                fam, sub = cached[file][1], cached[file][2]
            else
                missed = true
                fam, sub = names_from_bundle(p)
                if not fam then fam, sub = names_from_filename(file) end
            end
            add_face(p, true, fam, sub)
            out[#out + 1] = file .. "\t" .. fam .. "\t" .. (sub or "")
        end
    end
    if missed then pcall(love.filesystem.write, CACHE, table.concat(out, "\n") .. "\n") end
    for _, dir in ipairs(user_dirs()) do
        for _, file in ipairs(require("android").ls(dir)) do
            if is_font(file) then
                local p = dir .. "/" .. file
                local fam, sub, kind = names_from_path(p)
                if not fam then fam, sub = names_from_filename(file) end
                add_face(p, false, fam, sub, kind)
            end
        end
    end
    -- Every font, bundled or your own, alphabetically.
    table.sort(families, function(a, b) return a.name:lower() < b.name:lower() end)
    for _, f in ipairs(families) do
        f.kind = M.kind(f)
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
    -- Gone (deleted from the SD card, say): the default, else whatever there is.
    for _, f in ipairs(M.list()) do
        if f.name == M.DEFAULT then return f end
    end
    return M.list()[1]
end

---------------------------------------------------------------- loading

-- Font files from the fonts folder, read into memory: the few most recent
-- are kept (a font made from one keeps its own reference), so browsing many
-- fonts doesn't hold them all.
local FILEDATA_KEEP = 16                -- (a family and its fallbacks are 8)

-- One copy of each font file, shared by every size made from it (newFont with
-- a path reads the whole file again for each font: a family is 6 fonts, and
-- the Gentium fallbacks another 6).
local function new_font(face, size)
    local fd = filedata[face.path]
    if not fd then
        if face.bundled then
            fd = love.filesystem.newFileData(face.path)
        else
            local f = assert(io.open(face.path, "rb"))
            local data = f:read("*a")
            f:close()
            fd = love.filesystem.newFileData(data, face.path:match("[^/]+$"))
        end
        filedata[face.path] = fd
        filedata_order[#filedata_order + 1] = face.path
        while #filedata_order > FILEDATA_KEEP do filedata[table.remove(filedata_order, 1)] = nil end
    end
    return love.graphics.newFont(love.font.newRasterizer(fd, size))
end

-- The regular face of a family at a size, for showing a font's name in its
-- own typeface (menus). Cached; nil if it can't be loaded.
function M.preview(name, size)
    local key = name .. "@" .. size
    if previews[key] == nil then
        local ok, font = pcall(new_font, M.find(name).r, size)
        previews[key] = ok and font or false
        -- A pinch goes through every size from 18 to 64: keep the last few
        -- dozen (more than any one screen shows at once).
        preview_order[#preview_order + 1] = key
        if #preview_order > 48 then
            local old = table.remove(preview_order, 1)
            if previews[old] then previews[old]:release() end
            previews[old] = nil
        end
    end
    return previews[key] or nil
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
            sup = new_font(f.r, math.floor(size * 0.65)),      -- superscripts (note numbers)
        }
    end
    local ok, res = pcall(load_family, fam)
    if ok then
        -- Characters the font lacks (Cyrillic, Greek, special spaces, primes,
        -- accents...) come from Gentium Book Plus, which has the most of any
        -- bundled font, in the same style and size: not boxes.
        local g = fam.name ~= M.FALLBACK and M.find(M.FALLBACK)
        if g and g.name == M.FALLBACK then
            local okg, gres = pcall(load_family, g)
            if okg then
                for k, f in pairs(res) do
                    if gres[k] then pcall(f.setFallbacks, f, gres[k]) end
                end
            end
        end
        return res, fam.name
    end
    print("[fonts] failed to load " .. fam.name .. ": " .. tostring(res))
    local def = M.find(M.DEFAULT)
    ok, res = pcall(load_family, def)
    if ok then return res, def.name end
    local f = love.graphics.newFont(size)
    return { r = f, i = f, b = f, bi = f, h = love.graphics.newFont(math.floor(size * 1.45)),
        sup = love.graphics.newFont(math.floor(size * 0.65)) }, "Default"
end

return M
