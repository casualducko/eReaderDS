-- Loads EPUB (and plain .txt) books into a list of chapters made of simple blocks.
--
-- Block kinds:
--   text  { runs = {{text, i, b, off}}, center, heading (0,1,2), list }
--   blank { off }           -- empty paragraph / scene break
--   rule  { off }           -- <hr>
--   image { src, off }      -- path inside the zip
local Zip = require("zip")

local M = {}

---------------------------------------------------------------- helpers

local function utf8char(cp)
    if cp < 0x80 then return string.char(cp) end
    if cp < 0x800 then
        return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + cp % 0x40)
    end
    if cp < 0x10000 then
        return string.char(0xE0 + math.floor(cp / 0x1000),
            0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
    end
    if cp < 0x110000 then
        return string.char(0xF0 + math.floor(cp / 0x40000),
            0x80 + math.floor(cp / 0x1000) % 0x40,
            0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
    end
    return "?"
end

local ENTITIES = {
    amp = "&", lt = "<", gt = ">", quot = '"', apos = "'", nbsp = "\194\160",
    mdash = "—", ndash = "–", hellip = "…", lsquo = "‘", rsquo = "’",
    ldquo = "“", rdquo = "”", laquo = "«", raquo = "»", copy = "©", reg = "®",
    trade = "™", eacute = "é", egrave = "è", agrave = "à", aacute = "á",
    ccedil = "ç", ouml = "ö", uuml = "ü", auml = "ä", szlig = "ß", deg = "°",
    middot = "·", bull = "•", times = "×", shy = "", zwnj = "", zwj = "",
    thinsp = " ", ensp = " ", emsp = " ", iexcl = "¡", iquest = "¿",
    frac12 = "½", frac14 = "¼", frac34 = "¾", sect = "§", para = "¶",
    dagger = "†", Dagger = "‡", prime = "′", Prime = "″",
}

local function decode(s)
    return (s:gsub("&(#?[xX]?)(%w+);", function(kind, v)
        if kind == "#" then
            local n = tonumber(v); return n and utf8char(n) or ""
        elseif kind == "#x" or kind == "#X" then
            local n = tonumber(v, 16); return n and utf8char(n) or ""
        end
        return ENTITIES[v] or ("&" .. v .. ";")
    end))
end
M.decode = decode

local function urldecode(s)
    return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

local function dirname(p) return p:match("^(.*/)") or "" end

local function resolve(base, href)
    href = urldecode(href:gsub("#.*$", ""))
    if href:sub(1, 1) == "/" then href = href:sub(2) else href = dirname(base) .. href end
    local parts = {}
    for seg in href:gmatch("[^/]+") do
        if seg == ".." then table.remove(parts)
        elseif seg ~= "." then parts[#parts + 1] = seg end
    end
    return table.concat(parts, "/")
end

local function attr(tag, name)
    local v = tag:match("[%s]" .. name:gsub("%-", "%%-") .. '%s*=%s*"([^"]*)"')
        or tag:match("[%s]" .. name:gsub("%-", "%%-") .. "%s*=%s*'([^']*)'")
    return v and decode(v)
end

---------------------------------------------------------------- CSS (tiny subset)

-- Returns class -> {i=bool, b=bool, center=bool, hidden=bool}
local function style_props(body)
    body = body:lower()
    local p = {}
    local fs = body:match("font%-style%s*:%s*([%w%-]+)")
    if fs == "italic" or fs == "oblique" then p.i = true elseif fs == "normal" then p.i = false end
    local fw = body:match("font%-weight%s*:%s*([%w%-]+)")
    if fw then
        local n = tonumber(fw)
        if fw == "bold" or fw == "bolder" or (n and n >= 600) then p.b = true
        elseif fw == "normal" or (n and n < 600) then p.b = false end
    end
    local ta = body:match("text%-align%s*:%s*([%w%-]+)")
    if ta == "center" then p.center = true elseif ta then p.center = false end
    if body:match("display%s*:%s*none") then p.hidden = true end
    if body:match("vertical%-align%s*:%s*super") then p.sup = true end
    return p
end

local function parse_css(css, into)
    css = css:gsub("/%*.-%*/", "")
    for sel, body in css:gmatch("([^{}]+){([^}]*)}") do
        local props = style_props(body)
        if next(props) then
            for one in sel:gmatch("[^,]+") do
                -- only simple ".cls" / "tag.cls" selectors (last compound part)
                local last = one:match("([%w%-_%.]+)%s*$")
                local cls = last and last:match("%.([%w%-_]+)$")
                if cls then
                    local t = into[cls] or {}
                    for k, v in pairs(props) do t[k] = v end
                    into[cls] = t
                end
            end
        end
    end
    return into
end

---------------------------------------------------------------- HTML -> blocks

local BLOCK = {}
for t in ([[p div h1 h2 h3 h4 h5 h6 li blockquote section article header footer
    table tr td th ul ol dl dt dd pre figure figcaption aside nav body center
    main address caption]]):gmatch("%S+") do BLOCK[t] = true end
local SKIP = { head = true, script = true, style = true, title = true }
local VOID = { br = true, hr = true, img = true, image = true, meta = true, link = true,
    input = true, col = true, area = true, base = true, wbr = true, source = true }

local function parse_html(html, base, classes, show_notes)
    local blocks, anchors = {}, {}
    local off = 0
    local stack = {}          -- open elements with their style
    local cur = nil           -- current text block
    local skipping = 0
    local last_blank = false

    local function style()
        local s = stack[#stack]
        return s or { i = false, b = false, center = false, heading = 0 }
    end

    local function flush()
        if cur then
            -- trim trailing whitespace; drop empty blocks
            local has = false
            for _, r in ipairs(cur.runs) do
                if r.br or r.text:find("%S") then has = true; break end
            end
            if has then
                blocks[#blocks + 1] = cur
                last_blank = false
            elseif cur.explicit and not last_blank and #blocks > 0 then
                blocks[#blocks + 1] = { kind = "blank", off = cur.off }
                last_blank = true
            end
            cur = nil
        end
    end

    local function ensure_block()
        if not cur then
            local s = style()
            cur = { kind = "text", runs = {}, off = off, center = s.center,
                heading = s.heading, list = s.list }
        end
    end

    local function add_text(t)
        if skipping > 0 or t == "" then return end
        t = decode(t):gsub("[%s]+", " ")
        if t == "" then return end
        if not cur and not t:find("%S") then return end
        ensure_block()
        local s = style()
        local runs = cur.runs
        local last = runs[#runs]
        if last and not last.br and last.i == s.i and last.b == s.b and last.link == s.link and last.sup == s.sup then
            last.text = last.text .. t
        else
            if s.link and s.link.lead == nil then
                -- A link at the very start of a paragraph is a note's own
                -- label ("[1] The note..."), not a reference to a note.
                local lead = true
                for _, r in ipairs(runs) do
                    if r.br or (r.text and r.text:find("%S")) then lead = false; break end
                end
                s.link.lead = lead
            end
            runs[#runs + 1] = { text = t, i = s.i, b = s.b, off = off, link = s.link, sup = s.sup }
        end
        off = off + #t
    end

    local function push(name, tag)
        local parent = style()
        local s = { name = name, i = parent.i, b = parent.b, center = parent.center,
            heading = parent.heading, list = parent.list, hidden = parent.hidden,
            link = parent.link, sup = parent.sup }
        if name == "i" or name == "em" or name == "cite" or name == "var" or name == "dfn" then s.i = true end
        if name == "b" or name == "strong" then s.b = true end
        if name == "center" then s.center = true end
        local h = name:match("^h(%d)$")
        if h then
            h = tonumber(h)
            s.heading = h <= 3 and 2 or 1
            s.b = true
            s.center = true
        end
        if name == "li" then s.list = true end
        if name == "sup" then s.sup = true end
        if name == "a" then
            local href = attr(tag, "href")
            if href and not href:match("^%a[%w+.-]*:") then        -- in-book links only
                local file = href:sub(1, 1) == "#" and base or resolve(base, href)
                local frag = href:match("#(.+)$")
                local kind = (attr(tag, "epub:type") or "") .. " " .. (attr(tag, "role") or "")
                s.link = { target = frag and (file .. "#" .. urldecode(frag)) or file,
                    noteref = kind:find("noteref") ~= nil, sup = parent.sup,
                    backlink = kind:find("backlink") ~= nil }
                if s.link.noteref then s.sup = true end        -- note numbers are superscript
            end
        end
        -- EPUB 3 footnotes are shown on the other page, not in the text.
        if name == "aside" then
            local kind = (attr(tag, "epub:type") or "") .. " " .. (attr(tag, "role") or "")
            -- (Endnotes stay: they're often a chapter of their own.)
            if not show_notes and kind:find("footnote") then
                s.hidden = true
            end
        end
        local cls = attr(tag, "class")
        if cls then
            for c in cls:gmatch("%S+") do
                local p = classes[c]
                if p then for k, v in pairs(p) do s[k] = v end end
            end
        end
        local st = attr(tag, "style")
        if st then for k, v in pairs(style_props(st)) do s[k] = v end end
        stack[#stack + 1] = s
        return s
    end

    local function pop(name)
        for k = #stack, 1, -1 do
            if stack[k].name == name then
                for _ = #stack, k, -1 do
                    local s = table.remove(stack)
                    if s.skip then skipping = math.max(0, skipping - 1) end
                end
                return
            end
        end
    end

    local body_start = html:find("<body[%s>]") or 1
    local pos = body_start
    local len = #html
    while pos <= len do
        local lt = html:find("<", pos, true)
        if not lt then add_text(html:sub(pos)); break end
        if lt > pos then add_text(html:sub(pos, lt - 1)) end
        if html:sub(lt, lt + 3) == "<!--" then
            local e = html:find("-->", lt + 4, true)
            pos = (e or len) + 3
        elseif html:sub(lt, lt + 8) == "<![CDATA[" then
            local e = html:find("]]>", lt + 9, true) or len
            add_text(html:sub(lt + 9, e - 1))
            pos = e + 3
        else
            local gt = html:find(">", lt, true) or len
            local tag = html:sub(lt, gt)
            pos = gt + 1
            local closing, name = tag:match("^<(/?)([%w:%-]+)")
            if name then
                name = name:lower():gsub("^.*:", "")
                local selfclose = tag:sub(-2) == "/>"
                if closing == "/" then
                    if SKIP[name] then skipping = math.max(0, skipping - 1) end
                    if BLOCK[name] then flush() end
                    pop(name)
                elseif SKIP[name] then
                    if not selfclose then skipping = skipping + 1 end
                else
                    local id = attr(tag, "id")
                    if id then anchors[id] = off end
                    if name == "br" then
                        if skipping == 0 then
                            ensure_block()
                            cur.runs[#cur.runs + 1] = { br = true, off = off }
                        end
                    elseif name == "hr" then
                        flush()
                        blocks[#blocks + 1] = { kind = "rule", off = off }
                    elseif name == "img" or name == "image" then
                        local src = attr(tag, "src") or attr(tag, "xlink:href") or attr(tag, "href")
                        if src and skipping == 0 and not style().hidden then
                            flush()
                            blocks[#blocks + 1] = { kind = "image", src = resolve(base, src), off = off }
                            off = off + 1
                        end
                    else
                        if BLOCK[name] then flush() end
                        if not VOID[name] and not selfclose then
                            local s = push(name, tag)
                            if s.hidden then skipping = skipping + 1; s.skip = true end
                            if skipping == 0 and BLOCK[name] and (name == "p" or name:match("^h%d$") or name == "li") then
                                ensure_block()
                                cur.explicit = true
                            end
                        end
                    end
                end
            end
        end
    end
    flush()
    return blocks, anchors, off
end
M.parse_html = parse_html

---------------------------------------------------------------- TOC parsing

local function parse_ncx(xml, base)
    local toc = {}
    local depth, pending = 0, nil
    for tag, text in xml:gmatch("(<[^>]+>)([^<]*)") do
        local name = tag:match("^<([%w:]+)")
        if tag:match("^</navPoint") then depth = depth - 1
        elseif name == "navPoint" then depth = depth + 1; pending = nil
        elseif name == "text" and pending == nil then pending = decode(text):gsub("%s+", " ")
        elseif name == "content" then
            local src = attr(tag, "src")
            if src then
                toc[#toc + 1] = { title = pending or "?", depth = depth,
                    file = resolve(base, src), anchor = src:match("#(.+)$") }
                pending = false
            end
        end
    end
    return toc
end

local function parse_nav(xhtml, base)
    local toc = {}
    local navstart = xhtml:find('<nav[^>]-epub:type%s*=%s*"toc"') or xhtml:find("<nav")
    if not navstart then return toc end
    local navend = xhtml:find("</nav>", navstart, true) or #xhtml
    local s = xhtml:sub(navstart, navend)
    local depth = 0
    local pos = 1
    while true do
        local a, b, tag = s:find("(<[^>]+>)", pos)
        if not a then break end
        pos = b + 1
        if tag:match("^<ol") then depth = depth + 1
        elseif tag:match("^</ol") then depth = depth - 1
        elseif tag:match("^<a[%s>]") then
            local href = attr(tag, "href")
            local e = s:find("</a>", pos, true) or #s
            local title = decode(s:sub(pos, e - 1):gsub("<[^>]+>", "")):gsub("%s+", " ")
            if href then
                toc[#toc + 1] = { title = title, depth = depth, file = resolve(base, href),
                    anchor = href:match("#(.+)$") }
            end
            pos = e
        end
    end
    return toc
end

---------------------------------------------------------------- Book

local Book = {}
Book.__index = Book

local function basename_title(path)
    local n = path:match("([^/]+)$") or path
    return (n:gsub("%.[^.]+$", ""))
end

local function open_epub_zip(path, z)
    local container = z:read("META-INF/container.xml")
    if not container then return nil, "missing container.xml" end
    local opf_path = container:match('full%-path%s*=%s*"([^"]+)"')
    if not opf_path then return nil, "no rootfile" end
    local opf = z:read(opf_path)
    if not opf then return nil, "missing " .. opf_path end

    local book = setmetatable({ path = path, zip = z, chapters = {}, toc = {}, classes = {} }, Book)
    book.title = decode((opf:match("<dc:title[^>]*>(.-)</dc:title>") or basename_title(path)):gsub("<[^>]+>", ""))
    book.author = opf:match("<dc:creator[^>]*>(.-)</dc:creator>")
    book.author = book.author and decode(book.author:gsub("<[^>]+>", "")) or ""
    book.language = (opf:match("<dc:language[^>]*>%s*(.-)%s*</dc:language>") or ""):lower()

    local manifest, ncx, nav = {}, nil, nil
    for item in opf:gmatch("<item%s[^>]*>") do
        local id, href = attr(item, "id"), attr(item, "href")
        if id and href then
            local full = resolve(opf_path, href)
            local mt = attr(item, "media-type") or ""
            manifest[id] = { href = full, type = mt }
            if mt == "text/css" then
                local css = z:read(full)
                if css then parse_css(css, book.classes) end
            end
            local props = attr(item, "properties") or ""
            if props:find("nav") then nav = full end
            if props:find("cover%-image") then book.cover = full end
            if mt == "application/x-dtbncx+xml" then ncx = full end
        end
    end
    if not book.cover then
        local cid = opf:match('<meta[^>]-name%s*=%s*"cover"[^>]-content%s*=%s*"([^"]+)"')
            or opf:match('<meta[^>]-content%s*=%s*"([^"]+)"[^>]-name%s*=%s*"cover"')
        local m = cid and manifest[cid]
        if m and m.type:find("^image/") then book.cover = m.href end
    end
    local spine_toc = opf:match("<spine[^>]-toc%s*=%s*\"([^\"]+)\"")
    if spine_toc and manifest[spine_toc] then ncx = manifest[spine_toc].href end

    local total = 0
    for ref in opf:gmatch("<itemref%s[^>]*>") do
        local idref = attr(ref, "idref")
        local m = idref and manifest[idref]
        if m then
            local e = z.entries[m.href] or z.lower[m.href:lower()]
            local size = e and e.usize or 1
            book.chapters[#book.chapters + 1] = { file = m.href, weight = size, start = total }
            total = total + size
        end
    end
    book.total = math.max(total, 1)
    if #book.chapters == 0 then return nil, "empty spine" end

    local index = {}
    for i, c in ipairs(book.chapters) do index[c.file] = i end
    local toc = {}
    if nav then local x = z:read(nav); if x then toc = parse_nav(x, nav) end end
    if #toc == 0 and ncx then local x = z:read(ncx); if x then toc = parse_ncx(x, ncx) end end
    for _, t in ipairs(toc) do
        t.chapter = index[t.file]
        if t.chapter then book.toc[#book.toc + 1] = t end
    end
    return book
end

local function open_epub(path)
    local z, err = Zip.open(path)
    if not z then return nil, err end
    local ok, book, why = pcall(open_epub_zip, path, z)
    if ok and book then return book end
    z:close()
    return nil, ok and why or book
end

local function open_txt(path)
    local f, err = io.open(path, "rb")
    if not f then return nil, err end
    local text = f:read("*a"):gsub("\r\n?", "\n")
    f:close()
    if text:sub(1, 3) == "\239\187\191" then text = text:sub(4) end
    local book = setmetatable({ path = path, chapters = {}, toc = {}, classes = {},
        title = basename_title(path), author = "" }, Book)
    -- Split into ~64KB chapters at paragraph boundaries so layout stays fast.
    local blocks, off, size = {}, 0, 0
    local total = 0
    local function close_chapter()
        if #blocks > 0 then
            book.chapters[#book.chapters + 1] = { blocks = blocks, anchors = {}, length = off,
                weight = size, start = total }
            total = total + size
        end
        blocks, off, size = {}, 0, 0
    end
    for para in (text .. "\n\n"):gmatch("(.-)\n%s*\n") do
        local t = para:gsub("%s+", " "):gsub("^ ", "")
        if t ~= "" then
            blocks[#blocks + 1] = { kind = "text", off = off,
                runs = { { text = t, i = false, b = false, off = off } } }
            off = off + #t
            size = size + #t
            if size > 65536 then close_chapter() end
        end
    end
    close_chapter()
    book.total = math.max(total, 1)
    if #book.chapters == 0 then return nil, "empty file" end
    return book
end

function M.open(path)
    local ext = (path:match("%.([^.]+)$") or ""):lower()
    if ext == "txt" then return open_txt(path) end
    return open_epub(path)
end

-- Ensure chapter i has parsed blocks.
function Book:chapter(i)
    local c = self.chapters[i]
    if not c then return nil end
    if not c.blocks then
        local html = self.zip:read(c.file) or ""
        c.blocks, c.anchors, c.length = parse_html(html, c.file, self.classes)
        if #c.blocks == 0 then c.blocks = { { kind = "blank", off = 0 } } end
        c.length = math.max(c.length, 1)
    end
    return c
end

-- Fraction (0..1) through the whole book for chapter i at char offset off.
function Book:fraction(i, off)
    local c = self.chapters[i]
    if not c then return 0 end
    local within = (c.length and c.length > 0) and math.min(1, off / c.length) or 0
    return math.min(1, (c.start + within * c.weight) / self.total)
end

-- Find the chapter / offset for a whole-book fraction.
function Book:locate(frac)
    local target = frac * self.total
    for i, c in ipairs(self.chapters) do
        if target < c.start + c.weight or i == #self.chapters then
            self:chapter(i)
            local within = (target - c.start) / math.max(c.weight, 1)
            return i, math.floor(math.max(0, math.min(1, within)) * c.length)
        end
    end
    return 1, 0
end

-- The text of a footnote: the element a link points to ("file#id"), or the
-- paragraph (list item, aside...) around it when the id is on a small inline
-- anchor. Returns blocks like a chapter's, or nil.
local NOTE_BLOCKS = { p = true, li = true, aside = true, div = true, dd = true, dt = true,
    section = true, blockquote = true, td = true, span = false }
-- The raw HTML of a file and the position of the tag with id `frag`.
function Book:find_id(file, frag)
    if not self.zip then return nil end
    if self.html_cache and self.html_cache.file == file then
    else
        self.html_cache = { file = file, html = self.zip:read(file) }
    end
    local html = self.html_cache.html
    if not html then return nil end
    local esc = frag:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
    local at = html:find("[%s]id%s*=%s*[\"']" .. esc .. "[\"']")
    if not at then return nil end
    for i = at, 1, -1 do
        if html:byte(i) == 60 then return html, i end              -- "<"
    end
end

function Book:note(target)
    local file, frag = target:match("^(.-)#(.+)$")
    if not file then return nil end
    local html, lt = self:find_id(file, frag)
    if not html then return nil end
    local name = (html:match("^<([%w:%-]+)", lt) or ""):lower():gsub("^.*:", "")
    -- The end of an element starting at `start` (same-name tags may nest).
    local function element_end(start, tag)
        local depth, pos = 0, start
        while true do
            local s, e, close = html:find("<(/?)" .. tag .. "[%s/>]", pos)
            if not s then return nil end
            local tag_end = html:find(">", s, true) or e
            if close == "/" then
                depth = depth - 1
                if depth == 0 then return tag_end end
            elseif html:sub(tag_end - 1, tag_end) ~= "/>" then
                depth = depth + 1
            end
            pos = tag_end + 1
        end
    end
    if not NOTE_BLOCKS[name] then
        -- An inline anchor: the nearest block around it, or, for an empty
        -- anchor just before a block ("<a id=n2></a><p>Note 2</p>"), the next one.
        local best, best_name
        for _, b in ipairs({ "p", "li", "aside", "div", "dd", "section", "blockquote" }) do
            local from = 1
            while true do
                local s = html:find("<" .. b .. "[%s>]", from)
                if not s or s > lt then break end
                if not best or s > best then best, best_name = s, b end
                from = s + 1
            end
        end
        local best_end = best and element_end(best, best_name)
        if not best or (best_end and best_end < lt) then
            best, best_name = nil, nil
            for _, b in ipairs({ "p", "li", "aside", "div", "dd", "blockquote" }) do
                local s = html:find("<" .. b .. "[%s>]", lt)
                if s and (not best or s < best) then best, best_name = s, b end
            end
        end
        if not best then return nil end
        lt, name = best, best_name
    end
    local stop = element_end(lt, name)
    local snippet = html:sub(lt, stop or math.min(#html, lt + 4000))
    if #snippet > 12000 then snippet = snippet:sub(1, 12000) end
    local blocks = parse_html("<body>" .. snippet .. "</body>", file, self.classes, true)
    local out = {}
    for _, b in ipairs(blocks) do
        if b.kind == "text" then
            b.list, b.center, b.heading = nil, nil, 0
            -- Drop "back to the text" links (↩, ↑, ^, "Back").
            local runs = {}
            for _, r in ipairs(b.runs) do
                local t = r.text and r.text:gsub("%s", "") or ""
                if not (r.link and (t == "" or t:match("^[\226\128-\191%^]+$") or t:lower() == "back"
                        or t:lower() == "return")) then
                    runs[#runs + 1] = r
                end
            end
            b.runs = runs
            if #runs > 0 then out[#out + 1] = b end
        elseif b.kind ~= "blank" then
            out[#out + 1] = b
        end
    end
    if #out == 0 then return nil end
    return out
end

function Book:read_resource(p)
    return self.zip and self.zip:read(p)
end

-- Release the open book file (EPUBs keep it open to read chapters on demand).
function Book:close()
    if self.zip then self.zip:close() end
end

return M
