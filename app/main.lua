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

local function next_spread()
    if not spread then return end
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
    if book and book ~= b then book:close() end
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

-- Status bar option values, in cycling order.
local SB = {
    title = { "none", "book", "chapter", "both" },
    pages = { "hide", "left", "of" },
    bar = { "none", "chapter", "book" },
    bar_size = { 1, 2, 3 },
    clock = { "off", "12", "24" },
}
local SB_NAMES = {
    title = { none = "None", book = "Book", chapter = "Chapter", both = "Both" },
    pages = { hide = "Hide", left = "Pages left", of = "Page X of Y" },
    bar = { none = "None", chapter = "Chapter", book = "Book" },
    bar_size = { [1] = "Thin", [2] = "Medium", [3] = "Thick" },
    clock = { off = "Off", ["12"] = "12-hour", ["24"] = "24-hour" },
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

local function relayout() pages_cache = {}; goto_pos(pos.ch, pos.off) end

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
            { label = "Book percentage", value = S.sb_percent and "Show" or "Hide", adjust = function()
                S.sb_percent = not S.sb_percent end },
            { label = "Progress bar", value = SB_NAMES.bar[S.sb_bar], adjust = function(d)
                S.sb_bar = cycle(SB.bar, S.sb_bar, d) end },
            { label = "Bar thickness", value = SB_NAMES.bar_size[S.sb_bar_size], adjust = function(d)
                S.sb_bar_size = cycle(SB.bar_size, S.sb_bar_size, d) end },
        }),
        section("", {
            { label = "Back", act = function() menu.page = "main"; menu.sel = menu.status_row or 1; menu.top = nil end },
        })
    )
end

local function menu_items()
    if menu.page == "status" then return status_items() end
    local th = theme()
    return join(
        section(nil, {
            { label = "Resume reading", act = function() app.mode = "reader" end },
            { label = "Contents", act = function()
                if #book.toc == 0 then return end
                toc.sel = current_section() or 1
                toc.top = nil
                app.mode = "toc"
            end },
            { label = "Jump to % (" .. math.floor(book:fraction(pos.ch, pos.off) * 100 + 0.5) .. ")", value = "", adjust = function(d)
                local f = book:fraction(pos.ch, pos.off) + d * 0.01
                goto_pos(book:locate(math.max(0, math.min(1, f))))
                save_progress()
            end },
            { label = "Library", act = go_library },
        }),
        section("Text", {
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
        }),
        section("Layout", {
            { label = "Side margins", value = margins().name, adjust = function(d)
                S.margins = (S.margins - 1 + d) % #MARGINS + 1; relayout()
            end },
            { label = "Top/bottom margins", value = (VMARGINS[S.vmargins] or VMARGINS[2]).name, adjust = function(d)
                S.vmargins = (S.vmargins - 1 + d) % #VMARGINS + 1; relayout()
            end },
            { label = "Status bar", value = "›", act = function()
                menu.status_row = menu.sel; menu.page = "status"; menu.sel = 1; menu.top = nil
            end },
        }),
        section("Display", {
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
            { label = "Closing the lid", value = S.lid == "sleep" and "Sleep" or "Screen off", adjust = function()
                S.lid = S.lid == "sleep" and "screen" or "sleep"; S.lid_failed = nil
            end },
        }),
        section("Page turns", {
            { label = "Animation", value = ({ flip = "Flip", fade = "Fade", off = "Off" })[S.anim] or "Flip",
              adjust = function(d) S.anim = cycle({ "flip", "fade", "off" }, S.anim, d) end },
            { label = "Tap", value = S.tap == "next" and "Turn pages" or "Open menu", adjust = function()
                S.tap = S.tap == "next" and "menu" or "next"
            end },
        }),
        section("", {
            { label = "About", act = function() app.mode = "about" end },
            { label = "Quit", act = function() love.event.quit() end },
        })
    )
end

---------------------------------------------------------------- drawing

local function draw_page(page, side)
    local th = theme()
    local m = margins()
    local ox = side == "left" and m.outer or m.inner
    local oy = text_top()
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

    -- Right page top: clock at the left (by the hinge), battery in the outer
    -- corner. The title fits between them: [title_x, title_x + title_w].
    local title_x, title_w = outer_x, w
    if side == "right" then
        if info.clock then
            color(th.dim)
            love.graphics.print(info.clock, outer_x, head_y)
            local cw = ui.small:getWidth(info.clock) + 24
            title_x, title_w = title_x + cw, title_w - cw
        end
        if info.battery then
            local bw = draw_battery(0, 0, info.battery, true)
            draw_battery(outer_x + w - bw, head_y, info.battery)
            title_w = title_w - bw - 24
        end
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
    if S.sb_bar == "book" then
        info.bar_frac = frac
    elseif S.sb_bar == "chapter" then
        info.bar_frac = math.max(0, math.min(1, (shown - first + 1) / math.max(1, last - first + 1)))
    end

    return function(side)
        if side == "left" then
            draw_page(left, "left")
        else
            draw_page(right, "right")
        end
        draw_status(side, info)
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

-- Settings list geometry. Items are grouped under small section headers;
-- item rows shrink (down to a minimum) so everything fits, and if it still
-- doesn't, the list scrolls with the selection.
local MENU_TOP, MENU_BOTTOM = 120, PAGE_H - 78
local MENU_ROW_MAX, MENU_ROW_MIN = 52, 38
local MENU_HEADER_H, MENU_GAP_H = 30, 10

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
    love.graphics.print(menu.page == "status" and "Status bar" or "Settings", x, 60)
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
        end
    end
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
        if app.mode == "menu" and side == "left" and menu.page ~= "status" then
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

function app.on_raw_key(device, code)
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

local function action(a)
    if lid.closed then return end         -- pocket presses while the lid is shut
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
        elseif a == "menu" or a == "back" then app.mode = "menu"; menu.sel = 1; menu.page = "main"; menu.top = nil
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
        elseif a == "back" and menu.page == "status" then
            menu.page = "main"; menu.sel = menu.status_row or 1; menu.top = nil
        elseif a == "back" or a == "menu" then app.mode = "reader"; menu.page = "main" end
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
        if a == "menu" and book then app.mode = "menu"; menu.sel = 1; menu.page = "main"; menu.top = nil end
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
-- is pressing the analog stick in: it acts as OK (A). (The curved-arrow button
-- next to the Anbernic button is a separate "adc-keys" device that sends the
-- Back key; see KEYS below, where it toggles Settings.)
local EXTRA = { [9] = "confirm" }
function love.joystickpressed(joystick, b)
    -- Every press goes to log.txt, so unknown buttons can be identified.
    log_input("joystick %q button %d", joystick:getName(), b - 1)
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
    if S.chrome == false then
        -- "Page info: Off" from older versions: hide the status bar text.
        S.sb_title, S.sb_pages, S.sb_percent = "none", "hide", false
        S.chrome = true
    end
    local n = tonumber(S.theme)
    if n then S.theme = OLD_THEME_NUMBERS[n] or "Paper" end
    Timezone.apply(S.tz)
    Touch.open("gt9xx-0")
    KeyProbe.open(function(device, code) app.on_raw_key(device, code) end, "gt9xx-0")
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
    local f = last and io.open(last, "rb")
    if f then f:close(); open_book(last) end
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
            if a == "lid:close" or a == "lid:open" then
                app.on_raw_key(LID_DEVICE, a == "lid:close" and LID_CLOSE or LID_OPEN)
            elseif dir then dpad(dir)
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
        if overlay and love.timer.getTime() >= overlay.hide_at then overlay = nil; redraw() end
        if save_due and love.timer.getTime() >= save_due then save_progress() end
        if lid.closed then
            lid_tick()
            love.timer.sleep(0.25)              -- screens are off: check rarely
        end
        if S.sb_show and S.sb_clock ~= "off" and (app.mode == "reader" or app.mode == "menu") then
            local minute = os.date("%H%M")
            if minute ~= app.clock_minute then app.clock_minute = minute; redraw() end
        end
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
