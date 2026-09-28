-- OPDS catalogs (Calibre, Calibre-Web and others): the catalog list from
-- opds.txt, and parsing of catalog pages (Atom feeds) into entries.
local Book = require("book")
local Net = require("net")

local M = {}
M.parse_url = Net.parse_url

local SAMPLE = [[
# Online catalogs (OPDS) for "Get books" in the library.
# Remove the # from the lines below and fill them in. Add more blocks for
# more catalogs. Calibre's content server lives at /opds, for example
# http://192.168.1.20:8080/opds
#
# name = Calibre
# url = http://192.168.1.20:8080/opds
# user = me
# password = secret
#
# For a server with a self-signed certificate, add:  verify = no
#
# Project Gutenberg is always listed. To hide it, add:  gutenberg = off
]]

-- Catalogs from opds.txt: { name, url, user, password, verify }, plus
-- options ({ gutenberg = true|false }). Writes a commented example the first
-- time so there's something to edit.
function M.load_catalogs(file)
    local f = io.open(file, "rb")
    if not f then
        local w = io.open(file, "wb")
        if w then w:write(SAMPLE); w:close() end
        return {}, { gutenberg = true }
    end
    local list, cur, opts = {}, nil, { gutenberg = true }
    for line in f:lines() do
        line = line:gsub("\r$", "")
        local k, v = line:match("^%s*([%a_]+)%s*=%s*(.-)%s*$")
        if k and not line:match("^%s*#") and k:lower() == "gutenberg" then
            opts.gutenberg = not (v:lower():match("^no") or v:lower():match("^off") or v == "0" or v:lower() == "false")
        elseif k and not line:match("^%s*#") then
            k = k:lower()
            -- A new name or a second url starts another catalog.
            if not cur or (k == "name" and cur.name) or (k == "url" and cur.url) then
                cur = {}
                list[#list + 1] = cur
            end
            if k == "verify" then cur.verify = not v:lower():match("^n") and v ~= "0" and v:lower() ~= "false"
            elseif k == "user" or k == "username" then cur.user = v
            elseif k == "password" or k == "pass" then cur.password = v
            else cur[k] = v end
        end
    end
    f:close()
    local out = {}
    for _, c in ipairs(list) do
        if c.url and Net.parse_url(c.url) then
            c.name = c.name or Net.parse_url(c.url).host
            if c.verify == nil then c.verify = true end
            out[#out + 1] = c
        end
    end
    return out, opts
end

-- Free catalogs offered without any setup.
M.BUILT_IN = {
    -- www directly: m.gutenberg.org only redirects there, and is often slow
    -- or failing (504) when www is fine.
    { name = "Project Gutenberg", url = "https://www.gutenberg.org/ebooks.opds/", verify = true,
      about = "Over 70,000 free public-domain books." },
}

---------------------------------------------------------------- XML

-- A small tolerant XML parser: elements with local names (prefix dropped),
-- attributes and text. Enough for Atom feeds.
local function parse_xml(xml)
    local root = { name = "#root", kids = {}, attrs = {} }
    local stack = { root }
    local pos = 1
    xml = xml:gsub("<!%-%-.-%-%->", "")
    xml = xml:gsub("<!%[CDATA%[(.-)%]%]>", function(t)
        return (t:gsub("&", "&amp;"):gsub("<", "&lt;"))
    end)
    while true do
        local s, e, close, name, attrs, selfclose = xml:find("<(/?)([%w_:%-%.]+)(.-)(/?)>", pos)
        if not s then break end
        local top = stack[#stack]
        if s > pos then
            local text = xml:sub(pos, s - 1)
            if text:find("%S") then top.text = (top.text or "") .. text end
        end
        name = name:gsub("^.*:", "")
        if close == "/" then
            for i = #stack, 2, -1 do
                if stack[i].name == name then
                    for _ = i, #stack do table.remove(stack) end
                    break
                end
            end
        else
            local el = { name = name, attrs = {}, kids = {} }
            for k, _, v in attrs:gmatch('([%w_:%-]+)%s*=%s*(["\'])(.-)%2') do
                el.attrs[k:gsub("^.*:", "")] = Book.decode(v)
            end
            top.kids[#top.kids + 1] = el
            if selfclose ~= "/" then stack[#stack + 1] = el end
        end
        pos = e + 1
    end
    return root
end

local function child(el, name)
    for _, k in ipairs(el.kids) do if k.name == name then return k end end
end

local function children(el, name)
    local out = {}
    for _, k in ipairs(el.kids) do if k.name == name then out[#out + 1] = k end end
    return out
end

-- Text inside an element, including nested elements (e.g. XHTML content),
-- with tags removed, entities decoded and whitespace collapsed.
local function text_of(el)
    if not el then return "" end
    local parts = {}
    local function walk(e)
        if e.text then parts[#parts + 1] = e.text end
        for _, k in ipairs(e.kids) do
            walk(k)
            if k.name == "p" or k.name == "br" or k.name == "div" then parts[#parts + 1] = " " end
        end
    end
    walk(el)
    local s = table.concat(parts, " ")
    s = Book.decode(s)
    -- Escaped HTML (type="html" content) arrives as text: strip its tags too.
    s = s:gsub("<[^>]*>", " ")
    s = Book.decode(s)
    return (s:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
end

---------------------------------------------------------------- feeds

local BOOK_TYPES = {
    ["application/epub+zip"] = { rank = 1, ext = "epub" },
    ["application/epub"] = { rank = 2, ext = "epub" },
    ["text/plain"] = { rank = 3, ext = "txt" },
}

local function is_feed_type(t)
    return t and (t:find("atom%+xml") or t:find("opds%-catalog")) ~= nil
end

-- Parse a catalog page. Returns { title, next, entries }, where each entry is
-- { title, author, summary, href (a sub-catalog), book = { href, ext, size,
-- type }, formats (other formats offered), cover }.
function M.parse_feed(xml, base)
    local root = parse_xml(xml)
    local feed = child(root, "feed")
    if not feed then error("this address isn't an OPDS catalog", 0) end
    local out = { title = text_of(child(feed, "title")), entries = {} }
    for _, l in ipairs(children(feed, "link")) do
        local rel = l.attrs.rel
        if rel == "next" and l.attrs.href then out.next = Net.resolve(base, l.attrs.href) end
        -- Search: an address with {searchTerms} in it, or an OpenSearch
        -- description that has one (fetched when a search is made).
        if rel == "search" and l.attrs.href then
            local t = (l.attrs.type or ""):lower()
            if l.attrs.href:find("{searchTerms}", 1, true) and not t:find("html") then
                out.search = Net.resolve(base, l.attrs.href)
            elseif t:find("opensearchdescription") then
                out.search_osd = Net.resolve(base, l.attrs.href)
            end
        end
    end
    for _, e in ipairs(children(feed, "entry")) do
        local it = { title = text_of(child(e, "title")), formats = {} }
        local authors = {}
        for _, a in ipairs(children(e, "author")) do
            local n = text_of(child(a, "name"))
            -- "Austen, Jane, 1775-1817" (library style) -> "Jane Austen".
            n = n:gsub(",%s*[%d%-%?%s]+$", "")
            local last, first = n:match("^([^,]+),%s*([^,]+)$")
            if last then n = first .. " " .. last end
            if n ~= "" then authors[#authors + 1] = n end
        end
        it.author = table.concat(authors, ", ")
        local summary = text_of(child(e, "summary"))
        if summary == "" then summary = text_of(child(e, "content")) end
        it.summary = summary
        for _, l in ipairs(children(e, "link")) do
            local rel, t, href = l.attrs.rel or "", (l.attrs.type or ""):lower(), l.attrs.href
            if href then
                href = Net.resolve(base, href)
                if rel:find("opds%-spec%.org/acquisition") and not rel:find("buy") and not rel:find("subscribe") then
                    local mime = t:match("^[^;%s]+") or ""
                    local kind = BOOK_TYPES[mime]
                    if kind then
                        if not it.book or kind.rank < it.book.rank then
                            it.book = { href = href, ext = kind.ext, rank = kind.rank,
                                size = tonumber(l.attrs.length), type = mime }
                        end
                    else
                        local fmt = mime:match("/(.+)$") or mime
                        fmt = ({ ["x-mobipocket-ebook"] = "MOBI", ["pdf"] = "PDF",
                            ["vnd.amazon.ebook"] = "AZW3", ["x-mobi8-ebook"] = "AZW3",
                            ["x-cbz"] = "CBZ", ["vnd.comicbook+zip"] = "CBZ", ["x-fictionbook+xml"] = "FB2" })[fmt]
                            or fmt:upper()
                        it.formats[#it.formats + 1] = fmt
                    end
                elseif rel:find("opds%-spec%.org/image/thumbnail") or rel:find("x%-stanza%-cover%-image%-thumbnail") then
                    it.thumb = href
                elseif rel:find("opds%-spec%.org/image") or rel:find("x%-stanza%-cover%-image") then
                    it.cover = href
                elseif is_feed_type(t) and (rel == "" or rel == "subsection" or rel:find("^http")
                        or rel == "alternate" and not it.href) then
                    it.href = it.href or href
                end
            end
        end
        it.cover = it.thumb or it.cover
        if it.title ~= "" or it.href or it.book then out.entries[#out.entries + 1] = it end
    end
    return out
end

-- The catalog-search address in an OpenSearch description (the Url for Atom
-- results), resolved against the description's own address; or nil.
function M.search_template(osd, base)
    for tag in osd:gmatch("<[%w:]*Url%s[^>]*>") do
        local t, tpl = tag:match('type%s*=%s*"([^"]*)"'), tag:match('template%s*=%s*"([^"]*)"')
        if tpl and t and t:find("atom") then
            tpl = Net.resolve(base, (tpl:gsub("&amp;", "&")))
            -- Gutenberg's description still points at http://m.gutenberg.org,
            -- two redirects away from the (much faster) https://www.
            tpl = tpl:gsub("^https?://m%.gutenberg%.org/", "https://www.gutenberg.org/")
            -- Otherwise stay on https if the description came over https.
            if base:find("^https://") then tpl = tpl:gsub("^http://", "https://") end
            return tpl
        end
    end
end

-- Fill in a search address: the words for {searchTerms}, the first page for
-- {startPage}/{startIndex}, and nothing for other (optional) parameters.
function M.search_url(template, words)
    -- Spaces are "+" in a query string, "%20" in a path.
    local in_query = (template:find("?", 1, true) or math.huge) < (template:find("{searchTerms}", 1, true) or 0)
    local q = words:gsub("[^%w%-%._~ ]", function(c) return string.format("%%%02X", c:byte()) end)
        :gsub(" ", in_query and "+" or "%%20")
    return (template:gsub("{([%w:]+)(%??)}", function(name, _)
        if name == "searchTerms" then return q end
        if name == "startPage" or name == "startIndex" then return "1" end
        return ""
    end))
end

-- A file name for a downloaded book: "Title - Author.epub", matching how the
-- library splits titles and authors, without characters FAT/exFAT reject.
function M.file_name(it)
    local function clean(s)
        s = (s or ""):gsub('[%c\\/:%*%?"<>|]', " "):gsub("%s+", " "):gsub("^[%s%.]+", ""):gsub("[%s%.]+$", "")
        -- Keep names comfortably short (bytes), without cutting a UTF-8 character.
        if #s > 90 then
            s = s:sub(1, 90)
            while #s > 0 and s:byte(#s) >= 0x80 and s:byte(#s) < 0xC0 do s = s:sub(1, -2) end
            if #s > 0 and s:byte(#s) >= 0xC0 then s = s:sub(1, -2) end
            s = s:gsub("%s+$", "")
        end
        return s
    end
    local title = clean(it.title)
    if title == "" then title = "Book" end
    -- Only the first author, so the name stays readable.
    local author = clean((it.author or ""):match("^[^,&]+") or "")
    local base = author ~= "" and (title .. " - " .. author) or title
    return base .. "." .. (it.book and it.book.ext or "epub")
end

return M
