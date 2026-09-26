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
local OLD_THEME_NUMBERS = { "Paper", "White", "Sepia", "Night" }
local MARGINS = { { name = "Narrow", outer = 36, inner = 28 }, { name = "Normal", outer = 60, inner = 44 }, { name = "Wide", outer = 90, inner = 64 } }
-- Space above and below the text (the header/footer sit inside it).
local VMARGINS = { { name = "Narrow", size = 60 }, { name = "Normal", size = 76 }, { name = "Wide", size = 110 }, { name = "Extra wide", size = 150 } }

local S                      -- settings (persisted)
local app = {
    mode = "library",        -- library | reader | menu | toc | message
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
local images = {}            -- src -> Image (per open book)
local book, pages_cache = nil, {}
local pos = { ch = 1, off = 0 }  -- reading position (start of left page)
local spread = nil           -- { ch, pi, pages }
local library = { items = {}, sel = 1, top = 1 }
local menu = { sel = 1 }
local toc = { sel = 1, top = 1 }
local message = nil

---------------------------------------------------------------- utilities

local function theme_index()
    for i, t in ipairs(THEMES) do if t.name == S.theme then return i end end
    return 1
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
    pages_cache = {}
end

local function margins() return MARGINS[S.margins] or MARGINS[2] end
local function vmargin() return (VMARGINS[S.vmargins] or VMARGINS[2]).size end
local function content_size()
    local m = margins()
    return PAGE_W - m.outer - m.inner, PAGE_H - vmargin() * 2
end

---------------------------------------------------------------- images

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
    end
    return img or nil
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
            image_size = function(src)
                local img = get_image(src)
                if img then return img:getDimensions() end
            end,
        })
        pages_cache[ch] = p
        if os.getenv("READER_DEBUG") then
            print(string.format("layout ch=%d pages=%d %.0fms", ch, #p, (love.timer.getTime() - t0) * 1000))
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

local function goto_pos(ch, off)
    ch = math.max(1, math.min(ch, #book.chapters))
    local pages = pages_for(ch)
    set_spread(ch, Layout.find_page(pages, off))
end

local function save_progress()
    if book then
        Store.set_progress(book.path, pos.ch, pos.off, book:fraction(pos.ch, pos.off))
    end
end

local function next_spread()
    if not spread then return end
    if spread.pi + 2 <= #spread.pages then
        set_spread(spread.ch, spread.pi + 2)
    elseif spread.ch < #book.chapters then
        set_spread(spread.ch + 1, 1)
    else
        return
    end
    save_progress()
end

local function prev_spread()
    if not spread then return end
    if spread.pi - 2 >= 1 then
        set_spread(spread.ch, spread.pi - 2)
    elseif spread.ch > 1 then
        local pages = pages_for(spread.ch - 1)
        set_spread(spread.ch - 1, #pages)
    else
        return
    end
    save_progress()
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

---------------------------------------------------------------- opening books

local function show_message(text)
    message = text
    app.mode = "message"
    redraw()
end

local function open_book(path)
    local ok, b, err = pcall(Book.open, path)
    if not ok or not b then
        show_message("Could not open this book.\n\n" .. tostring(ok and err or b))
        return
    end
    book = b
    images, pages_cache = {}, {}
    local pr = Store.get_progress(path)
    app.mode = "reader"
    if pr then goto_pos(pr.ch, pr.off) else goto_pos(1, 0) end
    Store.set_last(path)
    save_progress()
end

local function scan_library()
    local items = {}
    local seen = {}
    for _, dir in ipairs(Store.book_dirs()) do
        local p = io.popen('ls -1 "' .. dir .. '" 2>/dev/null')
        if p then
            for name in p:lines() do
                local ext = (name:match("%.([^.]+)$") or ""):lower()
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
    table.sort(items, function(a, b) return a.title:lower() < b.title:lower() end)
    library.items = items
    library.sel = math.max(1, math.min(library.sel, #items))
    library.preview = nil
end

local function library_preview()
    local it = library.items[library.sel]
    if not it then return nil end
    if library.preview and library.preview.path == it.path then return library.preview end
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
    end
    library.preview = pv
    return pv
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

---------------------------------------------------------------- menu

local function menu_items()
    local th = theme()
    return {
        { label = "Resume reading", act = function() app.mode = "reader" end },
        { label = "Contents", act = function()
            if #book.toc == 0 then return end
            toc.sel = current_section() or 1
            toc.top = nil
            app.mode = "toc"
        end },
        { label = "Text size", value = tostring(S.font_size), adjust = function(d)
            S.font_size = math.max(18, math.min(64, S.font_size + d * 2)); build_fonts(); goto_pos(pos.ch, pos.off)
        end },
        -- The font's name is drawn in the font itself: a preview, and the only way
        -- names in other scripts (e.g. Chinese firmware fonts) can display.
        { label = "Font", value = fonts.name or S.font,
          value_font = Fonts.preview(fonts.name or S.font, UI_SIZE), adjust = function(d)
            local list = Fonts.list()
            local idx = 1
            for k, f in ipairs(list) do if f.name == fonts.name then idx = k end end
            S.font = list[(idx - 1 + d) % #list + 1].name
            build_fonts(); goto_pos(pos.ch, pos.off)
        end },
        { label = "Line spacing", value = string.format("%.2f", S.spacing), adjust = function(d)
            S.spacing = math.floor(math.max(0.75, math.min(2.0, S.spacing + d * 0.05)) * 100 + 0.5) / 100; pages_cache = {}; goto_pos(pos.ch, pos.off)
        end },
        { label = "Side margins", value = margins().name, adjust = function(d)
            S.margins = (S.margins - 1 + d) % #MARGINS + 1; pages_cache = {}; goto_pos(pos.ch, pos.off)
        end },
        { label = "Top/bottom margins", value = (VMARGINS[S.vmargins] or VMARGINS[2]).name, adjust = function(d)
            S.vmargins = (S.vmargins - 1 + d) % #VMARGINS + 1; pages_cache = {}; goto_pos(pos.ch, pos.off)
        end },
        { label = "Justify text", value = S.justify and "On" or "Off", adjust = function()
            S.justify = not S.justify; pages_cache = {}; goto_pos(pos.ch, pos.off)
        end },
        { label = "Brightness", value = Backlight.available() and ((S.brightness >= 0 and S.brightness or Backlight.get() or 0) .. "%") or "n/a",
            adjust = function(d)
                if not Backlight.available() then return end
                local cur = S.brightness >= 0 and S.brightness or Backlight.get() or 50
                S.brightness = Backlight.step(cur, d)
                Backlight.set(S.brightness)
            end },
        { label = "Theme", value = th.name, adjust = function(d)
            S.theme = THEMES[(theme_index() - 1 + d) % #THEMES + 1].name
        end },
        { label = "Page turn", value = ({ flip = "Flip", fade = "Fade", off = "Off" })[S.anim] or "Flip",
            adjust = function(d)
                local order = { "flip", "fade", "off" }
                local idx = 1
                for k, v in ipairs(order) do if v == S.anim then idx = k end end
                S.anim = order[(idx - 1 + d) % #order + 1]
            end },
        { label = "Tap", value = S.tap == "next" and "Turn pages" or "Open menu", adjust = function()
            S.tap = S.tap == "next" and "menu" or "next"
        end },
        { label = "Page info", value = S.chrome and "On" or "Off", adjust = function()
            S.chrome = not S.chrome
        end },
        { label = "Jump to % (" .. math.floor(book:fraction(pos.ch, pos.off) * 100 + 0.5) .. ")", value = "", adjust = function(d)
            local f = book:fraction(pos.ch, pos.off) + d * 0.01
            goto_pos(book:locate(math.max(0, math.min(1, f))))
            save_progress()
        end },
        { label = "About", act = function() app.mode = "about" end },
        { label = "Library", act = go_library },
        { label = "Quit", act = function() love.event.quit() end },
    }
end

---------------------------------------------------------------- drawing

local function draw_header_footer(side, left_text, right_text)
    if not S.chrome then return end
    local th = theme()
    local m = margins()
    local x = side == "left" and m.outer or m.inner
    local w = PAGE_W - m.outer - m.inner
    love.graphics.setFont(ui.small)
    color(th.dim)
    if left_text then
        love.graphics.printf(fit_text(ui.small, left_text, w), x, 26, w, side == "left" and "left" or "right")
    end
    if right_text then
        love.graphics.printf(right_text, x, PAGE_H - 26 - ui.small:getHeight(), w, side == "left" and "left" or "right")
    end
end

local function draw_page(page, side)
    local th = theme()
    local m = margins()
    local ox = side == "left" and m.outer or m.inner
    local oy = vmargin()
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

local function draw_reader_pages()
    local sec = current_section()
    local sec_title = sec and book.toc[sec].title or ""
    local frac = book:fraction(pos.ch, pos.off)
    local left, right = spread.pages[spread.pi], spread.pages[spread.pi + 1]

    -- pages left in this section
    local left_info
    local nxt = sec and book.toc[sec + 1] or (not sec and book.toc[1])
    local remaining
    if nxt and nxt.chapter == spread.ch then
        local _, off = toc_pos(nxt)
        remaining = Layout.find_page(spread.pages, off) - (spread.pi + 1)
        if off > 0 and spread.pages[Layout.find_page(spread.pages, off)].off == off then
            remaining = remaining - 1
        end
    else
        remaining = #spread.pages - (spread.pi + 1)
    end
    if remaining and remaining > 0 then
        left_info = remaining == 1 and "1 page left in chapter" or (remaining .. " pages left in chapter")
    end

    return function(side)
        if side == "left" then
            draw_page(left, "left")
            draw_header_footer("left", book.title, left_info)
        else
            draw_page(right, "right")
            draw_header_footer("right", sec_title, string.format("%d%%", math.floor(frac * 100 + 0.5)))
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
        local row_h = 96
        local rows = list_rows(row_h)
        if #library.items == 0 then
            love.graphics.setFont(ui.font)
            color(th.dim)
            love.graphics.printf("No books found.\n\nCopy .epub or .txt files into the Ebook folder on your SD card.",
                x, 180, w, "left")
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
            local pr = Store.get_progress(it.path)
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
        love.graphics.print("A  open      B  back to book      Menu  quit", x, PAGE_H - 70)
        love.graphics.printf("v" .. VERSION, x, PAGE_H - 70, w, "right")
    else
        local pv = library_preview()
        if not pv then return end
        local x, w = MARGINS[2].inner, PAGE_W - MARGINS[2].outer - MARGINS[2].inner
        local y = 80
        if pv.cover then
            local iw, ih = pv.cover:getDimensions()
            local s = math.min(w / iw, 620 / ih)
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
    end
end

-- Settings list geometry. Rows shrink (down to a minimum) to fit every item;
-- if there are still too many, the list scrolls with the selection.
local MENU_TOP, MENU_BOTTOM = 140, PAGE_H - 90
local MENU_ROW_MAX, MENU_ROW_MIN = 52, 44

local function menu_layout(n)
    local avail = MENU_BOTTOM - MENU_TOP
    local row_h = math.max(MENU_ROW_MIN, math.min(MENU_ROW_MAX, math.floor(avail / n)))
    local rows = math.min(n, math.floor(avail / row_h))
    -- keep the selection visible
    menu.top = menu.top or 1
    if menu.sel < menu.top then menu.top = menu.sel end
    if menu.sel > menu.top + rows - 1 then menu.top = menu.sel - rows + 1 end
    menu.top = math.max(1, math.min(menu.top, n - rows + 1))
    return row_h, rows, menu.top
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
    love.graphics.print("Settings", x, 60)
    love.graphics.setFont(ui.small)
    color(th.dim)
    love.graphics.printf("v" .. VERSION, x, 78, w, "right")
    local items = menu_items()
    local row_h, rows, top = menu_layout(#items)
    if top > 1 then color(th.dim); scroll_arrow(x + w / 2, MENU_TOP - 16, true) end
    if top + rows - 1 < #items then color(th.dim); scroll_arrow(x + w / 2, MENU_TOP + rows * row_h + 6, false) end
    draw_list(side, items, menu.sel, top, rows, x, MENU_TOP, w, row_h, function(it, _, rx, ry, rw, selected)
        love.graphics.setFont(ui.font)
        color(th.fg)
        local ty = centered_y(ui.font, UI_SIZE, ry, row_h - 4)
        love.graphics.print(it.label, rx, ty)
        local vf = it.value_font
        if vf and it.value and it.value ~= "" and vf:hasGlyphs(it.value) then
            local room = rw - ui.font:getWidth(it.label) - 40
            local open, close = "‹  ", "  ›"
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
    end)
    love.graphics.setFont(ui.small)
    color(th.dim)
    love.graphics.printf("A select    ‹ › change    B back", x, PAGE_H - 70, w, "left")
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

local CREDITS = {
    { "Fonts", "Gentium Book Plus and Charis SIL (SIL International), Literata "
        .. "(TypeTogether), Source Serif 4 (Adobe), Crimson Text (Sebastian Kosch), "
        .. "Bitter (Huerta Tipográfica), Atkinson Hyperlegible Next (Braille "
        .. "Institute), Inter (Rasmus Andersson), Lexend (Lexend Project) and "
        .. "OpenDyslexic (Abbie Gonzalez). SIL Open Font License 1.1." },
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
    elseif app.mode == "menu" then
        local reader = draw_reader_pages()
        painter = function(side)
            if side == "left" then reader("left") else draw_menu_panel(side) end
        end
    elseif app.mode == "toc" then painter = draw_toc
    elseif app.mode == "about" then painter = draw_about
    elseif app.mode == "message" then painter = draw_message
    else painter = draw_library end

    for i, side in ipairs({ "left", "right" }) do
        love.graphics.setCanvas(canvases[i])
        love.graphics.clear(th.bg[1], th.bg[2], th.bg[3], 1)
        love.graphics.origin()
        painter(side)
        if app.mode == "menu" and side == "left" then
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
    local side, u, v = touch_to_page(sx, sy)
    local now = love.timer.getTime()
    if kind == "down" then
        gesture = { side = side, u0 = u, v0 = v, u = u, t0 = now, moved = 0 }
    elseif kind == "move" and gesture then
        local du, dv = u - gesture.u0, v - gesture.v0
        gesture.moved = math.max(gesture.moved, math.abs(du), math.abs(dv))
        gesture.u = u
        if not gesture.mode and math.abs(du) > 24 and math.abs(du) > math.abs(dv) * 1.5 then
            gesture.mode = "swipe"          -- mostly horizontal: page turn on release
        elseif not gesture.mode and math.abs(dv) > 24 and math.abs(dv) > math.abs(du) * 1.5 then
            -- Mostly vertical slide: brightness. Work in sqrt space so the
            -- dim end gets finer control.
            gesture.mode = "brightness"
            gesture.v0 = v
            gesture.p0 = math.sqrt(current_brightness() / 100)
        end
        if gesture.mode == "brightness" then
            local p = gesture.p0 + (gesture.v0 - v) / (PAGE_H * 0.8)
            local pct = math.max(1, math.min(100, math.floor(p * p * 100 + 0.5)))
            if Backlight.available() and pct ~= S.brightness then
                S.brightness = pct
                Backlight.set(pct)
            end
            overlay = { side = gesture.side, pct = Backlight.available() and pct or nil, hide_at = now + 1e9 }
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
        elseif gesture.moved < 30 and now - gesture.t0 < 0.5 and app.on_tap then
            app.on_tap(gesture.side, gesture.u0, gesture.v0)
        end
        gesture = nil
    end
end

local function draw_overlay()
    if not overlay then return end
    love.graphics.push()
    page_transform(overlay.side)
    local w, h = 460, 118
    local x, y = (PAGE_W - w) / 2, 120
    love.graphics.setColor(0.08, 0.08, 0.08, 0.94)
    love.graphics.rectangle("fill", x, y, w, h, 22, 22)
    love.graphics.setColor(1, 1, 1, 0.95)
    love.graphics.setFont(ui.font)
    if overlay.pct then
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

function love.draw()
    love.graphics.push()
    love.graphics.scale(app.scale)
    frame()
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

-- Physical d-pad -> direction on the sideways page.
local ROTATE = {
    left = { up = "left", right = "up", down = "right", left = "down" },
    right = { up = "right", right = "down", down = "left", left = "up" },
}

local function action(a)
    local mode = app.mode
    if a == "quit" then love.event.quit() return end

    if mode == "message" then
        if a == "confirm" or a == "back" then app.mode = book and "reader" or "library"; redraw() end
        return
    end

    if mode == "reader" then
        if a == "next" or a == "right" or a == "down" then turn(1, next_spread)
        elseif a == "prev" or a == "left" or a == "up" then turn(-1, prev_spread)
        elseif a == "next_section" then jump_section(1)
        elseif a == "prev_section" then jump_section(-1)
        elseif a == "menu" or a == "back" then app.mode = "menu"; menu.sel = 1
        elseif a == "toc" and #book.toc > 0 then
            toc.sel = current_section() or 1; toc.top = nil; app.mode = "toc"
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
        elseif a == "back" or a == "menu" then app.mode = "reader" end
        Store.save_settings(S)
        redraw()
        return
    end

    if mode == "about" then
        if a == "back" or a == "confirm" or a == "menu" then app.mode = "menu" end
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
            goto_pos(toc_pos(book.toc[toc.sel])); save_progress(); app.mode = "reader"
        elseif a == "back" or a == "toc" or a == "menu" then app.mode = "reader" end
        redraw()
        return
    end

    if mode == "library" then
        local n = #library.items
        if n > 0 then
            if a == "up" or a == "left" or a == "prev" then library.sel = math.max(1, library.sel - 1)
            elseif a == "down" or a == "right" or a == "next" then library.sel = math.min(n, library.sel + 1)
            elseif a == "confirm" then open_book(library.items[library.sel].path) end
        end
        if a == "menu" and book then app.mode = "menu"; menu.sel = 1 end
        if a == "back" and book then app.mode = "reader" end
        redraw()
    end
end

-- A quick tap on the touchscreen (page coordinates of the touched side).
function app.on_tap(side, u, v)
    local mode = app.mode
    if mode == "reader" then
        if S.tap == "next" then
            -- Turn pages: right half of the page goes forward, left half back.
            if u >= PAGE_W / 2 then turn(1, next_spread) else turn(-1, prev_spread) end
        else
            action("menu")
        end
    elseif mode == "menu" then
        -- The settings panel is drawn on the right page.
        local m = MARGINS[2]
        local items = menu_items()
        local row_h, rows, top = menu_layout(#items)
        local r = math.floor((v - MENU_TOP) / row_h)
        local idx = (r >= 0 and r < rows) and top + r or nil
        if side == "right" and u >= m.inner - 14 and u <= PAGE_W - m.outer + 14 and items[idx] then
            menu.sel = idx
            action("confirm")
        elseif side == "left" then
            action("back")            -- tapped the dimmed book page: close
        end
    elseif mode == "about" then
        action("back")
    elseif mode == "toc" or mode == "message" then
        action("back")
    end
end

local BUTTON = {
    a = "confirm", b = "back", x = "menu", y = "toc",
    start = "menu", back = "menu", guide = "quit",
    rightshoulder = "next", leftshoulder = "prev",
    righttrigger = "next_section", lefttrigger = "prev_section",
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
local RAW = { [0] = "a", [1] = "b", [2] = "y", [3] = "x", [4] = "leftshoulder", [5] = "rightshoulder",
    [6] = "back", [7] = "start", [8] = "guide", [10] = "lefttrigger", [11] = "righttrigger" }
-- Analog stick acts like the D-pad: pushing past PRESS counts as one press in
-- that direction; it must come back inside RELEASE before it can fire again,
-- so one push is one press and stick drift never turns pages.
local STICK_PRESS, STICK_RELEASE = 0.6, 0.3
-- Stick axes after the gamepad mapping (leftx = raw axis 0, lefty = raw axis 1,
-- positive = right/down, like the D-pad). The mapping borrowed from another
-- port had them off by one, which made the stick's up/down read as left/right.
local STICK_MAP = { x = { axis = "x", sign = 1 }, y = { axis = "y", sign = 1 } }
local stick = { x = 0, y = 0 }          -- latched direction per axis: -1, 0, 1

local function stick_axis(raw, value)
    local m = STICK_MAP[raw]
    local which = m.axis
    local raw_value = value
    value = value * m.sign
    local neg, pos = "left", "right"
    if which == "y" then neg, pos = "up", "down" end
    local cur = stick[which]
    if cur == 0 then
        if value >= STICK_PRESS then
            stick[which] = 1
            print(string.format("[input] stick raw %s=%.2f -> %s", raw, raw_value, pos)); dpad(pos)
        elseif value <= -STICK_PRESS then
            stick[which] = -1
            print(string.format("[input] stick raw %s=%.2f -> %s", raw, raw_value, neg)); dpad(neg)
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
-- is pressing the analog stick in: it acts as OK (A). (The curved-arrow button
-- next to the Anbernic button is a separate "adc-keys" device that sends the
-- Back key; see KEYS below, where it toggles Settings.)
local EXTRA = { [9] = "confirm" }
function love.joystickpressed(joystick, b)
    -- Every press goes to log.txt, so unknown buttons can be identified.
    print(string.format("[input] joystick %q button %d", joystick:getName(), b - 1))
    local extra = EXTRA[b - 1]
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
        print(string.format("[input] raw axis %d = %.2f", axis - 1, value))
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
    -- The curved-arrow button sends Back (adc-keys, KEY_BACK): toggle Settings.
    appback = "menu", apphome = "menu", menu = "menu", application = "menu",
}
function love.keypressed(key, scancode)
    print(string.format("[input] key %s (scancode %s)", key, scancode))
    local a = KEYS[key]
    if a then action(a) end
end

---------------------------------------------------------------- main loop

function love.load()
    app.scale = love.graphics.getWidth() / 2048
    if os.getenv("READER_SCALE") == nil then pcall(love.window.setPosition, 0, 0, 1) end
    love.graphics.setDefaultFilter("linear", "linear")
    love.keyboard.setKeyRepeat(true)

    for _, joystick in ipairs(love.joystick.getJoysticks()) do
        if joystick:getName() == "ANBERNIC-rk3568-keys" then
            love.joystick.loadGamepadMappings(joystick:getGUID() ..
                ",ANBERNIC-rk3568-keys,a:b0,b:b1,x:b3,y:b2," ..
                "leftshoulder:b4,rightshoulder:b5,back:b6,start:b7,guide:b8," ..
                "lefttrigger:b10,righttrigger:b11,dpup:h0.1,dpdown:h0.4," ..
                "dpleft:h0.8,dpright:h0.2,leftx:a0,lefty:a1,platform:Linux,")
        end
    end

    print("[reader] eReaderDS v" .. VERSION)
    S = Store.load_settings()
    local n = tonumber(S.theme)
    if n then S.theme = OLD_THEME_NUMBERS[n] or "Paper" end
    Touch.open("gt9xx-0")
    KeyProbe.open(nil, "gt9xx-0")
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
    ui.title = load_font("GentiumBookPlus-Bold.ttf", 44)
    build_fonts()

    scan_library()
    local last = Store.get_last()
    if last and io.open(last, "rb") then open_book(last) end
end

function love.quit()
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
            if dir then dpad(dir)
            elseif sa then stick_axis(sa, tonumber(sv))
            else action(a) end
        end
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
    if freeze and app.anim then app.anim.fixed = freeze end
    local out = os.getenv("READER_SHOT")
    if out then
        local shot = love.graphics.newCanvas(2048, 768)
        if app.anim then
            love.graphics.setCanvas(shot)
            compose_anim(app.anim.fixed or 0.5)
        else
            love.graphics.setCanvas(shot)
            render_canvases()
            love.graphics.setCanvas(shot)
            compose()
        end
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
        if (app.dirty or app.anim) and love.graphics.isActive() then
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
        if Touch.enabled and Touch.poll(touch_event) then got = true end
        if KeyProbe.enabled and KeyProbe.poll() then got = true end
        if overlay and love.timer.getTime() >= overlay.hide_at then overlay = nil; redraw() end
        if app.anim then
            love.timer.sleep(0.001)            -- animating: next frame (vsync paces it)
        elseif Touch.enabled or overlay then
            -- Touch events don't wake love.event.wait(), so poll at a gentle rate.
            if not got and not app.dirty then love.timer.sleep(gesture and 0.008 or 0.025) end
        elseif not got then
            local r = handle(love.event.wait())
            if r then return r end
        end
    end
end
