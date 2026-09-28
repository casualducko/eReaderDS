-- eReaderDS for the Anbernic RG DS Plus.
-- Hold the device sideways like a book: each screen shows one portrait page.
--
-- The two 1024x768 screens form one 2048x768 window (top screen = x 0..1023,
-- bottom screen = x 1024..2047). Each page is drawn on a 768x1024 canvas and
-- rotated onto its screen.
-- Write log lines immediately, so log.txt is complete even after a crash.
io.stdout:setvbuf("line")

local Book = require("book")
local Layout = require("layout")
local Store = require("store")
local Backlight = require("backlight")
local Fonts = require("fonts")
local Touch = require("touch")
local KeyProbe = require("keyprobe")
local Battery = require("battery")
local Timezone = require("timezone")
local Opds = require("opds")
local VERSION = require("version")

local SCREEN_W, SCREEN_H = 1024, 768
local PAGE_W, PAGE_H = 768, 1024
local UI_SIZE, SMALL_SIZE = 30, 22

-- Reading themes, light to dark. Saved by name.
local THEMES = {
    { name = "Paper",     bg = { 0.965, 0.945, 0.905 }, fg = { 0.13, 0.12, 0.10 }, dim = { 0.50, 0.46, 0.40 }, sel = { 0.87, 0.82, 0.72 } },
    { name = "White",     bg = { 1, 1, 1 },             fg = { 0, 0, 0 },          dim = { 0.45, 0.45, 0.45 }, sel = { 0.85, 0.85, 0.85 } },
    { name = "Sepia",     bg = { 0.957, 0.925, 0.847 }, fg = { 0.357, 0.275, 0.212 }, dim = { 0.60, 0.52, 0.44 }, sel = { 0.88, 0.80, 0.66 } },
    { name = "Solarized", bg = { 0.992, 0.965, 0.890 }, fg = { 0.28, 0.357, 0.384 }, dim = { 0.53, 0.59, 0.59 }, sel = { 0.933, 0.910, 0.835 } },
    { name = "E-ink",     bg = { 0.82, 0.82, 0.81 },    fg = { 0.12, 0.12, 0.12 }, dim = { 0.40, 0.40, 0.40 }, sel = { 0.67, 0.67, 0.66 }, eink = true },
    { name = "Stone",     bg = { 0.890, 0.882, 0.863 }, fg = { 0.17, 0.17, 0.17 }, dim = { 0.47, 0.46, 0.44 }, sel = { 0.80, 0.79, 0.76 } },
    { name = "Sage",      bg = { 0.863, 0.902, 0.831 }, fg = { 0.16, 0.22, 0.15 }, dim = { 0.42, 0.49, 0.40 }, sel = { 0.76, 0.83, 0.72 } },
    { name = "Dusk",      bg = { 0.125, 0.145, 0.192 }, fg = { 0.80, 0.83, 0.88 }, dim = { 0.49, 0.53, 0.60 }, sel = { 0.22, 0.25, 0.32 } },
    { name = "Night",     bg = { 0.07, 0.07, 0.07 },    fg = { 0.78, 0.77, 0.74 }, dim = { 0.45, 0.44, 0.42 }, sel = { 0.22, 0.22, 0.22 } },
    { name = "Amber",     bg = { 0.075, 0.055, 0.035 }, fg = { 0.90, 0.64, 0.33 }, dim = { 0.55, 0.40, 0.22 }, sel = { 0.20, 0.14, 0.08 } },
    { name = "Black",     bg = { 0, 0, 0 },             fg = { 0.62, 0.62, 0.62 }, dim = { 0.36, 0.36, 0.36 }, sel = { 0.16, 0.16, 0.16 } },
}
-- Themes used to be saved as a number (their position in the original list).
-- Listed alphabetically in Settings.
table.sort(THEMES, function(a, b) return a.name:lower() < b.name:lower() end)
local OLD_THEME_NUMBERS = { "Paper", "White", "Sepia", "Night" }
local MARGINS = { { name = "Narrow", outer = 36, inner = 28 }, { name = "Normal", outer = 60, inner = 44 }, { name = "Wide", outer = 90, inner = 64 } }
-- Space above and below the text (the header/footer sit inside it).
local VMARGINS = { { name = "Narrow", size = 60 }, { name = "Normal", size = 76 }, { name = "Wide", size = 110 }, { name = "Extra wide", size = 150 } }

-- Extra dim: a dark layer over both screens for going below the backlight's
-- minimum. Levels 1-3 (reached by going past 1%).
local EXTRA_DIM = { 0.35, 0.55, 0.72 }

local S                      -- settings (persisted)
local app = {
    mode = "library",        -- library | reader | menu | toc | about | message
    dirty = true,
}
local fonts = {}
local ui = {}
local canvases = {}
local old_canvases = {}       -- previous spread, kept during a page-turn animation
local shadow_mesh
-- E-ink look: pages go through a filter that turns them grayscale, mixes in a
-- fixed noise pattern and reduces them to 16 gray levels, like an e-ink panel.
-- The noise makes flat areas speckle between neighbouring grays.
local eink_shader, eink_noise
local EINK_SHADER = [[
extern Image noise;
extern float amount;
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    vec4 c = Texel(tex, tc) * color;
    float g = dot(c.rgb, vec3(0.299, 0.587, 0.114));
    float n = Texel(noise, sc / 256.0).r - 0.5;
    g = clamp(g + n * amount, 0.0, 1.0);
    g = floor(g * 15.0 + 0.5) / 15.0;
    return vec4(vec3(g), c.a);
}
]]
local turn_mesh               -- strip mesh for the page being turned
local TURN_COLS = 24
local book = nil
-- Caches for the open book, kept small (1 GB of RAM): laid-out pages for the
-- few most recent chapters, decoded images for the most recently drawn ones,
-- and image sizes (read from file headers, so layout never decodes images).
local PAGES_KEEP, IMAGES_KEEP = 4, 12
local pages_cache, pages_order = {}, {}
local images, images_order, image_dims = {}, {}, {}
local function clear_pages() pages_cache, pages_order = {}, {} end
local function clear_book_caches()
    for _, img in pairs(images) do if img then img:release() end end
    images, images_order, image_dims = {}, {}, {}
    clear_pages()
end
local pos = { ch = 1, off = 0 }  -- reading position (start of left page)
local spread = nil           -- { ch, pi, pages }
local library = { items = {}, sel = 1, top = 1 }
local menu = { sel = 1 }
local toc = { sel = 1, top = 1 }
local message = nil

---------------------------------------------------------------- utilities

local function theme_index()
    local default = 1
    for i, t in ipairs(THEMES) do
        if t.name == S.theme then return i end
        if t.name == "Sepia" then default = i end   -- the default theme (store.lua)
    end
    return default
end
local function theme() return THEMES[theme_index()] end
local function color(c, a) love.graphics.setColor(c[1], c[2], c[3], a or 1) end
local function redraw() app.dirty = true end

local function fit_text(font, text, w)
    if font:getWidth(text) <= w then return text end
    local utf8 = require("utf8")
    local n = utf8.len(text) or #text
    while n > 0 do
        local cut = text:sub(1, (utf8.offset(text, n + 1) or (#text + 1)) - 1) .. "…"
        if font:getWidth(cut) <= w then return cut end
        n = n - 1
    end
    return "…"
end

local function load_font(file, size)
    local ok, f = pcall(love.graphics.newFont, "fonts/" .. file, size)
    if ok then return f end
    return love.graphics.newFont(size)
end

local function build_fonts()
    local loaded, name = Fonts.load(S.font, S.font_size)
    for k, v in pairs(loaded) do fonts[k] = v end
    fonts.name = name
    clear_pages()
end

local function margins() return MARGINS[S.margins] or MARGINS[2] end
-- With the status bar off, its rows' space goes to the text.
local STATUS_ROW_SPACE = 36
local function vmargin()
    local m = (VMARGINS[S.vmargins] or VMARGINS[2]).size
    return S.sb_show and m or m - STATUS_ROW_SPACE
end
local function content_size()
    local m = margins()
    return PAGE_W - m.outer - m.inner, PAGE_H - vmargin() * 2
end

-- Pages hold whole lines, so the space left under the last line would all end
-- up at the bottom. Shift the text down by half of it so the top and bottom
-- margins match. (Must use the same line height as layout.lua.)
local function text_top()
    local _, h = content_size()
    local lh = math.floor(math.max(fonts.r:getHeight(), S.font_size * 1.4) * S.spacing + 0.5)
    return vmargin() + math.floor((h % lh) / 2)
end

---------------------------------------------------------------- images

-- Decoded image for drawing (least recently used ones are released).
local function get_image(src)
    local img = images[src]
    if img == nil then
        img = false
        local data = book and book:read_resource(src)
        if data then
            local ok, res = pcall(function()
                return love.graphics.newImage(love.filesystem.newFileData(data, src))
            end)
            if ok then img = res end
        end
        images[src] = img
        images_order[#images_order + 1] = src
        if #images_order > IMAGES_KEEP then
            local old = table.remove(images_order, 1)
            if images[old] then images[old]:release() end
            images[old] = nil
        end
    end
    return img or nil
end

-- Width and height from the image file's header (PNG, JPEG, GIF), falling back
-- to decoding. Used by layout, so pages can be laid out without decoding.
local function header_dims(d)
    local function be16(i) local a, b = d:byte(i, i + 1); return a * 256 + b end
    local function be32(i) return be16(i) * 65536 + be16(i + 2) end
    if d:sub(1, 8) == "\137PNG\r\n\26\n" and #d >= 24 then return be32(17), be32(21) end
    if d:sub(1, 4) == "GIF8" and #d >= 10 then
        local w1, w2, h1, h2 = d:byte(7, 10); return w1 + w2 * 256, h1 + h2 * 256
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

local function get_image_size(src)
    local dims = image_dims[src]
    if dims == nil then
        dims = false
        local data = book and book:read_resource(src)
        if data then
            local w, h = header_dims(data)
            if not w then
                local ok, id = pcall(love.image.newImageData, love.filesystem.newFileData(data, src))
                if ok then w, h = id:getDimensions(); id:release() end
            end
            if w and w > 0 and h and h > 0 then dims = { w, h } end
        end
        image_dims[src] = dims
    end
    if dims then return dims[1], dims[2] end
end

---------------------------------------------------------------- pagination

local function pages_for(ch)
    local p = pages_cache[ch]
    if not p then
        local c = book:chapter(ch)
        if not c then return nil end
        local w, h = content_size()
        local breaks = {}
        for _, t in ipairs(book.toc) do
            if t.chapter == ch then breaks[#breaks + 1] = (t.anchor and c.anchors[t.anchor]) or 0 end
        end
        table.sort(breaks)
        local t0 = love.timer.getTime()
        p = Layout.paginate(c, {
            breaks = breaks,
            fonts = fonts, size = S.font_size, w = w, h = h, spacing = S.spacing, justify = S.justify,
            indent = true,
            -- The patterns are English: skip books that say they're in another language.
            hyphenate = S.hyphenate and (not book.language or book.language == "" or book.language:match("^en") ~= nil),
            image_size = get_image_size,
        })
        pages_cache[ch] = p
        pages_order[#pages_order + 1] = ch
        -- Keep the few most recent chapters (never the one on screen).
        while #pages_order > PAGES_KEEP do
            local k = 1
            if spread and pages_order[k] == spread.ch then k = 2 end
            pages_cache[table.remove(pages_order, k)] = nil
        end
        if os.getenv("READER_DEBUG") then
            print(string.format("layout ch=%d pages=%d %.0fms lua=%.0fMB", ch, #p, (love.timer.getTime() - t0) * 1000,
                collectgarbage("count") / 1024))
        end
    end
    return p
end

local function set_spread(ch, pi)
    local pages = pages_for(ch)
    if pi % 2 == 0 then pi = pi - 1 end
    pi = math.max(1, math.min(pi, #pages))
    if pi % 2 == 0 then pi = pi - 1 end
    spread = { ch = ch, pi = pi, pages = pages }
    pos.ch, pos.off = ch, pages[pi].off
    redraw()
end

-- Reading speed, learned from page turns: characters on the spread you just
-- read divided by the time you spent on it. Characters (not pages) keep it
-- valid across fonts and sizes. Quick flips and long pauses are ignored, and
-- anything other than reading forward (jumps, menus, the lid) pauses it.
local SPEED_MIN_S, SPEED_MAX_S = 3, 600
local reading = { since = nil }

local function reading_pause() reading.since = nil end

-- Text offset just past the visible spread.
local function spread_end_off(sp)
    local nxt = sp.pages[sp.pi + 2]
    if nxt then return nxt.off end
    return book.chapters[sp.ch].length or sp.pages[#sp.pages].off
end

local function learn_speed()
    local now = love.timer.getTime()
    if reading.since and app.mode == "reader" then
        local dt = now - reading.since
        local chars = spread_end_off(spread) - spread.pages[spread.pi].off
        if dt >= SPEED_MIN_S and dt <= SPEED_MAX_S and chars > 50 then
            local cps = chars / dt
            S.read_cps = math.max(3, math.min(80, S.read_cps * 0.85 + cps * 0.15))
        end
    end
    reading.since = now
end

local function goto_pos(ch, off)
    reading_pause()                      -- a jump: don't count it as reading
    ch = math.max(1, math.min(ch, #book.chapters))
    local pages = pages_for(ch)
    set_spread(ch, Layout.find_page(pages, off))
end

local save_due = nil          -- time a delayed progress save should happen

local function save_progress()
    save_due = nil
    if book then
        Store.set_progress(book.path, pos.ch, pos.off, book:fraction(pos.ch, pos.off))
    end
end

-- After a page turn, save once the reader pauses, instead of rewriting the
-- progress file on the SD card for every page. The main loop only wakes on its
-- own while it's polling the touchscreen; otherwise save straight away.
local SAVE_DELAY = 2
local function save_progress_soon()
    if Touch.enabled then save_due = love.timer.getTime() + SAVE_DELAY else save_progress() end
end

-- "Go back": where you were before the latest jump (Contents, Bookmarks,
-- Jump to %). Jumping again before reading keeps the original
-- spot. Going back uses it up; it's also forgotten once you've read on a few
-- spreads.
local jump = nil                     -- { ch, off, turns }
local JUMP_FORGET_AFTER = 5          -- spreads

local function remember_jump()
    if not spread then return end
    if jump and jump.turns == 0 then return end
    jump = { ch = pos.ch, off = pos.off, turns = 0 }
end

-- Jump somewhere, remembering where you were so B can go back, unless the
-- jump didn't actually move (e.g. picking the chapter you're already in).
function app.jump_to(ch, off)
    local from = spread and (spread.ch .. ":" .. spread.pi)
    local had = jump
    remember_jump()
    goto_pos(ch, off)
    if jump ~= had and spread and spread.ch .. ":" .. spread.pi == from then jump = had end
    save_progress()
end

local function jump_turned()
    if jump then
        jump.turns = jump.turns + 1
        if jump.turns >= JUMP_FORGET_AFTER then jump = nil end
    end
end

local function go_back()
    if not jump then return false end
    local ch, off = jump.ch, jump.off
    jump = nil
    goto_pos(ch, off)
    save_progress()
    return true
end

local function next_spread()
    if not spread then return end
    learn_speed()
    jump_turned()
    if spread.pi + 2 <= #spread.pages then
        set_spread(spread.ch, spread.pi + 2)
    elseif spread.ch < #book.chapters then
        set_spread(spread.ch + 1, 1)
    else
        return
    end
    save_progress_soon()
end

local function prev_spread()
    if not spread then return end
    reading_pause()
    jump_turned()
    if spread.pi - 2 >= 1 then
        set_spread(spread.ch, spread.pi - 2)
    elseif spread.ch > 1 then
        local pages = pages_for(spread.ch - 1)
        set_spread(spread.ch - 1, #pages)
    else
        return
    end
    save_progress_soon()
end

-- TOC entries with resolved positions (chapter, offset).
local function toc_pos(t)
    if t.off == nil then
        local c = book:chapter(t.chapter)
        t.off = (t.anchor and c.anchors[t.anchor]) or 0
    end
    return t.chapter, t.off
end

local function current_section()
    local best
    for idx, t in ipairs(book.toc) do
        if t.chapter < pos.ch then best = idx
        elseif t.chapter == pos.ch then
            local _, off = toc_pos(t)
            -- a section counts once it starts anywhere on the visible spread
            local limit = spread.pages[spread.pi + 2] and spread.pages[spread.pi + 2].off or math.huge
            if off < limit then best = idx else break end
        else break end
    end
    return best
end

local function jump_section(dir)
    remember_jump()
    if #book.toc == 0 then
        if dir > 0 and pos.ch < #book.chapters then set_spread(pos.ch + 1, 1)
        elseif dir < 0 then set_spread(math.max(1, spread.pi > 1 and pos.ch or pos.ch - 1), 1) end
        save_progress(); return
    end
    local cur = current_section() or 0
    local target
    if dir > 0 then target = book.toc[cur + 1]
    else
        -- go to start of current section, or previous one if already at its start
        local t = book.toc[cur]
        if t then
            local ch, off = toc_pos(t)
            local pages = pages_for(ch)
            local pi = Layout.find_page(pages, off)
            if pi % 2 == 0 then pi = pi - 1 end
            if ch == spread.ch and pi == spread.pi then target = book.toc[cur - 1] else target = t end
        end
    end
    if target then
        goto_pos(toc_pos(target))
        save_progress()
    end
end

---------------------------------------------------------------- footnotes

-- A (or tapping a note number) shows the notes referenced on this spread,
-- one at a time, on the facing page, so the text never moves. Functions live
-- on the table to stay under Lua's local-variable limit.
local note = { refs = {}, sel = 1, page = 1, cache = {} }

-- Which links are note references: marked as such (EPUB 3), or short markers
-- like "1", "[12]", "*", "†" or "[a]" (Gutenberg and most older books).
function note.is_ref(link, text)
    if link.noteref then return true end
    if link.lead or link.backlink or not link.target:find("#") then return false end
    local t = text:gsub("%s", "")
    return t:match("^%[?%(?%d+%)?%]?%.?$") ~= nil
        or t:match("^%[?[%*\226\194]+[\128-\191]*%]?$") ~= nil      -- * † ‡ § ¶
        or t:match("^%[%a%]$") ~= nil
        or (link.sup and #t <= 4)
end

-- Note references on the visible spread, in reading order, with their boxes
-- in page coordinates.
function note.collect()
    local refs, by_link = {}, {}
    local m = margins()
    local oy = text_top()
    for k, side in ipairs({ "left", "right" }) do
        local page = spread.pages[spread.pi + k - 1]
        local ox = side == "left" and m.outer or m.inner
        for _, it in ipairs(page and page.items or {}) do
            if it.kind == "text" and it.link then
                local x, y = ox + it.x, oy + it.y
                local w, h = it.font:getWidth(it.text), it.font:getHeight()
                local r = by_link[it.link]
                if r and r.side == side then
                    r.text = r.text .. it.text
                    r.x2, r.y2 = math.max(r.x2, x + w), math.max(r.y2, y + h)
                elseif not r then
                    r = { link = it.link, side = side, text = it.text, x = x, y = y, x2 = x + w, y2 = y + h }
                    by_link[it.link] = r
                    refs[#refs + 1] = r
                end
            end
        end
    end
    local out = {}
    for _, r in ipairs(refs) do
        if note.is_ref(r.link, r.text) then out[#out + 1] = r end
    end
    return out
end

-- Note references on the spread on screen, worked out once per spread.
function note.on_spread()
    -- Compared by identity (holding the table), so a rebuilt layout never
    -- matches an old one.
    if note.spread_pages ~= spread.pages or note.spread_pi ~= spread.pi then
        note.spread_pages, note.spread_pi, note.spread_refs = spread.pages, spread.pi, note.collect()
    end
    return note.spread_refs
end

-- The "Notes" button at the bottom left of the right page (the touchscreen):
-- x, y, w, h.
function note.button()
    local w, h = ui.small:getWidth("Notes") + 36, ui.small:getHeight() + 10
    -- Sit clear of the progress bar along the bottom edge.
    local bar = (S.sb_show and S.sb_bar ~= "none") and (({ 3, 6, 10 })[S.sb_bar_size] or 6) or 0   -- BAR_PX
    local bottom = PAGE_H - 10 - bar - 8
    return margins().inner - 14, bottom - h, w, h
end

-- The selected note laid out as pages (cached per target).
function note.pages(r)
    local key = book.path .. "|" .. r.link.target .. "|" .. S.font_size .. "|" .. S.font .. "|"
        .. S.spacing .. "|" .. S.margins .. "|" .. tostring(S.justify)
    local p = note.cache[key]
    if p == nil then
        local blocks = book:note(r.link.target)
        if blocks then
            local w, h = content_size()
            p = Layout.paginate({ blocks = blocks }, {
                fonts = fonts, size = S.font_size, w = w, h = h - 60, spacing = S.spacing,
                justify = S.justify, indent = false, image_size = get_image_size,
            })
        else
            p = false
        end
        note.cache = { [key] = p }         -- one note at a time is plenty
    end
    return p or nil
end

-- Open note mode (at a given ref, or the first on the spread).
function note.open(ref)
    note.refs = note.collect()
    if #note.refs == 0 then
        app.toast("No notes on these pages")
        return
    end
    note.sel, note.page = 1, 1
    for i, r in ipairs(note.refs) do
        if ref and r.link == ref.link then note.sel = i end
    end
    reading_pause()
    app.mode = "note"
    redraw()
end

-- The ref (if any) at a touch point on a page.
function note.hit(refs, side, u, v)
    for i, r in ipairs(refs) do
        if r.side == side and u >= r.x - 24 and u <= r.x2 + 24 and v >= r.y - 20 and v <= r.y2 + 20 then
            return r, i
        end
    end
end

---------------------------------------------------------------- dictionary

-- Y (or pressing and holding a word on the touchscreen) puts a cursor on a
-- word; its definition shows on the facing page. Left/right move word by
-- word, up/down line by line, across both pages.
local look = { words = {}, sel = 1, page = 1, fonts = nil, dict = require("dict") }

-- The words on the visible spread, in reading order: { side, text, line,
-- x, y, x2, y2 } in page coordinates. Pieces of one word (a note number
-- after it, a change of style) are joined.
function look.collect()
    local words, line = {}, 0
    local m = margins()
    local oy = text_top()
    for k, side in ipairs({ "left", "right" }) do
        local page = spread.pages[spread.pi + k - 1]
        local ox = side == "left" and m.outer or m.inner
        local prev, prev_x, prev_base
        for _, it in ipairs(page and page.items or {}) do
            if it.kind == "text" then
                local x, y = ox + it.x, oy + it.y
                local w, h = it.font:getWidth(it.text), it.font:getHeight()
                -- A new line: the text moved down (superscripts sit a little
                -- higher, so allow for that) or back to the left.
                local base = y + it.font:getBaseline()
                if not prev_x or x < prev_x or math.abs(base - prev_base) > h * 0.6 then
                    line = line + 1; prev = nil
                end
                prev_x = x
                if not prev then prev_base = base end
                if prev and x <= prev.x2 + 1 then
                    prev.text = prev.text .. it.text
                    prev.x2, prev.y, prev.y2 = x + w, math.min(prev.y, y), math.max(prev.y2, y + h)
                else
                    prev = { side = side, text = it.text, line = line, x = x, y = y, x2 = x + w, y2 = y + h }
                    words[#words + 1] = prev
                end
            end
        end
    end
    -- Only things worth looking up (not dashes or note numbers).
    local out = {}
    for _, w in ipairs(words) do
        if w.text:find("%a") or w.text:find("[\195-\201]") then out[#out + 1] = w end
    end
    return out
end

-- Look up the selected word. A word split by hyphenation at the end of a
-- line is joined back together first.
function look.find()
    local w = look.words[look.sel]
    if not w then look.results = {}; return end
    local tries = { w.text }
    local nxt, prv = look.words[look.sel + 1], look.words[look.sel - 1]
    if w.text:sub(-1) == "-" and nxt and nxt.line == w.line + 1 then
        table.insert(tries, 1, w.text:sub(1, -2) .. nxt.text)
        table.insert(tries, 2, w.text .. nxt.text)
    elseif prv and prv.text:sub(-1) == "-" and prv.line == w.line - 1 then
        table.insert(tries, 1, prv.text:sub(1, -2) .. w.text)
        table.insert(tries, 2, prv.text .. w.text)
    end
    -- Hyphenated compounds with no entry of their own: their parts.
    for part in look.dict.clean(w.text):gmatch("[^%-\226]+") do
        if part:find("%a") then tries[#tries + 1] = part end
    end
    look.results, look.word = {}, look.dict.clean(w.text)
    for _, t in ipairs(tries) do
        local r = look.dict.lookup(t, look.only())
        if #r > 0 then look.results, look.word = r, look.dict.clean(t); break end
    end
    look.page = 1
    look.pages = nil
end

-- Definitions laid out as pages, in a slightly smaller size of the reading font.
function look.layout()
    if look.pages then return look.pages end
    local size = math.max(18, math.floor(S.font_size * 0.8))
    if not look.fonts or look.fonts_key ~= S.font .. size then
        look.fonts = Fonts.load(S.font, size)
        look.fonts_key = S.font .. size
    end
    local blocks = {}
    for _, r in ipairs(look.results) do
        local off = #blocks
        blocks[#blocks + 1] = { kind = "text", heading = 1, off = 0,
            runs = { { text = r.word, i = false, b = true, off = 0 } } }
        local body
        -- Symbols the reading fonts lack (small squares used as bullets).
        local text = r.text:gsub("\226\150[\170\171\160\161]", "•")
        -- Some entries are huge (a big dictionary's "run" is 600 KB): show
        -- the start, cut at a paragraph so the markup stays whole.
        local LIMIT = 16000
        local cut = #text > LIMIT
        if cut then
            local last
            for pos in text:sub(1, LIMIT):gmatch("()</[pP]>") do last = pos end
            if not last then
                for pos in text:sub(1, LIMIT):gmatch("()</blockquote>") do last = pos end
            end
            text = text:sub(1, last and last - 1 or LIMIT):gsub("<[^>]*$", "")
        end
        if r.type == "h" or r.type == "g" or r.type == "x" then
            if cut then text = text .. "<p><i>(The rest of this entry is too long to show.)</i></p>" end
            body = Book.parse_html("<body>" .. text .. "</body>", "", {})
        else
            body = {}
            for para in (text .. "\n"):gmatch("([^\n]*)\n") do
                if para:find("%S") then
                    body[#body + 1] = { kind = "text", off = 0, runs = { { text = para, i = false, b = false, off = 0 } } }
                end
            end
        end
        for _, b in ipairs(body) do
            if b.kind == "text" then b.center, b.list = nil, nil end
            blocks[#blocks + 1] = b
        end
    end
    local w, h = content_size()
    look.pages = Layout.paginate({ blocks = blocks }, {
        fonts = look.fonts, size = size, w = w, h = h - 60, spacing = 1.0,
        justify = false, indent = false, image_size = function() return nil end,
    })
    return look.pages
end

-- Find dictionaries (once): Ebook/Dictionaries first, then the built-in one.
function look.scan()
    if look.dict.list then return look.dict.list end
    local dirs = {}
    for _, d in ipairs(Store.book_dirs()) do dirs[#dirs + 1] = d .. "/Dictionaries" end
    dirs[#dirs + 1] = love.filesystem.getSource() .. "/dict"
    return look.dict.scan(dirs)
end

-- The dictionary chosen in Settings (nil = all of them).
function look.only()
    if S.dict == "all" then return nil end
    for _, d in ipairs(look.scan()) do if d.name == S.dict then return d.name end end
    return nil                              -- it's been removed: use all
end

function look.open(word)
    look.scan()
    look.words = look.collect()
    if #look.words == 0 then app.toast("No words on these pages"); return end
    look.sel = 1
    for i, w in ipairs(look.words) do
        if word and w.side == word.side and w.x == word.x and w.y == word.y then look.sel = i end
    end
    look.find()
    reading_pause()
    app.mode = "lookup"
    redraw()
end

-- Move the cursor: by words (left/right) or to the nearest word on the
-- line above or below (up/down).
function look.move(a)
    local ws, cur = look.words, look.words[look.sel]
    if a == "left" or a == "right" then
        look.sel = math.max(1, math.min(#ws, look.sel + (a == "right" and 1 or -1)))
    else
        local target = cur.line + (a == "down" and 1 or -1)
        -- Lines with no words (images, blank) are skipped.
        local best, best_d
        for _ = 1, 20 do
            for i, w in ipairs(ws) do
                if w.line == target then
                    local d = math.abs((w.x + w.x2) / 2 - (cur.x + cur.x2) / 2)
                    if w.side ~= cur.side then d = math.abs(w.x - cur.x) end
                    if not best_d or d < best_d then best, best_d = i, d end
                end
            end
            if best then break end
            target = target + (a == "down" and 1 or -1)
        end
        if best then look.sel = best end
    end
    look.find()
end

-- The word (if any) at a touch point.
function look.hit(side, u, v)
    for i, w in ipairs(look.words) do
        if w.side == side and u >= w.x - 6 and u <= w.x2 + 6 and v >= w.y - 6 and v <= w.y2 + 6 then return w, i end
    end
end

---------------------------------------------------------------- bookmarks

-- A bookmark is a position in the text (chapter + offset), so it survives
-- changes to the font or layout. A spread counts as bookmarked when a bookmark
-- falls anywhere on it.
local bm = { sel = 1, top = nil, from = "reader" }   -- Bookmarks screen state

local function bookmark_here()
    if not book or not spread then return nil end
    local first = spread.pages[spread.pi].off
    local nxt = spread.pages[spread.pi + 2]
    local last = nxt and nxt.off or math.huge
    for i, b in ipairs(Store.get_bookmarks(book.path)) do
        if b.ch == spread.ch and b.off >= first and b.off < last then return i end
    end
end

-- The first words on the left page, to recognise the bookmark by.
local function page_snippet()
    local words, n = {}, 0
    for _, it in ipairs(spread.pages[spread.pi].items) do
        if it.kind == "text" then
            words[#words + 1] = it.text
            n = n + #it.text
            if n > 80 then break end
        end
    end
    return table.concat(words, " ")
end

local function toggle_bookmark()
    if not book or not spread then return end
    local list = {}
    for _, b in ipairs(Store.get_bookmarks(book.path)) do list[#list + 1] = b end
    local here = bookmark_here()
    if here then
        table.remove(list, here)
    else
        local sec = current_section()
        list[#list + 1] = { ch = pos.ch, off = pos.off, pct = book:fraction(pos.ch, pos.off),
            title = sec and book.toc[sec].title or book.title, snippet = page_snippet() }
    end
    Store.set_bookmarks(book.path, list)
    if app.toast then app.toast(here and "Bookmark removed" or "Bookmark added") end
    redraw()
end

local function open_bookmarks(from)
    bm.sel, bm.top, bm.from = 1, nil, from
    app.mode = "bookmarks"
    redraw()
end

---------------------------------------------------------------- opening books

local function show_message(text)
    message = text
    app.mode = "message"
    redraw()
end

local function open_book(path)
    library.confirm = nil
    local ok, b, err = pcall(Book.open, path)
    if not ok or not b then
        show_message("Could not open this book.\n\n" .. tostring(ok and err or b))
        return
    end
    if book and book ~= b then book:close() end
    jump = nil
    book = b
    clear_book_caches()
    local pr = Store.get_progress(path)
    app.mode = "reader"
    if pr then goto_pos(pr.ch, pr.off) else goto_pos(1, 0) end
    Store.set_last(path)
    Store.set_opened(path)
    save_progress()
end

-- Library order, chosen with left/right in the library.
local SORTS = { "recent", "title", "author", "progress" }
local SORT_NAMES = { recent = "Recent", title = "Title", author = "Author", progress = "Progress" }

-- "The Hobbit" sorts under H; authors sort by last name.
local function title_key(t) return (t:lower():gsub("^the%s+", ""):gsub("^an?%s+", "")) end
local function author_key(a)
    a = (a or ""):lower():match("^[^,&]+") or ""
    a = a:gsub("%s+$", "")
    return a:match("(%S+)$") or ""
end

function library.sort(items)
    local mode = S.lib_sort
    local key = {}
    for _, it in ipairs(items) do
        local k = { title = title_key(it.title) }
        if mode == "recent" then
            k.t = Store.get_opened(it.path) or 0
        elseif mode == "author" then
            k.a = author_key(it.author)
        elseif mode == "progress" then
            -- Books you're reading (most read first), then unread, then finished.
            local pr = Store.get_progress(it.path)
            local pct = pr and pr.pct or 0
            k.group = (pct >= 0.99 and 3) or (pct > 0 and 1) or 2
            k.pct = pct
        end
        key[it] = k
    end
    table.sort(items, function(a, b)
        local x, y = key[a], key[b]
        if mode == "recent" and x.t ~= y.t then return x.t > y.t end
        if mode == "author" and x.a ~= y.a then
            if x.a == "" or y.a == "" then return y.a == "" end   -- no author: last
            return x.a < y.a
        end
        if mode == "progress" then
            if x.group ~= y.group then return x.group < y.group end
            if x.pct ~= y.pct then return x.pct > y.pct end
        end
        return x.title < y.title
    end)
end

-- Get books state (see "get books (OPDS)" below); declared here so the
-- library scan can see whether a download is running.
local net = { thread = nil, next_id = 0, handlers = {}, count = 0 }
-- The "Get books" screen. Its functions live on the table to stay under
-- Lua's limit on local variables.
local shop = { catalog = nil, stack = {}, covers = {}, cover_order = {}, dl = nil }

-- Is the device on a network? Connected Wi-Fi gives the system a default
-- route, so this reads /proc/net/route (checked at most every 2 seconds).
-- Where that file doesn't exist (a computer), assume yes.
function shop.online(fresh)
    local now = love.timer.getTime()
    if not fresh and shop.online_at and now - shop.online_at < 2 then return shop.online_v end
    local v = true
    if os.getenv("READER_OFFLINE") then
        v = false
    else
        local f = io.open("/proc/net/route", "rb")
        if f then
            v = false
            for line in f:lines() do
                local iface, dest = line:match("^(%S+)%s+(%x+)")
                if dest == "00000000" and iface ~= "lo" then v = true end
            end
            f:close()
        end
    end
    shop.online_at, shop.online_v = now, v
    return v
end

local function scan_library()
    local items = {}
    local seen = {}
    for _, dir in ipairs(Store.book_dirs()) do
        local p = io.popen('ls -1 "' .. dir .. '" 2>/dev/null')
        if p then
            for name in p:lines() do
                local ext = (name:match("%.([^.]+)$") or ""):lower()
                -- Left over from a download that was cut off.
                if ext == "part" and not shop.dl then os.remove(dir .. "/" .. name) end
                if (ext == "epub" or ext == "txt") and not name:match("^%._") then
                    local path = dir .. "/" .. name
                    if not seen[path] then
                        seen[path] = true
                        local base = name:gsub("%.[^.]+$", "")
                        local title, author = base:match("^(.-)%s+%-%s+(.+)$")
                        items[#items + 1] = { path = path, title = title or base, author = author or "" }
                    end
                end
            end
            p:close()
        end
    end
    library.sort(items)
    -- Online catalogs from opds.txt, for "Get books" (Select, or the button
    -- on the right page).
    local ok, catalogs, opts = pcall(Opds.load_catalogs, Store.data_path("opds.txt"))
    if not ok then print("[opds] " .. tostring(catalogs)); catalogs, opts = {}, {} end
    if opts.gutenberg ~= false then
        for _, c in ipairs(Opds.BUILT_IN) do catalogs[#catalogs + 1] = c end
    end
    library.catalogs = catalogs
    library.items = items
    library.sel = math.max(1, math.min(library.sel, #items))
end

-- Change the order, keeping the same book selected.
function library.cycle_sort(d)
    local cur = library.items[library.sel]
    local i = 1
    for k, v in ipairs(SORTS) do if v == S.lib_sort then i = k end end
    S.lib_sort = SORTS[(i - 1 + d) % #SORTS + 1]
    Store.save_settings(S)
    scan_library()
    for k, it in ipairs(library.items) do
        if it.path and cur and it.path == cur.path then library.sel = k end
    end
    library.top = 1
end

-- Title, author and cover for the selected book, cached so moving through the
-- library doesn't reopen books (a few most recent are kept).
local previews, preview_order = {}, {}
local function library_preview()
    local it = library.items[library.sel]
    if not it then return nil end
    if previews[it.path] then return previews[it.path] end
    local pv = { path = it.path }
    local ok, b = pcall(Book.open, it.path)
    if ok and b then
        pv.title, pv.author = b.title, b.author
        if b.cover then
            local data = b:read_resource(b.cover)
            if data then
                local ok2, img = pcall(function()
                    return love.graphics.newImage(love.filesystem.newFileData(data, b.cover))
                end)
                if ok2 then pv.cover = img end
            end
        end
        if b ~= book then b:close() end
    end
    previews[it.path] = pv
    preview_order[#preview_order + 1] = it.path
    if #preview_order > 6 then previews[table.remove(preview_order, 1)] = nil end
    return pv
end

-- Delete a book file (Y in the library, then A to confirm).
function library.delete(path)
    if book and book.path == path then save_progress() end
    local ok, err = os.remove(path)
    if not ok then
        show_message("Could not delete this book.\n\n" .. tostring(err))
        return
    end
    if book and book.path == path then
        book:close()
        book, jump, spread = nil, nil, nil
        clear_book_caches()
    end
    previews[path] = nil
    Store.forget(path)
    Store.flush()
    scan_library()
    app.toast("Book deleted")
end

-- The "Get books" button on the library's right page: x, y, w, h.
function library.get_books_button()
    local w, h = 340, 60
    return math.floor((PAGE_W - w) / 2), PAGE_H - 96, w, h
end

local function go_library()
    save_progress()
    Store.flush()
    scan_library()
    for i, it in ipairs(library.items) do
        if book and it.path == book.path then library.sel = i end
    end
    app.mode = "library"
    redraw()
end

---------------------------------------------------------------- get books (OPDS)

-- Network jobs run on a thread (networker.lua); replies are dispatched here
-- from the main loop by job id.

function shop.net_job(job, handler)
    if not net.thread then
        net.thread = love.thread.newThread("networker.lua")
        net.thread:start()
    end
    net.next_id = net.next_id + 1
    job.id = net.next_id
    net.handlers[job.id] = handler
    net.count = net.count + 1
    love.thread.getChannel("net_jobs"):push(job)
    return job.id
end

function shop.net_poll()
    if net.count == 0 then return false end
    local got = false
    local out = love.thread.getChannel("net_out")
    while true do
        local msg = out:pop()
        if not msg then break end
        got = true
        local h = net.handlers[msg.id]
        if msg.kind ~= "progress" and h then
            net.handlers[msg.id] = nil
            net.count = net.count - 1
        end
        if h then h(msg) end
    end
    if net.thread and not net.thread:isRunning() and net.count > 0 then
        -- The thread died (a bug): fail whatever was waiting.
        local err = net.thread:getError() or "network thread stopped"
        print("[net] " .. err)
        net.thread = nil
        -- Don't let a new thread pick up the old jobs or replies.
        love.thread.getChannel("net_jobs"):clear()
        love.thread.getChannel("net_out"):clear()
        love.thread.getChannel("net_cancel"):clear()
        for id, h in pairs(net.handlers) do h({ id = id, kind = "error", message = err }) end
        net.handlers, net.count = {}, 0
        got = true
    end
    if got then redraw() end
    return got
end

-- Catalog pages browsed into: { title, url, entries, next, sel, top,
-- loading, error, more }. The last one is on screen.

function shop.page() return shop.stack[#shop.stack] end

function shop.catalog_opts(job)
    local c = shop.catalog
    job.user, job.password, job.verify = c.user, c.password, c.verify
    return job
end

function shop.load_page(pg, url, append)
    pg.loading, pg.error = true, nil
    pg.retry = { url = url, append = append }      -- what A retries if this fails
    shop.net_job(shop.catalog_opts({ kind = "fetch", url = url }), function(msg)
        pg.loading = false
        if msg.kind == "error" then
            pg.error = shop.online(true) and msg.message or "Not connected to Wi-Fi."
            return
        end
        local ok, feed = pcall(Opds.parse_feed, msg.body, msg.url or url)
        if not ok then pg.error = tostring(feed):gsub("^[^:]*:%d+: ", ""); return end
        -- Gutenberg's search results start with "Authors" and "Subjects"
        -- lists that its server refuses to apps (403); leave them out.
        for k = #feed.entries, 1, -1 do
            local h = feed.entries[k].href or ""
            if h:find("gutenberg%.org/ebooks/[%a]+/search%.opds") and not feed.entries[k].book then
                table.remove(feed.entries, k)
            end
        end
        if append then
            for _, e in ipairs(feed.entries) do pg.entries[#pg.entries + 1] = e end
        else
            pg.entries = feed.entries
            pg.search, pg.search_osd = feed.search, feed.search_osd
            if pg.root and (pg.search or pg.search_osd) then
                table.insert(pg.entries, 1, { title = "Search", author = "Titles and authors", formats = {},
                    search = true, summary = "Type a few words from a book's title or its author's name." })
            end
        end
        pg.next = feed.next
        pg.sel = math.max(1, math.min(pg.sel, #pg.entries))
        pg.top = math.max(1, math.min(pg.top, pg.sel))
    end)
end

function shop.push_page(title, url, root)
    local pg = { title = title, url = url, entries = {}, sel = 1, top = 1, root = root }
    shop.stack[#shop.stack + 1] = pg
    shop.load_page(pg, url)
    redraw()
end

function shop.open(catalog)
    shop.catalog = catalog
    shop.stack = {}
    app.mode = "shop"
    shop.push_page(catalog.name, catalog.url, true)
end

-- "Get books" from the library: a list of catalogs (yours from opds.txt,
-- then the free built-in ones), and how to add your own.
function shop.start()
    library.confirm = nil
    if not shop.online(true) then
        app.toast("Not connected to Wi-Fi")
        return
    end
    shop.dir = nil
    for url, c in pairs(shop.covers) do if c == false then shop.covers[url] = nil end end
    local entries = {}
    for _, c in ipairs(library.catalogs or {}) do
        local u = Opds.parse_url(c.url)
        entries[#entries + 1] = { title = c.name, author = u and u.host or "", summary = c.about or "",
            formats = {}, catalog = c }
    end
    entries[#entries + 1] = { title = "Add a catalog", author = "Calibre, Calibre-Web or any OPDS server",
        formats = {}, info = true, summary = "Get books from your own library over Wi-Fi. Edit "
            .. Store.books_folder() .. "/.ereaderds/opds.txt"
            .. (select(2, Store.books_folder()) and " on the SD card" or "") .. " (it has examples), for example:\n\n"
            .. "name = Calibre\nurl = http://192.168.1.20:8080/opds\nuser = me\npassword = secret" }
    shop.stack = { { title = "Get books", entries = entries, sel = 1, top = 1 } }
    app.mode = "shop"
    redraw()
end

-- Is this book already in the library (same file name, or same title)?
-- Worked out once per entry (it's drawn every frame) and cached in
-- it.have: a path, or false.
function shop.have(it)
    if not it.book then return nil end
    if it.have ~= nil then return it.have or nil end
    shop.dir = shop.dir or Store.download_dir()
    local path = shop.dir .. "/" .. Opds.file_name(it)
    local f = io.open(path, "rb")
    if f then f:close(); it.have = path; return path end
    -- Or a book with the same title and author (either may lack the author).
    local t = it.title:lower()
    local a = ((it.author or ""):match("^[^,&]+") or ""):lower():gsub("%s+$", "")
    for _, b in ipairs(library.items) do
        local ba = (b.author or ""):lower()
        if b.path and b.title:lower() == t and (a == "" or ba == "" or ba == a) then
            it.have = b.path
            return b.path
        end
    end
    it.have = false
end

-- Cover for the selected entry, fetched when the network is idle.
function shop.cover(it)
    local url = it and it.cover
    if not url then return nil end
    local c = shop.covers[url]
    if c ~= nil then return c or nil end
    if url:match("^data:") then
        -- Small images embedded in the feed itself (base64).
        local ok, img = pcall(function()
            local data = love.data.decode("string", "base64", url:match("^data:[^,]*;base64,(.*)$"))
            return love.graphics.newImage(love.filesystem.newFileData(data, "cover"))
        end)
        shop.covers[url] = ok and img or false
        shop.cover_order[#shop.cover_order + 1] = url
        if #shop.cover_order > 12 then shop.covers[table.remove(shop.cover_order, 1)] = nil end
        return ok and img or nil
    end
    if net.count == 0 then
        shop.covers[url] = false
        shop.net_job(shop.catalog_opts({ kind = "fetch", url = url }), function(msg)
            -- Failed or huge (decoding happens here, on the UI thread): no cover.
            if msg.kind ~= "done" or #msg.body > 4000000 then return end
            local ok, img = pcall(function()
                return love.graphics.newImage(love.filesystem.newFileData(msg.body, "cover"))
            end)
            if not ok then return end
            shop.covers[url] = img
            shop.cover_order[#shop.cover_order + 1] = url
            if #shop.cover_order > 12 then shop.covers[table.remove(shop.cover_order, 1)] = nil end
        end)
    end
end

function shop.start_download(it)
    shop.dir = shop.dir or Store.download_dir()
    local dest = shop.dir .. "/" .. Opds.file_name(it)
    local dl = { item = it, got = 0, total = it.book.size or 0, dest = dest }
    shop.dl = dl
    dl.id = shop.net_job(shop.catalog_opts({ kind = "download", url = it.book.href, dest = dest, size = it.book.size }), function(msg)
        if msg.kind == "progress" then
            dl.got, dl.total = msg.got, msg.total
        elseif msg.kind == "done" then
            shop.dl = nil
            it.have = dest
            Store.flush()
            scan_library()
        else
            shop.dl = nil
            if msg.message ~= "cancelled" then
                it.failed = shop.online(true) and msg.message or "not connected to Wi-Fi"
            end
        end
    end)
end

function shop.back()
    if shop.dl then
        love.thread.getChannel("net_cancel"):push(shop.dl.id)
        return
    end
    table.remove(shop.stack)
    if #shop.stack == 0 then
        scan_library()
        app.mode = "library"
    end
end

function shop.confirm()
    local pg = shop.page()
    if not pg then return end
    if pg.error and (#pg.entries == 0 or not (pg.entries[pg.sel] or {}).book) then
        local r = pg.retry or (pg.url and { url = pg.url })
        if r then shop.load_page(pg, r.url, r.append) end
        return
    end
    local it = pg.entries[pg.sel]
    if not it then return end
    if it.book then
        if shop.dl then return end
        local have = it.have or shop.have(it)
        if have then open_book(have) else it.failed = nil; shop.start_download(it) end
    elseif it.catalog then
        shop.catalog = it.catalog
        shop.push_page(it.catalog.name, it.catalog.url, true)
    elseif it.search then
        app.kb_open({ title = "Search " .. shop.catalog.name, text = shop.last_query,
            hint = "Words from a book's title or its author's name.",
            submit = function(q) shop.search(pg, q) end })
    elseif it.href then
        shop.push_page(it.title, it.href)
    end
end

-- Search the catalog: its search address, or the one in its OpenSearch
-- description (fetched once per catalog). The results are a catalog page.
function shop.search(pg, q)
    shop.last_query = q
    local c = shop.catalog
    local title = "“" .. q .. "”"
    local tpl = pg.search or c.search_tpl
    if tpl then shop.push_page(title, Opds.search_url(tpl, q)); return end
    local res = { title = title, entries = {}, sel = 1, top = 1, loading = true }
    shop.stack[#shop.stack + 1] = res
    shop.net_job(shop.catalog_opts({ kind = "fetch", url = pg.search_osd }), function(msg)
        local found = msg.kind ~= "error" and Opds.search_template(msg.body or "", msg.url or pg.search_osd)
        if not found then
            res.loading = false
            res.error = msg.kind == "error" and msg.message or "This catalog's search can't be used."
            return
        end
        c.search_tpl = found
        res.url = Opds.search_url(found, q)
        shop.load_page(res, res.url)
    end)
    redraw()
end

function shop.move(d)
    local pg = shop.page()
    if not pg or #pg.entries == 0 then return end
    pg.sel = math.max(1, math.min(#pg.entries, pg.sel + d))
    -- Reaching the end of a long list loads the next part.
    if pg.sel >= #pg.entries - 2 and pg.next and not pg.loading and not pg.error then
        local url = pg.next
        pg.next = nil
        pg.more = true
        shop.load_page(pg, url, true)
    end
end

---------------------------------------------------------------- menu

-- Status bar option values, in cycling order.
local SB = {
    title = { "none", "book", "chapter", "both" },
    pages = { "hide", "left", "of" },
    bar = { "none", "chapter", "book" },
    bar_size = { 1, 2, 3 },
    clock = { "off", "12", "24" },
    time = { "off", "chapter", "book", "both" },
}
local SB_NAMES = {
    title = { none = "None", book = "Book", chapter = "Chapter", both = "Both" },
    pages = { hide = "Hide", left = "Pages left", of = "Page X of Y" },
    bar = { none = "None", chapter = "Chapter", book = "Book" },
    bar_size = { [1] = "Thin", [2] = "Medium", [3] = "Thick" },
    clock = { off = "Off", ["12"] = "12-hour", ["24"] = "24-hour" },
    time = { off = "Off", chapter = "Chapter", book = "Book", both = "Both" },
}

-- Current time for the status bar, or nil when the clock is off.
local function clock_text()
    if S.sb_clock == "12" then
        local h = tonumber(os.date("%I"))
        return string.format("%d:%s %s", h, os.date("%M"), os.date("%p"))
    elseif S.sb_clock == "24" then
        return os.date("%H:%M")
    end
end
local BAR_PX = { 3, 6, 10 }

local function cycle(list, cur, d)
    local idx = 1
    for k, v in ipairs(list) do if v == cur then idx = k end end
    return list[(idx - 1 + d) % #list + 1]
end

-- Tags each item with its section; the menu draws a header where the section
-- changes ("" = a small gap with no header, nil = no header at the top).
local function section(name, items)
    for _, it in ipairs(items) do it.section = name end
    return items
end

local function join(...)
    local out = {}
    for _, list in ipairs({ ... }) do
        for _, it in ipairs(list) do out[#out + 1] = it end
    end
    return out
end

local function relayout() clear_pages(); goto_pos(pos.ch, pos.off) end

-- Time left is stored as one setting (off / chapter / book / both) but shown
-- as two Show/Hide rows.
-- Time left is only shown for the chapter: it's worked out from the text on
-- the pages, while a whole-book estimate had to guess at chapters not yet
-- opened and was often well off. The book shows its percentage instead.
local function time_shown(which)
    return which == "chapter" and (S.sb_time == "chapter" or S.sb_time == "both")
end
local function set_time_shown(which, on)
    if which == "chapter" then S.sb_time = on and "chapter" or "off" end
end

local function status_items()
    return join(
        section(nil, {
            { label = "Show status bar", value = S.sb_show and "On" or "Off", adjust = function()
                S.sb_show = not S.sb_show
                relayout()                          -- the text area changes size
            end },
        }),
        section("Top of page", {
            { label = "Title", value = SB_NAMES.title[S.sb_title], adjust = function(d)
                S.sb_title = cycle(SB.title, S.sb_title, d) end },
            { label = "Clock", value = SB_NAMES.clock[S.sb_clock], adjust = function(d)
                S.sb_clock = cycle(SB.clock, S.sb_clock, d) end },
            { label = "Time zone", value = S.tz, adjust = function(d)
                S.tz = cycle(Timezone.NAMES, S.tz, d)
                Timezone.apply(S.tz)
            end },
            { label = "Battery", value = Battery.get() and (S.sb_battery and "Show" or "Hide") or "n/a",
              adjust = function() S.sb_battery = not S.sb_battery end },
        }),
        section("Bottom of page", {
            { label = "Chapter pages", value = SB_NAMES.pages[S.sb_pages], adjust = function(d)
                S.sb_pages = cycle(SB.pages, S.sb_pages, d) end },
            { label = "Chapter time left", value = time_shown("chapter") and "Show" or "Hide", adjust = function()
                set_time_shown("chapter", not time_shown("chapter")) end },
            { label = "Book percentage", value = S.sb_percent and "Show" or "Hide", adjust = function()
                S.sb_percent = not S.sb_percent end },
            { label = "Progress bar", value = SB_NAMES.bar[S.sb_bar], adjust = function(d)
                S.sb_bar = cycle(SB.bar, S.sb_bar, d) end },
            { label = "Bar thickness", value = SB_NAMES.bar_size[S.sb_bar_size], adjust = function(d)
                S.sb_bar_size = cycle(SB.bar_size, S.sb_bar_size, d) end },
        }),
        section("", {
            { label = "Back", act = function() menu.page = "main"; menu.sel = menu.parent_row or 1; menu.top = nil end },
        })
    )
end

-- Open a sub-page of Settings (and come back to the same row with B).
local function open_sub(page)
    menu.parent_row = menu.sel; menu.page = page; menu.sel = 1; menu.top = nil
end

local function close_sub()
    menu.page = "main"; menu.sel = menu.parent_row or 1; menu.top = nil
end

-- Settings you set once: page turns, the lid, and About.
local function more_items()
    return join(
        section("Page turns", {
            { label = "Animation", value = ({ flip = "Flip", fade = "Fade", off = "Off" })[S.anim] or "Flip",
              adjust = function(d) S.anim = cycle({ "flip", "fade", "off" }, S.anim, d) end },
            { label = "Tap", value = S.tap == "next" and "Turn pages" or "Open menu", adjust = function()
                S.tap = S.tap == "next" and "menu" or "next"
            end },
        }),
        section("Look up", {
            { label = "Dictionary", value = look.only() or "All", adjust = function(d)
                local names = { "all" }
                for _, x in ipairs(look.scan()) do names[#names + 1] = x.name end
                S.dict = cycle(names, look.only() or "all", d)
            end },
        }),
        section("Device", {
            { label = "Closing the lid", value = S.lid == "sleep" and "Sleep" or "Screen off", adjust = function()
                S.lid = S.lid == "sleep" and "screen" or "sleep"; S.lid_failed = nil
            end },
        }),
        section("", {
            { label = "About", act = function() app.mode = "about" end },
            { label = "Back", act = close_sub },
        })
    )
end

local function menu_items()
    if menu.page == "status" then return status_items() end
    if menu.page == "more" then return more_items() end
    local th = theme()
    return join(
        section(nil, {
            { label = "Contents", act = function()
                if #book.toc == 0 then return end
                toc.sel = current_section() or 1
                toc.top = nil
                app.mode = "toc"
            end },
            { label = "Bookmarks", value = tostring(#Store.get_bookmarks(book.path)),
              act = function() open_bookmarks("menu") end },
            { label = "Find in book", act = function() app.find_open() end },
            { label = "Jump to %", value = "Currently " .. math.floor(book:fraction(pos.ch, pos.off) * 100 + 0.5) .. "%",
              act = function() app.open_jump() end },
            { label = "Library", act = go_library },
        }),
        section("Text", {
            -- The font's name is drawn in the font itself: a preview, and the only way
            -- names in other scripts (e.g. Chinese firmware fonts) can display.
            { label = "Font", value = fonts.name or S.font,
              value_font = Fonts.preview(fonts.name or S.font, UI_SIZE),
              act = function() app.font_open() end },     -- the font picker spread
            { label = "Text size", value = tostring(S.font_size), adjust = function(d)
                S.font_size = math.max(18, math.min(64, S.font_size + d * 2)); build_fonts(); goto_pos(pos.ch, pos.off)
            end },
            { label = "Line spacing", value = string.format("%.2f", S.spacing), adjust = function(d)
                S.spacing = math.floor(math.max(0.75, math.min(2.0, S.spacing + d * 0.05)) * 100 + 0.5) / 100
                relayout()
            end },
            { label = "Justify text", value = S.justify and "On" or "Off", adjust = function()
                S.justify = not S.justify; relayout()
            end },
            { label = "Hyphenation", value = S.hyphenate and "On" or "Off", adjust = function()
                S.hyphenate = not S.hyphenate; relayout()
            end },
        }),
        section("Page", {
            { label = "Margins", value = margins().name, adjust = function(d)
                S.margins = (S.margins - 1 + d) % #MARGINS + 1; relayout()
            end },
            { label = "Top/bottom margins", value = (VMARGINS[S.vmargins] or VMARGINS[2]).name, adjust = function(d)
                S.vmargins = (S.vmargins - 1 + d) % #VMARGINS + 1; relayout()
            end },
            { label = "Theme", value = th.name, adjust = function(d)
                S.theme = THEMES[(theme_index() - 1 + d) % #THEMES + 1].name
            end },
            { label = "Brightness",
              value = S.extra_dim > 0 and ("Extra dim " .. S.extra_dim)
                  or (Backlight.available() and ((S.brightness >= 0 and S.brightness or Backlight.get() or 0) .. "%") or "n/a"),
              adjust = function(d)
                  local avail = Backlight.available()
                  local cur = S.brightness >= 0 and S.brightness or (avail and Backlight.get()) or 50
                  if d < 0 and (S.extra_dim > 0 or not avail or cur <= 1) then
                      -- Past the backlight's minimum: extra dim levels.
                      S.extra_dim = math.min(#EXTRA_DIM, S.extra_dim + 1)
                      if avail and cur > 1 then S.brightness = 1; Backlight.set(1) end
                  elseif d > 0 and S.extra_dim > 0 then
                      S.extra_dim = S.extra_dim - 1
                  elseif avail then
                      S.brightness = Backlight.step(cur, d)
                      Backlight.set(S.brightness)
                  end
              end },
        }),
        section("", {
            { label = "Status bar", value = "›", act = function() open_sub("status") end },
            { label = "Page turns & device", value = "›", act = function() open_sub("more") end },
            { label = "Help", act = function() app.mode = "help" end },
            { label = "Quit", act = function() love.event.quit() end },
        })
    )
end

---------------------------------------------------------------- drawing

local function draw_page(page, side, top)
    local th = theme()
    local m = margins()
    local ox = side == "left" and m.outer or m.inner
    local oy = top or text_top()
    if not page then return end
    for _, it in ipairs(page.items) do
        if it.kind == "text" then
            color(th.fg)
            love.graphics.setFont(it.font)
            love.graphics.print(it.text, ox + it.x, oy + it.y)
        elseif it.kind == "image" then
            local img = get_image(it.src)
            if img then
                love.graphics.setColor(1, 1, 1)
                local iw, ih = img:getDimensions()
                love.graphics.draw(img, ox + it.x, oy + it.y, 0, it.w / iw, it.h / ih)
            end
        elseif it.kind == "rule" then
            color(th.dim)
            love.graphics.setLineWidth(2)
            love.graphics.line(ox + it.x, oy + it.y, ox + it.x + it.w, oy + it.y)
        end
    end
end

-- y for print() so a line of text looks vertically centered in a box.
-- Uses the baseline and cap height rather than the font's line box, which
-- includes descender space and makes text sit low.
local function centered_y(font, size, top, height)
    local mid = font:getBaseline() - size * 0.34     -- visual middle of the text
    return math.floor(top + height / 2 - mid + 0.5)
end

local RIBBON_ROOM = 60        -- title space kept clear for the bookmark ribbon

-- Small battery icon with the percentage; returns its width. x is the left edge.
local function draw_battery(x, y, b, measure)
    local label = b.pct .. "%"
    local bw, bh = 30, 15
    local w = bw + 4 + 8 + ui.small:getWidth(label)
    if measure then return w end
    local th = theme()
    local by = y + math.floor((ui.small:getHeight() - bh) / 2)
    color(th.dim)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", x, by, bw, bh, 3, 3)
    love.graphics.rectangle("fill", x + bw, by + 4, 3, bh - 8)
    local fill = math.max(2, math.floor((bw - 6) * b.pct / 100))
    love.graphics.rectangle("fill", x + 3, by + 3, fill, bh - 6, 1, 1)
    if b.charging then
        color(th.bg)
        local cx, cy = x + bw / 2, by + bh / 2
        love.graphics.polygon("fill", cx + 2, cy - 7, cx - 4, cy + 1, cx, cy + 1, cx - 2, cy + 7, cx + 4, cy - 1, cx, cy - 1)
    end
    love.graphics.setFont(ui.small)
    color(th.dim)
    love.graphics.print(label, x + bw + 12, y)
    return w
end

-- Status bar for one page. info: { book_title, chapter_title, pages_text,
-- percent_text, bar_frac, battery }
local function draw_status(side, info)
    if not S.sb_show then return end
    local th = theme()
    local m = margins()
    local outer_x = side == "left" and m.outer or m.inner
    local w = PAGE_W - m.outer - m.inner
    local head_y, foot_y = 26, PAGE_H - 26 - ui.small:getHeight()
    love.graphics.setFont(ui.small)

    -- Top row. Left page: title, battery by the hinge. Right page: clock by
    -- the hinge, title, and the outer corner kept clear for the bookmark
    -- ribbon when there is one. The title fits in [title_x, title_x + title_w].
    local title_x, title_w = outer_x, w
    if side == "left" and info.battery then
        local bw = draw_battery(0, 0, info.battery, true)
        draw_battery(outer_x + w - bw, head_y, info.battery)
        title_w = title_w - bw - 24
    elseif side == "right" then
        if info.clock then
            color(th.dim)
            love.graphics.print(info.clock, outer_x, head_y)
            local cw = ui.small:getWidth(info.clock) + 24
            title_x, title_w = title_x + cw, title_w - cw
        end
        if info.marked then title_w = title_w - RIBBON_ROOM end
    end

    -- Titles: the left page shows the book title (or the chapter title when
    -- only the chapter is chosen); with both, the chapter goes on the right.
    local t = S.sb_title
    local title
    if side == "left" then
        if t == "book" or t == "both" then title = info.book_title
        elseif t == "chapter" then title = info.chapter_title end
    elseif t == "both" then
        title = info.chapter_title
    end
    if title and title ~= "" then
        love.graphics.setFont(ui.small)
        color(th.dim)
        love.graphics.printf(fit_text(ui.small, title, title_w), title_x, head_y, title_w,
            side == "left" and "left" or "right")
    end

    color(th.dim)
    love.graphics.setFont(ui.small)
    if side == "left" and info.pages_text then
        love.graphics.printf(info.pages_text, outer_x, foot_y, w, "left")
    elseif side == "right" and info.percent_text then
        love.graphics.printf(info.percent_text, outer_x, foot_y, w, "right")
    end

    -- Progress bar: one continuous ribbon along the bottom of both pages.
    if info.bar_frac then
        local h = BAR_PX[S.sb_bar_size] or BAR_PX[2]
        local y = PAGE_H - 10 - h
        local x0 = side == "left" and m.outer or 0
        local x1 = side == "left" and PAGE_W or PAGE_W - m.outer
        local total = (PAGE_W - m.outer) * 2
        local done = info.bar_frac * total
        local here = side == "left" and done or done - (PAGE_W - m.outer)
        color(th.dim, 0.25)
        love.graphics.rectangle("fill", x0, y, x1 - x0, h)
        if here > 0 then
            color(th.fg, 0.75)
            love.graphics.rectangle("fill", x0, y, math.min(x1 - x0, here), h)
        end
    end
end

-- "4 h 10 min", or compact "4h 10m".
local function format_time(seconds, compact)
    local H, M = compact and "h" or " h", compact and "m" or " min"
    local m = seconds / 60
    if m < 1 then return "<1" .. M end
    if m < 60 then return string.format("%d%s", math.floor(m + 0.5), M) end
    local h = math.floor(m / 60)
    local mm = math.floor(m - h * 60 + 0.5)
    if mm == 60 then h, mm = h + 1, 0 end
    return mm > 0 and string.format("%d%s %d%s", h, H, mm, M) or string.format("%d%s", h, H)
end

-- Characters left in the book after offset `off` of chapter `ch`. Chapters
-- not opened yet are estimated from their file size, scaled by how much of the
-- file turned out to be text in the chapters already opened.
local function draw_reader_pages()
    local sec = current_section()
    local frac = book:fraction(pos.ch, pos.off)
    local left, right = spread.pages[spread.pi], spread.pages[spread.pi + 1]
    local pages = spread.pages

    -- The current section's page range within this chapter file.
    local first, last = 1, #pages
    local cur = sec and book.toc[sec]
    if cur and cur.chapter == spread.ch then
        local _, off = toc_pos(cur)
        first = Layout.find_page(pages, off)
    end
    local nxt = sec and book.toc[sec + 1] or (not sec and book.toc[1])
    if nxt and nxt.chapter == spread.ch then
        local _, off = toc_pos(nxt)
        local p = Layout.find_page(pages, off)
        if pages[p].off == off and p > first then last = p - 1 else last = p end
    end
    local shown = math.min(spread.pi + 1, #pages)

    local info = {
        book_title = book.title,
        chapter_title = cur and cur.title or "",
        battery = S.sb_battery and Battery.get() or nil,
        clock = clock_text(),
    }
    if S.sb_pages == "left" then
        local remaining = last - shown
        if remaining > 0 then
            info.pages_text = remaining == 1 and "1 page left in chapter" or (remaining .. " pages left in chapter")
        end
    elseif S.sb_pages == "of" then
        info.pages_text = string.format("Page %d of %d", math.max(1, spread.pi - first + 1), math.max(1, last - first + 1))
    end
    if S.sb_percent then
        info.percent_text = string.format("%d%% read", math.floor(frac * 100 + 0.5))
    end
    -- Time left, from the learned reading speed.
    local end_off = spread_end_off(spread)
    if S.sb_time == "chapter" or S.sb_time == "both" then
        local section_end = book.chapters[spread.ch].length or end_off
        if nxt and nxt.chapter == spread.ch then section_end = select(2, toc_pos(nxt)) end
        local left = section_end - end_off
        if left > 0 then
            local t = format_time(left / S.read_cps, true)
            info.pages_text = info.pages_text and (info.pages_text .. " (" .. t .. ")") or (t .. " left in chapter")
        end
    end
    if S.sb_bar == "book" then
        info.bar_frac = frac
    elseif S.sb_bar == "chapter" then
        info.bar_frac = math.max(0, math.min(1, (shown - first + 1) / math.max(1, last - first + 1)))
    end

    info.marked = bookmark_here() ~= nil
    return function(side)
        if side == "left" then
            draw_page(left, "left")
        else
            draw_page(right, "right")
            if app.mode == "reader" and #note.on_spread() > 0 then
                -- Notes on this spread: a button to show them (same as A).
                local bx, by, bw, bh = note.button()
                local th = theme()
                color(th.sel)
                love.graphics.rectangle("fill", bx, by, bw, bh, bh / 2, bh / 2)
                love.graphics.setFont(ui.small)
                color(th.fg)
                love.graphics.printf("Notes", bx, centered_y(ui.small, SMALL_SIZE, by, bh), bw, "center")
            end
            if info.marked then
                -- A ribbon hanging in the top-right corner, where a tap removes it.
                local w, h = 24, 66
                local x = PAGE_W - 30 - w
                love.graphics.setColor(0.72, 0.22, 0.20, 0.95)
                love.graphics.polygon("fill", x, 0, x + w, 0, x + w, h, x + w / 2, h - 10, x, h)
            end
        end
        draw_status(side, info)
        if side == "right" and jump then
            -- Replaces the bottom-right status text while a jump can be undone.
            local m = margins()
            local w = PAGE_W - m.outer - m.inner
            local y = PAGE_H - 26 - ui.small:getHeight()
            local th = theme()
            love.graphics.setFont(ui.small)
            color(th.bg)
            love.graphics.rectangle("fill", m.inner + w * 0.35, y - 2, w * 0.65, ui.small:getHeight() + 4)
            color(th.fg)
            love.graphics.printf(string.format("‹ Back to %d%%  (B)", math.floor(book:fraction(jump.ch, jump.off) * 100 + 0.5)),
                m.inner, y, w, "right")
        end
    end
end

local function draw_list(side, items, sel, first, rows, x, y, w, row_h, render)
    local th = theme()
    for r = 0, rows - 1 do
        local idx = first + r
        local it = items[idx]
        if not it then break end
        local ry = y + r * row_h
        if idx == sel then
            color(th.sel)
            love.graphics.rectangle("fill", x - 14, ry, w + 28, row_h - 4, 10, 10)
        end
        render(it, idx, x, ry, w, idx == sel)
    end
end

local function list_rows(row_h) return math.floor((PAGE_H - 200) / row_h) end

local function draw_library(side)
    local th = theme()
    local m = MARGINS[2]
    if side == "left" then
        local x, w = m.outer, PAGE_W - m.outer - m.inner
        love.graphics.setFont(ui.title)
        color(th.fg)
        love.graphics.print("Library", x, 60)
        if #library.items > 0 then
            -- The sort order, changed with left/right, like a settings value.
            love.graphics.setFont(ui.font)
            color(th.dim)
            love.graphics.printf("‹ " .. SORT_NAMES[S.lib_sort] .. " ›", x,
                60 + ui.title:getBaseline() - ui.font:getBaseline(), w, "right")
        end
        local row_h = 96
        local rows = list_rows(row_h)
        if #library.items == 0 then
            love.graphics.setFont(ui.font)
            color(th.dim)
            local folder, where = Store.books_folder()
            love.graphics.printf("No books found.\n\nCopy .epub or .txt files into the " .. folder
                .. " folder" .. (where and (" " .. where) or "") .. ".", x, 180, w, "left")
            love.graphics.setFont(ui.small)
            love.graphics.print("Press the Anbernic button to quit", x, PAGE_H - 70)
            love.graphics.printf("v" .. VERSION, x, PAGE_H - 70, w, "right")
            return
        end
        if library.sel < library.top then library.top = library.sel end
        if library.sel >= library.top + rows then library.top = library.sel - rows + 1 end
        draw_list(side, library.items, library.sel, library.top, rows, x, 160, w, row_h, function(it, _, rx, ry, rw)
            love.graphics.setFont(ui.font)
            color(th.fg)
            -- Center the title + author block: from the title's cap height to
            -- the author's baseline.
            local top = ui.font:getBaseline() - UI_SIZE * 0.68
            local bottom = 40 + ui.small:getBaseline()
            local ty = math.floor(ry + (row_h - 4) / 2 - (top + bottom) / 2 + 0.5)
            love.graphics.print(fit_text(ui.font, it.title, rw - 90), rx, ty)
            local pr = it.path and Store.get_progress(it.path)
            love.graphics.setFont(ui.small)
            color(th.dim)
            love.graphics.print(fit_text(ui.small, it.author, rw - 90), rx, ty + 40)
            if pr then
                love.graphics.printf(math.floor(pr.pct * 100 + 0.5) .. "%", rx,
                    ty + ui.font:getBaseline() - ui.small:getBaseline(), rw, "right")
            end
        end)
        love.graphics.setFont(ui.small)
        color(th.dim)
        love.graphics.print("A  open      Y  delete      ‹ ›  sort" .. (book and "      B  back" or ""), x, PAGE_H - 70)
        love.graphics.printf("v" .. VERSION, x, PAGE_H - 70, w, "right")
    else
        local x, w = MARGINS[2].inner, PAGE_W - MARGINS[2].outer - MARGINS[2].inner
        -- "Get books" button at the bottom of the touchscreen (also Select).
        local bx, by, bw, bh = library.get_books_button()
        local online = shop.online()
        if online then
            color(th.sel)
            love.graphics.rectangle("fill", bx, by, bw, bh, bh / 2, bh / 2)
        else
            -- Offline: an outline only, greyed out, saying why.
            color(th.dim, 0.5)
            love.graphics.setLineWidth(2)
            love.graphics.rectangle("line", bx, by, bw, bh, bh / 2, bh / 2)
        end
        love.graphics.setFont(ui.font)
        local label, hint = "Get books", online and "   Select" or "   No Wi-Fi"
        local lx = bx + (bw - ui.font:getWidth(label) - ui.small:getWidth(hint)) / 2
        local ly = centered_y(ui.font, UI_SIZE, by, bh)
        color(online and th.fg or th.dim, online and 1 or 0.6)
        love.graphics.print(label, lx, ly)
        love.graphics.setFont(ui.small)
        color(th.dim)
        love.graphics.print(hint, lx + ui.font:getWidth(label), ly + ui.font:getBaseline() - ui.small:getBaseline())
        local pv = library_preview()
        if not pv then return end
        local y = 80
        local confirming = library.confirm == pv.path
        if pv.cover and not confirming then
            local iw, ih = pv.cover:getDimensions()
            local s = math.min(w / iw, 520 / ih)
            love.graphics.setColor(1, 1, 1)
            love.graphics.draw(pv.cover, x + (w - iw * s) / 2, y, 0, s, s)
            y = y + ih * s + 40
        else
            y = 260
        end
        love.graphics.setFont(ui.title)
        color(th.fg)
        love.graphics.printf(pv.title or "", x, y, w, "center")
        local _, lines = ui.title:getWrap(pv.title or "", w)
        y = y + #lines * ui.title:getHeight() + 12
        love.graphics.setFont(ui.font)
        color(th.dim)
        love.graphics.printf(pv.author or "", x, y, w, "center")
        local pr = Store.get_progress(pv.path)
        if pr then
            y = y + 60
            local bw = w * 0.6
            local bx = x + (w - bw) / 2
            color(th.sel)
            love.graphics.rectangle("fill", bx, y, bw, 8, 4, 4)
            color(th.fg)
            love.graphics.rectangle("fill", bx, y, bw * pr.pct, 8, 4, 4)
            love.graphics.setFont(ui.small)
            color(th.dim)
            love.graphics.printf(math.floor(pr.pct * 100 + 0.5) .. "% read", x, y + 20, w, "center")
        end
        if confirming then
            local by = PAGE_H - 330
            color(th.sel)
            love.graphics.rectangle("fill", x - 14, by, w + 28, 150, 12, 12)
            love.graphics.setFont(ui.font)
            color(th.fg)
            love.graphics.printf("Delete this book from the SD card?", x, by + 28, w, "center")
            love.graphics.setFont(ui.small)
            love.graphics.printf("A  delete      B  keep", x, by + 90, w, "center")
        end
    end
end

function shop.format_size(n)
    if not n or n <= 0 then return nil end
    if n >= 1048576 then return string.format("%.1f MB", n / 1048576) end
    return math.max(1, math.floor(n / 1024 + 0.5)) .. " KB"
end

-- Print wrapped text into at most max_h pixels, ending with "…" if cut.
function shop.print_clipped(font, text, x, y, w, max_h, align)
    local _, lines = font:getWrap(text, w)
    local n = math.max(0, math.floor(max_h / font:getHeight()))
    if #lines > n then
        lines = { unpack(lines, 1, n) }
        if n > 0 then lines[n] = fit_text(font, lines[n] .. "…", w) end
    end
    love.graphics.printf(table.concat(lines, "\n"), x, y, w, align or "left")
    return #lines * font:getHeight()
end

function shop.draw(side)
    local th = theme()
    local m = MARGINS[2]
    local pg = shop.page()
    if not pg then return end
    local it = pg.entries[pg.sel]
    if side == "left" then
        local x, w = m.outer, PAGE_W - m.outer - m.inner
        love.graphics.setFont(ui.title)
        color(th.fg)
        love.graphics.print(fit_text(ui.title, pg.title, w), x, 60)
        love.graphics.setFont(ui.small)
        color(th.dim)
        local footer = "A open      B back"
        if #pg.entries == 0 then
            love.graphics.setFont(ui.font)
            local text = pg.loading and "Loading…"
                or pg.error and ("Couldn't load this page:\n" .. pg.error)
                or "Nothing here."
            love.graphics.printf(text, x, 180, w, "left")
            if pg.error then footer = "A try again      B back" end
        else
            local row_h = 96
            local rows = list_rows(row_h)
            if pg.sel < pg.top then pg.top = pg.sel end
            if pg.sel >= pg.top + rows then pg.top = pg.sel - rows + 1 end
            draw_list(side, pg.entries, pg.sel, pg.top, rows, x, 160, w, row_h, function(e, _, rx, ry, rw)
                local sub = e.author ~= "" and e.author or e.summary
                local size = e.book and shop.format_size(e.book.size)
                if size then sub = (sub ~= "" and (sub .. "  ·  ") or "") .. size end
                local top = ui.font:getBaseline() - UI_SIZE * 0.68
                local bottom = (sub ~= "" and 40 + ui.small:getBaseline()) or ui.font:getBaseline()
                local ty = math.floor(ry + (row_h - 4) / 2 - (top + bottom) / 2 + 0.5)
                local mark
                if e.book then
                    mark = (shop.dl and shop.dl.item == e) and "…"
                        or (e.have or shop.have(e)) and "✓" or nil
                elseif e.href or e.catalog then
                    mark = "›"
                end
                love.graphics.setFont(ui.font)
                color((e.book or e.href or e.catalog) and th.fg or th.dim)
                love.graphics.print(fit_text(ui.font, e.title, rw - 60), rx, ty)
                if mark then love.graphics.printf(mark, rx, ty, rw, "right") end
                if sub ~= "" then
                    love.graphics.setFont(ui.small)
                    color(th.dim)
                    love.graphics.print(fit_text(ui.small, sub, rw - 60), rx, ty + 40)
                end
            end)
            love.graphics.setFont(ui.small)
            color(th.dim)
            if pg.loading then footer = "Loading more…"
            elseif pg.error then footer = "Couldn't load more. A try again"
            elseif shop.dl then footer = "B cancel download" end
        end
        love.graphics.setFont(ui.small)
        color(th.dim)
        love.graphics.print(footer, x, PAGE_H - 70)
        if #pg.entries > 0 then
            love.graphics.printf(pg.sel .. " / " .. #pg.entries .. (pg.next and "+" or ""), x, PAGE_H - 70, w, "right")
        end
        return
    end

    -- Right page: the selected entry.
    if not it then return end
    local x, w = m.inner, PAGE_W - m.outer - m.inner
    local y = 70
    local cover = shop.cover(it)
    if cover and cover:getWidth() < 64 then cover = nil end    -- a menu icon, not a cover
    if cover then
        local iw, ih = cover:getDimensions()
        local s = math.min(w / iw, 440 / ih)
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(cover, x + (w - iw * s) / 2, y, 0, s, s)
        y = y + ih * s + 30
    elseif it.book then
        y = 160
    else
        y = 260
    end
    love.graphics.setFont(ui.title)
    color(th.fg)
    y = y + shop.print_clipped(ui.title, it.title, x, y, w, ui.title:getHeight() * 2, "center") + 6
    if it.author ~= "" then
        love.graphics.setFont(ui.font)
        color(th.dim)
        y = y + shop.print_clipped(ui.font, it.author, x, y, w, ui.font:getHeight(), "center") + 10
    end

    -- Status and action, pinned near the bottom; the summary fills the gap.
    local status, action_text, frac
    if it.book then
        local dl = shop.dl
        if dl and dl.item == it then
            frac = dl.total > 0 and math.min(1, dl.got / dl.total) or nil
            status = "Downloading…  " .. (shop.format_size(dl.got) or "0 KB")
                .. (dl.total > 0 and (" of " .. shop.format_size(dl.total)) or "")
            action_text = "B cancel"
        elseif it.have or shop.have(it) then
            status = "On your SD card"
            action_text = "A read now"
        elseif it.failed then
            status = "Download failed: " .. it.failed
            action_text = "A try again"
        else
            local size = shop.format_size(it.book.size)
            status = it.book.ext:upper() .. (size and ("  ·  " .. size) or "")
            action_text = dl and "Another download is running" or "A download"
        end
    elseif #it.formats > 0 then
        status = "Only as " .. table.concat(it.formats, ", ") .. ".\nThis reader needs EPUB or TXT."
    elseif it.href or it.catalog then
        action_text = "A open"
    elseif it.search then
        action_text = "A search"
    end

    local bottom = PAGE_H - 70
    local foot_y = bottom
    love.graphics.setFont(ui.small)
    if action_text then
        color(th.fg)
        love.graphics.printf(action_text, x, foot_y, w, "center")
        foot_y = foot_y - 50
    end
    if frac then
        local bw = w * 0.7
        local bx = x + (w - bw) / 2
        color(th.sel)
        love.graphics.rectangle("fill", bx, foot_y + 20, bw, 8, 4, 4)
        color(th.fg)
        if bw * frac >= 8 then love.graphics.rectangle("fill", bx, foot_y + 20, bw * frac, 8, 4, 4) end
        foot_y = foot_y - 30
    end
    if status then
        color(th.dim)
        local _, lines = ui.small:getWrap(status, w)
        local h = math.min(3, #lines) * ui.small:getHeight()
        foot_y = foot_y - h + ui.small:getHeight()
        shop.print_clipped(ui.small, status, x, foot_y, w, h, "center")
        foot_y = foot_y - 20
    end
    if it.summary ~= "" and it.summary ~= it.title then
        love.graphics.setFont(ui.small)
        color(th.fg)
        shop.print_clipped(ui.small, it.summary, x, y + 16, w, foot_y - y - 40, (it.book or it.info) and "left" or "center")
    end
end

-- Settings list geometry. Items are grouped under small section headers;
-- item rows shrink (down to a minimum) so everything fits, and if it still
-- doesn't, the list scrolls with the selection.
local MENU_TOP, MENU_BOTTOM = 140, PAGE_H - 78
local MENU_ROW_MAX, MENU_ROW_MIN = 52, 36
local MENU_HEADER_H, MENU_GAP_H = 27, 10

-- Returns the visible rows ({ kind = "item"|"header"|"gap", y, h, idx, text })
-- plus whether there is more above / below.
local function menu_layout(items)
    local rows, extra = {}, 0
    for i, it in ipairs(items) do
        if i > 1 and it.section ~= items[i - 1].section or (i == 1 and it.section and it.section ~= "") then
            if it.section and it.section ~= "" then
                rows[#rows + 1] = { kind = "header", text = it.section, h = MENU_HEADER_H }
            else
                rows[#rows + 1] = { kind = "gap", h = MENU_GAP_H }
            end
            extra = extra + rows[#rows].h
        end
        rows[#rows + 1] = { kind = "item", idx = i }
    end
    local avail = MENU_BOTTOM - MENU_TOP
    local row_h = math.max(MENU_ROW_MIN, math.min(MENU_ROW_MAX, math.floor((avail - extra) / #items)))
    local sel_r = 1
    for r, row in ipairs(rows) do
        if row.kind == "item" then row.h = row_h end
        if row.idx == menu.sel then sel_r = r end
    end
    -- Scroll so the selection (with its header, if any) stays in view.
    local top = menu.top or 1
    if sel_r < top then top = sel_r end
    if top > 1 and rows[top - 1].kind ~= "item" and top - 1 == sel_r - 1 then top = top - 1 end
    local function height(from, to)
        local h = 0
        for r = from, to do h = h + rows[r].h end
        return h
    end
    while height(top, sel_r) > avail do top = top + 1 end
    menu.top = top
    local visible, y = {}, MENU_TOP
    local last = top - 1
    for r = top, #rows do
        if y + rows[r].h > MENU_TOP + avail then break end
        local row = rows[r]
        row.y = y
        visible[#visible + 1] = row
        y = y + row.h
        last = r
    end
    return visible, top > 1, last < #rows
end

local function scroll_arrow(x, y, up)
    local s = 9
    if up then love.graphics.polygon("fill", x - s, y + s, x + s, y + s, x, y - s + 2)
    else love.graphics.polygon("fill", x - s, y - s, x + s, y - s, x, y + s - 2) end
end

local function draw_menu_panel(side)
    local th = theme()
    local m = MARGINS[2]
    local x, w = m.inner, PAGE_W - m.outer - m.inner
    love.graphics.setFont(ui.title)
    color(th.fg)
    love.graphics.print(({ status = "Status bar", more = "Page turns & device" })[menu.page] or "Settings", x, 60)
    love.graphics.setFont(ui.small)
    color(th.dim)
    love.graphics.printf("v" .. VERSION, x, 78, w, "right")
    local items = menu_items()
    local visible, more_up, more_down = menu_layout(items)
    if more_up then color(th.dim); scroll_arrow(x + w / 2, MENU_TOP - 14, true) end
    if more_down then
        local last = visible[#visible]
        color(th.dim); scroll_arrow(x + w / 2, last.y + last.h + 8, false)
    end
    for _, row in ipairs(visible) do
        if row.kind == "header" then
            -- Section header: small dimmed capitals and a hairline.
            love.graphics.setFont(ui.small)
            color(th.dim)
            local label = row.text:upper()
            local ty = row.y + row.h - ui.small:getHeight() - 2
            love.graphics.print(label, x, ty)
            local lx = x + ui.small:getWidth(label) + 14
            local ly = ty + math.floor(ui.small:getHeight() * 0.55)
            color(th.dim, 0.45)
            love.graphics.setLineWidth(1)
            love.graphics.line(lx, ly, x + w, ly)
        elseif row.kind == "item" then
            local it = items[row.idx]
            local ry, row_h, rx, rw = row.y, row.h, x, w
            if row.idx == menu.sel then
                color(th.sel)
                love.graphics.rectangle("fill", x - 14, ry, w + 28, row_h - 4, 10, 10)
            end
            love.graphics.setFont(ui.font)
            color(th.fg)
            local ty = centered_y(ui.font, UI_SIZE, ry, row_h - 4)
            love.graphics.print(it.label, rx, ty)
            local vf = it.value_font
            if vf and it.value and it.value ~= "" and vf:hasGlyphs(it.value) then
                local room = rw - ui.font:getWidth(it.label) - 40
                -- "‹ name ›" when left/right change it; "name ›" when it opens a page.
                local open, close = it.adjust and "‹  " or "", "  ›"
                local name = fit_text(vf, it.value, room - ui.font:getWidth(open .. close))
                local right = rx + rw
                local cw, nw = ui.font:getWidth(close), vf:getWidth(name)
                love.graphics.print(close, right - cw, ty)
                love.graphics.print(open, right - cw - nw - ui.font:getWidth(open), ty)
                love.graphics.setFont(vf)
                love.graphics.print(name, right - cw - nw, centered_y(vf, UI_SIZE, ry, row_h - 4))
                love.graphics.setFont(ui.font)
            elseif it.value and it.value ~= "" then
                local room = rw - ui.font:getWidth(it.label) - 40
                local v = it.value
                if it.adjust then
                    v = "‹  " .. fit_text(ui.font, v, room - ui.font:getWidth("‹    ›")) .. "  ›"
                end
                love.graphics.printf(v, rx, ty, rw, "right")
            elseif it.adjust then
                love.graphics.printf("‹  ›", rx, ty, rw, "right")
            end
        end
    end
    love.graphics.setFont(ui.small)
    color(th.dim)
    love.graphics.printf("A select    ‹ › change    B back", x, PAGE_H - 70, w, "left")
end

-- Box around the selected note number.
function note.highlight(r)
    local th = theme()
    color(th.fg, 0.85)
    love.graphics.setLineWidth(3)
    love.graphics.rectangle("line", r.x - 6, r.y - 2, r.x2 - r.x + 12, r.y2 - r.y + 4, 6, 6)
end

-- The note itself, on the page facing its number.
function note.draw_panel(side)
    local th = theme()
    local r = note.refs[note.sel]
    local m = margins()
    local ox = side == "left" and m.outer or m.inner
    local w = PAGE_W - m.outer - m.inner
    local top = text_top()
    love.graphics.setFont(ui.small)
    color(th.dim)
    local head = "Note " .. r.text:gsub("^%s+", ""):gsub("%s+$", "")
    if #note.refs > 1 then head = head .. "   ·   " .. note.sel .. " of " .. #note.refs end
    love.graphics.print(head, ox, top - 6)
    love.graphics.setLineWidth(1)
    love.graphics.line(ox, top + 30, ox + w, top + 30)
    local pages = note.pages(r)
    if not pages then
        love.graphics.setFont(ui.font)
        color(th.dim)
        love.graphics.printf("This note couldn't be found in the book.", ox, top + 60, w, "left")
    else
        note.page = math.max(1, math.min(note.page, #pages))
        draw_page(pages[note.page], side, top + 60)
    end
    love.graphics.setFont(ui.small)
    color(th.dim)
    local hint = (#note.refs > 1 and "‹ ›  other notes      " or "") .. "B  close"
    if pages and #pages > 1 then
        hint = "up/down  page " .. note.page .. " of " .. #pages .. "      " .. hint
    end
    love.graphics.print(hint, ox, PAGE_H - 26 - ui.small:getHeight())
end

-- The definition, on the page facing the selected word.
function look.draw_panel(side)
    local th = theme()
    local m = margins()
    local ox = side == "left" and m.outer or m.inner
    local w = PAGE_W - m.outer - m.inner
    local top = text_top()
    love.graphics.setFont(ui.small)
    color(th.dim)
    local r = look.results[1]
    love.graphics.print(r and r.dict or "Dictionary", ox, top - 6)
    love.graphics.setLineWidth(1)
    love.graphics.line(ox, top + 30, ox + w, top + 30)
    local pages
    if #look.results == 0 then
        love.graphics.setFont(ui.font)
        color(th.dim)
        local msg = #(look.dict.list or {}) == 0
            and ("No dictionary found. Put StarDict dictionaries in " .. Store.books_folder() .. "/Dictionaries.")
            or ("No entry for “" .. look.word .. "”.")
        love.graphics.printf(msg, ox, top + 60, w, "left")
    else
        pages = look.layout()
        look.page = math.max(1, math.min(look.page, #pages))
        draw_page(pages[look.page], side, top + 50)
    end
    love.graphics.setFont(ui.small)
    color(th.dim)
    local hint = "‹ ›  word      up/down  line      B  close"
    if pages and #pages > 1 then hint = "A  more (" .. look.page .. "/" .. #pages .. ")     " .. hint end
    love.graphics.print(hint, ox, PAGE_H - 26 - ui.small:getHeight())
end

local function draw_toc(side)
    local th = theme()
    local m = MARGINS[2]
    local x = side == "left" and m.outer or m.inner
    local w = PAGE_W - m.outer - m.inner
    local row_h = 58
    local rows = list_rows(row_h)
    -- two columns: left page then right page
    if not toc.top then toc.top = math.max(1, toc.sel - rows) end
    if toc.sel < toc.top then toc.top = toc.sel end
    if toc.sel >= toc.top + rows * 2 then toc.top = toc.sel - rows * 2 + 1 end
    local first = side == "left" and toc.top or toc.top + rows
    if side == "left" then
        love.graphics.setFont(ui.title)
        color(th.fg)
        love.graphics.print("Contents", x, 60)
    end
    draw_list(side, book.toc, toc.sel, first, rows, x, 160, w, row_h, function(it, _, rx, ry, rw)
        love.graphics.setFont(ui.font)
        color(th.fg)
        local indent = math.max(0, (it.depth or 1) - 1) * 28
        love.graphics.print(fit_text(ui.font, it.title, rw - indent), rx + indent,
            centered_y(ui.font, UI_SIZE, ry, row_h - 4))
    end)
end

---------------------------------------------------------------- jump picker

-- Choose a percentage first, then jump once. Left/right: 1%, up/down: 10%, or
-- drag the bar on the touchscreen.
local jp = { pct = 0 }
local JP_BAR_Y = 560
local function jp_bar()
    local m = MARGINS[2]
    return m.inner + 12, PAGE_W - m.outer - m.inner - 24     -- x, width on the right page
end

function app.open_jump()
    jp.pct = math.floor(book:fraction(pos.ch, pos.off) * 100 + 0.5)
    jp.here = jp.pct
    app.mode = "jump"
    redraw()
end

-- Chapter title near a whole-book fraction, without laying anything out:
-- find the chapter file by size, then the closest Contents entry.
local function section_title_at(frac)
    local target = frac * book.total
    local i = #book.chapters
    for k, c in ipairs(book.chapters) do
        if target < c.start + c.weight then i = k; break end
    end
    local c = book.chapters[i]
    local within = math.max(0, math.min(1, (target - c.start) / math.max(1, c.weight)))
    local best, in_file = nil, {}
    for idx, t in ipairs(book.toc) do
        if t.chapter < i then best = idx
        elseif t.chapter == i then in_file[#in_file + 1] = idx end
    end
    if #in_file > 0 then
        if c.length then
            -- Chapter already opened: use real offsets.
            local off = within * c.length
            for _, idx in ipairs(in_file) do
                local _, toff = toc_pos(book.toc[idx])
                if toff <= off then best = idx end
            end
        else
            -- Otherwise assume the entries are spread evenly through the file.
            local k = math.floor(within * #in_file) + 1
            if within > 0 or not best then best = in_file[math.min(k, #in_file)] end
        end
    end
    return best and book.toc[best].title or book.title
end

local function draw_jump_panel()
    local th = theme()
    local m = MARGINS[2]
    local x, w = m.inner, PAGE_W - m.outer - m.inner
    love.graphics.setFont(ui.title)
    color(th.fg)
    love.graphics.print("Jump to", x, 60)
    love.graphics.setFont(ui.big)
    love.graphics.printf(jp.pct .. "%", x, 250, w, "center")
    love.graphics.setFont(ui.font)
    color(th.dim)
    love.graphics.printf(fit_text(ui.font, section_title_at(jp.pct / 100), w), x, 400, w, "center")

    -- The bar: 10% ticks, a marker for where you are now, and the handle.
    local bx, bw = jp_bar()
    local by = JP_BAR_Y
    color(th.dim, 0.3)
    love.graphics.rectangle("fill", bx, by - 4, bw, 8, 4, 4)
    color(th.fg)
    love.graphics.rectangle("fill", bx, by - 4, bw * jp.pct / 100, 8, 4, 4)
    color(th.dim)
    for t = 0, 100, 10 do
        local tx = bx + bw * t / 100
        love.graphics.rectangle("fill", tx - 1, by + 14, 2, t % 50 == 0 and 14 or 8)
    end
    love.graphics.setFont(ui.small)
    love.graphics.print("0%", bx - 6, by + 34)
    love.graphics.printf("100%", bx, by + 34, bw + 12, "right")
    local hx = bx + bw * jp.here / 100
    love.graphics.polygon("fill", hx, by - 18, hx - 9, by - 32, hx + 9, by - 32)
    local lx = math.max(bx - 12, math.min(bx + bw + 12 - 200, hx - 100))   -- keep the label on the page
    love.graphics.printf("you are here", lx, by - 62, 200, "center")
    color(th.fg)
    love.graphics.circle("fill", bx + bw * jp.pct / 100, by, 16)
    color(th.bg)
    love.graphics.circle("fill", bx + bw * jp.pct / 100, by, 7)

    love.graphics.setFont(ui.small)
    color(th.dim)
    love.graphics.printf("Left/Right  1%      Up/Down  10%      Drag the bar",
        x, by + 110, w, "center")
    love.graphics.printf("A jump    B cancel", x, PAGE_H - 70, w, "left")
end

local function bookmark_entries()
    local entries = { { action = true } }
    for _, b in ipairs(Store.get_bookmarks(book.path)) do entries[#entries + 1] = b end
    return entries
end

local function draw_bookmarks(side)
    local th = theme()
    local m = MARGINS[2]
    local x = side == "left" and m.outer or m.inner
    local w = PAGE_W - m.outer - m.inner
    local row_h = 96
    local rows = list_rows(row_h)
    local entries = bookmark_entries()
    -- two columns: left page then right page
    if not bm.top then bm.top = 1 end
    if bm.sel < bm.top then bm.top = bm.sel end
    if bm.sel >= bm.top + rows * 2 then bm.top = bm.sel - rows * 2 + 1 end
    local first = side == "left" and bm.top or bm.top + rows
    if side == "left" then
        love.graphics.setFont(ui.title)
        color(th.fg)
        love.graphics.print("Bookmarks", x, 60)
    end
    draw_list(side, entries, bm.sel, first, rows, x, 160, w, row_h, function(it, _, rx, ry, rw)
        if it.action then
            love.graphics.setFont(ui.font)
            color(th.fg)
            love.graphics.print(bookmark_here() and "Remove bookmark here" or "+  Bookmark this page", rx,
                centered_y(ui.font, UI_SIZE, ry, row_h - 4))
            return
        end
        local top = ui.font:getBaseline() - UI_SIZE * 0.68
        local bottom = 40 + ui.small:getBaseline()
        local ty = math.floor(ry + (row_h - 4) / 2 - (top + bottom) / 2 + 0.5)
        local pct = math.floor(it.pct * 100 + 0.5) .. "%"
        love.graphics.setFont(ui.font)
        color(th.fg)
        love.graphics.print(fit_text(ui.font, it.title ~= "" and it.title or book.title, rw - 90), rx, ty)
        love.graphics.setFont(ui.small)
        color(th.dim)
        love.graphics.printf(pct, rx, ty + ui.font:getBaseline() - ui.small:getBaseline(), rw, "right")
        love.graphics.print(fit_text(ui.small, it.snippet, rw), rx, ty + 40)
    end)
    love.graphics.setFont(ui.small)
    color(th.dim)
    if side == "left" and #entries == 1 then
        love.graphics.printf("No bookmarks yet. While reading, press Select or tap the top-right "
            .. "corner of the page to bookmark it.", x, 160 + row_h + 20, w, "left")
    end
    if side == "right" then
        love.graphics.print("A open    Y delete    B back", x, PAGE_H - 70)
    end
end

local CREDITS = {
    { "Fonts", "Gentium Book Plus, Charis SIL and Andika (SIL International), Literata "
        .. "(TypeTogether), Source Serif 4 (Adobe), Crimson Text (Sebastian Kosch), "
        .. "EB Garamond (Georg Duffner, Octavio Pardo), Lora (Cyreal), Merriweather "
        .. "(Sorkin Type), PT Serif (ParaType), Spectral (Production Type), Vollkorn "
        .. "(Friedrich Althausen), Bitter (Huerta Tipográfica), Atkinson Hyperlegible "
        .. "Next (Braille Institute), Inter (Rasmus Andersson), Lexend (Lexend Project) "
        .. "and OpenDyslexic (Abbie Gonzalez). SIL Open Font License 1.1." },
    { "Hyphenation", "US English patterns from TeX's hyph-utf8, by Gerard D.C. Kuiken." },
    { "Dictionary", "WordNet 3.1, © 2011 Princeton University (WordNet license)." },
    { "Engine", "LÖVE 11.5 (zlib license), from the PortMaster runtime." },
}

local function draw_about(side)
    local th = theme()
    local m = MARGINS[2]
    local x = side == "left" and m.outer or m.inner
    local w = PAGE_W - m.outer - m.inner
    if side == "left" then
        love.graphics.setFont(ui.title)
        color(th.fg)
        love.graphics.printf("eReaderDS", x, 300, w, "center")
        love.graphics.setFont(ui.font)
        color(th.dim)
        love.graphics.printf("v" .. VERSION, x, 370, w, "center")
        color(th.fg)
        love.graphics.printf("Created by casualducko", x, 470, w, "center")
        love.graphics.setFont(ui.small)
        color(th.dim)
        love.graphics.printf("A two-page ebook reader for the Anbernic RG DS Plus", x, 530, w, "center")
    else
        love.graphics.setFont(ui.title)
        color(th.fg)
        love.graphics.print("Credits", x, 60)
        local y = 150
        for _, c in ipairs(CREDITS) do
            love.graphics.setFont(ui.font)
            color(th.fg)
            love.graphics.print(c[1], x, y)
            y = y + ui.font:getHeight() + 4
            love.graphics.setFont(ui.small)
            color(th.dim)
            love.graphics.printf(c[2], x, y, w, "left")
            local _, lines = ui.small:getWrap(c[2], w)
            y = y + #lines * ui.small:getHeight() + 30
        end
        love.graphics.setFont(ui.small)
        color(th.dim)
        love.graphics.print("B back", x, PAGE_H - 70)
    end
end

-- Help: the buttons on the left page, the touchscreen (the bottom screen,
-- where this is drawn) on the right. Kept to what fits on one page each.
app.HELP = {
    left = { "Buttons", {
        { "D-pad, stick", "Turn pages" },
        { "A", "Footnotes on these pages" },
        { "B", "Settings, or back after a jump" },
        { "X, Start", "Settings" },
        { "Curved arrow", "Settings (or press the stick)" },
        { "Y", "Look up a word" },
        { "Select", "Bookmark the page" },
        { "Anbernic", "Quit" },
    }, "In the library: ‹ › sort, A open, Y delete, Select get books." },
    right = { "Touchscreen", {
        { "Tap or swipe", "Turn pages (right half forward)" },
        { "Slide up/down", "Brightness, down to extra dim" },
        { "Pinch", "Text size" },
        { "Top-right corner", "Bookmark" },
        { "Top edge", "Show or hide the status bars" },
        { "Hold a word", "Look it up" },
        { "Note number", "Show the footnote" },
    }, "B back" },
}
function app.draw_help(side)
    local th = theme()
    local m = MARGINS[2]
    local x = side == "left" and m.outer or m.inner
    local w = PAGE_W - m.outer - m.inner
    local page = app.HELP[side]
    love.graphics.setFont(ui.title)
    color(th.fg)
    love.graphics.print(page[1], x, 60)
    local key_w, y = 230, 170
    for _, row in ipairs(page[2]) do
        local desc = row[2]
        if row[1] == "Tap or swipe" and S.tap == "menu" then desc = "Swipe: turn pages. Tap: Settings" end
        love.graphics.setFont(ui.font)
        color(th.fg)
        love.graphics.print(row[1], x, y)
        color(th.dim)
        love.graphics.printf(desc, x + key_w, y, w - key_w, "left")
        local _, lines = ui.font:getWrap(desc, w - key_w)
        y = y + math.max(1, #lines) * ui.font:getHeight() + 26
    end
    love.graphics.setFont(ui.small)
    color(th.dim)
    if side == "left" then
        love.graphics.printf(page[3], x, y + 20, w, "left")
    else
        love.graphics.print(page[3], x, PAGE_H - 70)
    end
end

---------------------------------------------------------------- keyboard

-- On-screen keyboard: the typed text and the keys on the right page (the
-- touchscreen), what the buttons do on the left. Tap a key, or move with the
-- D-pad and press A. B deletes (or cancels when empty), Y types a space,
-- Start or X searches.
app.KB_ROWS = {}
for _, row in ipairs({ "1234567890", "qwertyuiop", "asdfghjkl'", "zxcvbnm,.-" }) do
    local keys = {}
    for ch in row:gmatch(".") do keys[#keys + 1] = { key = ch, label = ch, span = 1 } end
    app.KB_ROWS[#app.KB_ROWS + 1] = keys
end
app.KB_ROWS[#app.KB_ROWS + 1] = { { key = "space", label = "Space", span = 6 }, { key = "del", label = "Delete", span = 4 } }
app.KB_ROWS[#app.KB_ROWS + 1] = { { key = "cancel", label = "Cancel", span = 4 }, { key = "ok", label = "Search", span = 6 } }
app.KB_TOP, app.KB_ROW_H = 300, 104          -- keys area on the right page
app.KB_MAX = 60                              -- characters

-- Open the keyboard. opts: title, hint, text, submit(text), cancel().
function app.kb_open(opts)
    -- No key is highlighted until the D-pad is used (r, c = nil).
    app.kb = { title = opts.title, hint = opts.hint, text = opts.text or "",
        submit = opts.submit, cancel = opts.cancel, back = app.mode }
    app.mode = "keyboard"
    redraw()
end

-- Column span [c0, c1) of key c in row r.
function app.kb_cols(r, c)
    local c0 = 0
    for i = 1, c - 1 do c0 = c0 + app.KB_ROWS[r][i].span end
    return c0, c0 + app.KB_ROWS[r][c].span
end

function app.kb_key_at(r, col)
    local c0 = 0
    for i, k in ipairs(app.KB_ROWS[r]) do
        if col >= c0 and col < c0 + k.span then return i end
        c0 = c0 + k.span
    end
    return #app.KB_ROWS[r]
end

function app.kb_type(t)
    local kb = app.kb
    if kb then kb.text = (kb.text .. t):sub(1, app.KB_MAX); redraw() end
end

function app.kb_press(key)
    local kb = app.kb
    if not kb then return end
    if key == "del" then
        kb.text = kb.text:sub(1, -2)
    elseif key == "space" then
        if kb.text ~= "" and kb.text:sub(-1) ~= " " then app.kb_type(" ") end
    elseif key == "cancel" then
        app.mode = kb.back
        app.kb = nil
        if kb.cancel then kb.cancel() end
    elseif key == "ok" then
        local q = kb.text:gsub("^%s+", ""):gsub("%s+$", "")
        if q == "" then return end
        app.mode = kb.back
        app.kb = nil
        kb.submit(q)
    else
        app.kb_type(key)
    end
    redraw()
end

function app.kb_action(a)
    local kb = app.kb
    local rows = app.KB_ROWS
    local dir = a == "left" or a == "prev" or a == "right" or a == "next" or a == "up" or a == "down"
    if dir and not kb.r then
        kb.r, kb.c = 2, 1                           -- the first press shows where you are
        redraw()
        return
    end
    if a == "left" or a == "prev" then kb.c = (kb.c - 2) % #rows[kb.r] + 1
    elseif a == "right" or a == "next" then kb.c = kb.c % #rows[kb.r] + 1
    elseif a == "up" or a == "down" then
        -- Keep to the same column: the key under the middle of this one.
        local c0, c1 = app.kb_cols(kb.r, kb.c)
        kb.r = (kb.r - 1 + (a == "down" and 1 or -1)) % #rows + 1
        kb.c = app.kb_key_at(kb.r, (c0 + c1) / 2 - 0.01)
    elseif a == "confirm" then
        if kb.r then app.kb_press(rows[kb.r][kb.c].key) end
    elseif a == "back" then
        if kb.text == "" then app.kb_press("cancel") else app.kb_press("del") end
    elseif a == "toc" then app.kb_press("space")
    elseif a == "menu" then app.kb_press("ok")
    end
    redraw()
end

-- Keys area geometry on the right page: x, width of one column.
function app.kb_geom()
    local m = MARGINS[2]
    local w = PAGE_W - m.outer - m.inner
    return m.inner, w / 10
end

function app.kb_tap(side, u, v)
    if side ~= "right" then return end
    local x0, unit = app.kb_geom()
    local r = math.floor((v - app.KB_TOP) / app.KB_ROW_H) + 1
    if r < 1 or r > #app.KB_ROWS or u < x0 - 10 or u > x0 + unit * 10 + 10 then return end
    local col = math.max(0, math.min(9.99, (u - x0) / unit))
    local kb = app.kb
    local c = app.kb_key_at(r, col)
    if kb.r then kb.r, kb.c = r, c end              -- follow taps only once the D-pad is in use
    app.kb_press(app.KB_ROWS[r][c].key)
end

function app.kb_draw(side)
    local th = theme()
    local kb = app.kb
    local m = MARGINS[2]
    local w = PAGE_W - m.outer - m.inner
    if side == "left" then
        local x = m.outer
        love.graphics.setFont(ui.title)
        color(th.fg)
        love.graphics.printf(kb.title, x, 60, w, "left")
        love.graphics.setFont(ui.font)
        color(th.dim)
        local y = 60 + ui.title:getHeight() * 2 + 20
        if kb.hint then
            love.graphics.printf(kb.hint, x, y, w, "left")
            local _, lines = ui.font:getWrap(kb.hint, w)
            y = y + #lines * ui.font:getHeight() + 40
        end
        for _, row in ipairs({ { "Type", "Tap the keys, or D-pad and A" }, { "B", "Delete" }, { "Y", "Space" },
                { "Start, X", "Search" } }) do
            color(th.fg)
            love.graphics.print(row[1], x, y)
            color(th.dim)
            love.graphics.print(row[2], x + 150, y)
            y = y + ui.font:getHeight() + 14
        end
        return
    end
    -- The text field.
    local x0, unit = app.kb_geom()
    color(th.sel)
    love.graphics.rectangle("fill", x0 - 8, 150, w + 16, 96, 12, 12)
    love.graphics.setFont(ui.title)
    color(th.fg)
    local shown = kb.text
    while ui.title:getWidth(shown .. "|") > w - 20 and #shown > 0 do shown = shown:sub(2) end
    love.graphics.print(shown .. "|", x0 + 8, 150 + (96 - ui.title:getHeight()) / 2)
    -- The keys.
    love.graphics.setLineWidth(2)
    for r, row in ipairs(app.KB_ROWS) do
        for c, k in ipairs(row) do
            local c0, c1 = app.kb_cols(r, c)
            local kx, ky = x0 + c0 * unit + 3, app.KB_TOP + (r - 1) * app.KB_ROW_H + 3
            local kw, kh = (c1 - c0) * unit - 6, app.KB_ROW_H - 6
            if kb.r and r == kb.r and c == kb.c then
                color(th.fg)
                love.graphics.rectangle("fill", kx, ky, kw, kh, 10, 10)
                color(th.bg)
            else
                color(th.dim, 0.45)
                love.graphics.rectangle("line", kx, ky, kw, kh, 10, 10)
                color(k.key == "ok" and th.fg or th.fg)
            end
            local f = #k.label > 1 and ui.font or ui.title
            love.graphics.setFont(f)
            love.graphics.printf(k.label, kx, ky + (kh - f:getHeight()) / 2, kw, "center")
        end
    end
end

---------------------------------------------------------------- font picker

-- Font, as a spread: the fonts on the right (the touchscreen), each name in
-- its own face, and a sample page on the left in the highlighted one (at a
-- fixed size, so fonts compare fairly). Up/down pick a font, left/right show
-- all / serif / sans-serif fonts; A (or tapping the chosen font again) uses
-- it, B leaves things as they were.
app.FONT_ROW_H = 58
app.FONT_SAMPLE_SIZE = 38
-- Rows that fit above the footer.
function app.font_rows() return list_rows(app.FONT_ROW_H) - 1 end
app.FONT_SAMPLE = {
    { "h", "Chapter One" },
    { "r", "It is a truth universally acknowledged, that a single man in possession of a good "
        .. "fortune, must be in want of a wife. However little known the feelings or views of such "
        .. "a man may be on his first entering a neighbourhood, this truth is so well fixed in the "
        .. "minds of the surrounding families, that he is considered as the rightful property of "
        .. "some one or other of their daughters." },
    { "i", "“My dear Mr. Bennet,” said his lady to him one day, “have you heard that Netherfield "
        .. "Park is let at last?”" },
    { "r", "Mr. Bennet replied that he had not." },
}

function app.font_open()
    local fp = { sel = 1, top = 1, size = app.FONT_SAMPLE_SIZE }
    app.font_pick = fp
    app.font_set_filter(app.font_filter_last or "all", fonts.name)
    app.mode = "fonts"
    redraw()
end

-- Show all fonts, or only serif or sans-serif ones, keeping the highlighted
-- font if it's still listed.
app.FONT_FILTERS = { { "all", "All" }, { "serif", "Serif" }, { "sans", "Sans" } }
function app.font_set_filter(filter, keep)
    local fp = app.font_pick
    keep = keep or (fp.list and fp.list[fp.sel] and fp.list[fp.sel].name)
    fp.filter = filter
    app.font_filter_last = filter
    fp.list = {}
    for _, f in ipairs(Fonts.list()) do
        if filter == "all" or f.kind == filter then fp.list[#fp.list + 1] = f end
    end
    fp.sel, fp.top = 1, 1
    for i, f in ipairs(fp.list) do if f.name == keep then fp.sel = i end end
end

-- The highlighted font's faces at the chosen size, loaded once; the previous
-- ones are released so scrolling through fonts doesn't pile them up.
function app.font_sample()
    local fp = app.font_pick
    if not fp.list[fp.sel] then return nil end
    local name = fp.list[fp.sel].name
    local cur = fp.sample
    if cur and cur.name == name and cur.size == fp.size then return cur.f end
    if cur then for _, f in pairs(cur.f) do f:release() end end
    local f = Fonts.load(name, fp.size)
    fp.sample = { name = name, size = fp.size, f = f }
    return f
end

function app.font_close(apply)
    local fp = app.font_pick
    if fp.sample then for _, f in pairs(fp.sample.f) do f:release() end end
    if apply and fp.list[fp.sel] then
        S.font = fp.list[fp.sel].name
        build_fonts()
        goto_pos(pos.ch, pos.off)
        Store.save_settings(S)
    end
    app.font_pick = nil
    app.mode = "menu"
    redraw()
end

function app.font_action(a)
    local fp = app.font_pick
    local n = #fp.list
    if a == "up" then fp.sel = math.max(1, fp.sel - 1)
    elseif a == "down" then fp.sel = math.min(n, fp.sel + 1)
    elseif a == "left" or a == "prev" or a == "right" or a == "next" then
        -- All / Serif / Sans, like the switch at the top of the list.
        local idx = 1
        for i, f in ipairs(app.FONT_FILTERS) do if f[1] == fp.filter then idx = i end end
        idx = idx + ((a == "left" or a == "prev") and -1 or 1)
        app.font_set_filter(app.FONT_FILTERS[math.max(1, math.min(#app.FONT_FILTERS, idx))][1])
    elseif a == "confirm" then app.font_close(true) return
    elseif a == "back" or a == "menu" then app.font_close(false) return
    end
    redraw()
end

function app.font_tap(side, u, v)
    if side ~= "right" then return end
    local fp = app.font_pick
    if v < 140 then                                 -- the All / Serif / Sans switch
        for _, t in ipairs(fp.tabs or {}) do
            if u >= t.x0 - 12 and u <= t.x1 + 12 then app.font_set_filter(t.filter); redraw() end
        end
        return
    end
    local idx = fp.top + math.floor((v - 160) / app.FONT_ROW_H)
    if v < 160 or idx >= fp.top + app.font_rows() or not fp.list[idx] then return end
    if idx == fp.sel then app.font_close(true) else fp.sel = idx; redraw() end
end

function app.font_draw(side)
    local th = theme()
    local fp = app.font_pick
    if side == "left" then
        -- A sample page, laid out roughly like the reader's.
        local f = app.font_sample()
        if not f then return end
        local m = margins()
        local x, w = m.outer, PAGE_W - m.outer - m.inner
        local lh = math.floor(math.max(f.r:getHeight(), fp.size * 1.4) * S.spacing + 0.5)
        local y = vmargin() + 10
        local limit = PAGE_H - vmargin()
        for k, para in ipairs(app.FONT_SAMPLE) do
            local font = f[para[1]]
            love.graphics.setFont(font)
            color(th.fg)
            if para[1] == "h" then
                love.graphics.printf(para[2], x, y, w, "center")
                y = y + font:getHeight() * 1.6
            else
                font:setLineHeight(lh / font:getHeight())
                local align = S.justify and "justify" or "left"
                local _, lines = font:getWrap(para[2], w - (k > 2 and 40 or 0))
                for li, line in ipairs(lines) do
                    if y + lh > limit then break end
                    local indent = (li == 1 and k > 2) and 40 or 0
                    love.graphics.printf(line, x + indent, y, w - indent, li < #lines and align or "left")
                    y = y + lh
                end
                font:setLineHeight(1)
            end
            if y + lh > limit then break end
        end
        love.graphics.setFont(ui.small)
        color(th.dim)
        love.graphics.print("Place your own .ttf or .otf files in " .. Store.books_folder() .. "/Fonts", x, PAGE_H - 70)
        return
    end
    local m = MARGINS[2]
    local x, w = m.inner, PAGE_W - m.outer - m.inner
    love.graphics.setFont(ui.title)
    color(th.fg)
    love.graphics.print("Font", x, 60)
    -- All / Serif / Sans, right-aligned on the title line; the current one bold.
    fp.tabs = {}
    local tx = x + w
    local ty = 60 + ui.title:getBaseline() - ui.font:getBaseline()
    for k = #app.FONT_FILTERS, 1, -1 do
        local t = app.FONT_FILTERS[k]
        local on = fp.filter == t[1]
        local f = on and ui.bold or ui.font
        local tw = f:getWidth(t[2])
        tx = tx - tw
        love.graphics.setFont(f)
        color(on and th.fg or th.dim)
        love.graphics.print(t[2], tx, ty)
        fp.tabs[#fp.tabs + 1] = { x0 = tx, x1 = tx + tw, filter = t[1] }
        if k > 1 then
            love.graphics.setFont(ui.font)
            color(th.dim)
            tx = tx - ui.font:getWidth("  ·  ")
            love.graphics.print("  ·  ", tx, ty)
        end
    end
    local rows = app.font_rows()
    if fp.sel < fp.top then fp.top = fp.sel end
    if fp.sel >= fp.top + rows then fp.top = fp.sel - rows + 1 end
    draw_list(side, fp.list, fp.sel, fp.top, rows, x, 160, w, app.FONT_ROW_H, function(it, _, rx, ry, rw)
        local pf = Fonts.preview(it.name, UI_SIZE) or ui.font
        love.graphics.setFont(pf)
        color(th.fg)
        love.graphics.print(fit_text(pf, it.name, rw - 40), rx, centered_y(pf, UI_SIZE, ry, app.FONT_ROW_H - 4))
        if it.name == fonts.name then
            love.graphics.setFont(ui.font)
            love.graphics.printf("✓", rx, centered_y(ui.font, UI_SIZE, ry, app.FONT_ROW_H - 4), rw, "right")
        end
    end)
    love.graphics.setFont(ui.small)
    color(th.dim)
    love.graphics.print("A use      B back      ‹ › all / serif / sans", x, PAGE_H - 70)
    love.graphics.printf(fp.sel .. " / " .. #fp.list, x, PAGE_H - 70, w, "right")
end

---------------------------------------------------------------- find in book

-- Search the open book for a word or phrase (not case-sensitive). Runs a
-- little at a time between frames (app.task) so the screen stays live; the
-- results fill in as it goes. Chapters loaded only for the search are
-- unloaded again. { query, book, results, sel, top, done, pct, capped }
app.FIND_MAX = 300
function app.find_open()
    local f = app.find
    if f and f.book == book and f.done then
        app.mode = "find"                       -- last results, B to search again
    else
        app.find_keyboard(f and f.book == book and f.query or "")
    end
    redraw()
end

function app.find_keyboard(text)
    app.mode = "reader"
    app.kb_open({ title = "Find in book", text = text,
        hint = "A word or phrase. Capitals don't matter.",
        submit = function(q) app.find_start(q) end })
end

-- The Contents entry a result falls under (the last one starting before it),
-- for labelling. Entries' offsets are worked out during the search, while
-- their chapter is loaded (toc_pos caches them).
function app.find_label(r)
    if r.label then return r.label end
    local best
    for _, t in ipairs(book.toc) do
        if t.chapter > r.ch or (t.chapter == r.ch and (t.off or 0) > r.off) then break end
        best = t
    end
    r.label = best and best.title or (book.title or "")
    return r.label
end

function app.find_start(query)
    local f = { query = query, book = book, results = {}, sel = 1, top = 1, pct = 0 }
    app.find = f
    app.mode = "find"
    local needle = query:lower()
    app.task = coroutine.create(function()
        local t0 = love.timer.getTime()
        local n = #book.chapters
        for i = 1, n do
            local c = book.chapters[i]
            local loaded = c.blocks ~= nil
            book:chapter(i)
            for _, t in ipairs(book.toc) do
                if t.chapter == i then toc_pos(t) end
            end
            for _, b in ipairs(c.blocks) do
                if b.kind == "text" then
                    local parts = {}
                    for _, r in ipairs(b.runs) do if r.text then parts[#parts + 1] = r.text end end
                    local text = table.concat(parts)
                    local low = text:lower()
                    local at = 1
                    while #f.results < app.FIND_MAX do
                        local s0, s1 = low:find(needle, at, true)
                        if not s0 then break end
                        f.results[#f.results + 1] = { ch = i, off = b.off + s0 - 1,
                            text = text, s0 = s0, s1 = s1 }
                        at = s1 + 1
                    end
                end
            end
            -- Free what only the search needed (the open chapter stays).
            if not loaded and i ~= pos.ch then c.blocks, c.anchors = nil, nil end
            f.pct = i / n
            if #f.results >= app.FIND_MAX then f.capped = true; break end
            if love.timer.getTime() - t0 > 0.03 then
                coroutine.yield()
                t0 = love.timer.getTime()
            end
        end
        f.done = true
    end)
end

-- One slice of the running task (called from the main loop).
function app.task_step()
    local ok, err = coroutine.resume(app.task)
    if not ok then
        print("[task] " .. tostring(err))
        if app.find and not app.find.done then app.find.done, app.find.error = true, true end
    end
    if coroutine.status(app.task) == "dead" then app.task = nil end
    redraw()
end

-- A result's text: a little before the match, the match, the rest.
function app.find_snippet(r)
    local a = math.max(1, r.s0 - 40)
    while a > 1 and a < r.s0 and r.text:byte(a) >= 0x80 and r.text:byte(a) < 0xC0 do a = a - 1 end
    local pre = r.text:sub(a, r.s0 - 1)
    if a > 1 then pre = "…" .. pre:gsub("^%S*%s", "") end
    return pre, r.text:sub(r.s0, r.s1), r.text:sub(r.s1 + 1, r.s1 + 160)
end

function app.find_draw(side)
    local th = theme()
    local f = app.find
    local m = MARGINS[2]
    local x = side == "left" and m.outer or m.inner
    local w = PAGE_W - m.outer - m.inner
    local row_h = 96
    local rows = list_rows(row_h)
    if f.sel < f.top then f.top = f.sel end
    if f.sel >= f.top + rows * 2 then f.top = f.sel - rows * 2 + 1 end
    local first = side == "left" and f.top or f.top + rows
    love.graphics.setFont(ui.title)
    color(th.fg)
    if side == "left" then
        love.graphics.print(fit_text(ui.title, "“" .. f.query .. "”", w), x, 60)
    end
    love.graphics.setFont(ui.small)
    color(th.dim)
    local status = (not f.done and ("Searching… " .. math.floor(f.pct * 100) .. "%"))
        or (f.error and "The search stopped on an error.")
        or (#f.results == 0 and "Not found in this book.")
        or (f.capped and ("The first " .. #f.results .. " matches"))
        or (#f.results == 1 and "1 match" or (#f.results .. " matches"))
    if side == "left" then love.graphics.printf(status, x, 60 + ui.title:getHeight() + 8, w, "left") end
    draw_list(side, f.results, f.sel, first, rows, x, 160, w, row_h, function(r, _, rx, ry, rw)
        -- The chapter in bold, then the words around the match, the match bold.
        love.graphics.setFont(ui.small_bold)
        color(th.fg)
        love.graphics.print(fit_text(ui.small_bold, app.find_label(r), rw), rx, ry + 8)
        local pre, hit, post = app.find_snippet(r)
        local y = ry + 8 + ui.small:getHeight() + 2
        -- Keep the match in view: trim the start if the line is too long.
        while pre ~= "…" and pre ~= "" and ui.font:getWidth(pre) + ui.bold:getWidth(hit) > rw * 0.7 do
            pre = "…" .. pre:gsub("^…", ""):gsub("^.[\128-\191]*", "")
        end
        love.graphics.setFont(ui.font)
        color(th.dim)
        love.graphics.print(pre, rx, y)
        local px = rx + ui.font:getWidth(pre)
        love.graphics.setFont(ui.bold)
        color(th.fg)
        love.graphics.print(hit, px, y)
        local hx = px + ui.bold:getWidth(hit)
        love.graphics.setFont(ui.font)
        color(th.dim)
        love.graphics.print(fit_text(ui.font, post, math.max(0, rx + rw - hx)), hx, y)
    end)
    love.graphics.setFont(ui.small)
    color(th.dim)
    if side == "left" then
        love.graphics.print("A go there      B search again      X close", x, PAGE_H - 70)
    elseif #f.results > 0 then
        love.graphics.printf(f.sel .. " / " .. #f.results, x, PAGE_H - 70, w, "right")
    end
end

function app.find_action(a)
    local f = app.find
    local n = #f.results
    local rows = list_rows(96)
    if a == "up" then f.sel = math.max(1, f.sel - 1)
    elseif a == "down" then f.sel = math.min(math.max(n, 1), f.sel + 1)
    elseif a == "left" or a == "prev" then f.sel = math.max(1, f.sel - rows)
    elseif a == "right" or a == "next" then f.sel = math.min(math.max(n, 1), f.sel + rows)
    elseif a == "confirm" and f.results[f.sel] then
        local r = f.results[f.sel]
        app.task = nil
        f.done = true
        app.jump_to(r.ch, r.off)
        app.mode = "reader"
        -- Mark the words on the spread it lands on.
        app.find_mark = { query = f.query, at = spread and (spread.ch .. ":" .. spread.pi) }
    elseif a == "back" then
        app.task = nil
        if not f.done then f.done = true end
        app.find_keyboard(f.query)
    elseif a == "menu" or a == "toc" then
        app.task = nil
        if not f.done then f.done = true end
        app.mode = "reader"
    end
    redraw()
end

-- The found words, outlined on the spread a result opened (until it's left).
function app.find_highlight(side)
    local mk = app.find_mark
    if not mk or not spread or mk.at ~= spread.ch .. ":" .. spread.pi then app.find_mark = nil; return end
    if not mk.words then
        local want = {}
        local n = 0
        for wd in mk.query:lower():gmatch("%S+") do
            wd = wd:gsub("^[%p]+", ""):gsub("[%p]+$", "")
            if wd ~= "" then want[wd] = true; n = n + 1 end
        end
        mk.words = {}
        for _, w in ipairs(look.collect()) do
            local t = w.text:lower():gsub("^[%p]+", ""):gsub("[%p]+$", ""):gsub("\226\128[\152-\157]", "")
            if want[t] and (n == 1 or #t > 2) then mk.words[#mk.words + 1] = w end
        end
    end
    for _, w in ipairs(mk.words) do
        if w.side == side then note.highlight(w) end
    end
end

local function draw_message(side)
    local th = theme()
    if side == "left" then
        local m = MARGINS[2]
        love.graphics.setFont(ui.font)
        color(th.fg)
        love.graphics.printf(message or "", m.outer, 200, PAGE_W - m.outer - m.inner, "left")
        love.graphics.setFont(ui.small)
        color(th.dim)
        love.graphics.print("Press A to continue", m.outer, PAGE_H - 70)
    end
end

local function render_canvases()
    local th = theme()
    local painter
    if app.mode == "reader" then
        painter = draw_reader_pages()
        if app.find_mark then
            local reader = painter
            painter = function(side) reader(side); app.find_highlight(side) end
        end
    elseif app.mode == "menu" then
        local reader = draw_reader_pages()
        painter = function(side)
            if side == "left" then reader("left") else draw_menu_panel(side) end
        end
    elseif app.mode == "toc" then painter = draw_toc
    elseif app.mode == "bookmarks" then painter = draw_bookmarks
    elseif app.mode == "jump" then
        local reader = draw_reader_pages()
        painter = function(side)
            if side == "left" then reader("left") else draw_jump_panel() end
        end
    elseif app.mode == "shop" then painter = shop.draw
    elseif app.mode == "lookup" then
        local reader = draw_reader_pages()
        local wd = look.words[look.sel]
        painter = function(side)
            if side == wd.side then reader(side); note.highlight(wd) else look.draw_panel(side) end
        end
    elseif app.mode == "note" then
        local reader = draw_reader_pages()
        local r = note.refs[note.sel]
        painter = function(side)
            if side == r.side then reader(side); note.highlight(r) else note.draw_panel(side) end
        end
    elseif app.mode == "about" then painter = draw_about
    elseif app.mode == "help" then painter = app.draw_help
    elseif app.mode == "keyboard" then painter = app.kb_draw
    elseif app.mode == "fonts" then painter = app.font_draw
    elseif app.mode == "find" then painter = app.find_draw
    elseif app.mode == "message" then painter = draw_message
    else painter = draw_library end

    for i, side in ipairs({ "left", "right" }) do
        love.graphics.setCanvas(canvases[i])
        love.graphics.clear(th.bg[1], th.bg[2], th.bg[3], 1)
        love.graphics.origin()
        painter(side)
        if (app.mode == "menu" and menu.page ~= "status" or app.mode == "jump") and side == "left" then
            love.graphics.setColor(th.bg[1], th.bg[2], th.bg[3], 0.55)
            love.graphics.rectangle("fill", 0, 0, PAGE_W, PAGE_H)
        end
    end
    love.graphics.setCanvas()
end

-- Transform so drawing happens in page coordinates (0..PAGE_W, 0..PAGE_H)
-- on the screen that shows the given side of the spread.
local function page_transform(side)
    if S.orient == "left" then
        -- Device turned counter-clockwise: top screen on the left.
        love.graphics.translate(side == "left" and SCREEN_W or SCREEN_W * 2, 0)
        love.graphics.rotate(math.pi / 2)
    else
        -- Device turned clockwise: bottom screen on the left.
        love.graphics.translate(side == "left" and SCREEN_W or 0, SCREEN_H)
        love.graphics.rotate(-math.pi / 2)
    end
end

-- Draw a page canvas squeezed horizontally toward the spine (s = 1 is flat,
-- s = 0 is edge-on), darkened by `shade` and faded by `alpha`.
local function blit_page(canvas, side, s, shade, alpha)
    s = s or 1
    if s <= 0 then return end
    love.graphics.push()
    page_transform(side)
    local k = 1 - (shade or 0)
    love.graphics.setColor(k, k, k, alpha or 1)
    local x = side == "left" and PAGE_W * (1 - s) or 0
    love.graphics.draw(canvas, x, 0, 0, s, 1)
    love.graphics.pop()
end

-- Draw the page that is turning. s = cos(angle): 1 flat, 0 edge-on.
-- The spine end is drawn slightly shorter than the outer edge so the page
-- appears to tilt toward the viewer as it lifts.
local function blit_turning(canvas, side, s, shade)
    if s <= 0.001 then return end
    local lift = 0.10 * math.sqrt(math.max(0, 1 - s * s))   -- sin(angle)
    local verts = {}
    for c = 0, TURN_COLS do
        local u = c / TURN_COLS                     -- 0 at spine, 1 at outer edge
        local x = u * PAGE_W * s
        local tu = u
        if side == "left" then x = PAGE_W - x; tu = 1 - u end
        local h = 1 - lift * (1 - u)
        local y0 = PAGE_H * (1 - h) / 2
        local k = 1 - 0.25 * lift * (1 - u) * 4      -- a little darker toward the fold
        verts[#verts + 1] = { x, y0, tu, 0, k, k, k, 1 }
        verts[#verts + 1] = { x, y0 + PAGE_H * h, tu, 1, k, k, k, 1 }
    end
    turn_mesh:setVertices(verts)
    turn_mesh:setTexture(canvas)
    love.graphics.push()
    page_transform(side)
    local k = 1 - (shade or 0)
    love.graphics.setColor(k, k, k, 1)
    love.graphics.draw(turn_mesh)
    love.graphics.pop()
end

-- Soft shadow cast by a turning page onto the page beneath it. `edge` is the
-- turning page's outer edge; the shadow fades away from it in direction `dir`.
local function page_shadow(side, edge, dir, alpha)
    if alpha <= 0 then return end
    love.graphics.push()
    page_transform(side)
    love.graphics.setColor(0, 0, 0, alpha)
    love.graphics.draw(shadow_mesh, edge, 0, 0, 70 * dir, PAGE_H)
    love.graphics.pop()
end

local function set_theme_shader(on)
    if on and theme().eink and eink_shader then
        love.graphics.setShader(eink_shader)
    else
        love.graphics.setShader()
    end
end

-- Draw the two page canvases onto the physical screens.
local function compose()
    set_theme_shader(true)
    local th = theme()
    love.graphics.clear(th.bg[1], th.bg[2], th.bg[3], 1)
    blit_page(canvases[1], "left")
    -- Get books: the selected book's page skips the E-ink filter, so covers
    -- stay in color whatever the theme.
    if app.mode == "shop" then set_theme_shader(false) end
    blit_page(canvases[2], "right")
    set_theme_shader(false)
end

local ANIM_TIME = { flip = 0.38, fade = 0.22 }

-- Page-turn animation between old_canvases and canvases at progress t (0..1).
local compose_anim_frame
local function compose_anim(t)
    set_theme_shader(true)
    compose_anim_frame(t)
    set_theme_shader(false)
end

function compose_anim_frame(t)
    local a = app.anim
    local th = theme()
    love.graphics.clear(th.bg[1], th.bg[2], th.bg[3], 1)
    local e = t * t * (3 - 2 * t)              -- ease in/out
    local old, new = old_canvases, canvases
    if a.style == "fade" then
        blit_page(new[1], "left"); blit_page(new[2], "right")
        blit_page(old[1], "left", 1, 0, 1 - e); blit_page(old[2], "right", 1, 0, 1 - e)
        return
    end
    -- Flip: the turning page folds to the spine, then unfolds on the other side.
    local first = e < 0.5
    local s = first and math.cos(e * math.pi) or -math.cos(e * math.pi)
    local shade, shadow = 0.35 * (1 - s), 0.3 * (1 - s)
    if a.dir > 0 then
        blit_page(old[1], "left"); blit_page(new[2], "right")
        if first then
            page_shadow("right", PAGE_W * s, 1, shadow)
            blit_turning(old[2], "right", s, shade)
        else
            page_shadow("left", PAGE_W * (1 - s), -1, shadow)
            blit_turning(new[1], "left", s, shade)
        end
    else
        blit_page(new[1], "left"); blit_page(old[2], "right")
        if first then
            page_shadow("left", PAGE_W * (1 - s), -1, shadow)
            blit_turning(old[1], "left", s, shade)
        else
            page_shadow("right", PAGE_W * s, 1, shadow)
            blit_turning(new[2], "right", s, shade)
        end
    end
end

-- Turn the page with the configured animation. `fn` changes the spread.
local function turn(dir, fn)
    app.anim = nil
    if S.anim == "off" or app.mode ~= "reader" or not spread then fn(); redraw(); return end
    render_canvases()                           -- what is on screen right now
    local ch, pi = spread.ch, spread.pi
    canvases, old_canvases = old_canvases, canvases
    fn()
    if spread.ch == ch and spread.pi == pi then     -- start/end of book: nothing to animate
        canvases, old_canvases = old_canvases, canvases
        return
    end
    render_canvases()
    app.anim = { dir = dir, style = S.anim, start = love.timer.getTime(), dur = ANIM_TIME[S.anim] or 0.3 }
    redraw()
end

---------------------------------------------------------------- touch brightness

-- Brightness popup shown while sliding a finger on the touchscreen.
local overlay = nil        -- { side, pct, hide_at }
local gesture = nil        -- current touch: { side, u0, v0, mode, p0 }

-- Bottom-screen native coordinates (0..1024 x 0..768) -> page side + page coords.
local function touch_to_page(sx, sy)
    if S.orient == "left" then return "right", sy, SCREEN_W - sx end
    return "left", SCREEN_H - sy, sx
end

local function current_brightness()
    if S.brightness >= 0 then return S.brightness end
    return Backlight.get() or 50
end

local function touch_event(kind, sx, sy)
    local now = love.timer.getTime()
    -- Two-finger pinch while reading: previews a text size (shown with a
    -- percentage and a sample line) and applies it when the fingers lift.
    -- The size follows the square root of the pinch, so it changes gently.
    if kind == "pinch_start" then
        gesture = app.mode == "reader" and { mode = "pinch", d0 = math.max(40, sx), size0 = S.font_size }
            or { mode = "ignore" }
        return
    elseif kind == "pinch" then
        if gesture and gesture.mode == "pinch" then
            local ratio = math.sqrt(math.max(1, sx) / gesture.d0)
            local size = math.max(18, math.min(64, math.floor(gesture.size0 * ratio + 0.5)))
            gesture.size = size
            overlay = { side = "right", pinch = size, pct = math.floor(size / gesture.size0 * 100 + 0.5),
                hide_at = now + 1e9 }
            redraw()
        end
        return
    elseif kind == "pinch_end" then
        if gesture and gesture.mode == "pinch" then
            if overlay then overlay.hide_at = now + 0.7 end
            if gesture.size and gesture.size ~= S.font_size then
                S.font_size = gesture.size
                build_fonts()
                goto_pos(pos.ch, pos.off)
                Store.save_settings(S)
            end
        end
        gesture = nil
        return
    end
    local side, u, v = touch_to_page(sx, sy)
    if app.mode == "jump" and side == "right" and kind ~= "up" and math.abs(v - JP_BAR_Y) < 140 then
        -- Dragging along the picker's bar sets the percentage directly.
        local bx, bw = jp_bar()
        jp.pct = math.max(0, math.min(100, math.floor((u - bx) / bw * 100 + 0.5)))
        gesture = nil
        redraw()
        return
    end
    if kind == "down" then
        gesture = { side = side, u0 = u, v0 = v, u = u, t0 = now, moved = 0 }
    elseif kind == "move" and gesture then
        local du, dv = u - gesture.u0, v - gesture.v0
        gesture.moved = math.max(gesture.moved, math.abs(du), math.abs(dv))
        gesture.u = u
        if gesture.held then
            -- A press-and-hold (look-up) doesn't turn into a swipe or slide.
        elseif not gesture.mode and math.abs(du) > 24 and math.abs(du) > math.abs(dv) * 1.5 then
            gesture.mode = "swipe"          -- mostly horizontal: page turn on release
        elseif not gesture.mode and math.abs(dv) > 24 and math.abs(dv) > math.abs(du) * 1.5 then
            -- Mostly vertical slide: brightness. Work in sqrt space so the
            -- dim end gets finer control.
            gesture.mode = "brightness"
            gesture.v0 = v
            gesture.p0 = S.extra_dim > 0 and (0.1 - S.extra_dim * 0.05) or math.sqrt(current_brightness() / 100)
        end
        if gesture.mode == "brightness" then
            local p = gesture.p0 + (gesture.v0 - v) / (PAGE_H * 0.8)
            -- Below 1% (p < 0.1) the slide continues into the extra dim levels.
            local pct, extra = 1, 0
            if p < 0.1 then
                extra = math.max(1, math.min(#EXTRA_DIM, math.ceil((0.1 - p) / 0.05)))
            else
                pct = math.max(1, math.min(100, math.floor(p * p * 100 + 0.5)))
            end
            S.extra_dim = extra
            if Backlight.available() and pct ~= S.brightness then
                S.brightness = pct
                Backlight.set(pct)
            end
            overlay = { side = gesture.side, pct = Backlight.available() and pct or nil, extra = extra, hide_at = now + 1e9 }
            redraw()
        end
    elseif kind == "up" and gesture then
        if gesture.mode == "brightness" then
            if overlay then overlay.hide_at = now + 0.9 end
            Store.save_settings(S)
        elseif gesture.mode == "swipe" then
            -- Swipe left (toward the page's left edge) = next page, like a book.
            local du = gesture.u - gesture.u0
            if app.mode == "reader" and math.abs(du) > 60 and now - gesture.t0 < 1.0 then
                if du < 0 then turn(1, next_spread) else turn(-1, prev_spread) end
            end
        elseif gesture.held then
            -- Already handled while the finger was down.
        elseif gesture.moved < 30 and now - gesture.t0 < 0.5 and app.on_tap then
            app.on_tap(gesture.side, gesture.u0, gesture.v0)
        end
        gesture = nil
    end
end

-- A short message popup (e.g. "Bookmark added").
function app.toast(text)
    overlay = { side = "right", text = text, hide_at = love.timer.getTime() + 1.2 }
    redraw()
end

local function draw_overlay()
    if not overlay then return end
    love.graphics.push()
    page_transform(overlay.side)
    if overlay.pinch then
        -- Pinching: the size it will become, and a sample at that size.
        local w, h = 560, 200
        local x, y = (PAGE_W - w) / 2, 110
        love.graphics.setColor(0.08, 0.08, 0.08, 0.94)
        love.graphics.rectangle("fill", x, y, w, h, 22, 22)
        love.graphics.setColor(1, 1, 1, 0.95)
        love.graphics.setFont(ui.font)
        love.graphics.print("Text size " .. overlay.pinch, x + 28, y + 16)
        love.graphics.printf(overlay.pct .. "%", x, y + 16, w - 28, "right")
        local f = Fonts.preview(fonts.name or S.font, overlay.pinch) or ui.font
        love.graphics.setFont(f)
        local sample = fit_text(f, "The quick brown fox", w - 56)
        love.graphics.printf(sample, x + 28, y + 70 + (110 - f:getHeight()) / 2, w - 56, "center")
        love.graphics.pop()
        return
    end
    if overlay.text then
        local w, h = 460, 80
        local x, y = (PAGE_W - w) / 2, 120
        love.graphics.setColor(0.08, 0.08, 0.08, 0.94)
        love.graphics.rectangle("fill", x, y, w, h, 22, 22)
        love.graphics.setColor(1, 1, 1, 0.95)
        love.graphics.setFont(ui.font)
        love.graphics.printf(overlay.text, x, centered_y(ui.font, UI_SIZE, y, h), w, "center")
        love.graphics.pop()
        return
    end
    local w, h = 460, 118
    local x, y = (PAGE_W - w) / 2, 120
    love.graphics.setColor(0.08, 0.08, 0.08, 0.94)
    love.graphics.rectangle("fill", x, y, w, h, 22, 22)
    love.graphics.setColor(1, 1, 1, 0.95)
    love.graphics.setFont(ui.font)
    if overlay.extra and overlay.extra > 0 then
        love.graphics.print("Extra dim", x + 28, y + 14)
        love.graphics.printf(overlay.extra .. " of " .. #EXTRA_DIM, x, y + 14, w - 28, "right")
        local bx, by, bw = x + 28, y + 76, w - 56
        for k = 1, #EXTRA_DIM do
            love.graphics.setColor(1, 1, 1, k <= overlay.extra and 0.95 or 0.25)
            local sw = (bw - 16) / #EXTRA_DIM
            love.graphics.rectangle("fill", bx + (k - 1) * (sw + 8), by, sw, 12, 6, 6)
        end
    elseif overlay.pct then
        love.graphics.print("Brightness", x + 28, y + 14)
        love.graphics.printf(overlay.pct .. "%", x, y + 14, w - 28, "right")
        local bx, by, bw = x + 28, y + 76, w - 56
        love.graphics.setColor(1, 1, 1, 0.25)
        love.graphics.rectangle("fill", bx, by, bw, 12, 6, 6)
        love.graphics.setColor(1, 1, 1, 0.95)
        love.graphics.rectangle("fill", bx, by, math.max(12, bw * overlay.pct / 100), 12, 6, 6)
    else
        love.graphics.printf("Brightness unavailable", x, y + 38, w, "center")
    end
    love.graphics.pop()
end

-- Draws one full frame (both screens).
local function frame()
    local a = app.anim
    if a then
        local t = a.fixed or math.min(1, (love.timer.getTime() - a.start) / a.dur)
        if t < 1 then compose_anim(t) return end
        app.anim = nil
    end
    render_canvases()
    compose()
end

local function draw_extra_dim()
    local a = EXTRA_DIM[S.extra_dim]
    if a then
        love.graphics.setColor(0, 0, 0, a)
        love.graphics.rectangle("fill", 0, 0, SCREEN_W * 2, SCREEN_H)
    end
end

function love.draw()
    love.graphics.push()
    love.graphics.scale(app.scale)
    frame()
    draw_extra_dim()
    draw_overlay()
    love.graphics.pop()
end

-- Desktop testing: the mouse on the bottom-screen half acts as a finger.
function love.mousepressed(x, y)
    x, y = x / app.scale, y / app.scale
    if x >= SCREEN_W and not Touch.enabled then touch_event("down", x - SCREEN_W, y) end
end
function love.mousemoved(x, y)
    if gesture and not Touch.enabled and love.mouse.isDown(1) then
        touch_event("move", math.max(0, x / app.scale - SCREEN_W), y / app.scale)
    end
end
function love.mousereleased(x, y)
    if gesture and not Touch.enabled then touch_event("up", x / app.scale - SCREEN_W, y / app.scale) end
end

---------------------------------------------------------------- input

---------------------------------------------------------------- lid

-- The RG DS Plus reports its lid through the power-key device: key 110 when it
-- closes, 111 when it opens. The firmware only sleeps for its own apps, so the
-- reader does it: save, screens off, then suspend (or just screens off).
local LID_DEVICE, LID_CLOSE, LID_OPEN = "rk805 pwrkey", 110, 111
local RESLEEP_AFTER = 5              -- seconds awake with the lid still closed
local lid = { closed = false }

local function suspend()
    -- Blocks until the device wakes up again.
    print("[lid] suspending")
    local f = io.open("/sys/power/state", "w")
    if not f then print("[lid] cannot open /sys/power/state"); return false end
    f:setvbuf("no")                         -- write now, so errors show up here
    local ok, err = f:write("mem")
    f:close()
    if not ok then print("[lid] suspend refused: " .. tostring(err)); return false end
    print("[lid] woke up")
    return true
end

local function lid_closed()
    if lid.closed then return end
    lid.closed = true
    reading_pause()
    save_progress()
    Store.save_settings(S)
    Store.flush()
    lid.pct = S.brightness >= 0 and S.brightness or Backlight.get() or 50
    Backlight.power(false)
    lid.since = love.timer.getTime()
    if S.lid == "sleep" then
        if not suspend() then S.lid_failed = true end
        lid.since = love.timer.getTime()
    end
end

local function lid_opened()
    if not lid.closed then return end
    lid.closed = false
    Backlight.power(true, lid.pct)
    redraw()
end

-- Called by the main loop while the lid is closed and the device is awake
-- (e.g. woken by something else): go back to sleep after a few seconds.
local function lid_tick()
    if lid.closed and S.lid == "sleep" and not S.lid_failed
        and love.timer.getTime() - lid.since > RESLEEP_AFTER then
        suspend()
        lid.since = love.timer.getTime()
    end
end

-- ROCKNIX: the curved-arrow button sends BTN_Z from its own device, which
-- SDL doesn't see (on the stock firmware it arrives as the Back key).
app.BACK_DEVICE, app.BACK_CODE = "adc-keys-back", 309
function app.on_raw_key(device, code)
    if device == app.BACK_DEVICE and code == app.BACK_CODE then app.on_back() return end
    if device ~= LID_DEVICE then return end
    if code == LID_CLOSE then lid_closed()
    elseif code == LID_OPEN then lid_opened() end
end

-- Input logging for identifying buttons: the first presses of each session go
-- to log.txt, then it stops, so reading doesn't keep writing to the SD card.
local INPUT_LOG_LIMIT = 40
local input_logged = 0
local function log_input(fmt, ...)
    if input_logged >= INPUT_LOG_LIMIT then return end
    input_logged = input_logged + 1
    print("[input] " .. string.format(fmt, ...))
    if input_logged == INPUT_LOG_LIMIT then print("[input] (further input not logged)") end
end

-- Physical d-pad -> direction on the sideways page.
local ROTATE = {
    left = { up = "left", right = "up", down = "right", left = "down" },
    right = { up = "right", right = "down", down = "left", left = "up" },
}

local handle_action
local function action(a)
    handle_action(a)
    -- Time outside the pages (menus, lists) doesn't count as reading.
    if app.mode ~= "reader" then reading_pause() end
end
function app.on_back() action("menu") end   -- see app.on_raw_key

function handle_action(a)
    if lid.closed then return end         -- pocket presses while the lid is shut
    local mode = app.mode
    -- Select bookmarks while reading; elsewhere it behaves like the menu button.
    if a == "bookmark" and mode ~= "reader" and mode ~= "library" then a = "menu" end
    -- Pressing the stick in opens Settings while reading, and selects elsewhere.
    if a == "stick" then a = mode == "reader" and "menu" or "confirm" end
    if a == "quit" then love.event.quit() return end

    if mode == "message" then
        if a == "confirm" or a == "back" then
            app.mode = app.message_back or (book and "reader" or "library")
            app.message_back = nil
            redraw()
        end
        return
    end

    if mode == "reader" then
        if a == "next" or a == "right" or a == "down" then turn(1, next_spread)
        elseif a == "prev" or a == "left" or a == "up" then turn(-1, prev_spread)
        elseif a == "bookmark" then toggle_bookmark()
        elseif a == "next_section" then jump_section(1)
        elseif a == "prev_section" then jump_section(-1)
        elseif a == "back" and go_back() then -- B: back to where you were
        elseif a == "menu" or a == "back" then app.mode = "menu"; menu.sel = 1; menu.page = "main"; menu.top = nil
        elseif a == "toc" then look.open()          -- Y: look up a word
        elseif a == "confirm" then note.open()
        end
        redraw()
        return
    end

    if mode == "menu" then
        local items = menu_items()
        if a == "up" then menu.sel = (menu.sel - 2) % #items + 1
        elseif a == "down" then menu.sel = menu.sel % #items + 1
        elseif a == "left" or a == "right" or a == "prev" or a == "next" then
            local it = items[menu.sel]
            local back = a == "left" or a == "prev"
            if it.adjust then
                it.adjust(back and -1 or 1)
            elseif a == "left" or a == "right" then
                -- Rows with nothing to change: left/right move the selection.
                menu.sel = back and (menu.sel - 2) % #items + 1 or menu.sel % #items + 1
            end
        elseif a == "confirm" then
            local it = items[menu.sel]
            if it.act then it.act() elseif it.adjust then it.adjust(1) end
        elseif a == "back" and menu.page ~= "main" then
            menu.page = "main"; menu.sel = menu.parent_row or 1; menu.top = nil
        elseif a == "back" or a == "menu" then app.mode = "reader"; menu.page = "main" end
        Store.save_settings(S)
        redraw()
        return
    end

    if mode == "keyboard" then app.kb_action(a) return end
    if mode == "fonts" then app.font_action(a) return end
    if mode == "find" then app.find_action(a) return end

    if mode == "about" or mode == "help" then
        if a == "back" or a == "confirm" or a == "menu" then app.mode = "menu" end
        redraw()
        return
    end

    if mode == "jump" then
        local step = ({ left = -1, right = 1, up = -10, down = 10 })[a]
        if step then
            jp.pct = math.max(0, math.min(100, jp.pct + step))
        elseif a == "confirm" then
            if jp.pct ~= jp.here then
                remember_jump()
                goto_pos(book:locate(jp.pct / 100))
                save_progress()
            end
            app.mode = "reader"
        elseif a == "back" or a == "menu" then
            app.mode = "menu"
        end
        redraw()
        return
    end

    if mode == "bookmarks" then
        local entries = bookmark_entries()
        local n = #entries
        local rows = list_rows(96)
        if a == "up" then bm.sel = math.max(1, bm.sel - 1)
        elseif a == "down" then bm.sel = math.min(n, bm.sel + 1)
        elseif a == "left" or a == "prev" then bm.sel = math.max(1, bm.sel - rows)
        elseif a == "right" or a == "next" then bm.sel = math.min(n, bm.sel + rows)
        elseif a == "confirm" then
            local e = entries[bm.sel]
            if e.action then
                toggle_bookmark()
            else
                app.jump_to(e.ch, e.off); app.mode = "reader"
            end
        elseif a == "toc" and bm.sel > 1 then              -- Y deletes
            local list = {}
            for i, b in ipairs(Store.get_bookmarks(book.path)) do
                if i ~= bm.sel - 1 then list[#list + 1] = b end
            end
            Store.set_bookmarks(book.path, list)
            bm.sel = math.min(bm.sel, #list + 1)
            if app.toast then app.toast("Bookmark deleted") end
        elseif a == "back" or a == "menu" then
            app.mode = bm.from == "menu" and "menu" or "reader"
        end
        redraw()
        return
    end

    if mode == "toc" then
        local n = #book.toc
        local rows = list_rows(58)
        if a == "up" then toc.sel = math.max(1, toc.sel - 1)
        elseif a == "down" then toc.sel = math.min(n, toc.sel + 1)
        elseif a == "left" or a == "prev" then toc.sel = math.max(1, toc.sel - rows)
        elseif a == "right" or a == "next" then toc.sel = math.min(n, toc.sel + rows)
        elseif a == "confirm" then
            app.jump_to(toc_pos(book.toc[toc.sel])); app.mode = "reader"
        elseif a == "back" or a == "toc" or a == "menu" then app.mode = "reader" end
        redraw()
        return
    end

    if mode == "lookup" then
        if a == "left" or a == "right" or a == "up" or a == "down" then look.move(a)
        elseif a == "confirm" then look.page = look.page + 1
            if look.pages and look.page > #look.pages then look.page = 1 end
        elseif a == "back" or a == "menu" or a == "toc" or a == "bookmark" then
            app.mode = "reader"
            reading.since = love.timer.getTime()
        end
        redraw()
        return
    end

    if mode == "note" then
        if a == "left" or a == "right" then
            note.sel = (note.sel - 1 + (a == "right" and 1 or -1)) % #note.refs + 1
            note.page = 1
        elseif a == "up" or a == "down" then
            note.page = math.max(1, note.page + (a == "down" and 1 or -1))
        elseif a == "confirm" or a == "back" or a == "menu" or a == "bookmark" then
            app.mode = "reader"
            reading.since = love.timer.getTime()
        end
        redraw()
        return
    end

    if mode == "shop" then
        if a == "up" then shop.move(-1)
        elseif a == "down" then shop.move(1)
        elseif a == "confirm" then shop.confirm()
        elseif a == "back" then shop.back()
        elseif a == "menu" and not shop.dl then shop.stack = {}; shop.back() end
        redraw()
        return
    end

    if mode == "library" then
        local n = #library.items
        if library.confirm then
            -- "Delete this book?" is showing: A deletes, anything else keeps it.
            local path = library.confirm
            library.confirm = nil
            local it = library.items[library.sel]
            if a == "confirm" and it and it.path == path then library.delete(path) end
            redraw()
            return
        end
        if n > 0 then
            if a == "up" then library.sel = math.max(1, library.sel - 1)
            elseif a == "down" then library.sel = math.min(n, library.sel + 1)
            elseif a == "left" or a == "right" then library.cycle_sort(a == "right" and 1 or -1)
            elseif a == "confirm" then
                open_book(library.items[library.sel].path)
            elseif a == "toc" then
                library.confirm = library.items[library.sel].path
            end
        end
        if a == "bookmark" then shop.start() end
        if a == "menu" and book then app.mode = "menu"; menu.sel = 1; menu.page = "main"; menu.top = nil end
        if a == "back" and book then app.mode = "reader" end
        redraw()
    end
end

-- Pressing and holding on the touchscreen: look up the word under the finger.
function app.on_hold(side, u, v)
    if app.mode ~= "reader" and app.mode ~= "lookup" then return end
    -- In look-up mode the other page is the definition: holds there do nothing.
    local cur = look.words[look.sel]
    if app.mode == "lookup" and cur and side ~= cur.side then return end
    local saved = look.words
    look.words = look.collect()
    local w = look.hit(side, u, v)
    if w then look.open(w) else look.words = saved end
end

-- A quick tap on the touchscreen (page coordinates of the touched side).
function app.on_tap(side, u, v)
    local mode = app.mode
    if mode == "reader" then
        local ref = side == "right" and note.hit(note.on_spread(), side, u, v)
        local bx, by, bw, bh = note.button()
        if ref then
            note.open(ref)                    -- a note number: show the note on the left page
        elseif side == "right" and #note.on_spread() > 0 and u >= bx - 16 and u <= bx + bw + 16
            and v >= by - 16 and v <= by + bh + 16 then
            note.open()                       -- the Notes button
        elseif jump and side == "right" and v > PAGE_H - 90
            and u >= margins().inner + (PAGE_W - margins().outer - margins().inner) * 0.35 then
            go_back()                         -- the "Back to ..." line
        elseif side == "right" and u > PAGE_W - 170 and v < 150 then
            toggle_bookmark()                 -- top-right corner, like a Kindle
        elseif side == "right" and v < 90 and u > PAGE_W - 230 then
            -- A gap between the bookmark corner and the status bar strip, so a
            -- slightly-off bookmark tap does nothing rather than the wrong thing.
        elseif side == "right" and v < 90 then
            -- The top edge (left of the bookmark corner): show or hide all
            -- the status bars.
            S.sb_show = not S.sb_show
            relayout()
            Store.save_settings(S)
        elseif S.tap == "next" then
            -- Turn pages: right half of the page goes forward, left half back.
            if u >= PAGE_W / 2 then turn(1, next_spread) else turn(-1, prev_spread) end
        else
            action("menu")
        end
    elseif mode == "menu" then
        -- The settings panel is drawn on the right page.
        local m = MARGINS[2]
        local items = menu_items()
        local idx
        for _, row in ipairs((menu_layout(items))) do
            if row.kind == "item" and v >= row.y and v < row.y + row.h then idx = row.idx end
        end
        if side == "right" and u >= m.inner - 14 and u <= PAGE_W - m.outer + 14 and idx then
            menu.sel = idx
            action("confirm")
        elseif side == "left" then
            action("back")            -- tapped the dimmed book page: close
        end
    elseif mode == "library" then
        local bx, by, bw, bh = library.get_books_button()
        if side == "right" and u >= bx - 20 and u <= bx + bw + 20 and v >= by - 20 and v <= by + bh + 30 then
            shop.start()
        end
    elseif mode == "lookup" then
        -- Another word on this page: look that up. Anywhere else: close.
        -- (Only on the page with the text; the other page is the definition.)
        local cur = look.words[look.sel]
        local _, i
        if cur and side == cur.side then _, i = look.hit(side, u, v) end
        if i then look.sel = i; look.find(); redraw() else action("back") end
    elseif mode == "note" then
        -- Another note number on this page: show that one. Anywhere else: close.
        local cur = note.refs[note.sel]
        local _, i
        if cur and side == cur.side then _, i = note.hit(note.refs, side, u, v) end
        if i then note.sel, note.page = i, 1; redraw() else action("back") end
    elseif mode == "shop" then
        -- Tap a row to open it; tap the right page to download or read.
        local pg = shop.page()
        if side == "left" and pg and v >= 160 then
            local idx = pg.top + math.floor((v - 160) / 96)
            if pg.entries[idx] and idx < pg.top + list_rows(96) then
                pg.sel = idx
                action("confirm")
            end
        elseif side == "right" and v > PAGE_H - 200 then
            action("confirm")
        end
    elseif mode == "about" or mode == "help" then
        action("back")
    elseif mode == "keyboard" then
        app.kb_tap(side, u, v)
    elseif mode == "fonts" then
        app.font_tap(side, u, v)
    elseif mode == "find" then
        -- Like Contents: a tap on a result (right column) opens it.
        local f, rows = app.find, list_rows(96)
        local first = f.top + rows
        local idx = first + math.floor((v - 160) / 96)
        if side == "right" and v >= 160 and idx < first + rows and f.results[idx] then
            f.sel = idx
            action("confirm")
        end
    elseif mode == "toc" or mode == "bookmarks" then
        -- A tap on a row (the bottom screen shows the list's second column)
        -- opens it, like A. Anywhere else does nothing: closing on a tap
        -- looked like the chapter had been chosen.
        local st, row_h, n = toc, 58, book and #book.toc or 0
        if mode == "bookmarks" then st, row_h, n = bm, 96, #bookmark_entries() end
        local rows = list_rows(row_h)
        local first = (st.top or 1) + rows
        local idx = first + math.floor((v - 160) / row_h)
        if side == "right" and v >= 160 and idx < first + rows and idx <= n then
            st.sel = idx
            action("confirm")
        end
    elseif mode == "message" then
        action("back")
    end
end

local BUTTON = {
    a = "confirm", b = "back", x = "menu", y = "toc",
    start = "menu", back = "bookmark", guide = "quit",
    leftstick = "stick",            -- pressing the stick in (ROCKNIX)
}

local function dpad(dir)
    action(ROTATE[S.orient][dir])
end

function love.gamepadpressed(_, button)
    local d = button:match("^dp(%a+)$")
    if d then dpad(d) return end
    local a = BUTTON[button]
    if a then action(a) end
end

-- Fallback when the controller has no gamepad mapping.
-- The L/R shoulder buttons (4, 5) and L2/R2 (10, 11) are deliberately unused.
local RAW = { [0] = "a", [1] = "b", [2] = "y", [3] = "x",
    [6] = "back", [7] = "start", [8] = "guide" }
-- Analog stick acts like the D-pad: pushing past PRESS counts as one press in
-- that direction; it must come back inside RELEASE before it can fire again,
-- so one push is one press and stick drift never turns pages.
local STICK_PRESS, STICK_RELEASE = 0.6, 0.3
-- Axes follow the gamepad mapping (leftx = raw axis 0, lefty = raw axis 1,
-- positive = right/down, like the D-pad). The mapping borrowed from another
-- port had them off by one, which made the stick's up/down read as left/right.
local stick = { x = 0, y = 0 }          -- latched direction per axis: -1, 0, 1

local function stick_axis(which, value)
    local neg, pos = "left", "right"
    if which == "y" then neg, pos = "up", "down" end
    local cur = stick[which]
    if cur == 0 then
        if value >= STICK_PRESS then
            stick[which] = 1
            log_input("stick %s=%.2f -> %s", which, value, pos); dpad(pos)
        elseif value <= -STICK_PRESS then
            stick[which] = -1
            log_input("stick %s=%.2f -> %s", which, value, neg); dpad(neg)
        end
    elseif math.abs(value) < STICK_RELEASE then
        stick[which] = 0
    end
end

function love.gamepadaxis(_, axis, value)
    if axis == "leftx" then stick_axis("x", value)
    elseif axis == "lefty" then stick_axis("y", value) end
end

-- Raw buttons that aren't in the gamepad mapping. On the RG DS Plus, button 9
-- is pressing the analog stick in: Settings while reading, OK (A) elsewhere. (The curved-arrow button
-- next to the Anbernic button is a separate "adc-keys" device that sends the
-- Back key; see KEYS below, where it toggles Settings.)
local EXTRA = { [9] = "stick" }        -- pressing the stick in
function love.joystickpressed(joystick, b)
    -- Every press goes to log.txt, so unknown buttons can be identified.
    log_input("joystick %q button %d", joystick:getName(), b - 1)
    local extra = joystick:getName() == "ANBERNIC-rk3568-keys" and EXTRA[b - 1]
    if extra then action(extra) return end
    if joystick:isGamepad() then return end
    local name = RAW[b - 1]
    if name then love.gamepadpressed(joystick, name) end
end
-- Raw axes: log big movements on any axis (to identify axes on new hardware),
-- and act on them directly when there's no gamepad mapping (axis 1 = x, 2 = y).
local raw_logged = {}
function love.joystickaxis(joystick, axis, value)
    local big = math.abs(value) >= STICK_PRESS
    if big and not raw_logged[axis] then
        log_input("raw axis %d = %.2f", axis - 1, value)
    end
    raw_logged[axis] = big
    if joystick:isGamepad() then return end
    if axis == 1 then stick_axis("x", value)
    elseif axis == 2 then stick_axis("y", value) end
end
function love.joystickhat(joystick, _, dir)
    if joystick:isGamepad() then return end
    local map = { u = "up", d = "down", l = "left", r = "right" }
    if map[dir] then dpad(map[dir]) end
end

-- Keyboard (for testing on a computer; arrow keys are page directions).
local KEYS = {
    right = "right", left = "left", up = "up", down = "down",
    space = "next", pagedown = "next", pageup = "prev", ["return"] = "confirm",
    escape = "back", m = "menu", t = "toc", q = "quit", n = "next_section", p = "prev_section",
    b = "bookmark",
    -- The curved-arrow button sends Back (adc-keys, KEY_BACK): toggle Settings.
    appback = "menu", apphome = "menu", menu = "menu", application = "menu",
}
local REPEATABLE = { right = true, left = true, up = true, down = true, next = true, prev = true }
function love.keypressed(key, scancode, isrepeat)
    local a = KEYS[key]
    if isrepeat then
        -- Holding a key repeats movement only (the Back button toggles Settings).
        if a and REPEATABLE[a] then action(a) end
        return
    end
    log_input("key %s (scancode %s)", key, scancode)
    if a then action(a) end
end

---------------------------------------------------------------- main loop

function love.load()
    app.scale = love.graphics.getWidth() / 2048
    if os.getenv("READER_SCALE") == nil then pcall(love.window.setPosition, 0, 0, 1) end
    love.graphics.setDefaultFilter("linear", "linear")
    love.keyboard.setKeyRepeat(true)

    for _, joystick in ipairs(love.joystick.getJoysticks()) do
        if joystick:getName() == "retrogame_joypad" then
            -- ROCKNIX: its own mapping goes by position (its "a" is the B
            -- button); map by the printed letters like the stock firmware.
            love.joystick.loadGamepadMappings(joystick:getGUID() ..
                ",retrogame_joypad,a:b1,b:b0,x:b2,y:b3,back:b8,start:b9,guide:b10," ..
                "leftstick:b11,dpup:b13,dpdown:b14,dpleft:b15,dpright:b16," ..
                "leftx:a0,lefty:a1,platform:Linux,")
        elseif joystick:getName() == "ANBERNIC-rk3568-keys" then
            love.joystick.loadGamepadMappings(joystick:getGUID() ..
                ",ANBERNIC-rk3568-keys,a:b0,b:b1,x:b3,y:b2," ..
                "leftshoulder:b4,rightshoulder:b5,back:b6,start:b7,guide:b8," ..
                "lefttrigger:b10,righttrigger:b11,dpup:h0.1,dpdown:h0.4," ..
                "dpleft:h0.8,dpright:h0.2,leftx:a0,lefty:a1,platform:Linux,")
        end
    end

    for _, joystick in ipairs(love.joystick.getJoysticks()) do
        print(string.format("[joystick] %q %s gamepad=%s", joystick:getName(), joystick:getGUID(),
            tostring(joystick:isGamepad())))
    end
    print("[reader] eReaderDS v" .. VERSION)
    S = Store.load_settings()
    if S.chrome == false then
        -- "Page info: Off" from older versions: hide the status bar text.
        S.sb_title, S.sb_pages, S.sb_percent = "none", "hide", false
        S.chrome = true
    end
    local n = tonumber(S.theme)
    if n then S.theme = OLD_THEME_NUMBERS[n] or "Paper" end
    Timezone.apply(S.tz)
    Touch.open("gt9xx-0")
    KeyProbe.open(function(device, code) app.on_raw_key(device, code) end,
        { ["gt9xx-0"] = true, ["Goodix Capacitive TouchScreen"] = true },  -- stock, ROCKNIX
        { [LID_DEVICE] = true, [app.BACK_DEVICE] = true })
    if S.brightness >= 0 and Backlight.available() then Backlight.set(S.brightness) end
    canvases[1] = love.graphics.newCanvas(PAGE_W, PAGE_H)
    canvases[2] = love.graphics.newCanvas(PAGE_W, PAGE_H)
    old_canvases[1] = love.graphics.newCanvas(PAGE_W, PAGE_H)
    old_canvases[2] = love.graphics.newCanvas(PAGE_W, PAGE_H)
    -- Horizontal gradient, opaque at x=0 fading to clear at x=1.
    shadow_mesh = love.graphics.newMesh({
        { 0, 0, 0, 0, 1, 1, 1, 1 }, { 1, 0, 1, 0, 1, 1, 1, 0 },
        { 1, 1, 1, 1, 1, 1, 1, 0 }, { 0, 1, 0, 1, 1, 1, 1, 1 },
    }, "fan", "static")
    turn_mesh = love.graphics.newMesh((TURN_COLS + 1) * 2, "strip", "stream")
    -- Fixed white-noise texture for the E-ink filter (same pattern every run,
    -- like a real panel's grain).
    local rng = love.math.newRandomGenerator(1234)
    local noise = love.image.newImageData(256, 256)
    noise:mapPixel(function()
        local v = rng:random()
        return v, v, v, 1
    end)
    eink_noise = love.graphics.newImage(noise)
    eink_noise:setWrap("repeat", "repeat")
    eink_noise:setFilter("nearest", "nearest")
    local ok, sh = pcall(love.graphics.newShader, EINK_SHADER)
    if ok then
        eink_shader = sh
        eink_shader:send("noise", eink_noise)
        eink_shader:send("amount", 1.3 / 15)
    else
        print("[eink] shader unavailable: " .. tostring(sh))
    end
    ui.font = load_font("GentiumBookPlus-Regular.ttf", UI_SIZE)
    ui.small = load_font("GentiumBookPlus-Regular.ttf", SMALL_SIZE)
    ui.bold = load_font("GentiumBookPlus-Bold.ttf", UI_SIZE)
    ui.small_bold = load_font("GentiumBookPlus-Bold.ttf", SMALL_SIZE)
    ui.title = load_font("GentiumBookPlus-Bold.ttf", 44)
    ui.big = load_font("GentiumBookPlus-Bold.ttf", 110)
    build_fonts()

    scan_library()
    local last = Store.get_last()
    local f = last and io.open(last, "rb")
    if f then f:close(); open_book(last) end
end

function love.quit()
    if net.thread then
        -- Stop a download (its .part file is removed) and the network thread.
        if shop.dl then love.thread.getChannel("net_cancel"):push(shop.dl.id) end
        love.thread.getChannel("net_jobs"):clear()
        love.thread.getChannel("net_jobs"):push({ kind = "quit" })
        net.thread:wait()
    end
    save_progress()
    Store.save_settings(S)
    Store.flush()
    return false
end

-- Scripted actions + screenshot, for testing without the device.
local function run_test_script()
    local script = os.getenv("READER_SCRIPT")
    if script then
        for a in script:gmatch("[^,]+") do
            local dir = a:match("^dp(%a+)$")
            local sa, sv = a:match("^stick:(%a):([%-%d.]+)$")
            local wait = tonumber(a:match("^wait:([%d.]+)$") or "")
            if wait then
                love.timer.sleep(wait)           -- simulate time spent reading
            elseif a == "lid:close" or a == "lid:open" then
                app.on_raw_key(LID_DEVICE, a == "lid:close" and LID_CLOSE or LID_OPEN)
            elseif a:match("^pinch") then                -- pinch:start:200, pinch:300, pinch:end
                local what, d = a:match("^pinch:(%a*):?([%d.]*)$")
                if what == "start" then touch_event("pinch_start", tonumber(d))
                elseif what == "end" then touch_event("pinch_end")
                else touch_event("pinch", tonumber(a:match("([%d.]+)$"))) end
            elseif a == "poll" then shop.net_poll()
            elseif a:match("^type:") then app.kb_type(a:sub(6):gsub("_", " "))
            elseif a == "work" then                -- finish a background task
                while app.task do app.task_step() end
            elseif a == "net" then               -- wait for network jobs (and the cover)
                for _ = 1, 2 do
                    local t = love.timer.getTime()
                    while net.count > 0 and love.timer.getTime() - t < 30 do
                        shop.net_poll()
                        love.timer.sleep(0.05)
                    end
                    local pg = shop.page()
                    if app.mode == "shop" and pg then shop.cover(pg.entries[pg.sel]) end
                end
            elseif dir then dpad(dir)
            elseif sa then stick_axis(sa, tonumber(sv))
            else action(a) end
        end
    end
    if os.getenv("READER_DEBUG") then
        collectgarbage("collect")
        print(string.format("[debug] memory after script: lua=%.1fMB", collectgarbage("count") / 1024))
    end
    local drag = os.getenv("READER_TOUCH")
    if drag then
        local x0, y0, x1, y1 = drag:match("([%d.]+),([%d.]+),([%d.]+),([%d.]+)")
        x0, y0, x1, y1 = tonumber(x0), tonumber(y0), tonumber(x1), tonumber(y1)
        touch_event("down", x0, y0)
        for k = 1, 10 do touch_event("move", x0 + (x1 - x0) * k / 10, y0 + (y1 - y0) * k / 10) end
        touch_event("up", x1, y1)
    end
    local freeze = tonumber(os.getenv("READER_ANIM_T") or "")
    if freeze and app.anim then app.anim.fixed = freeze
    elseif app.anim then app.anim = nil end      -- screenshot the finished page
    local out = os.getenv("READER_SHOT")
    if out then
        local shot = love.graphics.newCanvas(2048, 768)
        if app.anim then
            love.graphics.setCanvas(shot)
            compose_anim(app.anim.fixed or 0.5)
        else
            render_canvases()           -- renders the page canvases, then resets
            love.graphics.setCanvas(shot)
            compose()
        end
        draw_extra_dim()
        draw_overlay()
        love.graphics.setCanvas()
        local png = shot:newImageData():encode("png"):getString()
        local f = io.open(out, "wb"); f:write(png); f:close()
        love.event.quit()
    end
end

-- Event-driven loop: sleep until input arrives and only redraw on change.
function love.run()
    love.load(love.arg.parseGameArguments(arg), arg)
    run_test_script()
    return function()
        if (app.dirty or app.anim) and love.graphics.isActive() and not lid.closed then
            app.dirty = false
            love.graphics.origin()
            love.draw()
            love.graphics.present()
        end
        local function handle(name, a, b, c, d, e, f)
            if not name then return end
            if name == "quit" then
                if not love.quit() then return a or 0 end
            elseif name == "visible" or name == "focus" or name == "resize" or name == "displayrotated" then
                redraw()
            end
            if love.handlers[name] then love.handlers[name](a, b, c, d, e, f) end
        end
        -- Events pushed by the app itself (e.g. quit) sit in LÖVE's own queue,
        -- which love.event.wait() never looks at, so drain that first.
        local got = false
        love.event.pump()
        for name, a, b, c, d, e, f in love.event.poll() do
            got = true
            local r = handle(name, a, b, c, d, e, f)
            if r then return r end
        end
        if Touch.enabled and Touch.poll(lid.closed and function() end or touch_event) then got = true end
        if KeyProbe.enabled and KeyProbe.poll() then got = true end
        if gesture and not gesture.mode and not gesture.held and gesture.moved < 30
            and love.timer.getTime() - gesture.t0 > 0.6 then
            gesture.held = true                -- press and hold
            app.on_hold(gesture.side, gesture.u0, gesture.v0)
        end
        if shop.net_poll() then got = true end
        if app.task and not lid.closed then app.task_step(); got = true end
        if overlay and love.timer.getTime() >= overlay.hide_at then overlay = nil; redraw() end
        if save_due and love.timer.getTime() >= save_due then save_progress() end
        if app.mode == "library" and not lid.closed then
            -- Wi-Fi coming or going changes the Get books button.
            local was = shop.online_v
            if shop.online() ~= was and was ~= nil then redraw() end
        end
        if lid.closed then
            lid_tick()
            love.timer.sleep(0.25)              -- screens are off: check rarely
        end
        if S.sb_show and S.sb_clock ~= "off" and (app.mode == "reader" or app.mode == "menu") then
            local minute = os.date("%H%M")
            if minute ~= app.clock_minute then app.clock_minute = minute; redraw() end
        end
        if app.anim or app.task then
            love.timer.sleep(0.001)            -- animating or working: next frame
        elseif Touch.enabled or overlay or net.count > 0 then
            -- Touch events don't wake love.event.wait(), so poll at a gentle rate.
            if not got and not app.dirty then love.timer.sleep(gesture and 0.008 or 0.025) end
        elseif not got then
            local r = handle(love.event.wait())
            if r then return r end
        end
    end
end
