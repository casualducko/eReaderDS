-- Comics (.cbz): a zip of page pictures. What's here doesn't draw anything:
-- the pages in reading order, the comic's own details (ComicInfo.xml), the
-- pictures' sizes (from their file headers, without decoding them), and
-- how the pages pair up on the two screens. book.lua opens a comic as a
-- book with one picture a page; main.lua draws it.
local M = {}

-- Pictures LÖVE can show, and ones it can't (yet), to say so.
M.IMAGE = { jpg = true, jpeg = true, png = true, gif = true, bmp = true, tga = true }
M.LATER = { webp = true, avif = true, jxl = true, heic = true, heif = true }

-- "page2" before "page10": names compared with their numbers as numbers,
-- ignoring case.
local function chunks(s)
    local t = {}
    for text, num in s:lower():gmatch("(%D*)(%d*)") do
        if text ~= "" then t[#t + 1] = text end
        if num ~= "" then t[#t + 1] = tonumber(num) end
        if text == "" and num == "" then break end
    end
    return t
end
function M.natural_less(a, b)
    local x, y = chunks(a), chunks(b)
    for i = 1, math.max(#x, #y) do
        local p, q = x[i], y[i]
        if p == nil then return true end
        if q == nil then return false end
        if p ~= q then
            if type(p) == type(q) then return p < q end
            return type(p) == "number"            -- (numbers before letters)
        end
    end
    return a < b
end

-- The page pictures of an open zip, in reading order, and how many pictures
-- there are that can't be shown (WebP and the like). Folders are kept in
-- order too (a volume's chapters); hidden files and macOS's leftovers aren't.
function M.list(z)
    local pages, later = {}, 0
    for name in pairs(z.entries) do
        local hidden = name:match("^%.") or name:find("/%.") or name:match("^__MACOSX/")
        local ext = (name:match("%.([^./]+)$") or ""):lower()
        if not hidden and not name:match("/$") then
            if M.IMAGE[ext] then pages[#pages + 1] = name
            elseif M.LATER[ext] then later = later + 1 end
        end
    end
    table.sort(pages, M.natural_less)
    return pages, later
end

-- The chapters: when the pages are in folders (a volume of several
-- chapters), one entry for each folder, at its first page: { title, page }.
function M.chapters(pages)
    local out, last = {}, nil
    for i, p in ipairs(pages) do
        local dir = p:match("^(.*)/[^/]+$")
        if dir ~= last then
            last = dir
            if dir then out[#out + 1] = { title = dir:match("([^/]+)$"), page = i } end
        end
    end
    if #out < 2 then return {} end              -- (one folder of pages: no chapters)
    return out
end

local function xml_text(s)
    if not s then return nil end
    s = s:gsub("<!%[CDATA%[(.-)%]%]>", "%1"):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&quot;", '"')
        :gsub("&apos;", "'"):gsub("&amp;", "&"):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
    return s ~= "" and s or nil
end

-- ComicInfo.xml (ComicRack's details, which most comic tools write):
-- { title, series, number, writer, rtl } (any may be missing), or {}.
function M.info(z)
    local name
    for n in pairs(z.entries) do
        if n:lower():match("^comicinfo%.xml$") or n:lower():match("/comicinfo%.xml$") then name = n break end
    end
    local x = name and z:read(name)
    if not x then return {} end
    local function tag(t) return xml_text(x:match("<" .. t .. "[^>]*>(.-)</" .. t .. ">")) end
    local manga = (tag("Manga") or ""):lower()
    return {
        title = tag("Title"), series = tag("Series"), number = tag("Number"),
        writer = tag("Writer") or tag("Penciller"),
        -- "YesAndRightToLeft" is manga read right to left; plain "Yes" only
        -- says it's manga (often already turned to read left to right).
        rtl = manga == "yesandrighttoleft" or nil,
    }
end

-- Width and height from a picture file's header (PNG, JPEG, GIF, BMP), or nil.
function M.header_dims(d)
    local function be16(i) local a, b = d:byte(i, i + 1); return a * 256 + b end
    local function be32(i) return be16(i) * 65536 + be16(i + 2) end
    local function le32(i) local a, b, c, e = d:byte(i, i + 3); return a + b * 256 + c * 65536 + e * 16777216 end
    if d:sub(1, 8) == "\137PNG\r\n\26\n" and #d >= 24 then return be32(17), be32(21) end
    if d:sub(1, 4) == "GIF8" and #d >= 10 then
        local w1, w2, h1, h2 = d:byte(7, 10); return w1 + w2 * 256, h1 + h2 * 256
    end
    if d:sub(1, 2) == "BM" and #d >= 26 then
        local h = le32(23)
        if h >= 2147483648 then h = 4294967296 - h end      -- (stored top down)
        return le32(19), h
    end
    if d:byte(1) == 0xFF and d:byte(2) == 0xD8 then
        local i = 3
        while i + 8 <= #d do
            if d:byte(i) ~= 0xFF then i = i + 1
            else
                local m = d:byte(i + 1)
                if m >= 0xC0 and m <= 0xCF and m ~= 0xC4 and m ~= 0xC8 and m ~= 0xCC then
                    return be16(i + 7), be16(i + 5)
                elseif m == 0xD8 or m == 0x01 or (m >= 0xD0 and m <= 0xD7) or m == 0xFF then
                    i = i + 2
                else
                    i = i + 2 + be16(i + 2)
                end
            end
        end
    end
end

-- A page picture's size, reading as little of it as can be: the start of a
-- stored one (comics' pictures are usually stored, being compressed
-- already), else the whole picture. nil if it can't be told.
function M.dims(z, name)
    for _, n in ipairs({ 16384, 131072 }) do
        local head = z:read_head(name, n)
        if not head then break end
        local w, h = M.header_dims(head)
        if w then return w, h end
        if #head < n then break end              -- (it was the whole file)
    end
    local all = z:read(name)
    return all and M.header_dims(all)
end

-- A picture wider than it's tall: a two-page spread, shown half on each screen.
function M.wide(w, h) return w and h and w > h * 1.1 end

-- The pages of the two screens, in reading order: { src, off, half } for a
-- picture (half 1 or 2 of a spread, else none), or { blank = true, off }.
-- Pages pair up two by two (a pair on the two screens), so the cover is on
-- its own, as a real book's (an empty page beside it), and a spread always
-- starts a pair, so its halves are side by side. off: picture i's first is
-- (i-1)*2, a spread's second half one more, so a place in the comic stays
-- put however the pages pair up.
function M.pages(names, dims_of)
    local out = {}
    for i, src in ipairs(names) do
        local off = (i - 1) * 2
        local w, h = dims_of(src)
        local wide = M.wide(w, h)
        -- The cover alone, unless it's a spread itself (a wraparound cover).
        if i == 1 and not wide then out[#out + 1] = { blank = true, off = off } end
        if wide then
            if #out % 2 == 1 then out[#out + 1] = { blank = true, off = off } end
            out[#out + 1] = { src = src, off = off, half = 1 }
            out[#out + 1] = { src = src, off = off + 1, half = 2 }
        else
            out[#out + 1] = { src = src, off = off }
        end
    end
    return out
end

return M
