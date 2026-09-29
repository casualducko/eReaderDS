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
    { name = "Midnight",  bg = { 0.07, 0.07, 0.07 },    fg = { 0.78, 0.77, 0.74 }, dim = { 0.45, 0.44, 0.42 }, sel = { 0.22, 0.22, 0.22 } },
    { name = "Amber",     bg = { 0.075, 0.055, 0.035 }, fg = { 0.90, 0.64, 0.33 }, dim = { 0.55, 0.40, 0.22 }, sel = { 0.20, 0.14, 0.08 } },
    { name = "Black",     bg = { 0, 0, 0 },             fg = { 0.62, 0.62, 0.62 }, dim = { 0.36, 0.36, 0.36 }, sel = { 0.16, 0.16, 0.16 } },
    -- Light versions of dark palettes listed below (Gruvbox, Catppuccin
    -- Latte, Rosé Pine Dawn), a warm parchment, and a pale blue (tinted pages
    -- some readers, dyslexic readers especially, find easier than white).
    { name = "Gruvbox Light",    bg = { 0.984, 0.945, 0.780 }, fg = { 0.235, 0.220, 0.212 }, dim = { 0.486, 0.435, 0.392 }, sel = { 0.902, 0.851, 0.682 } },
    { name = "Catppuccin Latte", bg = { 0.937, 0.945, 0.961 }, fg = { 0.298, 0.310, 0.412 }, dim = { 0.549, 0.561, 0.631 }, sel = { 0.835, 0.851, 0.890 } },
    { name = "Rosé Pine Dawn",   bg = { 0.980, 0.957, 0.929 }, fg = { 0.341, 0.322, 0.475 }, dim = { 0.596, 0.576, 0.647 }, sel = { 0.918, 0.875, 0.839 } },
    { name = "Parchment",        bg = { 0.929, 0.878, 0.769 }, fg = { 0.227, 0.180, 0.125 }, dim = { 0.490, 0.420, 0.322 }, sel = { 0.863, 0.796, 0.651 } },
    { name = "Sky",              bg = { 0.894, 0.925, 0.957 }, fg = { 0.118, 0.165, 0.220 }, dim = { 0.369, 0.431, 0.502 }, sel = { 0.792, 0.843, 0.898 } },
    -- The Kindle app's green page: pale mint, dark gray-green text; restful at low brightness.
    { name = "Mint",             bg = { 0.800, 0.902, 0.816 }, fg = { 0.247, 0.302, 0.271 }, dim = { 0.431, 0.506, 0.463 }, sel = { 0.698, 0.831, 0.722 } },
    -- Dark palettes readers and programmers like for long sessions (Gruvbox,
    -- Nord, Solarized, Dracula, Catppuccin, Everforest), a warm dark sepia,
    -- and red on black, which keeps eyes used to the dark.
    { name = "Dark Sepia",     bg = { 0.169, 0.133, 0.098 }, fg = { 0.851, 0.780, 0.655 }, dim = { 0.561, 0.482, 0.376 }, sel = { 0.275, 0.220, 0.165 } },
    { name = "Gruvbox",        bg = { 0.157, 0.157, 0.157 }, fg = { 0.922, 0.859, 0.698 }, dim = { 0.573, 0.514, 0.455 }, sel = { 0.235, 0.220, 0.212 } },
    { name = "Nord",           bg = { 0.180, 0.204, 0.251 }, fg = { 0.847, 0.871, 0.914 }, dim = { 0.482, 0.533, 0.631 }, sel = { 0.263, 0.298, 0.369 } },
    { name = "Solarized Dark", bg = { 0.000, 0.169, 0.212 }, fg = { 0.576, 0.631, 0.631 }, dim = { 0.396, 0.482, 0.514 }, sel = { 0.039, 0.271, 0.333 } },
    { name = "Dracula",        bg = { 0.157, 0.165, 0.212 }, fg = { 0.902, 0.902, 0.875 }, dim = { 0.478, 0.525, 0.722 }, sel = { 0.267, 0.278, 0.353 } },
    { name = "Catppuccin",     bg = { 0.118, 0.118, 0.180 }, fg = { 0.804, 0.839, 0.957 }, dim = { 0.498, 0.518, 0.612 }, sel = { 0.212, 0.220, 0.314 } },
    { name = "Everforest",     bg = { 0.176, 0.208, 0.231 }, fg = { 0.827, 0.776, 0.667 }, dim = { 0.522, 0.573, 0.537 }, sel = { 0.263, 0.310, 0.333 } },
    { name = "Red Night",      bg = { 0.000, 0.000, 0.000 }, fg = { 0.753, 0.224, 0.169 }, dim = { 0.431, 0.165, 0.133 }, sel = { 0.180, 0.059, 0.043 } },
}
-- Themes used to be saved as a number (their position in the original list).
-- Listed alphabetically in Settings.
table.sort(THEMES, function(a, b) return a.name:lower() < b.name:lower() end)
local OLD_THEME_NUMBERS = { "Paper", "White", "Sepia", "Midnight" }
-- Side margins. The two screens sit apart (there's no shared gutter as in a
-- printed book), so each page is centred on its own screen: the same margin
-- on both sides. The totals are the old outer + inner, so line lengths and
-- page breaks are unchanged.
local MARGINS = { { name = "Narrow", outer = 32, inner = 32 }, { name = "Normal", outer = 52, inner = 52 }, { name = "Wide", outer = 77, inner = 77 } }
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
-- app.page_offs: where each laid-out file's pages start (numbers only), kept
-- after its pages are dropped, for counting a chapter's pages across files.
local function clear_pages() pages_cache, pages_order, app.page_offs = {}, {}, {} end
app.page_offs = {}
local function clear_book_caches()
    for _, img in pairs(images) do if img then img:release() end end
    images, images_order, image_dims = {}, {}, {}
    app.image_ink = {}
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
    -- The night theme at night; a preview while one is being picked.
    local want = app.preview_theme or (app.night and S.night_theme or S.theme)
    for i, t in ipairs(THEMES) do
        if t.name == want then return i end
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
    local function cut(n) return text:sub(1, (utf8.offset(text, n + 1) or (#text + 1)) - 1) .. "…" end
    -- The most characters that fit with "…" after them (halving, not one at a time).
    local lo, hi = 0, (utf8.len(text) or #text) - 1
    while lo < hi do
        local mid = math.ceil((lo + hi) / 2)
        if font:getWidth(cut(mid)) <= w then lo = mid else hi = mid - 1 end
    end
    return lo > 0 and cut(lo) or "…"
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

-- Line art (chapter numbers, ornaments, drawings, title pages): mostly
-- grayscale and white, with a pale edge. Drawn in the page's ink instead of
-- as a white box, so it sits on any theme like the text (photos and colour
-- pictures are drawn as they are). A sample of pixels decides.
app.image_ink = {}
function app.is_line_art(id)
    local w, h = id:getDimensions()
    local step = math.max(1, math.floor(math.sqrt(w * h / 4096)))
    local n, white, sat = 0, 0, 0
    for y = 0, h - 1, step do
        for x = 0, w - 1, step do
            local r, g, b, a = id:getPixel(x, y)
            n = n + 1
            if a < 0.2 or math.min(r, g, b) > 0.88 then white = white + 1 end
            sat = sat + (math.max(r, g, b) - math.min(r, g, b)) * a
        end
    end
    local edge, pale = 0, 0
    local function look(x, y)
        local r, g, b, a = id:getPixel(x, y)
        edge = edge + 1
        if a < 0.2 or math.min(r, g, b) > 0.85 then pale = pale + 1 end
    end
    for x = 0, w - 1, math.max(1, math.floor(w / 64)) do look(x, 0); look(x, h - 1) end
    for y = 0, h - 1, math.max(1, math.floor(h / 64)) do look(0, y); look(w - 1, y) end
    if n == 0 or sat / n >= 0.05 then return false end
    -- Tiny and gray: a letter or mark drawn as a picture ("ə"), often cropped
    -- tight, so with little white around it.
    if w <= 48 and h <= 48 then return white / n >= 0.2 end
    return white / n >= 0.4 and pale / edge >= 0.6
end

-- The shader, made once (nil if the GPU won't have it: then a white box).
function app.ink_shader()
    if app.ink_sh == nil then
        local ok, sh = pcall(love.graphics.newShader, app.INK_SHADER)
        app.ink_sh = ok and sh or false
        if not ok then print("[images] ink shader unavailable: " .. tostring(sh)) end
    end
    return app.ink_sh or nil
end

-- Draws line art in the ink colour: dark becomes ink, white becomes clear.
app.INK_SHADER = [[
extern vec3 ink;
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    vec4 p = Texel(tex, tc);
    float lum = dot(p.rgb, vec3(0.299, 0.587, 0.114));
    float a = clamp((0.94 - lum) / 0.94, 0.0, 1.0) * p.a;
    return vec4(ink, a * color.a);
}
]]

-- Decoded image for drawing (the oldest ones are released).
local function get_image(src)
    local img = images[src]
    if img == nil then
        img = false
        local data = book and book:read_resource(src)
        if data then
            local ok, res = pcall(function()
                local id = love.image.newImageData(love.filesystem.newFileData(data, src))
                local okl, line = pcall(app.is_line_art, id)
                app.image_ink[src] = okl and line or nil
                local image = love.graphics.newImage(id)
                id:release()
                return image
            end)
            if ok then img = res end
        end
        images[src] = img
        images_order[#images_order + 1] = src
        if #images_order > IMAGES_KEEP then
            local old = table.remove(images_order, 1)
            if images[old] then images[old]:release() end
            images[old], app.image_ink[old] = nil, nil
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
        local offs = {}
        for k, pg in ipairs(p) do offs[k] = pg.off end
        app.page_offs[ch] = offs
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

-- Jump somewhere (Contents, bookmarks, highlights, Jump to %, Find).
function app.jump_to(ch, off)
    goto_pos(ch, off)
    save_progress()
    if book and app.sync then app.sync.moved[book.path] = true end     -- (for KOReader sync)
end

local function next_spread()
    if not spread then return end
    learn_speed()
    if spread.pi + 2 <= #spread.pages then
        set_spread(spread.ch, spread.pi + 2)
    elseif spread.ch < #book.chapters then
        set_spread(spread.ch + 1, 1)
    else
        app.check_finished()                   -- already on the last page (a one-spread book)
        return
    end
    save_progress_soon()
    app.check_finished()
    app.sync_tick()
end

local function prev_spread()
    if not spread then return end
    reading_pause()
    if spread.pi - 2 >= 1 then
        set_spread(spread.ch, spread.pi - 2)
    elseif spread.ch > 1 then
        local pages = pages_for(spread.ch - 1)
        set_spread(spread.ch - 1, #pages)
    else
        return
    end
    save_progress_soon()
    if app.sync then app.sync.moved[book.path] = true end
end

-- TOC entries with resolved positions (chapter, offset).
local function toc_pos(t)
    if t.off == nil then
        local c = book:chapter(t.chapter)      -- (a file that can't be read comes back blank)
        t.off = (c and t.anchor and c.anchors[t.anchor]) or 0
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
        save_progress()
        if app.sync then app.sync.moved[book.path] = true end     -- (for KOReader sync)
        return
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
    if target then app.jump_to(toc_pos(target)) end
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
    -- Only the marks * † ‡ § ¶ (not any character starting like them: — … →).
    local marks = t:gsub("^%[", ""):gsub("%]$", ""):gsub("\226\128[\160\161]", ""):gsub("\194[\167\182]", "")
    return t:match("^%[?%(?%d+%)?%]?%.?$") ~= nil
        or (t:match("^%[?[%*\226\194]") ~= nil and marks:gsub("%*", "") == "")
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

app.BAR_PX = { 3, 6, 10 }        -- the progress bar's thicknesses (also BAR_PX further down)

-- The "Notes" button at the bottom of the touchscreen's page, by the spine
-- (bottom left of the right page; turned round, bottom right of the left):
-- x, y, w, h.
function note.button()
    local w, h = ui.small:getWidth("Notes") + 36, ui.small:getHeight() + 10
    -- Sit clear of the progress bar along the bottom edge.
    local bar = (S.sb_show and S.sb_bar ~= "none") and (app.BAR_PX[S.sb_bar_size] or 6) or 0
    local bottom = PAGE_H - 10 - bar - 8
    if app.touch_side() == "left" then return PAGE_W - margins().inner + 14 - w, bottom - h, w, h end
    return margins().inner - 14, bottom - h, w, h
end

-- The selected note laid out as pages (cached per target).
function note.pages(r)
    local w, h = content_size()          -- margins, top/bottom margins, status bar
    local key = book.path .. "|" .. r.link.target .. "|" .. S.font_size .. "|" .. S.font .. "|"
        .. S.spacing .. "|" .. w .. "x" .. h .. "|" .. tostring(S.justify)
    local p = note.cache[key]
    if p == nil then
        local blocks = book:note(r.link.target)
        if blocks then
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
                    -- off: where it starts in the chapter's text (for highlights).
                    prev = { side = side, text = it.text, line = line, x = x, y = y, x2 = x + w, y2 = y + h, off = it.off }
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
    look.sel, look.hl_start = 1, nil
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

---------------------------------------------------------------- highlights

-- A highlight is a run of words, saved as text offsets in a chapter (so it
-- survives changes to the font or layout), like a bookmark. Made in look-up
-- (Y): Select at the first word, move to the last, Select again. Select on a
-- highlighted word removes it. Listed with the bookmarks.

-- The highlights on the visible chapter, and the one being chosen.
function app.hl_ranges()
    local out = {}
    if not book or not spread then return out end
    for _, h in ipairs(Store.get_highlights(book.path)) do
        if h.ch == spread.ch then out[#out + 1] = h end
    end
    local p = app.mode == "lookup" and app.hl_span()
    if p then out[#out + 1] = p end
    return out
end

-- The words being chosen: { s, e, a, b } (offsets and word indexes), or nil.
function app.hl_span()
    if not look.hl_start then return nil end
    local a, b = math.min(look.hl_start, look.sel), math.max(look.hl_start, look.sel)
    local wa, wb = look.words[a], look.words[b]
    if not (wa and wb and wa.off and wb.off) then return nil end
    return { s = wa.off, e = wb.off + #wb.text, a = a, b = b }
end

-- The saved highlight a word is in (its index), or nil.
function app.hl_at(w)
    if not (w and w.off and book and spread) then return nil end
    for i, h in ipairs(Store.get_highlights(book.path)) do
        if h.ch == spread.ch and w.off >= h.s and w.off < h.e then return i end
    end
end

-- Bands behind the highlighted words of a page (drawn before the text). A
-- band runs on across the space to the next highlighted word on its line.
function app.hl_bands(page, ox, oy)
    local marked, seq, n = {}, {}, 0
    for _, it in ipairs(page.items) do
        if it.kind == "text" and it.off then
            n = n + 1
            for _, r in ipairs(app.hl_active) do
                if it.off >= r.s and it.off < r.e then marked[#marked + 1] = it; seq[#marked] = n; break end
            end
        end
    end
    if #marked == 0 then return end
    color(theme().sel)
    for i, it in ipairs(marked) do
        local x2 = it.x + it.font:getWidth(it.text)
        local nx = seq[i + 1] == seq[i] + 1 and marked[i + 1]   -- only the very next word, not one further on
        if nx and nx.x > it.x and math.abs((nx.y + nx.font:getBaseline()) - (it.y + it.font:getBaseline())) < 4 then
            x2 = nx.x
        end
        local h = it.font:getHeight()
        love.graphics.rectangle("fill", ox + it.x - 3, oy + it.y + math.floor(h * 0.06), x2 - it.x + 6,
            math.ceil(h * 0.92), 4, 4)
    end
end

-- While choosing: what to do, over the bottom of the touchscreen page.
function app.hl_hint()
    local th = theme()
    local m = margins()
    love.graphics.setFont(ui.small)
    local h = ui.small:getHeight() + 24
    color(th.bg)
    love.graphics.rectangle("fill", 0, PAGE_H - h - 8, PAGE_W, h + 8)
    color(th.fg)
    love.graphics.print("Highlighting: move to the last word", m.inner, PAGE_H - h + 4)
    app.hints(m.inner + ui.small:getWidth("Highlighting: move to the last word") + 32, PAGE_H - h + 4,
        { "Select", "save", "B", "cancel" })
end

-- Select in look-up: start a highlight, save it, or remove the one here.
function app.hl_select()
    local w = look.words[look.sel]
    if not (w and w.off) then app.toast("This can't be highlighted"); return end
    local list = {}
    for _, h in ipairs(Store.get_highlights(book.path)) do list[#list + 1] = h end
    if not look.hl_start then
        local i = app.hl_at(w)
        if i then
            table.remove(list, i)
            Store.set_highlights(book.path, list)
            app.export_notes()
            app.toast("Highlight removed")
        else
            look.hl_start = look.sel
        end
        redraw()
        return
    end
    local span = app.hl_span()
    look.hl_start = nil
    if not span then return end
    -- The words a..b, with a word split over two lines joined back up.
    local function words_text(a, b)
        local parts = {}
        for k = a, b do
            local t, prv = look.words[k].text, look.words[k - 1]
            if k > a and prv.text:sub(-1) == "-" and look.words[k].line == prv.line + 1 then
                parts[#parts] = parts[#parts]:sub(1, -2) .. t
            else
                parts[#parts + 1] = t
            end
        end
        return table.concat(parts, " ")
    end
    local text = words_text(span.a, span.b)
    -- Overlapping highlights become one.
    local keep, merged = {}, false
    for _, h in ipairs(list) do
        if h.ch == spread.ch and h.s < span.e and h.e > span.s then
            if h.s < span.s then span.s, text, merged = h.s, h.text .. " … " .. text, true end
            if h.e > span.e then span.e, text, merged = h.e, text .. " … " .. h.text, true end
        else
            keep[#keep + 1] = h
        end
    end
    if merged then
        -- All of it on this spread: its words, without the overlap twice.
        local a, b
        for k, w in ipairs(look.words) do
            if w.off and w.off >= span.s and w.off < span.e then a = a or k; b = k end
        end
        local last = look.words[#look.words]
        if a and look.words[a].off == span.s and (b < #look.words or (last.off and span.e <= last.off + #last.text)) then
            text = words_text(a, b)
        end
    end
    keep[#keep + 1] = { ch = spread.ch, s = span.s, e = span.e, pct = book:fraction(spread.ch, span.s),
        title = app.find_label({ ch = spread.ch, off = span.s }), text = text }
    Store.set_highlights(book.path, keep)
    app.export_notes()
    app.mode = "reader"
    reading.since = love.timer.getTime()
    app.toast("Highlighted")
    redraw()
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
    local pg = spread and spread.pages[spread.pi]
    for _, it in ipairs(pg and pg.items or {}) do
        -- The text, not a heading (the chapter's name is shown beside it).
        if it.kind == "text" and it.font ~= fonts.h then
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
    app.export_notes()
    app.toast(here and "Bookmark removed" or "Bookmark added")
    redraw()
end

local function open_bookmarks(from)
    bm.sel, bm.top, bm.from, bm.filter = 1, nil, from, "all"
    app.mode = "bookmarks"
    redraw()
end

---------------------------------------------------------------- opening books

local function show_message(text)
    message = text
    if app.mode ~= "message" then app.message_back = app.mode end
    app.mode = "message"
    redraw()
end

local function open_book(path)
    app.asking = nil
    if book and book.path ~= path then app.sync_push() end    -- the book being left
    local ok, b, err = pcall(Book.open, path)
    if not ok or not b then
        show_message("Could not open this book.\n\n" .. tostring(ok and err or b))
        return
    end
    if book and book ~= b then book:close() end
    -- Find results belong to one book; drop them (and the old book they hold).
    if app.find and app.find.book ~= b then app.find_stop(); app.find, app.find_mark = nil, nil end
    book = b
    clear_book_caches()
    local pr = Store.get_progress(path)
    app.mode = "reader"
    if pr then goto_pos(pr.ch, pr.off) else goto_pos(1, 0) end
    Store.set_last(path)
    Store.set_opened(path)
    save_progress()
    app.export_notes(true)                 -- highlights from before there were files
    app.sync.checked[path], app.sync.pushed[path], app.sync.asked[path] = nil, nil, nil
    app.sync.seen[path], app.sync.moved[path] = nil, nil
    app.sync_pull("open")                  -- where another device has got to
end

-- Highlights and bookmarks as a file to read on a computer, like a Kindle's
-- "My Clippings": Ebook/Highlights/<Title - Author>.md, one per book, written
-- again whenever they change (removed when there are none). Markdown, which
-- reads as plain text too. only_if_missing: write it if it isn't there yet.
function app.notes_path(b)
    local name = (b.title ~= "" and b.title or "Book") .. ((b.author or "") ~= "" and (" - " .. b.author) or "")
    name = name:gsub('[%c<>:"/\\|%?%*]', ""):gsub("%s+", " "):gsub("^[%s%.]+", ""):gsub("[%s%.]+$", "")
    local short = ""
    for ch in name:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        if #short + #ch > 120 then break end
        short = short .. ch
    end
    -- Another copy of the same book (same title and author) keeps its own
    -- file: the first line says whose file it is.
    local dir = Store.download_dir() .. "/Highlights"
    local owner = app.notes_owner(dir .. "/" .. short .. ".md")
    local file = b.path:match("([^/]+)$") or b.path
    if owner and owner ~= file then
        short = short .. " (" .. file:gsub("%.[^.]*$", ""):gsub('[%c<>:"/\\|%?%*]', "") .. ")"
    end
    return dir, short .. ".md"
end

app.NOTES_MARK = "<!-- eReaderDS: "
-- The book file a notes file was written for (nil: none, or an older file
-- without the line, which is taken as this book's).
function app.notes_owner(file)
    local f = io.open(file, "rb")
    if not f then return nil end
    local first = f:read("*l") or ""
    f:close()
    return first:sub(1, #app.NOTES_MARK) == app.NOTES_MARK and first:sub(#app.NOTES_MARK + 1):gsub(" %-%->%s*$", "") or nil
end

function app.export_notes(only_if_missing)
    if not book then return end
    local dir, name = app.notes_path(book)
    local file = dir .. "/" .. name
    local hls, bms = Store.get_highlights(book.path), Store.get_bookmarks(book.path)
    if #hls + #bms == 0 then
        -- Only a file this book wrote (an older one without the line: only
        -- when its last note was just removed, not on opening the book).
        if app.notes_owner(file) or not only_if_missing then os.remove(file) end
        return
    end
    if only_if_missing then
        local f = io.open(file, "rb")
        if f then f:close() return end
    end
    local all = {}
    for _, h in ipairs(hls) do all[#all + 1] = { ch = h.ch, off = h.s, pct = h.pct, title = h.title, text = h.text, hl = true } end
    for _, b in ipairs(bms) do all[#all + 1] = { ch = b.ch, off = b.off, pct = b.pct, title = b.title, text = b.snippet } end
    table.sort(all, function(x, y) return x.ch < y.ch or (x.ch == y.ch and x.off < y.off) end)
    local function n(k, one) return k .. " " .. one .. (k == 1 and "" or "s") end
    local out = { app.NOTES_MARK .. (book.path:match("([^/]+)$") or book.path) .. " -->", "# " .. book.title, "" }
    if (book.author or "") ~= "" then out[#out + 1] = "*" .. book.author .. "*"; out[#out + 1] = "" end
    out[#out + 1] = n(#hls, "highlight") .. " and " .. n(#bms, "bookmark") .. ", in reading order, from eReaderDS. "
        .. "This file is written again whenever they change, so anything added to it here is replaced."
    local chapter
    for _, e in ipairs(all) do
        local t = (e.title or "") ~= "" and e.title or book.title
        if t ~= chapter then
            out[#out + 1] = ""
            out[#out + 1] = "## " .. t
            out[#out + 1] = ""
            chapter = t
        end
        local pct = math.floor((e.pct or 0) * 100 + 0.5) .. "%"
        if e.hl then
            out[#out + 1] = "- “" .. (e.text or "") .. "” (" .. pct .. ")"
        else
            out[#out + 1] = "- Bookmark (" .. pct .. "): " .. ((e.text or "") ~= "" and (e.text .. "…") or "")
        end
    end
    local f = io.open(file .. ".tmp", "wb")
    if not f then
        os.execute('mkdir -p "' .. dir .. '"')
        f = io.open(file .. ".tmp", "wb")
        if not f then return end
    end
    local ok = f:write(table.concat(out, "\n") .. "\n")
    f:close()
    if ok then os.remove(file); os.rename(file .. ".tmp", file) else os.remove(file .. ".tmp") end
end

-- Library order, chosen with left/right in the library.
local SORTS = { "recent", "title", "author", "series", "progress" }
local SORT_NAMES = { recent = "Recent", title = "Title", author = "Author", series = "Series", progress = "Progress" }

-- "The Hobbit" sorts under H; authors sort by last name.
local function title_key(t) return (t:lower():gsub("^the%s+", ""):gsub("^an?%s+", "")) end
local function author_key(a, sort)
    -- The book's own sort name when it has one ("Suarez, Daniel").
    if sort and sort ~= "" then return sort:lower() end
    a = (a or ""):lower():match("^[^,&]+") or ""
    a = a:gsub("%s+$", "")
    return a:match("(%S+)$") or ""
end

-- The last spread of the book: mark it finished (once) and say so.
function app.check_finished()
    if not book or not spread or spread.ch < #book.chapters or spread.pi + 2 <= #spread.pages then return end
    if not Store.get_finished(book.path) then
        Store.set_finished(book.path, true)
        app.toast("Finished!\nIt's marked as finished in My Books", 3)
    end
end

-- "Finished ✓", "Reading · 16%", or nil for a book not started.
function app.book_status(p)
    if Store.get_finished(p) then return "Finished ✓" end
    local pr = Store.get_progress(p)
    if pr and pr.pct >= 0.005 then return "Reading  ·  " .. math.floor(pr.pct * 100 + 0.5) .. "%" end
end

function library.sort(items)
    local mode = S.lib_sort
    local key = {}
    for _, it in ipairs(items) do
        local k = { title = title_key(it.title) }
        if mode == "recent" then
            k.t = Store.get_opened(it.path) or 0
        elseif mode == "author" then
            k.a = author_key(it.author, it.sort)
        elseif mode == "series" then
            -- Each series in order (1, 2, 3...), then the books in none.
            k.s = it.series and title_key(it.series) or nil
            k.i = it.index or math.huge
        elseif mode == "progress" then
            -- Books you're reading (most read first), then unread, then finished.
            local pr = Store.get_progress(it.path)
            local pct = pr and pr.pct or 0
            k.group = (Store.get_finished(it.path) and 3) or (pct > 0 and 1) or 2
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
        if mode == "series" then
            if (x.s == nil) ~= (y.s == nil) then return x.s ~= nil end
            if x.s ~= y.s then return x.s < y.s end
            if x.i ~= y.i then return x.i < y.i end
        end
        if mode == "progress" then
            if x.group ~= y.group then return x.group < y.group end
            if x.pct ~= y.pct then return x.pct > y.pct end
        end
        return x.title < y.title
    end)
end

-- Get Books state (see "get books (OPDS)" below); declared here so the
-- library scan can see whether a download is running.
local net = { thread = nil, next_id = 0, handlers = {}, count = 0 }
-- The "Get Books" screen. Its functions live on the table to stay under
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

-- The books in a folder and the folders inside it (a Calibre library is
-- Author/Title (id)/book.epub; people arrange their own in folders too), but
-- not hidden folders or the fonts, dictionaries and highlights folders:
-- { path, size }.
function app.find_books(dir)
    local function run(cmd)
        local out = {}
        local p = io.popen(cmd)
        if not p then return out end
        for line in p:lines() do
            local size, path = line:match("^(%d+)|(/.+)$")
            path = path or line
            local rel = path:sub(#dir + 2)
            local top = (rel:match("^([^/]+)/") or ""):lower()
            if path:sub(1, #dir + 1) == dir .. "/" and not rel:match("^%.") and not rel:find("/%.")
                    and top ~= "fonts" and top ~= "dictionaries" and top ~= "highlights" then
                out[#out + 1] = { path = path, size = tonumber(size) }
            end
        end
        p:close()
        return out
    end
    local match = '-maxdepth 6 -type f \\( -iname "*.epub" -o -iname "*.txt" -o -iname "*.part" \\)'
    local found = run('find "' .. dir .. '" ' .. match .. ' -exec stat -c "%s|%n" {} + 2>/dev/null')
    -- No stat that way (not the device's busybox): without the sizes.
    if #found == 0 then found = run('find "' .. dir .. '" ' .. match .. ' 2>/dev/null') end
    return found
end

local function scan_library()
    local items = {}
    local seen = {}
    local pending = {}
    for _, dir in ipairs(Store.book_dirs()) do
        for _, f in ipairs(app.find_books(dir)) do
            local path = f.path
            local name = path:match("([^/]+)$")
            local ext = (name:match("%.([^.]+)$") or ""):lower()
            if ext == "part" then
                -- Left over from a download that was cut off.
                if not shop.dl and not app.recv then os.remove(path) end
            elseif not seen[path] then
                seen[path] = true
                -- The file name ("Title - Author.epub") until the book's own
                -- title and author are known (read in the background).
                local base = name:gsub("%.[^.]+$", "")
                local title, author = base:match("^(.-)%s+%-%s+(.+)$")
                local it = { path = path, title = title or base, author = author or "" }
                if ext == "epub" then
                    local m = Store.get_meta(path, f.size)
                    if not m then
                        it.size = f.size
                        pending[#pending + 1] = it
                    elseif m.title then
                        it.title, it.author, it.sort = m.title, m.author or "", m.sort
                        it.series, it.index = m.series, m.index
                    end
                end
                items[#items + 1] = it
            end
        end
    end
    -- "Hide finished books" (Y in My Books): leave them out, counting them.
    library.hidden = 0
    if S.lib_hide_finished then
        for k = #items, 1, -1 do
            if Store.get_finished(items[k].path) then table.remove(items, k); library.hidden = library.hidden + 1 end
        end
    end
    library.sort(items)
    library.pending = #pending > 0 and pending or nil
    library.seen = seen
    if not library.pending then Store.save_meta(seen) end
    -- Online catalogs from opds.txt, for "Get Books" (Select, or the button
    -- on the right page).
    local ok, catalogs, opts = pcall(Opds.load_catalogs, Store.data_path("opds.txt"))
    if not ok then print("[opds] " .. tostring(catalogs)); catalogs, opts = {}, {} end
    for _, c in ipairs(Opds.BUILT_IN) do
        if opts[c.key] ~= false then catalogs[#catalogs + 1] = c end      -- "gutenberg = off" etc.
    end
    library.catalogs = catalogs
    library.items = items
    library.sel = math.max(1, math.min(library.sel, #items))
end

-- Titles and authors from books not read yet, a few between frames; then
-- the list is sorted again (keeping the selected book) and the list saved.
function app.library_meta_step()
    local q = library.pending
    if not q then return end
    local t0 = love.timer.getTime()
    while #q > 0 and love.timer.getTime() - t0 < 0.03 do
        local it = table.remove(q)
        local ok, m = pcall(Book.meta, it.path)      -- a damaged file mustn't stop the library
        if not ok then print("[library] " .. tostring(m)) end
        m = ok and m or {}
        Store.set_meta(it.path, it.size, m)
        if m.title then it.title, it.author, it.sort, it.series, it.index = m.title, m.author or "", m.sort, m.series, m.index end
    end
    if #q == 0 then
        library.pending = nil
        local cur = library.items[library.sel]
        library.sort(library.items)
        for i, it in ipairs(library.items) do if it == cur then library.sel = i end end
        Store.save_meta(library.seen)
    end
    redraw()
end

-- Y in My Books: what to do with the selected book, and the finished filter.
function app.library_options(it)
    local function hide(on)
        S.lib_hide_finished = on
        Store.save_settings(S)
        scan_library()
        if it then
            for i, b in ipairs(library.items) do if b.path == it.path then library.sel = i end end
        end
    end
    local opts = {}
    if it then
        local done = Store.get_finished(it.path)
        opts[#opts + 1] = { done and "Mark as not finished" or "Mark as finished", function()
            Store.set_finished(it.path, not done)
            app.toast(done and "Marked as not finished" or "Marked as finished")
            hide(S.lib_hide_finished)
        end }
    end
    opts[#opts + 1] = { S.lib_hide_finished and "Show finished books" or "Hide finished books", function()
        hide(not S.lib_hide_finished)
    end }
    if it then
        opts[#opts + 1] = { "Delete from the SD card", function()
            app.ask({ question = "Delete this book from the SD card?", detail = it.title,
                yes = "Delete", on_yes = function() library.delete(it.path) end })
        end }
    end
    app.choose({ title = it and it.title or "My Books", options = opts })
end

-- Change the order, keeping the same book selected.
function library.cycle_sort(d)
    local cur = library.items[library.sel]
    local i = 1
    for k, v in ipairs(SORTS) do if v == S.lib_sort then i = k end end
    S.lib_sort = SORTS[(i - 1 + d) % #SORTS + 1]
    Store.save_settings(S)
    library.sort(library.items)           -- the same books in a new order (no need to look at the SD card again)
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
    if #preview_order > 6 then
        local old = table.remove(preview_order, 1)
        if previews[old].cover then previews[old].cover:release() end   -- big textures: don't wait for the GC
        previews[old] = nil
    end
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
        book, spread = nil, nil
        app.find, app.find_mark = nil, nil
        clear_book_caches()
    end
    if previews[path] then
        previews[path] = nil
        for i, p in ipairs(preview_order) do if p == path then table.remove(preview_order, i) break end end
    end
    Store.forget(path)
    Store.flush()
    scan_library()
    app.toast("Book deleted")
end

-- The "Get Books" button on the library's right page: x, y, w, h.
function library.get_books_button()
    -- Beside the "My Books" title, like "Get More Fonts" beside "Fonts".
    local key = shop.online() and "   Select" or "   No Wi-Fi"
    local w, h = ui.font:getWidth("Get Books") + ui.small:getWidth(key) + 44, 50
    local x = MARGINS[2].inner + ui.title:getWidth("My Books") + 24
    return x, math.floor(60 + (ui.title:getHeight() - h) / 2), w, h
end

local function go_library()
    save_progress()
    app.sync_push()
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
    if net.thread and not net.thread:isRunning() then
        shop.net_poll()                    -- fails anything still waiting on it
        if net.thread then print("[net] " .. (net.thread:getError() or "network thread stopped")) end
        net.thread = nil
        love.thread.getChannel("net_jobs"):clear()
        love.thread.getChannel("net_cancel"):clear()
    end
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
        local waiting = net.handlers   -- a handler may start a new job
        net.handlers, net.count = {}, 0
        for id, h in pairs(waiting) do h({ id = id, kind = "error", message = err }) end
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
    shop.net_job(shop.catalog_opts({ kind = "feed", url = url }), function(msg)
        pg.loading = false
        if msg.kind == "error" then
            local err = shop.online(true) and msg.message or "Not connected to Wi-Fi."
            if append then
                -- The list so far stays; reaching its end again tries again.
                pg.next = url
                app.toast("Couldn't load more: " .. err)
            else
                pg.error = err
            end
            return
        end
        local feed = msg.feed
        -- Gutenberg: leave out entries that can't be opened here: the
        -- "Authors" and "Subjects" lists at the top of search results (its
        -- server refuses them to apps, 403), and links to its social media
        -- pages ("Follow new books on Facebook...") at the top of Latest.
        if (msg.url or url):find("gutenberg%.org") then
            for k = #feed.entries, 1, -1 do
                local e = feed.entries[k]
                local h = e.href or ""
                if not e.book and h ~= "" and (h:find("gutenberg%.org/ebooks/[%a]+/search%.opds")
                        or not h:find("^https?://[%w%.]*gutenberg%.org/")) then
                    table.remove(feed.entries, k)
                end
            end
        end
        -- Standard Ebooks: its "All" list is every book at once (1,500, several MB,
        -- slow to load and endless to scroll); search finds them instead.
        for k = #feed.entries, 1, -1 do
            if feed.entries[k].href == "https://standardebooks.org/feeds/opds/all" then table.remove(feed.entries, k) end
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

-- "Get Books" from the library: a list of catalogs (yours from opds.txt,
-- then the free built-in ones), and how to add your own.
function shop.start()
    app.asking = nil
    if not shop.online(true) then
        app.toast("Not connected to Wi-Fi")
        return
    end
    shop.dir = nil
    for url, c in pairs(shop.covers) do if c == false then shop.covers[url] = nil end end
    local entries = { { title = "Send from Your Phone or Computer", author = "Over Wi-Fi, from a web browser",
        formats = {}, receive = true, summary = "Send your own books (.epub or .txt) to eReaderDS from a phone "
            .. "or computer on the same Wi-Fi: open the address it shows in a web browser and choose the files. "
            .. "Fonts (.ttf or .otf) can be sent the same way." } }
    for _, c in ipairs(library.catalogs or {}) do
        local u = Opds.parse_url(c.url)
        entries[#entries + 1] = { title = c.name, author = u and u.host or "", summary = c.about or "",
            formats = {}, catalog = c }
    end
    entries[#entries + 1] = { title = "Add a Catalog", author = "Calibre, Calibre-Web or any OPDS server",
        formats = {}, info = true, summary = "Get books from your own library over Wi-Fi. Edit "
            .. Store.books_folder() .. "/.ereaderds/opds.txt"
            .. (select(2, Store.books_folder()) and " on the SD card" or "") .. " (it has examples), for example:\n\n"
            .. "name = Calibre\nurl = http://192.168.1.20:8080/opds\nuser = me\npassword = secret" }
    shop.stack = { { title = "Get Books", entries = entries, sel = 1, top = 1 } }
    app.mode = "shop"
    redraw()
end

-- The hints under a catalog page: what A does to the selected entry.
function shop.hints(pg, it)
    if pg.error and (#pg.entries == 0 or not (it and it.book)) then return { "A", "try again", "B", "back" } end
    if not it then return { "B", "back" } end
    if it.book then
        if shop.dl and shop.dl.item == it then return { "B", "cancel" } end
        if it.have or shop.have(it) then return { "A", "read", "B", "back" } end
        if it.failed then return { "A", "try again", "B", "back" } end
        if shop.dl then return { "B", "back" } end
        return { "A", "download", "B", "back" }
    end
    if it.search then return { "A", "search", "B", "back" } end
    if it.receive then return { "A", "start", "B", "back" } end
    if it.href or it.catalog then return { "A", "open", "B", "back" } end
    return { "B", "back" }
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
        shop.keep_cover(url, ok and img or false)
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
            if ok then shop.keep_cover(url, img) end
        end)
    end
end

-- The last dozen covers are kept; older ones are let go.
function shop.keep_cover(url, img)
    for i, u in ipairs(shop.cover_order) do
        if u == url then table.remove(shop.cover_order, i) break end
    end
    shop.covers[url] = img
    shop.cover_order[#shop.cover_order + 1] = url
    if #shop.cover_order > 12 then
        local old = table.remove(shop.cover_order, 1)
        if shop.covers[old] then shop.covers[old]:release() end
        shop.covers[old] = nil
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
        if pg.redo then pg.redo()
        elseif pg.retry then shop.load_page(pg, pg.retry.url, pg.retry.append) end
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
    elseif it.receive then
        app.recv_open()
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
            res.redo = function()
                if shop.page() == res then table.remove(shop.stack) end
                shop.search(pg, q)
            end
            return
        end
        c.search_tpl = found
        shop.load_page(res, Opds.search_url(found, q))
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
local BAR_PX = app.BAR_PX

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

-- Time left (S.sb_time: "chapter" or "off"; older settings may say "both") is only shown for the chapter: it's worked out from the text on
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
    if menu.page == "server" then app.server_close() return end       -- a page of KOReader Sync
    menu.page = "main"; menu.sel = menu.parent_row or 1; menu.top = nil
end

---------------------------------------------------------------- KOReader sync

-- Your place in a book, shared with KOReader (on a phone, a Kobo, a Kindle...)
-- through its sync server (kosync.lua). As KOReader and others do it, with
-- their lessons learned:
--  * Opening a book (online), ask the server first. If another device has
--    been reading it since, offer to go there. Nothing is sent for a book
--    until that check is done, so a stale place here never overwrites a newer
--    one there.
--  * Send the place when leaving the book (My Books, another book, Quit, the
--    lid, the screens going off) and every few minutes while reading; while
--    offline it waits for the next chance.
--  * Places are to the paragraph (Book:xpointer, Book:resolve_xpointer); one
--    whose paragraph can't be found goes by its chapter and percentage.
-- EPUB only: KOReader marks places in other kinds of file differently.
app.KOSync = require("kosync")
app.sync = { checked = {}, pushed = {}, docs = {}, asked = {}, seen = {}, moved = {}, last_push = 0, last_try = 0 }

function app.sync_on() return S.kosync_user ~= "" and S.kosync_key ~= "" end
function app.sync_url() return app.KOSync.server(S.kosync_server, S.kosync_custom) end

-- A new server: log in again there; match books the way its readers do.
function app.sync_set_server(key)
    S.kosync_server = key
    if key == "crosspoint" then S.kosync_match = "filename"
    elseif key == "koreader" then S.kosync_match = "binary" end
    app.sync.checked, app.sync.pushed = {}, {}
    Store.save_settings(S)
end

-- The book's name on the server (worked out once per book and way of matching).
function app.sync_doc(b)
    local key = b.path .. "|" .. S.kosync_match
    local d = app.sync.docs[key]
    if d == nil then
        d = app.KOSync.document(b.path, S.kosync_match) or false
        app.sync.docs[key] = d
    end
    return d or nil
end

-- This device's id on the server: made once, kept in the settings.
function app.sync_device_id()
    if S.kosync_device == "" then
        local t = {}
        for i = 1, 16 do t[i] = string.format("%02x", love.math.random(0, 255)) end
        S.kosync_device = table.concat(t)
        Store.save_settings(S)
    end
    return S.kosync_device
end

local function ago(t)
    local d = os.time() - (tonumber(t) or os.time())
    if d < 120 then return "just now" end
    if d < 7200 then return math.floor(d / 60) .. " minutes ago" end
    if d < 172800 then return math.floor(d / 3600) .. " hours ago" end
    return math.floor(d / 86400) .. " days ago"
end

-- Ask the server where the open book is up to, and decide, the way
-- CrossPoint's "smart sync" does, without trusting either device's clock:
-- "new there" = a place from another device that we haven't seen yet (the
-- server's timestamp differs from the last one we saw); "moved here" = pages
-- turned here since the last sync.
--   nothing new there        -> this device's place stands (sent if moved)
--   new there, not moved     -> go there (asked on opening a book)
--   new there and moved here -> ask: Jump, or Stay (and send this one)
-- how: "open" (opening a book: ask), "check" (before the regular send:
-- send if nothing's new there, else ask), "now" (Sync this book now: say
-- what happened; go there without asking when only the other moved).
function app.sync_pull(how)
    how = how or "open"
    local now = how == "now"
    local b = book
    if not (b and b.zip and app.sync_on()) then
        if now then app.toast(b and not b.zip and "KOReader sync is for EPUB books" or "Log in to KOReader sync first") end
        return
    end
    local doc = app.sync_doc(b)
    if not doc then return end
    if not shop.online() then
        if now then app.toast("Not connected to Wi-Fi") end
        return
    end
    app.sync.pulling, app.sync.last_try = true, love.timer.getTime()
    shop.net_job(app.KOSync.get_job(app.sync_url(), S.kosync_user, S.kosync_key, doc), function(msg)
        app.sync.pulling = nil
        if book ~= b then return end
        if msg.kind ~= "done" then
            print("[sync] pull failed: " .. tostring(msg.message))
            app.sync.failed = love.timer.getTime()
            if now then app.toast("Couldn't reach the sync server", 3) end
            return
        end
        app.sync.failed = nil
        if msg.status == 401 then
            if now then app.toast("The sync server didn't accept your user name and password", 3) end
            return
        end
        if msg.status ~= 200 then
            print("[sync] pull: status " .. tostring(msg.status))
            if now then app.toast("The sync server answered " .. tostring(msg.status), 3) end
            return
        end
        local moved = app.sync.moved[b.path]
        local here = math.floor(b:fraction(pos.ch, pos.off) * 100 + 0.5)
        -- This device's place stands: mark the book checked (sends may go from
        -- now on) and send it if it has moved here, or if the server has
        -- nothing for the book yet (send).
        local function stands(say, send)
            app.sync.checked[b.path] = true
            if moved or send then
                if send then app.sync.pushed[b.path] = nil end
                app.sync_push()
                say = "Sent your place (" .. here .. "%) to the sync server"
            end
            if now then app.toast(say) end
        end
        local ok, r = pcall(require("json").decode, msg.body or "")
        if not ok or type(r) ~= "table" or tonumber(r.percentage) == nil then
            print("[sync] pull: nothing there yet")
            return stands(nil, true)
        end
        local seen = app.sync.seen[b.path]
        local new_there = r.device_id ~= S.kosync_device and (seen == nil or r.timestamp ~= seen)
        app.sync.seen[b.path] = r.timestamp
        if r.device_id == S.kosync_device then
            print("[sync] pull: it's this device's place (" .. tostring(r.timestamp) .. ")")
            return stands("Already in sync")
        end
        -- Where that is here: the paragraph, else its chapter and percentage.
        -- (CrossPoint often sends just its chapter, so the percentage decides.)
        local frac = math.max(0, math.min(1, tonumber(r.percentage) or 0))
        local ch, off = b:resolve_xpointer(r.progress)
        if not off then
            local lc, loff = b:locate(frac)
            if not ch or lc == ch then ch, off = lc, loff else off = 0 end
        end
        -- The same place means on the spread you're looking at.
        local sp = spread
        local same = sp and ch == sp.ch and off >= sp.pages[sp.pi].off and off < spread_end_off(sp)
        print(string.format("[sync] pull: %s at %.1f%% (%s) -> chapter %d offset %d; %s, moved here: %s, same spread: %s (ts %s, seen %s)",
            tostring(r.device), frac * 100, tostring(r.progress), ch, off, new_there and "new" or "seen before",
            tostring(moved), tostring(same), tostring(r.timestamp), tostring(seen)))
        if same then
            -- Nothing to do; the server's place counts as this one until you read on.
            moved = false
            app.sync.moved[b.path] = nil
            app.sync.pushed[b.path] = b:xpointer(pos.ch, pos.off)
            return stands("Already in sync")
        end
        if not new_there then
            -- Seen before (you chose Stay, or it was checked already): what you've
            -- read here since goes out; asked by hand, go to it if you haven't.
            if moved or not now then return stands("Already in sync") end
        end
        local device = (r.device and r.device ~= "") and r.device or "another device"
        local function go()
            if book ~= b then return end
            app.sync.checked[b.path], app.sync.asked[b.path] = true, nil
            app.jump_to(ch, off)
            app.mode = "reader"
            app.sync.moved[b.path] = nil
            app.sync.pushed[b.path] = b:xpointer(pos.ch, pos.off) -- the server has this place already
            app.toast("Moved to " .. math.floor(frac * 100 + 0.5) .. "%, where you were on " .. device, 3)
        end
        if now and not moved then go() return end
        -- Until it's answered, nothing is sent for this book (not even on quitting).
        app.sync.checked[b.path] = nil
        app.sync.asked[b.path] = true           -- (not asked again on its own this time)
        app.ask({ question = "Continue from " .. math.floor(frac * 100 + 0.5) .. "%?",
            detail = "Where you were on " .. device .. ", " .. ago(r.timestamp)
                .. (moved and (". Here you're at " .. here .. "%.") or ""),
            yes = "Jump", no = "Stay", on_yes = go,
            -- Stay: this device's place wins, and is sent.
            on_no = function()
                if book ~= b then return end
                app.sync.checked[b.path], app.sync.asked[b.path] = true, nil
                app.sync.pushed[b.path] = nil
                app.sync_push()
            end })
    end)
end

-- Send where the open book is up to. now: leaving the book (the app may quit
-- or sleep next), so wait for the answer, briefly.
function app.sync_push(now)
    local b = book
    if not (b and b.zip and app.sync_on() and spread) then return end
    if not app.sync.checked[b.path] then
        -- Not checked yet (offline when it opened): check first.
        if not now and not app.sync.pulling and not app.sync.asked[b.path] and shop.online() then app.sync_pull("check") end
        return
    end
    local doc = app.sync_doc(b)
    local xp = doc and b:xpointer(pos.ch, pos.off)
    if not xp or app.sync.pushed[b.path] == xp or not shop.online() then return end
    local meta = S.kosync_meta and { filename = b.path:match("([^/]+)$"), title = b.title, authors = b.author } or nil
    local job = app.KOSync.put_job(app.sync_url(), S.kosync_user, S.kosync_key, doc, xp,
        b:fraction(pos.ch, pos.off), app.sync_device_id(), meta)
    app.sync.last_push = love.timer.getTime()
    -- Sent: the server's timestamp for it is the one we've "seen" now.
    local function sent(status, body)
        if not (status and status < 300) then return end
        app.sync.pushed[b.path], app.sync.moved[b.path] = xp, nil
        local ok, r = pcall(require("json").decode, body or "")
        if ok and type(r) == "table" and r.timestamp then app.sync.seen[b.path] = r.timestamp end
    end
    if now then
        -- Waited for (the app may quit or sleep next), briefly, and not at all
        -- when the server just failed: quitting mustn't hang on a dead server.
        if app.sync.failed and love.timer.getTime() - app.sync.failed < 600 then return end
        local ok, status, body = pcall(require("net").call, job.method, job.url, { headers = job.headers, body = job.body, timeout = 4 })
        print("[sync] push " .. xp .. ": " .. tostring(status))
        if ok and status < 500 then sent(status, body) else app.sync.failed = love.timer.getTime() end
        return
    end
    shop.net_job(job, function(msg)
        print("[sync] push " .. xp .. ": " .. tostring(msg.status or msg.message))
        -- (A server error, 5xx, counts as failing too.)
        if msg.kind == "done" and (msg.status or 500) < 500 then sent(msg.status, msg.body); app.sync.failed = nil
        else app.sync.failed = love.timer.getTime() end
    end)
end

-- After a page turn: every few minutes, check the server and send (or ask,
-- if another device has moved on meanwhile); check if that hasn't happened yet.
function app.sync_tick()
    if not (book and book.zip and app.sync_on()) then return end
    app.sync.moved[book.path] = true
    local t = love.timer.getTime()
    if app.sync.pulling or app.sync.asked[book.path] or not shop.online() then return end
    if not app.sync.checked[book.path] then
        if t - app.sync.last_try > 60 then app.sync_pull("check") end
    elseif t - app.sync.last_push > 300 and t - app.sync.last_try > 60 then
        app.sync.last_push = t
        app.sync_pull("check")
    end
end

-- Settings → KOReader Sync.
function app.sync_items()
    local on = app.sync_on()
    local server = app.KOSync.SERVERS[S.kosync_server] and S.kosync_server or "custom"
    local shown = app.KOSync.SERVER_NAMES[server]
    if server == "custom" and S.kosync_custom ~= "" then shown = app.sync_own_name() end
    local items = {
        { label = "Account", value = on and S.kosync_user or "Log in", act = app.sync_login },
        -- Its own page (tap or A): CrossPoint, KOReader, or your own address.
        { label = "Server", value = shown, opens = true, act = function() app.server_open() end },
        { label = "Match books by", value = S.kosync_match == "filename" and "File name" or "File contents",
          adjust = function()
              S.kosync_match = S.kosync_match == "filename" and "binary" or "filename"
              app.sync.checked, app.sync.pushed = {}, {}
          end },
        { label = "Send book details", value = S.kosync_meta and "On" or "Off", adjust = function()
              S.kosync_meta = not S.kosync_meta
          end },
    }
    if on then
        items[#items + 1] = { label = "Sync this book now", act = function()
            if not book then app.toast("Open a book first") else app.sync_pull("now") end
        end }
        items[#items + 1] = { label = "Log out", act = function()
            S.kosync_user, S.kosync_key = "", ""
            Store.save_settings(S)
            app.sync.checked, app.sync.pushed = {}, {}
            app.toast("Logged out of KOReader sync")
        end }
    end
    return join(section(nil, items), section("", { { label = "Back", act = close_sub } }))
end

-- The Sync Server page, opened from KOReader Sync (B goes back there).
function app.server_open()
    menu.page, menu.sel, menu.top = "server", 1, nil
    local cur = app.KOSync.SERVERS[S.kosync_server] and S.kosync_server or "custom"
    for i, k in ipairs({ "crosspoint", "koreader", "custom" }) do if k == cur then menu.sel = i end end
end

function app.server_items()
    local cur = app.KOSync.SERVERS[S.kosync_server] and S.kosync_server or "custom"
    local function pick(key)
        return function()
            app.sync_set_server(key)
            app.server_close()
        end
    end
    local rows = {
        { label = "CrossPoint", value = cur == "crosspoint" and "✓" or "", act = pick("crosspoint") },
        { label = "KOReader", value = cur == "koreader" and "✓" or "", act = pick("koreader") },
    }
    -- Your own: its name; A (or a tap) to use, edit, rename or delete it.
    if S.kosync_custom ~= "" then
        rows[#rows + 1] = { label = app.sync_own_name(), value = cur == "custom" and "✓" or "",
            act = function() app.server_own_options() end }
    else
        rows[#rows + 1] = { label = "Add your own server", act = function() app.server_add() end }
    end
    return join(section(nil, rows), section("", { { label = "Back", act = function() app.server_close() end } }))
end

-- Your own server's address as shown (no https://).
function app.sync_own_address()
    return (app.KOSync.server("custom", S.kosync_custom):gsub("^https?://", ""))
end

-- Its name: the one you gave it, or its address.
function app.sync_own_name()
    return S.kosync_custom_name ~= "" and S.kosync_custom_name or app.sync_own_address()
end

-- Type an address (a new server, or a change to yours); done(address).
function app.server_address(title, ok, done)
    app.kb_open({ title = title, text = S.kosync_custom, ok = ok,
        hint = "The address of a KOReader sync server, such as https://sync.example.com or "
            .. "http://192.168.1.20:7200 (Kavita, Komga, Calibre-Web, BookLore and others can be one).",
        submit = done })
end

function app.server_name(text, done)
    app.kb_open({ title = "Name this server", text = text, ok = "Save", allow_empty = true,
        hint = "What to call it in Settings. Empty: its address.", submit = done })
end

-- Add your own: its address, then a name; then it's the one used.
function app.server_add()
    app.server_address("Your own sync server", "Next", function(addr)
        S.kosync_custom, S.kosync_custom_name = addr, ""
        app.server_name("", function(name)
            S.kosync_custom_name = name
            app.sync_set_server("custom")
            app.server_close()
        end)
    end)
end

-- A card for your own server: use it, change its address, rename, delete.
function app.server_own_options()
    local name = app.sync_own_name()
    app.choose({ title = name, options = {
        { "Use this server", function() app.sync_set_server("custom"); app.server_close() end },
        { "Edit address", function()
            app.server_address("Address of " .. name, "Save", function(addr)
                S.kosync_custom = addr
                if S.kosync_server == "custom" then app.sync_set_server("custom") else Store.save_settings(S) end
                app.toast("Address saved")
            end)
        end },
        { "Rename", function()
            app.server_name(name, function(n) S.kosync_custom_name = n; Store.save_settings(S) end)
        end },
        { "Delete", function()
            app.ask({ question = "Delete " .. name .. "?",
                detail = S.kosync_server == "custom" and "Sync goes back to CrossPoint." or app.sync_own_address(),
                yes = "Delete", on_yes = function()
                    if S.kosync_server == "custom" then app.sync_set_server("crosspoint") end
                    S.kosync_custom, S.kosync_custom_name = "", ""
                    Store.save_settings(S)
                    menu.sel = 1
                    app.toast("Server deleted")
                end })
        end },
    } })
end

function app.server_close()
    menu.page, menu.sel, menu.top = "sync", 2, nil          -- (the Server row)
end

function app.sync_login()
    app.kb_open({ title = "KOReader sync: user name", text = S.kosync_user, ok = "Next",
        hint = "Your KOReader progress sync account (KOReader: Tools → Progress sync). A new name makes a new account.",
        submit = function(user)
            app.kb_open({ title = "Password for " .. user, secret = true, ok = "Log in",
                hint = "The password for " .. user .. " on the sync server.",
                submit = function(pw) app.sync_auth(user, app.KOSync.md5(pw)) end })
        end })
end

function app.sync_auth(user, key)
    if not shop.online(true) then app.toast("Not connected to Wi-Fi") return end
    app.toast("Logging in…", 20)
    shop.net_job(app.KOSync.auth_job(app.sync_url(), user, key), function(msg)
        if msg.kind ~= "done" then app.toast("Couldn't reach the sync server", 3) return end
        if msg.status == 200 then
            S.kosync_user, S.kosync_key = user, key
            Store.save_settings(S)
            app.sync.checked, app.sync.pushed = {}, {}
            app.toast("Logged in as " .. user)
            app.sync_pull()
        elseif msg.status == 401 then
            app.untoast()
            app.ask({ question = "Make a new account?", detail = "“" .. user .. "” isn't an account there with that password. "
                .. "If it is yours, check the password instead.", yes = "Make it", no = "Cancel",
                on_yes = function() app.sync_register(user, key) end })
        else
            app.toast("The sync server answered " .. tostring(msg.status), 3)
        end
    end)
end

function app.sync_register(user, key)
    app.toast("Making the account…", 20)
    shop.net_job(app.KOSync.register_job(app.sync_url(), user, key), function(msg)
        if msg.kind ~= "done" then app.toast("Couldn't reach the sync server", 3) return end
        if msg.status == 201 then
            S.kosync_user, S.kosync_key = user, key
            Store.save_settings(S)
            app.sync.checked, app.sync.pushed = {}, {}
            app.toast("Account made. Logged in as " .. user, 3)
            app.sync_pull()
        elseif msg.status == 402 then
            app.toast("That name is taken: if it's yours, check the password", 4)
        else
            app.toast("The sync server answered " .. tostring(msg.status), 3)
        end
    end)
end

-- Night Mode: another theme, used automatically between two hours (by
-- the device's clock, like the status bar). app.night says whether it's on
-- now; checked once a minute.
function app.night_check()
    local was = app.night
    local h = tonumber(os.date("%H")) or 0
    local from, to = S.night_from, S.night_to
    app.night = S.night_theme ~= "off" and from ~= to
        and ((from < to and h >= from and h < to) or (from > to and (h >= from or h < to))) or false
    if app.night ~= was then redraw() end
end

-- An hour as the clock shows it: "9 PM" or "21:00".
function app.hour_label(h)
    if S.sb_clock == "24" then return string.format("%02d:00", h) end
    return ((h + 11) % 12 + 1) .. (h < 12 and " AM" or " PM")
end

-- The Night Mode row on the main page: "Off" or "Dusk · 9 PM–7 AM".
function app.night_summary()
    if S.night_theme == "off" then return "Off" end
    return S.night_theme .. "  ·  " .. app.hour_label(S.night_from) .. "–" .. app.hour_label(S.night_to)
end

-- Picking a night theme: the touchscreen shows the menu in it.
function app.night_preview(side)
    if side == "right" and app.mode == "menu" and menu.page == "night" and S.night_theme ~= "off" then
        return S.night_theme
    end
    -- The Themes page: the book's page in the theme highlighted.
    if side == "left" and app.mode == "themes" then return THEMES[app.themes.sel].name end
end


-- The Night Mode page: which theme, and when.
function app.night_items()
    local names = { "off" }
    for _, t in ipairs(THEMES) do names[#names + 1] = t.name end
    local rows = {
        { label = "Theme", value = S.night_theme == "off" and "Off" or S.night_theme,
          adjust = function(d)
            S.night_theme = cycle(names, S.night_theme, d); app.night_check()
        end },
    }
    if S.night_theme ~= "off" then
        rows[#rows + 1] = { label = "From", value = app.hour_label(S.night_from), adjust = function(d)
            S.night_from = (S.night_from + d) % 24; app.night_check()
        end }
        rows[#rows + 1] = { label = "Until", value = app.hour_label(S.night_to), adjust = function(d)
            S.night_to = (S.night_to + d) % 24; app.night_check()
        end }
    end
    return join(section(nil, rows), section("", { { label = "Back", act = close_sub } }))
end

-- About eReaderDS: what's new, updates and credits.
function app.about_items()
    local u = app.upd
    return join(
        u.state == "available" and section(nil, {
            { label = "Update to v" .. u.version, act = app.update_open },
        }) or {},
        section(u.state == "available" and "" or nil, {
            { label = "What's New", act = app.whatsnew_open },
            { label = "Check for Updates",
              value = app.update_status(), act = app.update_check_open },
            { label = "Update notices", value = S.update_notices and "On" or "Off", adjust = function()
                S.update_notices = not S.update_notices
            end },
            { label = "Report a Problem", act = app.report_open },
            { label = "About & Credits", act = function() app.mode = "about" end },
        }),
        section("", { { label = "Back", act = close_sub } })
    )
end

-- Reading & Device: page turns, look up, the lid and the time zone.
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
            -- The grip: buttons under the right hand (the usual), or turned
            -- round with them under the left (everything turns 180°).
            { label = "Hold it with buttons", value = app.flipped() and "On the left" or "On the right", adjust = function()
                S.orient = app.flipped() and "left" or "right"
                app.toast(app.flipped() and "Turned round: buttons on the left" or "Buttons on the right", 2)
            end },
            { label = "Screens off after", value = S.idle_min > 0 and (S.idle_min .. " min") or "Never", adjust = function(d)
                S.idle_min = cycle(app.IDLE_CHOICES, S.idle_min, d)
            end },
            { label = "Closing the lid", value = S.lid == "sleep" and "Sleep" or "Screen off", adjust = function()
                S.lid = S.lid == "sleep" and "screen" or "sleep"; S.lid_failed = nil
            end },
            -- The clock's zone: the status bar and the night theme's hours.
            { label = "Time zone", value = S.tz, adjust = function(d)
                S.tz = cycle(Timezone.NAMES, S.tz, d)
                Timezone.apply(S.tz)
                app.night_check()
            end },
        }),
        section("", { { label = "Back", act = close_sub } })
    )
end

local function menu_items()
    if menu.page == "status" then return status_items() end
    if menu.page == "more" then return more_items() end
    if menu.page == "night" then return app.night_items() end
    if menu.page == "about" then return app.about_items() end
    if menu.page == "sync" then return app.sync_items() end
    if menu.page == "server" then return app.server_items() end
    local th = theme()
    local u = app.upd
    -- Two pages (swipe, or up/down past the end). The first holds what a
    -- reader opens Settings for in the middle of a book: getting around it,
    -- and making the page comfortable right now (brightness first: the
    -- change most often wanted, at night). My Books, leaving the book, is
    -- last. The second holds what's set once: the page's layout, the other
    -- settings pages, and help.
    return join(
        app.menu_on_page(1, section("This book", join(
            u.state == "available" and { { label = "Update to v" .. u.version, bold = true, act = app.update_open } } or {},
            {
            { label = "Table of Contents", act = function()
                if #book.toc == 0 then return end
                toc.sel = current_section() or 1
                toc.top = nil
                app.mode = "toc"
            end },
            { label = "Bookmarks and Highlights", value = tostring(#Store.get_bookmarks(book.path) + #Store.get_highlights(book.path)),
              act = function() open_bookmarks("menu") end },
            { label = "Find in Book", act = function() app.find_open() end },
            { label = "Jump to %", value = "Currently " .. math.floor(book:fraction(pos.ch, pos.off) * 100 + 0.5) .. "%",
              act = function() app.open_jump() end },
            },
            -- KOReader sync users: fetch another device's place (or send this one) now.
            app.sync_on() and { { label = "Sync with KOReader", act = function() app.sync_pull("now") end } } or {}))),
        app.menu_on_page(1, section("Reading", {
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
            { label = "Text size", value = tostring(S.font_size), adjust = function(d)
                S.font_size = math.max(18, math.min(64, S.font_size + d * 2)); build_fonts(); goto_pos(pos.ch, pos.off)
            end },
            -- Changes the theme on screen: at night, the night theme.
            -- Opens the Themes page (tap or A), which shows each on your book.
            { label = "Theme", value = th.name .. (app.night and "  (night)" or ""), act = app.theme_open },
            -- The font's name is drawn in the font itself: a preview, and the only way
            -- names in other scripts (e.g. Chinese firmware fonts) can display.
            { label = "Fonts", value = fonts.name or S.font,
              value_font = Fonts.preview(fonts.name or S.font, app.MENU_SIZE),
              act = function() app.font_open() end },
        })),
        app.menu_on_page(1, section("", {
            { label = "My Books", act = go_library },
        })),
        app.menu_on_page(2, section("Page layout", {
            { label = "Line spacing", value = string.format("%.2f", S.spacing), adjust = function(d)
                S.spacing = math.floor(math.max(0.75, math.min(2.0, S.spacing + d * 0.05)) * 100 + 0.5) / 100
                relayout()
            end },
            { label = "Margins", value = margins().name, adjust = function(d)
                S.margins = (S.margins - 1 + d) % #MARGINS + 1; relayout()
            end },
            { label = "Top/bottom margins", value = (VMARGINS[S.vmargins] or VMARGINS[2]).name, adjust = function(d)
                S.vmargins = (S.vmargins - 1 + d) % #VMARGINS + 1; relayout()
            end },
            { label = "Justify text", value = S.justify and "On" or "Off", adjust = function()
                S.justify = not S.justify; relayout()
            end },
            { label = "Hyphenation", value = S.hyphenate and "On" or "Off", adjust = function()
                S.hyphenate = not S.hyphenate; relayout()
            end },
        })),
        app.menu_on_page(2, section("More settings", {
            { label = "Night Mode", value = app.night_summary(), opens = true, act = function() open_sub("night") end },
            { label = "Status Bar", value = "›", act = function() open_sub("status") end },
            { label = "Reading & Device", value = "›", act = function() open_sub("more") end },
            { label = "KOReader Sync", value = app.sync_on() and "On" or "Off", opens = true, act = function() open_sub("sync") end },
        })),
        app.menu_on_page(2, section("", {
            { label = "Help", act = function() app.mode = "help" end },
            { label = "About eReaderDS", value = app.upd.state ~= "available" and "›" or nil,
              value_bold = app.upd.state == "available" and "Update" or nil,
              act = function() open_sub("about") end },
            { label = "Quit", act = function() love.event.quit() end },
        }))
    )
end

---------------------------------------------------------------- drawing

local function draw_page(page, side, top)
    local th = theme()
    local m = margins()
    local ox = side == "left" and m.outer or m.inner
    local oy = top or text_top()
    if not page then return end
    if app.hl_active and #app.hl_active > 0 then app.hl_bands(page, ox, oy) end
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
                local ink = app.image_ink[it.src] and app.ink_shader()
                if ink then
                    ink:send("ink", { th.fg[1], th.fg[2], th.fg[3] })
                    love.graphics.setShader(ink)
                end
                love.graphics.draw(img, ox + it.x, oy + it.y, 0, it.w / iw, it.h / ih)
                if ink then love.graphics.setShader() end
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
    if side == "left" and info.marked and app.touch_side() == "left" then
        title_x, title_w = title_x + RIBBON_ROOM, title_w - RIBBON_ROOM      -- (turned round)
    end
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
        if info.marked and app.touch_side() == "right" then title_w = title_w - RIBBON_ROOM end
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

-- "4h 10m".
local function format_time(seconds)
    local H, M = "h", "m"
    local m = seconds / 60
    if m < 1 then return "<1" .. M end
    if m < 60 then return string.format("%d%s", math.floor(m + 0.5), M) end
    local h = math.floor(m / 60)
    local mm = math.floor(m - h * 60 + 0.5)
    if mm == 60 then h, mm = h + 1, 0 end
    return mm > 0 and string.format("%d%s %d%s", h, H, mm, M) or string.format("%d%s", h, H)
end

-- A section (Contents entry) can run over several files of the EPUB. Its
-- pages and characters outside the current file: exact for files already
-- laid out, otherwise estimated (text per byte of the files opened so far,
-- characters per page of this one). Returns the pages before this file, the
-- pages after it and the characters after it; nil when the section is most
-- of the book (a Contents with just a title entry), where the file itself
-- is the more useful "chapter".
function app.section_extent(cur, nxt)
    local ch = spread.ch
    local s_ch, s_off = ch, 0
    if cur and cur.chapter < ch then s_ch, s_off = toc_pos(cur) end
    local e_ch, e_off = #book.chapters + 1, 0                -- no next entry: the book's end
    if nxt then
        e_ch = nxt.chapter
        e_off = nxt.anchor and select(2, toc_pos(nxt)) or 0  -- no anchor: the file's start
    end
    if e_ch == ch then e_ch, e_off = ch + 1, 0 end         -- ends in this file
    if s_ch == ch and e_ch == ch + 1 and e_off == 0 then return 0, 0, 0 end
    local span = 0
    for i = s_ch, math.min(e_off > 0 and e_ch or e_ch - 1, #book.chapters) do span = span + book.chapters[i].weight end
    if span > book.total * 0.5 then return nil end
    local text, bytes = 0, 0
    for _, c in ipairs(book.chapters) do
        if c.length then text, bytes = text + c.length, bytes + c.weight end
    end
    local ratio = bytes > 0 and text / bytes or 0.5
    local cpp = math.max(1, (book.chapters[ch].length or 1) / math.max(1, #spread.pages))
    local function chars(i) local c = book.chapters[i]; return c.length or c.weight * ratio end
    -- Pages of file i between offsets a and b (b nil: to its end).
    local function pages(i, a, b)
        local offs = app.page_offs[i]
        if offs and #offs > 0 then
            local function find(x)              -- the page holding offset x
                local k = 1
                while offs[k + 1] and offs[k + 1] <= x do k = k + 1 end
                return k
            end
            local first, last = find(a), #offs
            if b then
                last = find(b)
                if offs[last] >= b then last = last - 1 end
            end
            return math.max(0, last - first + 1)
        end
        return math.max(0, (b or chars(i)) - a) / cpp
    end
    local before, after, after_chars = 0, 0, 0
    for i = s_ch, ch - 1 do before = before + pages(i, i == s_ch and s_off or 0) end
    for i = ch + 1, math.min(e_ch, #book.chapters) do
        if i < e_ch then
            after, after_chars = after + pages(i, 0), after_chars + chars(i)
        elseif e_off > 0 then
            after, after_chars = after + pages(i, 0, e_off), after_chars + e_off
        end
    end
    return math.floor(before + 0.5), math.floor(after + 0.5), after_chars
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
    -- Pages and characters of the section in other files (0 when it's all here).
    local before, after, after_chars = 0, 0, 0
    if sec then
        local b, a, c = app.section_extent(cur, nxt)
        if b then before, after, after_chars = b, a, c end
    end

    local info = {
        book_title = book.title,
        chapter_title = cur and cur.title or "",
        battery = S.sb_battery and Battery.get() or nil,
        clock = clock_text(),
    }
    if S.sb_pages == "left" then
        local remaining = last - shown + after
        if remaining > 0 then
            info.pages_text = remaining == 1 and "1 page left in chapter" or (remaining .. " pages left in chapter")
        end
    elseif S.sb_pages == "of" then
        info.pages_text = string.format("Page %d of %d", math.max(1, before + spread.pi - first + 1),
            math.max(1, before + last - first + 1 + after))
    end
    if S.sb_percent then
        info.percent_text = string.format("%d%% read", math.floor(frac * 100 + 0.5))
    end
    -- Time left, from the learned reading speed.
    local end_off = spread_end_off(spread)
    if S.sb_time == "chapter" or S.sb_time == "both" then
        local section_end = book.chapters[spread.ch].length or end_off
        if nxt and nxt.chapter == spread.ch then section_end = select(2, toc_pos(nxt)) end
        local left = section_end - end_off + after_chars
        if left > 0 then
            local t = format_time(left / S.read_cps)
            info.pages_text = info.pages_text and (info.pages_text .. " (" .. t .. ")") or (t .. " left in chapter")
        end
    end
    if S.sb_bar == "book" then
        info.bar_frac = frac
    elseif S.sb_bar == "chapter" then
        info.bar_frac = math.max(0, math.min(1, (before + shown - first + 1) / math.max(1, before + last - first + 1 + after)))
    end

    info.marked = bookmark_here() ~= nil
    local ranges = app.hl_ranges()
    return function(side)
        app.hl_active = ranges                   -- highlights, drawn behind the words
        if side == "left" then
            draw_page(left, "left")
            app.hl_active = nil
        else
            draw_page(right, "right")
            app.hl_active = nil
        end
        if side == app.touch_side() then
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
                -- A ribbon hanging in the outer top corner, where a tap removes it.
                local w, h = 24, 66
                local x = side == "left" and 30 or PAGE_W - 30 - w
                love.graphics.setColor(0.72, 0.22, 0.20, 0.95)
                love.graphics.polygon("fill", x, 0, x + w, 0, x + w, h, x + w / 2, h - 10, x, h)
            end
        end
        draw_status(side, info)
    end
end

-- Button hints at the foot of a page, the same everywhere: each button in the
-- text colour, what it does dimmed, e.g. app.hints(x, y, { "A", "open", "B", "back" }).
-- y defaults to the foot of the page.
function app.hints(x, y, list)
    local th = theme()
    y = y or PAGE_H - 70
    for i = 1, #list, 2 do
        local key = app.key(list[i])
        love.graphics.setFont(ui.small_bold)
        color(th.fg)
        love.graphics.print(key, x, y)
        x = x + ui.small_bold:getWidth(key) + 9
        love.graphics.setFont(ui.small)
        color(th.dim)
        love.graphics.print(list[i + 1], x, y)
        x = x + ui.small:getWidth(list[i + 1]) + 32
    end
end

-- "3 / 12" at the right of a list's foot.
function app.count(x, w, sel, n, more, note)
    if n < 1 and not note then return end
    love.graphics.setFont(ui.small)
    color(theme().dim)
    local text = n > 0 and (sel .. " / " .. n .. (more and "+" or "")) or ""
    if note then text = text .. (text ~= "" and "  ·  " or "") .. note end
    love.graphics.printf(text, x, PAGE_H - 70, w, "right")
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

---------------------------------------------------------------- themes page

-- Settings → Theme (tap the row, or A): every theme on the touchscreen, each
-- with a swatch in its own colours, and your book's page on the other screen
-- in the one highlighted, to see it before choosing. A (or a second tap) uses
-- it. While the night theme is on, this chooses the night theme.
app.themes = { sel = 1, top = 1 }
app.THEME_ROW_H = 70

function app.theme_current() return app.night and S.night_theme or S.theme end

function app.theme_open()
    app.themes.sel, app.themes.top = 1, 1
    for i, t in ipairs(THEMES) do if t.name == app.theme_current() then app.themes.sel = i end end
    app.mode = "themes"
    redraw()
end

function app.theme_use()
    local t = THEMES[app.themes.sel]
    if app.night then S.night_theme = t.name else S.theme = t.name end
    Store.save_settings(S)
    app.mode = "menu"
    redraw()
end

function app.theme_action(a)
    local T = app.themes
    if a == "up" then T.sel = math.max(1, T.sel - 1)
    elseif a == "down" then T.sel = math.min(#THEMES, T.sel + 1)
    elseif a == "confirm" then app.theme_use() return
    elseif a == "back" or a == "menu" then app.mode = "menu" end
    redraw()
end

function app.theme_tap(side, u, v)
    if side ~= "right" then return end
    local T = app.themes
    local rows = list_rows(app.THEME_ROW_H)
    local idx = T.top + math.floor((v - 160) / app.THEME_ROW_H)
    if v >= 160 and idx < T.top + rows and THEMES[idx] then
        if idx == T.sel then app.theme_use() else T.sel = idx; redraw() end
    end
end

function app.theme_draw(side)
    local th = theme()
    local T = app.themes
    local m = MARGINS[2]
    local x, w = m.inner, PAGE_W - m.outer - m.inner
    local row_h = app.THEME_ROW_H
    local rows = list_rows(row_h)
    if T.sel < T.top then T.top = T.sel end
    if T.sel >= T.top + rows then T.top = T.sel - rows + 1 end
    love.graphics.setFont(ui.title)
    color(th.fg)
    love.graphics.print(app.night and "Night Mode Theme" or "Themes", x, 60)
    local cur = app.theme_current()
    draw_list(side, THEMES, T.sel, T.top, rows, x, 160, w, row_h, function(t, _, rx, ry, rw)
        local h = row_h - 4
        -- A swatch: the theme's page with "Aa" in its ink.
        local sw, sh = 96, h - 16
        local sy = ry + 8
        love.graphics.setColor(t.bg[1], t.bg[2], t.bg[3])
        love.graphics.rectangle("fill", rx, sy, sw, sh, 8, 8)
        color(th.dim, 0.6)
        love.graphics.setLineWidth(1)
        love.graphics.rectangle("line", rx, sy, sw, sh, 8, 8)
        love.graphics.setFont(ui.font)
        love.graphics.setColor(t.fg[1], t.fg[2], t.fg[3])
        love.graphics.printf("Aa", rx, centered_y(ui.font, UI_SIZE, sy, sh), sw, "center")
        color(th.fg)
        love.graphics.print(t.name, rx + sw + 24, centered_y(ui.font, UI_SIZE, ry, h))
        if t.name == cur then
            color(th.dim)
            love.graphics.printf("✓", rx, centered_y(ui.font, UI_SIZE, ry, h), rw, "right")
        end
    end)
    app.hints(x, nil, { "A", "use", "B", "back" })
    app.count(x, w, T.sel, #THEMES)
end

-- Sorted by progress or by series, My Books has a header over each group:
-- the group's key and its header (nil when this order has no groups).
app.LIB_GROUPS = { "READING", "NOT STARTED", "FINISHED" }
app.LIB_HEADER_H = 44
function app.library_group(it)
    if S.lib_sort == "series" then
        if it.series then return it.series, it.series:upper() end
        return "", "NOT IN A SERIES"
    end
    if S.lib_sort ~= "progress" then return nil end
    local g = 2
    if Store.get_finished(it.path) then g = 3
    else
        local pr = Store.get_progress(it.path)
        if pr and pr.pct > 0 then g = 1 end
    end
    return g, app.LIB_GROUPS[g]
end

-- A number in a series: 2, or 1.5.
function app.series_number(i)
    if not i then return nil end
    return i == math.floor(i) and tostring(math.floor(i)) or tostring(i)
end

-- Where things go on the touchscreen from book `top` down: { { idx, y } or
-- { header, y } }, and how many books fit. The top book's group always has
-- its header, even partway down a group.
function app.library_layout(top)
    local rows, y, n, last = {}, 160, 0, nil
    local bottom = 160 + library.list_rows() * 96
    for i = top, #library.items do
        local g, label = app.library_group(library.items[i])
        if g ~= nil and g ~= last then
            if y + app.LIB_HEADER_H + 96 > bottom then break end
            rows[#rows + 1] = { header = label, y = y }
            y, last = y + app.LIB_HEADER_H, g
        end
        if y + 96 > bottom then break end
        rows[#rows + 1] = { idx = i, y = y }
        y, n = y + 96, n + 1
    end
    return rows, math.max(1, n)
end

-- Library rows that fit on the touchscreen above its hints.
function library.list_rows() return list_rows(96) end

local function draw_library(side)
    local th = theme()
    local m = MARGINS[2]
    local x = side == "left" and m.outer or m.inner
    local w = PAGE_W - m.outer - m.inner
    if side == "right" then
        -- The touchscreen: the books (tap one to see it, again to open it),
        -- with "Get Books" (also Select) beside the title.
        love.graphics.setFont(ui.title)
        color(th.fg)
        love.graphics.print("My Books", x, 60)
        if #library.items > 0 then
            -- The sort order, changed with left/right, like a settings value.
            love.graphics.setFont(ui.font)
            color(th.dim)
            love.graphics.printf("‹ " .. SORT_NAMES[S.lib_sort] .. " ›", x,
                60 + ui.title:getBaseline() - ui.font:getBaseline(), w, "right")
            local row_h = 96
            if library.sel < library.top then library.top = library.sel end
            local rows, fit = app.library_layout(library.top)
            while library.sel >= library.top + fit and library.top < library.sel do
                library.top = library.top + 1
                rows, fit = app.library_layout(library.top)
            end
            local function book_row(it, rx, ry, rw)
                love.graphics.setFont(ui.font)
                color(th.fg)
                -- Center the title + author block: from the title's cap height to
                -- the author's baseline.
                local top = ui.font:getBaseline() - UI_SIZE * 0.68
                local bottom = 40 + ui.small:getBaseline()
                local ty = math.floor(ry + (row_h - 4) / 2 - (top + bottom) / 2 + 0.5)
                love.graphics.print(fit_text(ui.font, it.title, rw), rx, ty)
                -- The author, and where you are with it: Reading · 16% / Finished ✓.
                local status = app.book_status(it.path)
                local sw = status and ui.small:getWidth(status) + 24 or 0
                love.graphics.setFont(ui.small)
                color(th.dim)
                local by = it.author
                if S.lib_sort == "series" and it.series and it.index then
                    by = "Book " .. app.series_number(it.index) .. (by ~= "" and ("  ·  " .. by) or "")
                end
                love.graphics.print(fit_text(ui.small, by, rw - sw), rx, ty + 40)
                if status then love.graphics.printf(status, rx, ty + 40, rw, "right") end
            end
            for _, r in ipairs(rows) do
                if r.header then
                    -- A group (sorted by progress or series): small capitals and a hairline, as in Settings.
                    love.graphics.setFont(ui.small)
                    color(th.dim)
                    local ty = r.y + app.LIB_HEADER_H - ui.small:getHeight() - 8
                    local label = fit_text(ui.small, r.header, w - 40)
                    love.graphics.print(label, x, ty)
                    local lx = x + ui.small:getWidth(label) + 14
                    local ly = ty + math.floor(ui.small:getHeight() * 0.55)
                    color(th.dim, 0.45)
                    love.graphics.setLineWidth(1)
                    love.graphics.line(lx, ly, x + w, ly)
                else
                    if r.idx == library.sel then
                        color(th.sel)
                        love.graphics.rectangle("fill", x - 14, r.y, w + 28, row_h - 4, 10, 10)
                    end
                    book_row(library.items[r.idx], x, r.y, w)
                end
            end
        end
        local bx, by, bw, bh = library.get_books_button()
        -- Offline: an outline only, greyed out, saying why.
        local online = shop.online()
        local key = online and "Select" or "No Wi-Fi"
        if online and app.flipped() then key = nil end   -- (turned round, Select does Y's job)
        app.button(bx, by, bw, bh, "Get Books", key, online and "soft" or "off")
        local hidden = (library.hidden or 0) > 0 and (library.hidden .. " finished hidden") or nil
        if #library.items > 0 then
            app.hints(x, nil, book and { "A", "open", "Y", "options", "‹ ›", "sort", "B", "back" }
                or { "A", "open", "Y", "options", "‹ ›", "sort" })
        elseif hidden then
            app.hints(x, nil, { "Y", "show finished books" })
        end
        app.count(x, w, library.sel, #library.items, nil, hidden)
        return
    end

    -- The top screen: the selected book, or how to add books.
    if app.upd.state == "available" then
        love.graphics.setFont(ui.small_bold)
        color(th.fg)
        love.graphics.printf("eReaderDS v" .. app.upd.version .. " is available: "
            .. (book and "Settings → About eReaderDS" or "press Start"), x, PAGE_H - 110, w, "left")
    end
    if #library.items == 0 and (library.hidden or 0) > 0 then
        love.graphics.setFont(ui.title)
        color(th.fg)
        love.graphics.print("All finished", x, 60)
        love.graphics.setFont(ui.font)
        color(th.dim)
        love.graphics.printf("Your " .. (library.hidden == 1 and "finished book is" or (library.hidden .. " finished books are"))
            .. " hidden. Press " .. app.key("Y") .. " to show " .. (library.hidden == 1 and "it" or "them") .. ".", x, 180, w, "left")
        return
    end
    if #library.items == 0 then
        love.graphics.setFont(ui.title)
        color(th.fg)
        love.graphics.print("No books yet", x, 60)
        love.graphics.setFont(ui.font)
        color(th.dim)
        local folder, where = Store.books_folder()
        love.graphics.printf("Copy .epub or .txt files into the " .. folder .. " folder"
            .. (where and (" " .. where) or "") .. " (folders inside it are fine), or tap Get Books to download some or send them from a phone or computer.", x, 180, w, "left")
        love.graphics.setFont(ui.small)
        app.hints(x, nil, { "Anbernic button", "quit" })
        love.graphics.printf("v" .. VERSION, x, PAGE_H - 70, w, "right")
        return
    end
    love.graphics.setFont(ui.small)
    color(th.dim)
    love.graphics.setFont(ui.small)
    color(th.dim)
    love.graphics.printf("v" .. VERSION, x, PAGE_H - 70, w, "right")
    local pv = library_preview()
    if not pv then return end
    local y = 80
    if pv.cover then
        local iw, ih = pv.cover:getDimensions()
        -- A little smaller when the "v… is available" line is at the bottom.
        local s = math.min(w / iw, (app.upd.state == "available" and 440 or 520) / ih)
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
    -- Its series: "The Expanse, book 2".
    local cur = library.items[library.sel]
    if cur and cur.path == pv.path and cur.series then
        y = y + ui.font:getHeight() + 2
        love.graphics.setFont(ui.small)
        love.graphics.printf(cur.series .. (cur.index and (", book " .. app.series_number(cur.index)) or ""), x, y, w, "center")
    end
    local pr = Store.get_progress(pv.path)
    local done = Store.get_finished(pv.path)
    if done then
        love.graphics.setFont(ui.small)
        color(th.dim)
        love.graphics.printf("✓  Finished " .. (os.date("%b %d, %Y", done):gsub(" 0", " ")), x, y + 60, w, "center")
    elseif pr then
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
    -- The list is on the right page (the touchscreen), so rows can be
    -- tapped; the selected entry (cover, details) is on the left.
    if side == "right" then
        local x, w = m.inner, PAGE_W - m.outer - m.inner
        love.graphics.setFont(ui.title)
        color(th.fg)
        love.graphics.print(fit_text(ui.title, pg.title, w), x, 60)
        love.graphics.setFont(ui.small)
        color(th.dim)
        local footer = shop.hints(pg, it)
        if #pg.entries == 0 then
            love.graphics.setFont(ui.font)
            local text = pg.loading and "Loading…"
                or pg.error and ("Couldn't load this page:\n" .. pg.error)
                or "Nothing here."
            love.graphics.printf(text, x, 180, w, "left")
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
                elseif e.href or e.catalog or e.receive or e.search then
                    mark = "›"
                end
                love.graphics.setFont(ui.font)
                color((e.book or e.href or e.catalog or e.receive or e.search) and th.fg or th.dim)
                love.graphics.print(fit_text(ui.font, e.title, rw - 60), rx, ty)
                if mark then love.graphics.printf(mark, rx, ty, rw, "right") end
                if sub ~= "" then
                    love.graphics.setFont(ui.small)
                    color(th.dim)
                    love.graphics.print(fit_text(ui.small, sub, rw - 60), rx, ty + 40)
                end
            end)
        end
        if pg.loading and #pg.entries > 0 then
            love.graphics.setFont(ui.small)
            color(th.dim)
            love.graphics.print("Loading more…", x, PAGE_H - 70)
        else
            app.hints(x, nil, footer)
        end
        app.count(x, w, pg.sel, #pg.entries, pg.next)
        return
    end

    -- Left page: the selected entry.
    if not it then return end
    local x, w = m.outer, PAGE_W - m.outer - m.inner
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
    local status, frac
    if it.book then
        local dl = shop.dl
        if dl and dl.item == it then
            frac = dl.total > 0 and math.min(1, dl.got / dl.total) or nil
            status = "Downloading…  " .. (shop.format_size(dl.got) or "0 KB")
                .. (dl.total > 0 and (" of " .. shop.format_size(dl.total)) or "")
        elseif it.have or shop.have(it) then
            status = "On your SD card"
        elseif it.failed then
            status = "Download failed: " .. it.failed
        else
            local size = shop.format_size(it.book.size)
            status = it.book.ext:upper() .. (size and ("  ·  " .. size) or "")
                .. (dl and "\nAnother download is running" or "")
        end
    elseif #it.formats > 0 then
        status = "Only as " .. table.concat(it.formats, ", ") .. ".\nThis reader needs EPUB or TXT."
    end

    local bottom = PAGE_H - 70
    local foot_y = bottom
    love.graphics.setFont(ui.small)
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
local MENU_HEADER_H, MENU_GAP_H = 27, 10

-- Settings pages: the rows are big (easy to read and tap), so the items
-- are spread over pages. The main page says which item goes on which page
-- (app.menu_on_page); others are filled in order. The page shown is the one
-- with the selected item. Returns the visible rows (with y), the page and
-- the number of pages.
app.MENU_ROW_BIG = 74
app.MENU_SIZE = 36                   -- the Settings rows' text (UI_SIZE is 30)
app.MENU_AVAIL = MENU_BOTTOM - 44 - MENU_TOP       -- room above the page dots

function app.menu_on_page(n, items)
    for _, it in ipairs(items) do it.page = n end
    return items
end

-- The extra height before item i: a section header or a gap (none at the top of a page).
local function menu_extra(items, i, first_on_page)
    local it = items[i]
    if first_on_page then return (it.section and it.section ~= "") and MENU_HEADER_H or 0 end
    if it.section ~= items[i - 1].section then
        return (it.section and it.section ~= "") and MENU_HEADER_H or MENU_GAP_H
    end
    return 0
end

app.MENU_ROW_FIT = 58                -- rows can shrink to this to keep a page whole

function app.menu_pages(items)
    if items[1] and not items[1].page then
        -- All on one page if it fits with slightly smaller rows...
        local total = 0
        for i = 1, #items do total = total + menu_extra(items, i, i == 1) + app.MENU_ROW_FIT end
        if total <= app.MENU_AVAIL then
            for _, it in ipairs(items) do it.page = 1 end
            return 1
        end
        -- ...else spread over pages of big rows.
        local page, used = 1, 0
        for i, it in ipairs(items) do
            local extra = menu_extra(items, i, used == 0)
            if used > 0 and used + extra + app.MENU_ROW_BIG > app.MENU_AVAIL then
                page, used = page + 1, 0
                extra = menu_extra(items, i, true)
            end
            it.page = page
            used = used + extra + app.MENU_ROW_BIG
        end
    end
    local n = 1
    for _, it in ipairs(items) do n = math.max(n, it.page) end
    return n
end

local function menu_layout(items)
    local pages = app.menu_pages(items)
    menu.sel = math.max(1, math.min(menu.sel, #items))
    local page = items[menu.sel] and items[menu.sel].page or 1
    local rows, extra, n = {}, 0, 0
    local prev
    for i, it in ipairs(items) do
        if it.page == page then
            local e = menu_extra(items, i, prev == nil)
            if e > 0 then
                rows[#rows + 1] = (it.section and it.section ~= "") and { kind = "header", text = it.section, h = e }
                    or { kind = "gap", h = e }
                extra = extra + e
            end
            rows[#rows + 1] = { kind = "item", idx = i }
            n = n + 1
            prev = i
        end
    end
    -- Page 1 of the main page keeps a row's room for "Swipe for more options".
    local slots = n + ((menu.page == "main" and page == 1 and pages > 1) and 1 or 0)
    local row_h = math.min(app.MENU_ROW_BIG, math.floor((app.MENU_AVAIL - extra) / math.max(1, slots)))
    local y = MENU_TOP
    for _, row in ipairs(rows) do
        if row.kind == "item" then row.h = row_h end
        row.y = y
        y = y + row.h
    end
    return rows, page, pages
end

-- A row's "‹  value  ›" as drawn (the value shortened to fit beside the label);
-- taps measure it to find the ‹ and the ›.
function app.menu_value_text(it, w)
    local F = ui.menu
    if not it.value or it.value == "" then return "‹  ›" end
    local room = w - F:getWidth(it.label) - 40
    return "‹  " .. fit_text(F, tostring(it.value), room - F:getWidth("‹    ›")) .. "  ›"
end

-- Turn the settings page: select the first item of the next / previous one.
function app.menu_page(d)
    local items = menu_items()
    local pages = app.menu_pages(items)
    local cur = items[menu.sel] and items[menu.sel].page or 1
    local want = math.max(1, math.min(pages, cur + d))
    if want == cur then return end
    for i, it in ipairs(items) do
        if it.page == want then menu.sel = i; break end
    end
    redraw()
end

local function draw_menu_panel(side)
    local th = theme()
    local m = MARGINS[2]
    local x, w = m.inner, PAGE_W - m.outer - m.inner
    love.graphics.setFont(ui.title)
    color(th.fg)
    love.graphics.print(({ status = "Status Bar", more = "Reading & Device", night = "Night Mode",
        about = "About eReaderDS", sync = "KOReader Sync", server = "Sync Server" })[menu.page] or "Settings", x, 60)
    if menu.page == "main" then
        love.graphics.setFont(ui.font)               -- the version, on the title's baseline
        color(th.dim)
        love.graphics.printf("v" .. VERSION, x, 60 + ui.title:getBaseline() - ui.font:getBaseline(), w, "right")
    end
    local items = menu_items()
    local visible, page, pages = menu_layout(items)
    if pages > 1 then
        -- Which page: dots (swipe or up/down past the end for the others).
        local gap, r = 26, 6
        local cx = x + w / 2 - (pages - 1) * gap / 2
        for k = 1, pages do
            color(k == page and th.fg or th.dim, k == page and 1 or 0.45)
            love.graphics.circle("fill", cx + (k - 1) * gap, MENU_BOTTOM - 16, r)
        end
    end
    local F, FB, FS = ui.menu, ui.menu_bold, app.MENU_SIZE
    if menu.page == "main" and page == 1 and pages > 1 then
        -- Where to find the rest (not a row: the cursor never stops on it).
        local last = visible[#visible]
        love.graphics.setFont(F)
        color(th.dim)
        love.graphics.print("Swipe for more options  ›", x, centered_y(F, FS, last.y + last.h + 10, last.h - 4))
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
            love.graphics.setFont(F)
            color(th.fg)
            local ty = centered_y(F, FS, ry, row_h - 4)
            if it.bold then love.graphics.setFont(FB) end
            love.graphics.print(it.label, rx, ty)
            love.graphics.setFont(F)
            local vf = it.value_font
            if vf and it.value and it.value ~= "" and vf:hasGlyphs(it.value) then
                local room = rw - F:getWidth(it.label) - 40
                -- "‹ name ›" when left/right change it; just the name when it
                -- opens a page (Font).
                local open, close = it.adjust and "‹  " or "", it.adjust and "  ›" or ""
                local name = fit_text(vf, it.value, room - F:getWidth(open .. close))
                local right = rx + rw
                local cw, nw = F:getWidth(close), vf:getWidth(name)
                love.graphics.print(close, right - cw, ty)
                love.graphics.print(open, right - cw - nw - F:getWidth(open), ty)
                love.graphics.setFont(vf)
                love.graphics.print(name, right - cw - nw, centered_y(vf, FS, ry, row_h - 4))
                love.graphics.setFont(F)
            elseif it.value_bold then
                -- A word in bold, then the › of a row that opens a page ("Update ›").
                local tail = "  ›"
                local tw = F:getWidth(tail)
                love.graphics.print(tail, rx + rw - tw, ty)
                love.graphics.setFont(FB)
                love.graphics.print(it.value_bold, rx + rw - tw - FB:getWidth(it.value_bold), ty)
                love.graphics.setFont(F)
            elseif it.value and it.value ~= "" then
                local v = it.value
                if it.adjust then
                    v = app.menu_value_text(it, rw)
                elseif it.opens then
                    local room = rw - F:getWidth(it.label) - 40
                    -- A row that opens a page, showing its setting: "Off  ›".
                    v = fit_text(F, v, room - F:getWidth("  ›")) .. "  ›"
                end
                love.graphics.printf(v, rx, ty, rw, "right")
            elseif it.adjust then
                love.graphics.printf("‹  ›", rx, ty, rw, "right")
            end
        end
    end
    love.graphics.setFont(ui.small)
    color(th.dim)
    app.hints(x, nil, { "A", "select", "‹ ›", "change", "B", "back" })
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
    local hint = { "‹ ›", "word", "Up/Down", "line", "Select", app.hl_at(look.words[look.sel]) and "remove highlight" or "highlight",
        "B", "close" }
    if pages and #pages > 1 then table.insert(hint, 1, "more (" .. look.page .. "/" .. #pages .. ")"); table.insert(hint, 1, "A") end
    app.hints(ox, PAGE_H - 26 - ui.small:getHeight(), hint)
end

local function draw_toc(side)
    local th = theme()
    local m = MARGINS[2]
    local x = side == "left" and m.outer or m.inner
    local w = PAGE_W - m.outer - m.inner
    local row_h = 58
    local rows = app.toc_rows()
    -- The list is on the touchscreen (swipe to scroll, tap to see one, again
    -- to go there); the selected one is described on the other page.
    if not toc.top then toc.top = math.max(1, toc.sel - math.floor(rows / 2)) end
    if toc.sel < toc.top then toc.top = toc.sel end
    if toc.sel >= toc.top + rows then toc.top = toc.sel - rows + 1 end
    local here = current_section()
    if side == "left" then app.toc_draw_left(x, w, here) return end
    love.graphics.setFont(ui.font)
    color(th.dim)
    love.graphics.printf(math.floor(book:fraction(pos.ch, pos.off) * 100 + 0.5) .. "% read", x,
        60 + ui.title:getBaseline() - ui.font:getBaseline(), w, "right")
    draw_list(side, book.toc, toc.sel, toc.top, rows, x, 160, w, row_h, function(it, idx, rx, ry, rw)
        love.graphics.setFont(ui.font)
        local indent = math.max(0, (it.depth or 1) - 1) * 28
        local ty = centered_y(ui.font, UI_SIZE, ry, row_h - 4)
        local mark = idx == here and "here" or nil
        local mw = mark and ui.small:getWidth(mark) + 16 or 0
        color(th.fg)
        love.graphics.print(fit_text(ui.font, it.title, rw - indent - mw), rx + indent, ty)
        if mark then
            love.graphics.setFont(ui.small)
            color(th.dim)
            love.graphics.printf(mark, rx, ty + ui.font:getBaseline() - ui.small:getBaseline(), rw, "right")
        end
    end)
    app.hints(x, nil, { "A", "go there", "B", "back" })
    app.count(x, w, toc.sel, #book.toc)
end

-- Table of Contents rows that fit on the touchscreen above its footer.
function app.toc_rows() return math.floor((PAGE_H - 250) / 58) end

-- The open book's cover, loaded once (nil if it has none).
function app.book_cover()
    if app.cover_img and app.cover_for ~= (book and book.path) then
        app.cover_img:release()             -- the last book's
        app.cover_for, app.cover_img = nil, nil
    end
    if not book or not book.cover then return nil end
    if app.cover_for ~= book.path then
        app.cover_for, app.cover_img = book.path, nil
        local ok, img = pcall(function()
            return love.graphics.newImage(love.filesystem.newFileData(book:read_resource(book.cover), book.cover))
        end)
        if ok then app.cover_img = img end
    end
    return app.cover_img
end

-- The left page of Table of Contents: the book (cover, title, author), then
-- the selected entry: its title, and where it is in the book next to where
-- you are.
function app.toc_draw_left(x, w, here)
    local th = theme()
    love.graphics.setFont(ui.title)
    color(th.fg)
    love.graphics.print("Table of Contents", x, 60)
    local y = 160
    local tx, tw, top_h = x, w, 0
    local cover = app.book_cover()
    if cover then
        local sc = math.min(150 / cover:getHeight(), 110 / cover:getWidth())
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(cover, x, y, 0, sc, sc)
        tx, tw, top_h = x + cover:getWidth() * sc + 22, w - cover:getWidth() * sc - 22, cover:getHeight() * sc
    end
    love.graphics.setFont(ui.bold)
    color(th.fg)
    local _, tl = ui.bold:getWrap(book.title or "", tw)
    local ty = y
    for k = 1, math.min(2, #tl) do
        love.graphics.print(k == 2 and #tl > 2 and fit_text(ui.bold, tl[2] .. " …", tw) or tl[k], tx, ty)
        ty = ty + ui.bold:getHeight()
    end
    if book.author and book.author ~= "" then
        love.graphics.setFont(ui.small)
        color(th.dim)
        love.graphics.print(fit_text(ui.small, book.author, tw), tx, ty + 4)
        ty = ty + ui.small:getHeight() + 4
    end
    y = math.max(y + top_h, ty) + 60
    local t = book.toc[toc.sel]
    if not t then return end
    -- Where it is: the book as a bar, this entry's stretch dark, a mark at your place.
    local f0 = book:fraction(t.chapter, t.off or 0)
    local nxt = book.toc[toc.sel + 1]
    local f1 = nxt and book:fraction(nxt.chapter, nxt.off or 0) or 1
    if f1 < f0 then f1 = f0 end
    local me = book:fraction(pos.ch, pos.off)
    love.graphics.setFont(ui.small)
    color(th.dim)
    love.graphics.print(toc.sel == here and "YOU'RE HERE" or ("STARTS AT " .. math.floor(f0 * 100 + 0.5) .. "%"), x, y)
    y = y + ui.small:getHeight() + 14
    color(th.sel)
    love.graphics.rectangle("fill", x, y, w, 10, 5, 5)
    color(th.fg)
    love.graphics.rectangle("fill", x + w * f0, y, math.max(6, w * (f1 - f0)), 10, 5, 5)
    local mx = x + w * math.max(0, math.min(1, me))
    love.graphics.polygon("fill", mx, y + 16, mx - 9, y + 30, mx + 9, y + 30)
    love.graphics.setFont(ui.small)
    color(th.dim)
    local lab = "you"
    love.graphics.print(lab, math.max(x, math.min(x + w - ui.small:getWidth(lab), mx - ui.small:getWidth(lab) / 2)), y + 32)
    y = y + 32 + ui.small:getHeight() + 36
    -- Its title, in full.
    love.graphics.setFont(ui.title)
    color(th.fg)
    local _, lines = ui.title:getWrap(t.title or "", w)
    for k = 1, math.min(3, #lines) do
        love.graphics.print(lines[k], x, y)
        y = y + ui.title:getHeight()
    end
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
    color(th.fg)
    love.graphics.circle("fill", bx + bw * jp.pct / 100, by, 16)
    color(th.bg)
    love.graphics.circle("fill", bx + bw * jp.pct / 100, by, 7)

    love.graphics.setFont(ui.small)
    color(th.dim)
    love.graphics.printf("Left/Right  1%      Up/Down  10%",
        x, by + 110, w, "center")
    app.hints(x, nil, { "A", "jump", "B", "cancel" })
end

-- Bookmarks and highlights together, in reading order.
-- What the page shows (left/right, like My Books' order): all, or just one kind.
app.BM_FILTERS = { "all", "highlights", "bookmarks" }
app.BM_FILTER_NAMES = { all = "All", highlights = "Highlights", bookmarks = "Bookmarks" }

function app.bm_filter(d)
    local i = 1
    for k, f in ipairs(app.BM_FILTERS) do if f == (bm.filter or "all") then i = k end end
    bm.filter = app.BM_FILTERS[(i - 1 + d) % #app.BM_FILTERS + 1]
    bm.sel, bm.top = 1, 1
    redraw()
end

local function bookmark_entries()
    local f = bm.filter or "all"
    local entries = f ~= "highlights" and { { action = true } } or {}
    local all = {}
    if f ~= "highlights" then
        for _, b in ipairs(Store.get_bookmarks(book.path)) do all[#all + 1] = { item = b, ch = b.ch, off = b.off } end
    end
    if f ~= "bookmarks" then
        for _, h in ipairs(Store.get_highlights(book.path)) do all[#all + 1] = { item = h, ch = h.ch, off = h.s, hl = true } end
    end
    table.sort(all, function(x, y) return x.ch < y.ch or (x.ch == y.ch and x.off < y.off) end)
    for _, e in ipairs(all) do entries[#entries + 1] = e end
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
    -- The list is on the touchscreen (swipe to scroll, tap to see one, again
    -- to go there); the selected one is shown in full on the other page.
    if not bm.top then bm.top = 1 end
    if bm.sel < bm.top then bm.top = bm.sel end
    if bm.sel >= bm.top + rows then bm.top = bm.sel - rows + 1 end
    if side == "left" then app.bm_draw_left(entries, x, w) return end
    love.graphics.setFont(ui.font)
    color(th.dim)
    love.graphics.printf("‹ " .. app.BM_FILTER_NAMES[bm.filter or "all"] .. " ›", x,
        60 + ui.title:getBaseline() - ui.font:getBaseline(), w, "right")
    draw_list(side, entries, bm.sel, bm.top, rows, x, 160, w, row_h, function(it, _, rx, ry, rw, selected)
        if it.action then
            -- The page you're on (the one this bookmarks), like the rows below:
            -- where it is, and its first words.
            local top = ui.font:getBaseline() - UI_SIZE * 0.68
            local bottom = 40 + ui.small:getBaseline()
            local ty = math.floor(ry + (row_h - 4) / 2 - (top + bottom) / 2 + 0.5)
            love.graphics.setFont(ui.font)
            color(th.fg)
            love.graphics.print(bookmark_here() and "Remove the bookmark on this page" or "+  Bookmark this page", rx, ty)
            local sec = current_section()
            local where = (sec and book.toc[sec].title or book.title or "") .. "  ·  "
                .. math.floor(book:fraction(pos.ch, pos.off) * 100 + 0.5) .. "%  ·  "
            love.graphics.setFont(ui.small)
            color(th.dim)
            love.graphics.print(fit_text(ui.small, where .. page_snippet(), rw), rx, ty + 40)
            return
        end
        local top = ui.font:getBaseline() - UI_SIZE * 0.68
        local bottom = 40 + ui.small:getBaseline()
        local ty = math.floor(ry + (row_h - 4) / 2 - (top + bottom) / 2 + 0.5)
        local e = it.item
        local pct = math.floor(e.pct * 100 + 0.5) .. "%"
        local title = fit_text(ui.font, e.title ~= "" and e.title or book.title, rw - 90)
        love.graphics.setFont(ui.small)
        color(th.dim)
        love.graphics.printf(pct, rx, ty + ui.font:getBaseline() - ui.small:getBaseline(), rw, "right")
        if it.hl then
            -- A highlight: its words, marked like on the page; the chapter under them.
            local words = "“" .. fit_text(ui.font, e.text, rw - 110) .. "”"
            love.graphics.setFont(ui.font)
            color(selected and th.bg or th.sel)
            love.graphics.rectangle("fill", rx - 3, ty + 2, ui.font:getWidth(words) + 6, ui.font:getHeight() - 4, 4, 4)
            color(th.fg)
            love.graphics.print(words, rx, ty)
            love.graphics.setFont(ui.small)
            color(th.dim)
            love.graphics.print(fit_text(ui.small, title, rw), rx, ty + 40)
            return
        end
        love.graphics.setFont(ui.font)
        color(th.fg)
        love.graphics.print(title, rx, ty)
        love.graphics.setFont(ui.small)
        color(th.dim)
        love.graphics.print(fit_text(ui.small, e.snippet, rw), rx, ty + 40)
    end)
    love.graphics.setFont(ui.small)
    color(th.dim)
    local real = 0
    for _, e in ipairs(entries) do if not e.action then real = real + 1 end end
    if real == 0 then
        local how_b = "While reading, press Select or tap the top-right corner of the page to bookmark it."
        local how_h = "To highlight, press Y, then Select at the first word and again at the last."
        local f = bm.filter or "all"
        love.graphics.printf((f == "highlights" and ("No highlights yet. " .. how_h))
            or (f == "bookmarks" and ("No bookmarks yet. " .. how_b))
            or ("No bookmarks or highlights yet. " .. how_b .. " " .. how_h),
            x, 160 + (#entries > 0 and row_h or 0) + 20, w, "left")
    end
    local cur = entries[bm.sel]
    if cur and cur.action then
        app.hints(x, nil, { "A", bookmark_here() and "remove its bookmark" or "bookmark this page", "‹ ›", "filter", "B", "back" })
    elseif cur then
        app.hints(x, nil, { "A", "go there", "Y", "delete", "‹ ›", "filter", "B", "back" })
    else
        app.hints(x, nil, { "‹ ›", "filter", "B", "back" })
    end
    -- (Counting the bookmarks and highlights, not the "this page" row.)
    local skip = entries[1] and entries[1].action and 1 or 0
    if real > 0 then app.count(x, w, math.max(1, bm.sel - skip), real) end
end

-- The mark on Bookmarks and Highlights: an open book with a ribbon, drawn in
-- the theme's colours. (cx, cy) is the middle of the spine; s the scale.
function app.draw_book_art(cx, cy, s)
    local th = theme()
    local function curve(...)
        local pts = {}
        local c = love.math.newBezierCurve(...)
        for _, v in ipairs(c:render(4)) do pts[#pts + 1] = v end
        return pts
    end
    love.graphics.setLineWidth(3 * s)
    love.graphics.setLineJoin("bevel")
    for _, d in ipairs({ -1, 1 }) do
        -- A page: its top and bottom edges bow away from the spine.
        local top = curve(cx, cy - 46 * s, cx + d * 50 * s, cy - 72 * s, cx + d * 118 * s, cy - 60 * s)
        local bottom = curve(cx + d * 118 * s, cy + 58 * s, cx + d * 50 * s, cy + 46 * s, cx, cy + 70 * s)
        local shape = {}
        for _, v in ipairs(top) do shape[#shape + 1] = v end
        for _, v in ipairs(bottom) do shape[#shape + 1] = v end
        local ok, tris = pcall(love.math.triangulate, shape)
        color(th.sel)
        if ok then for _, t in ipairs(tris) do love.graphics.polygon("fill", t) end end
        color(th.dim)
        love.graphics.polygon("line", shape)
        -- Lines of text.
        color(th.dim, 0.45)
        for k = 0, 4 do
            local ly = cy - 30 * s + k * 18 * s
            love.graphics.line(cx + d * 20 * s, ly, cx + d * (k == 4 and 70 or 98) * s, ly - d * d * 3 * s)
        end
    end
    -- The ribbon, hanging from the top of the right page.
    local rx, rw = cx + 64 * s, 22 * s
    color(th.fg, 0.85)
    love.graphics.polygon("fill", rx, cy - 64 * s, rx + rw, cy - 66 * s, rx + rw, cy + 104 * s,
        rx + rw / 2, cy + 90 * s, rx, cy + 104 * s)
end

-- The left page of Bookmarks and Highlights: the title, the mark, and the
-- selected entry in full (a highlight's whole passage, a bookmark's words).
function app.bm_draw_left(entries, x, w)
    local th = theme()
    local nb, nh = #Store.get_bookmarks(book.path), #Store.get_highlights(book.path)
    if nb + nh > 0 then
        local folder, where = Store.books_folder()
        love.graphics.setFont(ui.small)
        color(th.dim)
        love.graphics.printf("Also saved in " .. folder .. "/Highlights" .. (where and (" " .. where) or "")
            .. ", to read on a computer.", x, PAGE_H - 70 - ui.small:getHeight(), w, "left")
    end
    love.graphics.setFont(ui.title)
    color(th.fg)
    love.graphics.print("Bookmarks and Highlights", x, 60)
    love.graphics.setFont(ui.small)
    color(th.dim)
    love.graphics.print(nb .. (nb == 1 and " bookmark" or " bookmarks") .. "  ·  " .. nh
        .. (nh == 1 and " highlight" or " highlights"), x, 60 + ui.title:getHeight() + 4)
    app.draw_book_art(x + w / 2, 260, 0.9)
    local e = entries[bm.sel]
    if not e then return end
    local y = 400
    local label, title, pct, body
    if e.action then
        local sec = current_section()
        label = bookmark_here() and "THIS PAGE  ·  BOOKMARKED" or "THIS PAGE"
        title = sec and book.toc[sec].title or book.title or ""
        pct = book:fraction(pos.ch, pos.off)
        body = page_snippet()
    else
        local it = e.item
        label = e.hl and "HIGHLIGHT" or "BOOKMARK"
        title = it.title ~= "" and it.title or book.title
        pct = it.pct
        body = (e.hl and it.text or it.snippet) or ""
    end
    love.graphics.setFont(ui.small)
    color(th.dim)
    love.graphics.print(label .. "  ·  " .. math.floor(pct * 100 + 0.5) .. "%", x, y)
    y = y + ui.small:getHeight() + 8
    love.graphics.setFont(ui.bold)
    color(th.fg)
    love.graphics.print(fit_text(ui.bold, title, w), x, y)
    y = y + ui.bold:getHeight() + 14
    -- The words: a highlight marked as on the page, as many lines as fit.
    love.graphics.setFont(ui.font)
    local text = e.hl and ("“" .. (body or "") .. "”") or ((body or "") .. (body ~= "" and "…" or ""))
    local _, lines = ui.font:getWrap(text, w - 8)
    local lh = ui.font:getHeight()
    local max = math.max(1, math.floor((PAGE_H - 130 - y) / lh))
    for k = 1, math.min(#lines, max) do
        local line = lines[k]
        if k == max and #lines > max then line = fit_text(ui.font, line .. " …", w - 8) end
        if e.hl then
            color(th.sel)
            love.graphics.rectangle("fill", x - 3, y + 2, ui.font:getWidth(line) + 6, lh - 4, 4, 4)
        end
        color(th.fg)
        love.graphics.print(line, x, y)
        y = y + lh
    end
end

-- Deleting from the list: a card on the touchscreen asks first.
function app.bm_delete(e, n)
    local list = {}
    for _, it in ipairs(e.hl and Store.get_highlights(book.path) or Store.get_bookmarks(book.path)) do
        if it ~= e.item then list[#list + 1] = it end
    end
    if e.hl then Store.set_highlights(book.path, list) else Store.set_bookmarks(book.path, list) end
    app.export_notes()
    bm.sel = math.max(1, math.min(bm.sel, n - 1))
    app.toast(e.hl and "Highlight deleted" or "Bookmark deleted")
end

-- A rounded button: its label, then the button that does the same in small
-- dimmed text ("Get Books  Select", "Delete  A"). style: "strong" (dark),
-- "soft" (the selection colour), "plain" (the page colour) or "off" (an
-- outline, greyed out).
function app.button(bx, by, bw, bh, label, key, style)
    local th = theme()
    if style == "off" then
        color(th.dim, 0.5)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", bx, by, bw, bh, bh / 2, bh / 2)
    else
        color(style == "strong" and th.fg or style == "plain" and th.bg or th.sel)
        love.graphics.rectangle("fill", bx, by, bw, bh, bh / 2, bh / 2)
    end
    local k = key and ("   " .. app.key(key)) or ""
    local lx = bx + (bw - ui.font:getWidth(label) - ui.small:getWidth(k)) / 2
    local ly = centered_y(ui.font, UI_SIZE, by, bh)
    love.graphics.setFont(ui.font)
    color(style == "strong" and th.bg or th.fg, style == "off" and 0.6 or 1)
    love.graphics.print(label, lx, ly)
    love.graphics.setFont(ui.small)
    color(style == "strong" and th.bg or th.dim, style == "strong" and 0.75 or 1)
    love.graphics.print(k, lx + ui.font:getWidth(label), ly + ui.font:getBaseline() - ui.small:getBaseline())
end

-- Before anything that can't be undone, a card on the touchscreen asks:
-- app.ask({ question = "Delete this bookmark?", detail = "Chapter 3",
-- yes = "Delete", on_yes = function() ... end }). A or the button does it;
-- B, or a tap anywhere else, keeps things as they are. on_no (optional):
-- when the other button, or B, was chosen (not just any other press).
function app.ask(q)
    app.asking = q
    redraw()
end

-- The card's two buttons: x, y, w, h on the right page.
function app.ask_button(which)
    local m = MARGINS[2]
    local w = PAGE_W - m.outer - m.inner
    local bw, bh = math.floor((w - 24) / 2), 70
    local y = PAGE_H - 240
    return m.inner + (which == "yes" and 0 or bw + 24), y, bw, bh
end

-- A key while the card is up: true if it was the card's.
function app.ask_action(a)
    local q = app.asking
    if not q then return false end
    -- Only A or B answer; other keys (a page turn out of habit) leave it up.
    if a ~= "confirm" and a ~= "back" then return true end
    app.asking = nil
    if a == "confirm" then q.on_yes()
    elseif q.on_no then q.on_no() end
    redraw()
    return true
end

function app.ask_tap(side, u, v)
    local q = app.asking
    app.asking = nil
    local function hit(which)
        local bx, by, bw, bh = app.ask_button(which)
        return side == app.touch_side() and u >= bx - 12 and u <= bx + bw + 12 and v >= by - 12 and v <= by + bh + 12
    end
    if hit("yes") then q.on_yes()
    elseif hit("no") and q.on_no then q.on_no() end
    redraw()
end

-- A few choices on a card on the touchscreen: app.choose({ title, options =
-- { { label, fn }, ... } }). Up/down and A, or tap one; B or a tap outside closes.
function app.choose(c)
    c.sel = 1
    app.choosing = c
    redraw()
end

-- Row i of the card: x, y, w, h on the right page.
function app.choose_row(i, n)
    local m = MARGINS[2]
    n = n or #app.choosing.options
    local top = PAGE_H - 110 - n * 80
    return m.inner, top + (i - 1) * 80, PAGE_W - m.outer - m.inner, 72
end

function app.choose_action(a)
    local c = app.choosing
    if not c then return false end
    if a == "up" then c.sel = math.max(1, c.sel - 1)
    elseif a == "down" then c.sel = math.min(#c.options, c.sel + 1)
    elseif a == "confirm" then
        app.choosing = nil
        c.options[c.sel][2]()
    elseif a == "back" or a == "menu" or a == "toc" then
        app.choosing = nil
    end
    redraw()
    return true
end

function app.choose_tap(side, u, v)
    local c = app.choosing
    app.choosing = nil
    if side == app.touch_side() then
        for i, o in ipairs(c.options) do
            local x, y, w, h = app.choose_row(i, #c.options)
            if u >= x - 14 and u <= x + w + 14 and v >= y and v < y + h + 8 then o[2]() break end
        end
    end
    redraw()
end

function app.choose_draw()
    local c = app.choosing
    local th = theme()
    local x, y0, w = app.choose_row(1)
    local top = y0 - 76
    color(th.bg)
    love.graphics.rectangle("fill", x - 30, top - 20, w + 60, PAGE_H - top + 20, 16, 16)
    color(th.sel)
    love.graphics.rectangle("fill", x - 14, top, w + 28, PAGE_H - 96 - top, 14, 14)
    love.graphics.setFont(ui.font)
    color(th.dim)
    love.graphics.printf(fit_text(ui.font, c.title, w - 20), x, top + 22, w, "center")
    for i, o in ipairs(c.options) do
        local rx, ry, rw, rh = app.choose_row(i)
        color(i == c.sel and th.bg or th.sel)
        love.graphics.rectangle("fill", rx, ry, rw, rh, 10, 10)
        color(th.fg)
        love.graphics.printf(o[1], rx, centered_y(ui.font, UI_SIZE, ry, rh), rw, "center")
    end
    app.hints(x, nil, { "A", "select", "B", "close" })
end

function app.ask_draw()
    local q = app.asking
    local th = theme()
    local m = MARGINS[2]
    local x, w = m.inner, PAGE_W - m.outer - m.inner
    local top = PAGE_H - 440
    color(th.bg)
    love.graphics.rectangle("fill", x - 30, top - 20, w + 60, PAGE_H - top + 20, 16, 16)
    color(th.sel)
    love.graphics.rectangle("fill", x - 14, top, w + 28, 320, 14, 14)
    love.graphics.setFont(ui.font)
    color(th.fg)
    love.graphics.printf(q.question, x, top + 26, w, "center")
    if q.detail and q.detail ~= "" then
        love.graphics.setFont(ui.small)
        color(th.dim)
        love.graphics.printf(fit_text(ui.small, q.detail, w - 40), x + 20, top + 80, w - 40, "center")
    end
    local bx, by, bw, bh = app.ask_button("yes")
    app.button(bx, by, bw, bh, q.yes or "Yes", "A", "strong")
    bx, by, bw, bh = app.ask_button("no")
    app.button(bx, by, bw, bh, q.no or "Keep", "B", "plain")
    app.hints(x, nil, { "A", (q.yes or "yes"):lower(), "B", (q.no or "keep"):lower() })
end

local CREDITS = {
    { "Fonts", "Crimson Pro (Jacques Le Bailly), Gentium Book Plus, Charis SIL and Andika (SIL International), Literata "
        .. "(TypeTogether), Source Serif 4 (Adobe), Crimson Text (Sebastian Kosch), "
        .. "EB Garamond (Georg Duffner, Octavio Pardo), Lora (Cyreal), Merriweather "
        .. "(Sorkin Type), PT Serif (ParaType), Spectral (Production Type), Vollkorn "
        .. "(Friedrich Althausen), Bitter (Huerta Tipográfica), Atkinson Hyperlegible "
        .. "Next (Braille Institute), Inter (Rasmus Andersson), Lexend (Lexend Project) "
        .. "and OpenDyslexic (Abbie Gonzalez). SIL Open Font License 1.1." },
    { "Hyphenation", "US English patterns from TeX's hyph-utf8, by Gerard D.C. Kuiken." },
    { "Dictionary", "WordNet 3.1, © 2011 Princeton University (WordNet license)." },
    { "Engine", "LÖVE 11.5 (zlib license), from the PortMaster runtime." },
    { "QR codes", "qrencode.lua by Patrick Gundlach and contributors (BSD license)." },
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
        app.hints(x, nil, { "B", "back" })
    end
end

-- Help: the buttons on the left page, the touchscreen (the bottom screen,
-- where this is drawn) on the right. Kept to what fits on one page each.
-- The buttons, held the other way round (Hold it with buttons: On the left).
app.HELP_FLIPPED = { "Buttons", {
    { "D-pad, stick", "Turn pages" },
    { "D-pad up", "Look up or highlight a word" },
    { "A, X", "Next page" },
    { "B, Y", "Previous page" },
    { "Select", "Bookmark the page" },
    { "Start", "Settings (or press the stick)" },
    { "In menus", "Y up, A down, X select, B back; Select deletes or shows options" },
    { "Anbernic", "Quit" },
} }
app.HELP = {
    left = { "Buttons", {
        { "D-pad, stick", "Turn pages" },
        { "A", "Footnotes on these pages" },
        { "B", "Settings" },
        { "X, Start", "Settings" },
        { "Curved arrow", "Settings (or press the stick)" },
        { "Y", "Look up a word" },
        { "Y, then Select", "Highlight: Select at the first and last word" },
        { "Select", "Bookmark the page" },
        { "Anbernic", "Quit" },
    } },
    right = { "Touchscreen", {
        { "Tap or swipe", "Turn pages (right half forward)" },
        { "Slide up/down", "Brightness (in lists: scroll)" },
        { "Pinch", "Text size" },
        { "Top-right corner", "Bookmark" },
        { "Top edge", "Show or hide the status bars" },
        { "Hold a word", "Look it up" },
        { "Tap a word", "While highlighting: highlight up to it" },
        { "Note number", "Show the footnote" },
    }, "B back" },
}
function app.draw_help(side)
    local th = theme()
    local m = MARGINS[2]
    local x = side == "left" and m.outer or m.inner
    local w = PAGE_W - m.outer - m.inner
    local page = app.HELP[side]
    -- Turned round, the buttons do other things while reading (as printed).
    local literal = side == "left" and app.flipped()
    if literal then page = app.HELP_FLIPPED end
    love.graphics.setFont(ui.title)
    color(th.fg)
    love.graphics.print(page[1], x, 60)
    local key_w, y = 270, 158
    for _, row in ipairs(page[2]) do
        local desc = row[2]
        if row[1] == "Tap or swipe" and S.tap == "menu" then desc = "Swipe: turn pages. Tap: Settings" end
        love.graphics.setFont(ui.help)
        color(th.fg)
        local key = row[1]
        if key == "Top-right corner" and app.flipped() then key = "Top-left corner" end    -- (turned round)
        love.graphics.print(literal and key or app.keys_text(key), x, y)
        color(th.dim)
        love.graphics.printf(desc, x + key_w, y, w - key_w, "left")
        local _, lines = ui.help:getWrap(desc, w - key_w)
        y = y + math.max(1, #lines) * ui.help:getHeight() + 16
    end
    love.graphics.setFont(ui.small)
    color(th.dim)
    if page[3] then app.hints(x, nil, { "B", "back" }) end
end

---------------------------------------------------------------- keyboard

-- On-screen keyboard: the typed text and the keys on the right page (the
-- touchscreen), what the buttons do on the left. Tap a key, or move with the
-- D-pad and press A. B deletes (or cancels when empty), Y types a space,
-- Start or X searches.
-- Three layers: small letters, capitals (the shift arrow) and symbols ("#@"), for
-- searches as well as user names, passwords and web addresses.
app.KB_LAYERS = {
    lower = { "1234567890", "qwertyuiop", "asdfghjkl'", "zxcvbnm,.-" },
    upper = { "1234567890", "QWERTYUIOP", "ASDFGHJKL'", "ZXCVBNM,.-" },
    symbols = { "1234567890", "@#$%&*+=/:", "_~()[]{}<>", "!?;\"`^|\\,." },
}
function app.kb_layer(layer)
    app.KB_ROWS = {}
    for _, row in ipairs(app.KB_LAYERS[layer]) do
        local keys = {}
        for ch in row:gmatch(".") do keys[#keys + 1] = { key = ch, label = ch, span = 1 } end
        app.KB_ROWS[#app.KB_ROWS + 1] = keys
    end
    -- One bottom row, its keys lined up with the columns above.
    app.KB_ROWS[#app.KB_ROWS + 1] = { { key = "cancel", label = "Cancel", span = 2 },
        { key = "shift", label = "", span = 1 }, { key = "symbols", label = layer == "symbols" and "abc" or "#@", span = 1 },
        { key = "space", label = "Space", span = 2 }, { key = "del", label = "Delete", span = 2 },
        { key = "ok", label = "Search", span = 2 } }
    if app.kb then app.kb.layer = layer end
end
app.kb_layer("lower")
app.KB_TOP, app.KB_ROW_H = 300, 112          -- keys area on the right page
app.KB_MAX = 120                             -- characters

-- Open the keyboard. opts: title, hint, text, submit(text), cancel(),
-- ok (the confirm key's label, "Search" by default), secret (show dots).
function app.kb_open(opts)
    -- No key is highlighted until the D-pad is used (r, c = nil).
    app.kb = { title = opts.title, hint = opts.hint, text = opts.text or "",
        submit = opts.submit, cancel = opts.cancel, back = app.mode, ok = opts.ok, secret = opts.secret,
        allow_empty = opts.allow_empty }
    app.kb_layer("lower")
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
    elseif key == "shift" then
        app.kb_layer(kb.layer == "upper" and "lower" or "upper")
    elseif key == "symbols" then
        app.kb_layer(kb.layer == "symbols" and "lower" or "symbols")
    elseif key == "ok" then
        local q = kb.text:gsub("^%s+", ""):gsub("%s+$", "")
        if q == "" and not kb.allow_empty then return end
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
    if kb.r == 0 and (a == "left" or a == "prev" or a == "right" or a == "next") then
        -- (the eye is alone on its row)
    elseif a == "left" or a == "prev" then kb.c = (kb.c - 2) % #rows[kb.r] + 1
    elseif a == "right" or a == "next" then kb.c = kb.c % #rows[kb.r] + 1
    elseif a == "up" or a == "down" then
        -- Keep to the same column: the key under the middle of this one. For
        -- a password, the eye (row 0) sits above the top row.
        if kb.r == 0 then
            kb.r = a == "down" and 1 or #rows
            kb.c = app.kb_key_at(kb.r, 9)
        elseif kb.secret and ((a == "up" and kb.r == 1) or (a == "down" and kb.r == #rows)) then
            kb.r = 0
        else
            local c0, c1 = app.kb_cols(kb.r, kb.c)
            kb.r = (kb.r - 1 + (a == "down" and 1 or -1)) % #rows + 1
            kb.c = app.kb_key_at(kb.r, (c0 + c1) / 2 - 0.01)
        end
    elseif a == "confirm" then
        if kb.r == 0 then kb.reveal = not kb.reveal
        elseif kb.r then app.kb_press(rows[kb.r][kb.c].key) end
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
    if app.kb.secret then
        local ex, ey, ew, eh = app.kb_eye_box()
        if u >= ex - 16 and u <= ex + ew + 16 and v >= ey - 16 and v <= ey + eh + 16 then
            app.kb.reveal = not app.kb.reveal
            redraw()
            return
        end
    end
    local x0, unit = app.kb_geom()
    local r = math.floor((v - app.KB_TOP) / app.KB_ROW_H) + 1
    if r < 1 or r > #app.KB_ROWS or u < x0 - 10 or u > x0 + unit * 10 + 10 then return end
    local col = math.max(0, math.min(9.99, (u - x0) / unit))
    local kb = app.kb
    local c = app.kb_key_at(r, col)
    if kb.r then kb.r, kb.c = r, c end              -- follow taps only once the D-pad is in use
    app.kb_press(app.KB_ROWS[r][c].key)
end

-- The eye button at the end of a password field: x, y, w, h.
function app.kb_eye_box()
    local x0 = app.kb_geom()
    local m = MARGINS[2]
    local w = PAGE_W - m.outer - m.inner
    return x0 + w - 76, 160, 76, 76
end

-- An eye (open: the password shows; struck through: hidden), in colour c.
function app.kb_eye_icon(cx, cy, open, c)
    color(c)
    love.graphics.setLineWidth(3)
    local pts = {}
    for i = 0, 16 do                                    -- the upper lid, then the lower
        local t = i / 16
        pts[#pts + 1] = cx - 24 + 48 * t
        pts[#pts + 1] = cy - 14 * math.sin(math.pi * t)
    end
    love.graphics.line(pts)
    for i = 1, #pts, 2 do pts[i + 1] = cy + (cy - pts[i + 1]) end
    love.graphics.line(pts)
    love.graphics.circle("fill", cx, cy, 6)
    if not open then love.graphics.line(cx - 20, cy + 18, cx + 20, cy - 18) end
end

-- The shift key's arrow: an outline, filled while capitals are on.
function app.kb_shift_icon(cx, cy, on)
    local s = 16
    local pts = { cx, cy - s * 1.25, cx + s, cy - s * 0.1, cx + s * 0.45, cy - s * 0.1,
        cx + s * 0.45, cy + s, cx - s * 0.45, cy + s, cx - s * 0.45, cy - s * 0.1, cx - s, cy - s * 0.1 }
    if on then        -- (not convex, so filled as triangles)
        for _, t in ipairs(love.math.triangulate(pts)) do love.graphics.polygon("fill", t) end
    else
        love.graphics.setLineWidth(3)
        love.graphics.polygon("line", pts)
    end
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
            love.graphics.print(app.keys_text(row[1]), x, y)
            color(th.dim)
            love.graphics.print(app.keys_text(row[2]), x + 150, y)
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
    local tw = w - 20
    if kb.secret then
        -- The eye at the field's end shows or hides what's typed.
        local ex, ey, ew, eh = app.kb_eye_box()
        if kb.r == 0 then color(th.fg); love.graphics.rectangle("fill", ex, ey, ew, eh, 10, 10) end
        app.kb_eye_icon(ex + ew / 2, ey + eh / 2, kb.reveal, kb.r == 0 and th.bg or th.fg)
        color(th.fg)
        tw = tw - ew - 12
        if not kb.reveal then shown = string.rep("•", #kb.text:gsub("[\128-\191]", "")) end
    end
    while ui.title:getWidth(shown .. "|") > tw and #shown > 0 do
        shown = shown:sub(2):gsub("^[\128-\191]+", "")
    end
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
                -- Search, the main action, filled; the rest outlined.
                -- (and the layer keys while their layer is on)
                if k.key == "ok" or (k.key == "shift" and kb.layer == "upper") or (k.key == "symbols" and kb.layer == "symbols") then
                    color(th.sel); love.graphics.rectangle("fill", kx, ky, kw, kh, 10, 10)
                end
                color(th.dim, 0.45)
                love.graphics.rectangle("line", kx, ky, kw, kh, 10, 10)
                color(th.fg)
            end
            if k.key == "shift" then
                app.kb_shift_icon(kx + kw / 2, ky + kh / 2, kb.layer == "upper")
            else
                local label = k.key == "ok" and (kb.ok or "Search") or k.label
                local f = #label > 1 and ui.font or ui.title
                love.graphics.setFont(f)
                love.graphics.printf(label, kx, ky + (kh - f:getHeight()) / 2, kw, "center")
            end
        end
    end
end

---------------------------------------------------------------- updates

-- On launch (when online) eReaderDS asks GitHub for its newest releases; a
-- newer one is offered in Settings (and a note says so). Updating downloads
-- the release zip, unpacks it beside the app, and restarts: the launcher
-- moves it into place (see updater.lua and launch.sh). app.upd = { state =
-- "checking" | "none" | "available" | "downloading" | "unpacking" | "ready"
-- | "error", version, url, size, notes, got, total, frac, message }
app.Updater = require("updater")
app.UPDATE_EXIT = 42                 -- tells the launcher to install and restart
app.upd = { state = "none" }

-- The version to compare with (READER_FAKE_VERSION pretends to be older, for testing).
function app.update_current() return os.getenv("READER_FAKE_VERSION") or VERSION end

-- Network trouble in plain words.
function app.update_error(msg)
    msg = tostring(msg or "")
    if not shop.online(true) then return "Not connected to Wi-Fi." end
    if msg:find("403") or msg:find("429") then return "GitHub is busy right now. Try again in a little while." end
    if msg:find("stopped responding") or msg:find("timeout") or msg:find("slow to answer")
            or msg:find("closed early") or msg:find("cut off") then
        return "The connection dropped. Check Wi-Fi and try again."
    end
    if msg:find("404") then return "The update isn't on GitHub (any more). Try again later." end
    if msg:find("couldn't find") or msg:find("couldn't connect") then
        return "Couldn't reach GitHub. Check Wi-Fi and try again."
    end
    return msg ~= "" and msg or "Something went wrong."
end

function app.update_check(by_hand)
    local u = app.upd
    if u.state == "checking" then u.by_hand = u.by_hand or by_hand return end   -- asked while the launch check runs
    if u.state == "downloading" or u.state == "unpacking" or u.state == "ready" then return end
    if not shop.online(true) then
        if by_hand then app.upd = { state = "error", message = "Not connected to Wi-Fi." } end
        return
    end
    local checking = { state = "checking", by_hand = by_hand }
    app.upd = checking
    shop.net_job({ kind = "fetch", url = app.Updater.RELEASES }, function(msg)
        by_hand = checking.by_hand
        if msg.kind == "error" then
            -- Checked on launch: stay quiet. Checked by hand: say why.
            app.upd = { state = by_hand and "error" or "none", message = by_hand and app.update_error(msg.message) }
            return
        end
        local rel, err = app.Updater.parse(msg.body or "", app.update_current())
        if rel then
            rel.state = "available"
            rel.url = os.getenv("READER_FAKE_UPDATE_URL") or rel.url     -- for testing failures
            -- Skipped: nothing is said unless you check by hand.
            rel.skipped = rel.version == S.skip_version
            if rel.skipped and not by_hand then rel.state = "none"; rel.quiet = true end
            app.upd = rel
            -- Its notes in plain words (the release notes are the fallback).
            shop.net_job({ kind = "fetch", url = app.Updater.whatsnew_url(rel.version) }, function(m2)
                if m2.kind ~= "error" and app.upd == rel then
                    local list = app.Updater.whatsnew_since(m2.body, app.update_current())
                    if #list > 0 then rel.whatsnew = list end
                    redraw()
                end
            end)
            if app.mode ~= "update" and not rel.skipped then
                -- Tapping it opens the update (so do Settings, and Start in the library).
                app.toast("Update available: v" .. rel.version .. "\nYou have v" .. app.update_current()
                    .. "  ·  Tap here to update", 8, app.update_open)
            end
        else
            app.upd = { state = (by_hand and err) and "error" or "none", message = err, checked = not err }
        end
    end)
end

function app.update_open()
    if app.mode ~= "update" then app.update_back = app.mode end
    app.mode = "update"
    redraw()
end

function app.update_start()
    local u = app.upd
    if not shop.online(true) then
        u.state, u.message = "error", "Not connected to Wi-Fi."
        redraw()
        return
    end
    local dir = app.Updater.app_dir()
    local zip = dir .. "/.update.zip"
    u.state, u.got, u.total, u.message = "downloading", 0, u.size or 0, nil
    u.job = shop.net_job({ kind = "download", url = u.url, dest = zip, size = u.size }, function(msg)
        if msg.kind == "progress" then
            u.got, u.total = msg.got, msg.total
        elseif msg.kind == "done" then
            -- A download cut short is caught here, before unpacking.
            local f = io.open(zip, "rb")
            local size = f and f:seek("end") or 0
            if f then f:close() end
            if (u.size or 0) > 0 and size ~= u.size then
                os.remove(zip)
                u.state, u.message = "error", "The download was incomplete. Try again."
                return
            end
            u.state, u.frac, u.saving = "unpacking", 0, nil
            -- Unpack a file at a time between frames (the screen stays live).
            app.find_stop()                                -- the update comes first
            app.task_kind = "update"
            app.task = coroutine.create(function()
                local ok, err = pcall(function()
                    local co = coroutine.create(app.Updater.unpack)
                    local args = { zip, dir .. "/.delta", u.version }
                    while true do
                        local ok2, frac, phase = coroutine.resume(co, unpack(args))
                        args = {}
                        if not ok2 then error(frac, 0) end
                        if coroutine.status(co) == "dead" then break end
                        u.frac, u.saving = frac, phase == "saving"
                        coroutine.yield()
                    end
                end)
                os.remove(zip)
                if ok then u.state = "ready"
                else
                    os.execute('rm -rf "' .. dir .. '/.delta"')
                    u.state, u.message = "error", tostring(err)
                end
            end)
        else
            os.remove(zip)
            u.state = "available"
            if msg.message ~= "cancelled" then
                u.state, u.message = "error", app.update_error(msg.message)
            end
        end
    end)
end

-- "Check for Updates" (Settings): open what was found, even a
-- skipped version, or check now.
function app.update_check_open()
    local u = app.upd
    if u.quiet then u.state, u.quiet = "available", nil end     -- skipped, but asked for
    if u.state == "available" or u.state == "ready" then app.update_open()
    else app.update_check(true); app.update_open() end
end

function app.update_status()
    local u = app.upd
    return (u.state == "checking" and "Checking…")
        or (u.quiet and ("v" .. u.version .. " skipped"))
        or (u.state == "available" and ("v" .. u.version .. (u.skipped and " skipped" or "") .. " available"))
        or (u.checked and "Up to date") or ""
end

-- Skip this version: no more notes about it; the next one is offered as usual.
function app.update_skip()
    local u = app.upd
    if u.state ~= "available" then return end
    S.skip_version = u.version
    Store.save_settings(S)
    -- Quiet from now on: no bold Update, no library line (Check for Updates
    -- still finds it).
    u.skipped, u.state, u.quiet = true, "none", true
    app.toast("Skipped v" .. u.version .. ". You'll hear about the next version.", 3)
    app.mode = app.update_back or (book and "menu" or "library")
    redraw()
end

function app.update_action(a)
    local u = app.upd
    if a == "toc" then app.update_skip() return end               -- Y
    if a == "confirm" then
        if u.state == "available" or (u.state == "error" and u.url) then app.update_start()
        elseif u.state == "error" or (u.state == "none" and not u.checked) then app.update_check(true)
        elseif u.state == "ready" then love.event.quit(app.UPDATE_EXIT) end
    elseif a == "back" or a == "menu" then
        if u.state == "downloading" and u.job then
            love.thread.getChannel("net_cancel"):push(u.job)
        elseif u.state ~= "unpacking" then
            app.mode = app.update_back or (book and "menu" or "library")
        end
    end
    redraw()
end

-- The button on the touchscreen: what A does.
function app.update_button()
    local w, h = 420, 80
    return math.floor((PAGE_W - w) / 2), PAGE_H - 260, w, h
end

function app.update_tap(side, u, v)
    local bx, by, bw, bh = app.update_button()
    if side ~= "right" then return end
    if u >= bx - 20 and u <= bx + bw + 20 and v >= by - 20 and v <= by + bh + 20 then
        app.update_action("confirm")
    elseif app.upd.state == "available" and v > by + bh + 20 and v < by + bh + 110 then
        app.update_skip()                               -- "Skip this version" under the button
    end
end

function app.update_draw(side)
    local th = theme()
    local u = app.upd
    local m = MARGINS[2]
    local x = side == "left" and m.outer or m.inner
    local w = PAGE_W - m.outer - m.inner
    if side == "left" then
        love.graphics.setFont(ui.title)
        color(th.fg)
        love.graphics.print(u.version and ("Update to v" .. u.version) or "Updates", x, 60)
        love.graphics.setFont(ui.font)
        color(th.dim)
        love.graphics.print("You have v" .. app.update_current(), x, 60 + ui.title:getHeight() + 6)
        -- What's in it, like the What's new page: each newer version's notes
        -- in plain words (else the release notes), as far as they fit.
        local y, limit, full = 200, PAGE_H - 110, false
        local function item(text)
            local _, lines = ui.font:getWrap(text, w - 34)
            if y + #lines * ui.font:getHeight() > limit then full = true; return end
            color(th.dim)
            love.graphics.setFont(ui.font)
            love.graphics.print("•", x, y)
            color(th.fg)
            for _, l in ipairs(lines) do love.graphics.print(l, x + 34, y); y = y + ui.font:getHeight() end
            y = y + 8
        end
        if u.whatsnew then
            for k, ver in ipairs(u.whatsnew) do
                if full then break end
                if #u.whatsnew > 1 then
                    if y + ui.bold:getHeight() + ui.font:getHeight() > limit then full = true; break end
                    love.graphics.setFont(ui.bold)
                    color(th.fg)
                    love.graphics.print("Version " .. ver.version, x, y)
                    y = y + ui.bold:getHeight() + 6
                end
                for _, t in ipairs(ver.items) do if not full then item(t) end end
                y = y + (k < #u.whatsnew and 16 or 0)
            end
        elseif u.notes and u.notes ~= "" then
            for para in u.notes:gmatch("[^\n]+") do
                if not full then item((para:gsub("^•%s*", ""))) end
            end
        end
        if full then
            love.graphics.setFont(ui.font)
            color(th.dim)
            love.graphics.print("…", x + 34, y - 4)
        end
        love.graphics.setFont(ui.small)
        color(th.dim)
        love.graphics.printf("Your books, settings and progress are kept.", x, PAGE_H - 70, w, "left")
        return
    end
    -- The touchscreen: what's happening, and the button.
    local status, button
    if u.state == "available" then
        status, button = "eReaderDS v" .. u.version .. (u.size and u.size > 0 and ("  ·  " .. shop.format_size(u.size)) or ""), "Update now"
    elseif u.state == "downloading" then
        status = "Downloading…  " .. (shop.format_size(u.got or 0) or "0 KB")
            .. ((u.total or 0) > 0 and (" of " .. shop.format_size(u.total)) or "")
    elseif u.state == "unpacking" then
        status = u.saving and "Saving to the SD card…" or ("Installing…  " .. math.floor((u.frac or 0) * 100) .. "%")
    elseif u.state == "ready" then
        status, button = "Ready. eReaderDS restarts with the new version.", "Restart now"
    elseif u.state == "checking" then
        status = "Checking for updates…"
    elseif u.state == "error" then
        status, button = "Couldn't update: " .. (u.message or "unknown error"), "Try again"
    elseif u.checked then
        status = "eReaderDS v" .. VERSION .. " is up to date."
    else
        status, button = "eReaderDS v" .. VERSION, "Check for updates"
    end
    love.graphics.setFont(ui.font)
    color(th.fg)
    love.graphics.printf(status, x, 300, w, "center")
    local frac = (u.state == "downloading" and (u.total or 0) > 0 and u.got / u.total)
        or (u.state == "unpacking" and u.frac) or nil
    if frac then
        local bw = w * 0.8
        local bx = x + (w - bw) / 2
        color(th.sel)
        love.graphics.rectangle("fill", bx, 400, bw, 10, 5, 5)
        color(th.fg)
        love.graphics.rectangle("fill", bx, 400, bw * math.min(1, frac), 10, 5, 5)
    end
    if button then
        local bx, by, bw, bh = app.update_button()
        color(th.sel)
        love.graphics.rectangle("fill", bx, by, bw, bh, bh / 2, bh / 2)
        love.graphics.setFont(ui.title)
        color(th.fg)
        love.graphics.printf(button, bx, centered_y(ui.title, 44, by, bh), bw, "center")
        if u.state == "available" then
            love.graphics.setFont(ui.font)
            color(th.dim)
            love.graphics.printf(u.skipped and "You skipped this version" or "Skip this version",
                x, by + bh + 40, w, "center")
        end
    end
    app.hints(x, nil, (u.state == "downloading" and { "B", "cancel" }) or (u.state == "unpacking" and {})
        or (u.state == "available" and { "A", "update now", "Y", "skip this version", "B", "back" })
        or (button and { "A", button:lower(), "B", "back" }) or { "B", "back" })
end

---------------------------------------------------------------- what's new

-- The changes in each version, in plain words (whatsnew.txt), flowing down
-- the left page, then the right, then onto further spreads.
app.WN_TOP, app.WN_BOTTOM = 190, PAGE_H - 110

function app.whatsnew_open()
    if app.mode ~= "whatsnew" then app.whatsnew_back = app.mode end
    app.wn = { spread = 1 }
    app.mode = "whatsnew"
    redraw()
end

-- Lay the text out into pages: { { {font, text, x, y}, ... }, ... }.
function app.whatsnew_pages(w)
    local pages, page, y = {}, {}, app.WN_TOP
    local function new_page() pages[#pages + 1] = page; page, y = {}, 60 end
    local function put(font, text, dx, h)
        if y + h > app.WN_BOTTOM then new_page() end
        page[#page + 1] = { font, text, dx, y }
        y = y + h
    end
    local data = love.filesystem.read("whatsnew.txt") or ""
    local block = 0                                  -- 1 = the latest version
    for line in data:gmatch("[^\n]+") do
        if not line:match("^#") and line:match("%S") then
            local v = line:match("^v(%d[%d%.]*)%s*$")
            if v then
                block = block + 1
                if block > 1 then y = y + 28 end
                -- The latest version gets a bigger heading and a "Latest" tag.
                local hf = block == 1 and ui.title or ui.bold
                if y + hf:getHeight() + ui.font:getHeight() > app.WN_BOTTOM then new_page() end
                put(hf, "Version " .. v, 0, hf:getHeight() + 8)
                page[#page].latest = block == 1
                page[#page].heading = true
                page[#page].yours = v == VERSION
            else
                local _, lines = ui.font:getWrap(line, w - 34)
                for i, l in ipairs(lines) do
                    put(ui.font, (i == 1 and "•" or "") .. "\t" .. l, 0, ui.font:getHeight())
                    page[#page].latest = block == 1
                end
                y = y + 8
            end
        end
    end
    pages[#pages + 1] = page
    return pages
end

function app.whatsnew_draw(side)
    local th = theme()
    local m = MARGINS[2]
    local x = side == "left" and m.outer or m.inner
    local w = PAGE_W - m.outer - m.inner
    local wn = app.wn
    wn.pages = wn.pages or app.whatsnew_pages(w)
    wn.spreads = math.ceil(#wn.pages / 2)
    wn.spread = math.max(1, math.min(wn.spreads, wn.spread))
    if side == "left" and wn.spread == 1 then
        love.graphics.setFont(ui.title)
        color(th.fg)
        love.graphics.print("What's New", x, 60)
        love.graphics.setFont(ui.font)
        color(th.dim)
        love.graphics.print("You have v" .. VERSION, x, 60 + ui.title:getHeight() + 6)
    end
    local page = wn.pages[(wn.spread - 1) * 2 + (side == "left" and 1 or 2)] or {}
    -- The latest version: a bar down the side of its notes.
    local bar0, bar1
    for _, it in ipairs(page) do
        if it.latest and not it.heading then
            bar0 = bar0 or it[4]
            bar1 = it[4] + it[1]:getHeight()
        end
    end
    if bar0 then
        color(th.fg)
        love.graphics.rectangle("fill", x - 22, bar0 + 4, 5, bar1 - bar0 - 4, 2, 2)
    end
    for _, it in ipairs(page) do
        love.graphics.setFont(it[1])
        color(th.fg)
        local text = it[2]
        if it.heading then
            love.graphics.print(text, x, it[4])
            -- An outlined "Latest" tag (no fill, so it works on every theme),
            -- and which one you have.
            local tx = x + it[1]:getWidth(text) + 18
            local ty = it[4] + it[1]:getBaseline() - ui.small:getBaseline()
            love.graphics.setFont(ui.small_bold)
            if it.latest then
                local tw, thh = ui.small_bold:getWidth("LATEST") + 22, ui.small_bold:getHeight() + 6
                love.graphics.setLineWidth(2)
                love.graphics.rectangle("line", tx, ty - 3, tw, thh, thh / 2, thh / 2)
                love.graphics.print("LATEST", tx + 11, ty)
                tx = tx + tw + 12
            end
            if it.yours then
                color(th.dim)
                love.graphics.setFont(ui.small)
                love.graphics.print("yours", tx, ty)
            end
            goto continue
        end
        -- "•\t..." starts an item, "\t..." continues one ("•?" would make only
        -- the bullet's last byte optional).
        local bullet, rest = text:match("^(•)\t(.*)$")
        if not bullet then rest = text:match("^\t(.*)$"); bullet = rest and "" end
        if bullet then
            if bullet ~= "" then color(th.dim); love.graphics.print("•", x, it[4]); color(th.fg) end
            love.graphics.print(rest, x + 34, it[4])
        else
            love.graphics.print(text, x, it[4])
        end
        ::continue::
    end
    love.graphics.setFont(ui.small)
    color(th.dim)
    if side == "right" then
        app.hints(x, nil, wn.spreads > 1 and { "‹ ›", "more", "B", "back" } or { "B", "back" })
        if wn.spreads > 1 then app.count(x, w, wn.spread, wn.spreads) end
    end
end

function app.whatsnew_action(a)
    local wn = app.wn
    if a == "right" or a == "next" or a == "down" or a == "confirm" then wn.spread = wn.spread + 1
    elseif a == "left" or a == "prev" or a == "up" then wn.spread = math.max(1, wn.spread - 1)
    elseif a == "back" or a == "menu" then app.mode = app.whatsnew_back or (book and "menu" or "library") end
    redraw()
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
app.FONT_LIST_Y = 160                 -- the list, under the title
function app.font_rows() return math.floor((PAGE_H - 90 - app.FONT_LIST_Y) / app.FONT_ROW_H) end

-- "Get More Fonts", beside the "Fonts" title (always in view); Y does the same.
function app.font_get_button()
    local w, h = ui.font:getWidth("Get More Fonts") + ui.small:getWidth("   Y") + 44, 50
    local x = MARGINS[2].inner + ui.title:getWidth("Fonts") + 24
    return x, math.floor(60 + (ui.title:getHeight() - h) / 2), w, h
end

function app.font_to_get()
    app.font_close(false)
    app.fget_open()
end
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
    if apply and fp.list[fp.sel] and fp.list[fp.sel].name ~= S.font then   -- (the same font: nothing to redo)
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
    elseif a == "down" then fp.sel = math.min(math.max(1, n), fp.sel + 1)
    elseif a == "left" or a == "prev" or a == "right" or a == "next" then
        -- All / Serif / Sans, like the switch at the top of the list.
        local idx = 1
        for i, f in ipairs(app.FONT_FILTERS) do if f[1] == fp.filter then idx = i end end
        idx = idx + ((a == "left" or a == "prev") and -1 or 1)
        app.font_set_filter(app.FONT_FILTERS[math.max(1, math.min(#app.FONT_FILTERS, idx))][1])
    elseif a == "confirm" then app.font_close(true) return
    elseif a == "toc" then app.font_to_get() return               -- Y: get more fonts
    elseif a == "back" or a == "menu" then app.font_close(false) return
    end
    redraw()
end

function app.font_tap(side, u, v)
    if side ~= "right" then return end
    local fp = app.font_pick
    local bx, by, bw, bh = app.font_get_button()
    if u >= bx - 10 and u <= bx + bw + 10 and v >= by - 8 and v <= by + bh + 8 then
        app.font_to_get()
        return
    end
    if v < app.FONT_LIST_Y then                     -- the All / Serif / Sans switch
        for _, t in ipairs(fp.tabs or {}) do
            if u >= t.x0 - 12 and u <= t.x1 + 12 then app.font_set_filter(t.filter); redraw() end
        end
        return
    end
    local idx = fp.top + math.floor((v - app.FONT_LIST_Y) / app.FONT_ROW_H)
    if v < app.FONT_LIST_Y or idx >= fp.top + app.font_rows() or not fp.list[idx] then return end
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
    love.graphics.print("Fonts", x, 60)
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
    local bx, by, bw, bh = app.font_get_button()
    app.button(bx, by, bw, bh, "Get More Fonts", "Y", "soft")
    draw_list(side, fp.list, fp.sel, fp.top, rows, x, app.FONT_LIST_Y, w, app.FONT_ROW_H, function(it, _, rx, ry, rw)
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
    app.hints(x, nil, { "A", "use", "Y", "get more", "‹ ›", "filter", "B", "back" })
    app.count(x, w, fp.sel, #fp.list)
end

---------------------------------------------------------------- get more fonts

-- Free reading fonts to download (SIL Open Font License, from Google Fonts),
-- listed in the eReaderDS repository (fontpack/, built by
-- tools/build-font-pack.py): each is a zip of its styles, unpacked into the
-- fonts folder, and a preview of its name set in the font.
app.FONTPACK = "https://raw.githubusercontent.com/casualducko/eReaderDS/main/fontpack/"
app.FGET_ROW_H = 84
app.fget = { sel = 1, top = 1 }

function app.fget_open()
    local g = app.fget
    g.sel, g.top = 1, 1
    -- A download cut short (the app quit) leaves a hidden zip: tidy it away.
    local dir = not g.busy and Fonts.user_dir()
    if dir then os.execute('rm -f "' .. dir .. '"/.*.zip "' .. dir .. '"/.*.zip.part 2>/dev/null') end
    app.mode = "fontget"
    if not g.list and not g.loading then app.fget_load() end
    redraw()
end

function app.fget_load()
    local g = app.fget
    if not shop.online(true) then g.error = "Not connected to Wi-Fi."; return end
    g.loading, g.error = true, nil
    shop.net_job({ kind = "fetch", url = app.FONTPACK .. "catalog.json" }, function(msg)
        g.loading = false
        if msg.kind ~= "done" then g.error = app.update_error(msg.message); redraw(); return end
        local ok, data = pcall(require("json").decode, msg.body or "")
        if not ok or type(data) ~= "table" or type(data.fonts) ~= "table" then
            g.error = "Couldn't read the list of fonts."
        else
            -- Not the ones built in (a font can move into the app later).
            local bundled = {}
            for _, f in ipairs(Fonts.list()) do if f.bundled then bundled[f.name] = true end end
            g.all = {}
            for _, e in ipairs(data.fonts) do
                -- (Whole entries only: zip becomes a file name, preview an address.)
                if type(e) == "table" and type(e.name) == "string" and not bundled[e.name]
                        and type(e.zip) == "string" and not e.zip:find("[/\\]") and not e.zip:find("..", 1, true)
                        and type(e.preview) == "string" then
                    g.all[#g.all + 1] = e
                end
            end
            table.sort(g.all, function(a, b) return a.name:lower() < b.name:lower() end)
            app.fget_filter(g.filter or "all")
            for _, e in ipairs(g.all) do app.fget_fetch_preview(e) end      -- small: get them all now
        end
        redraw()
    end)
end

-- All / Serif / Sans, like the Fonts page, keeping the highlighted font if it's still listed.
function app.fget_filter(filter)
    local g = app.fget
    local keep = g.list and g.list[g.sel]
    g.filter, g.list = filter, {}
    for _, e in ipairs(g.all or {}) do
        if filter == "all" or e.kind == filter then g.list[#g.list + 1] = e end
    end
    g.sel, g.top = 1, 1
    for i, e in ipairs(g.list) do if e == keep then g.sel = i end end
end

-- Is it in the fonts folder already?
function app.fget_installed(e)
    for _, f in ipairs(Fonts.list()) do
        if f.name == e.name and not f.bundled then return true end
    end
    return false
end

-- A font's preview image (its name set in the font), once fetched; or nil.
function app.fget_preview(e)
    local p = (app.fget.previews or {})[e.preview]
    return p or nil
end

function app.fget_fetch_preview(e)
    local g = app.fget
    g.previews = g.previews or {}
    if g.previews[e.preview] ~= nil then return end
    g.previews[e.preview] = false
    shop.net_job({ kind = "fetch", url = app.FONTPACK .. e.preview }, function(msg)
        if msg.kind == "done" then
            local ok, img = pcall(function()
                return love.graphics.newImage(love.filesystem.newFileData(msg.body, e.preview))
            end)
            if ok then g.previews[e.preview] = img end
        end
        redraw()
    end)
end

function app.fget_download(e)
    local g = app.fget
    if g.busy then return end
    if not shop.online(true) then app.toast("Not connected to Wi-Fi"); return end
    local dir = Fonts.user_dir()
    if not dir then app.toast("There's no fonts folder"); return end
    local zip = dir .. "/." .. e.zip
    local b = { e = e, got = 0, total = e.size or 0 }
    g.busy = b
    b.id = shop.net_job({ kind = "download", url = app.FONTPACK .. e.zip, dest = zip, size = e.size }, function(msg)
        if msg.kind == "progress" then b.got, b.total = msg.got, msg.total; redraw(); return end
        g.busy = nil
        if msg.kind ~= "done" then
            os.remove(zip)
            app.toast(msg.message == "cancelled" and "Download cancelled" or ("Couldn't download " .. e.name
                .. "\n" .. app.update_error(msg.message)), 3)
            redraw()
            return
        end
        local ok, err = pcall(app.fget_unpack, zip, dir)
        os.remove(zip)
        if not ok then
            print("[fonts] " .. tostring(err))
            app.toast("Couldn't install " .. e.name .. "\nIs the SD card full?", 3)
        else
            Fonts.scan()
            app.toast(e.name .. " is ready", 2)
        end
        redraw()
    end)
    redraw()
end

-- The zip's font files and licence, straight into the fonts folder.
function app.fget_unpack(zip, dir)
    local z = assert(require("zip").open(zip))
    for name in pairs(z.entries) do
        if not name:find("/") and (name:match("%.[ot]tf$") or name:match("%.txt$")) then
            local data = assert(z:read(name))
            local f = assert(io.open(dir .. "/" .. name, "wb"))
            local wrote = f:write(data)
            wrote = f:close() and wrote        -- a full card shows up at close
            assert(wrote, "write failed")
        end
    end
    z:close()
end

function app.fget_delete(e)
    local dir = Fonts.user_dir()
    if not dir then return end
    local stem = e.zip:gsub("%.zip$", "")
    for _, st in ipairs(e.styles or {}) do os.remove(dir .. "/" .. stem .. "-" .. st .. ".ttf") end
    os.remove(dir .. "/" .. stem .. "-OFL.txt")
    Fonts.scan()
    if S.font == e.name then               -- the font in use: back to the default
        S.font = Fonts.DEFAULT
        build_fonts()
        if book then goto_pos(pos.ch, pos.off) end
        Store.save_settings(S)
    end
    app.toast(e.name .. " deleted")
end

-- Read in it now: back to the font page with it chosen.
function app.fget_use(e)
    S.font = e.name
    build_fonts()
    if book then goto_pos(pos.ch, pos.off) end
    Store.save_settings(S)
    app.font_open()
end

function app.fget_action(a)
    local g = app.fget
    local list = g.list or {}
    local e = list[g.sel]
    if a == "up" then g.sel = math.max(1, g.sel - 1)
    elseif a == "down" then g.sel = math.min(math.max(1, #list), g.sel + 1)
    elseif (a == "left" or a == "right" or a == "prev" or a == "next") and g.all then
        local idx = 1
        for i, f in ipairs(app.FONT_FILTERS) do if f[1] == (g.filter or "all") then idx = i end end
        idx = math.max(1, math.min(#app.FONT_FILTERS, idx + ((a == "left" or a == "prev") and -1 or 1)))
        app.fget_filter(app.FONT_FILTERS[idx][1])
    elseif a == "confirm" then
        if not g.list then
            if not g.loading then app.fget_load() end
        elseif e and app.fget_installed(e) then
            app.fget_use(e)
            return
        elseif e then
            app.fget_download(e)
        end
    elseif a == "toc" and e and app.fget_installed(e) and not g.busy then
        app.ask({ question = "Delete " .. e.name .. "?", detail = "From the fonts folder on the SD card",
            yes = "Delete", on_yes = function() app.fget_delete(e) end })
    elseif a == "back" or a == "menu" then
        if g.busy then
            love.thread.getChannel("net_cancel"):push(g.busy.id)
        else
            app.font_open()
            return
        end
    end
    redraw()
end

function app.fget_tap(side, u, v)
    local g = app.fget
    if side ~= "right" then return end
    if not g.list then
        if g.error then app.fget_action("confirm") end
        return
    end
    if v < 140 then                                 -- the All / Serif / Sans switch
        for _, t in ipairs(g.tabs or {}) do
            if u >= t.x0 - 12 and u <= t.x1 + 12 then app.fget_filter(t.filter); redraw() end
        end
        return
    end
    local idx = g.top + math.floor((v - 160) / app.FGET_ROW_H)
    if v >= 160 and idx < g.top + list_rows(app.FGET_ROW_H) and g.list[idx] then
        if idx == g.sel then app.fget_action("confirm") else g.sel = idx; redraw() end
    end
end

function app.fget_draw(side)
    local th = theme()
    local g = app.fget
    local m = MARGINS[2]
    local w = PAGE_W - m.outer - m.inner
    local list = g.list or {}
    local e = list[g.sel]
    if side == "left" then
        local x = m.outer
        love.graphics.setFont(ui.title)
        color(th.fg)
        love.graphics.print("Get More Fonts", x, 60)
        if not e then
            love.graphics.setFont(ui.font)
            color(th.dim)
            love.graphics.printf(g.loading and "Getting the list of fonts…" or (g.error or ""), x, 180, w, "left")
            return
        end
        local y = 190
        local img = app.fget_preview(e)
        color(th.fg)
        if img then
            local sc = math.min(w / img:getWidth(), 100 / img:getHeight())
            love.graphics.draw(img, x, y, 0, sc, sc)
            y = y + img:getHeight() * sc + 36
        else
            love.graphics.setFont(ui.title)
            love.graphics.print(e.name, x, y)
            y = y + ui.title:getHeight() + 36
        end
        love.graphics.setFont(ui.font)
        love.graphics.printf(e.about or "", x, y, w, "left")
        local _, lines = ui.font:getWrap(e.about or "", w)
        y = y + #lines * ui.font:getHeight() + 24
        love.graphics.setFont(ui.small)
        color(th.dim)
        local styles = #(e.styles or {}) >= 4 and "regular, italic, bold and bold italic"
            or (#(e.styles or {}) == 3 and "regular, italic and bold" or "")
        love.graphics.printf((e.kind == "sans" and "Sans-serif" or "Serif") .. ", " .. styles .. ". "
            .. shop.format_size(e.size or 0) .. ".\n" .. (e.license or ""), x, y, w, "left")
        local status
        if g.busy and g.busy.e == e then
            status = "Downloading…  " .. math.floor(g.busy.got / math.max(1, g.busy.total) * 100) .. "%"
        elseif app.fget_installed(e) then status = "✓  On your SD card" end
        if status then
            love.graphics.setFont(ui.font)
            color(th.fg)
            love.graphics.printf(status, x, PAGE_H - 200, w, "left")
        end
        love.graphics.setFont(ui.small)
        color(th.dim)
        love.graphics.printf("Fonts go in " .. Store.books_folder() .. "/Fonts.", x, PAGE_H - 70, w, "left")
        return
    end
    local x = m.inner
    love.graphics.setFont(ui.title)
    color(th.fg)
    love.graphics.print("Fonts", x, 60)
    if g.all then
        -- All / Serif / Sans, right-aligned on the title line; the current one bold.
        g.tabs = {}
        local tx = x + w
        local ty = 60 + ui.title:getBaseline() - ui.font:getBaseline()
        for k = #app.FONT_FILTERS, 1, -1 do
            local t = app.FONT_FILTERS[k]
            local on = (g.filter or "all") == t[1]
            local f = on and ui.bold or ui.font
            local tw = f:getWidth(t[2])
            tx = tx - tw
            love.graphics.setFont(f)
            color(on and th.fg or th.dim)
            love.graphics.print(t[2], tx, ty)
            g.tabs[#g.tabs + 1] = { x0 = tx, x1 = tx + tw, filter = t[1] }
            if k > 1 then
                love.graphics.setFont(ui.font)
                color(th.dim)
                tx = tx - ui.font:getWidth("  ·  ")
                love.graphics.print("  ·  ", tx, ty)
            end
        end
    end
    if not g.list then
        love.graphics.setFont(ui.font)
        color(th.dim)
        love.graphics.printf(g.loading and "Loading…" or (g.error or ""), x, 180, w, "left")
        app.hints(x, nil, g.error and { "A", "try again", "B", "back" } or { "B", "back" })
        return
    end
    local rows = list_rows(app.FGET_ROW_H)
    if g.sel < g.top then g.top = g.sel end
    if g.sel >= g.top + rows then g.top = g.sel - rows + 1 end
    draw_list(side, list, g.sel, g.top, rows, x, 160, w, app.FGET_ROW_H, function(it, _, rx, ry, rw)
        local h = app.FGET_ROW_H - 4
        local img = app.fget_preview(it)
        color(th.fg)
        if img then
            local sc = math.min((rw - 110) / img:getWidth(), 46 / img:getHeight())
            love.graphics.draw(img, rx, math.floor(ry + (h - img:getHeight() * sc) / 2), 0, sc, sc)
        else
            love.graphics.setFont(ui.font)
            love.graphics.print(it.name, rx, centered_y(ui.font, UI_SIZE, ry, h))
        end
        love.graphics.setFont(ui.small)
        color(th.dim)
        local right = app.fget_installed(it) and "✓" or shop.format_size(it.size or 0)
        love.graphics.printf(right, rx, centered_y(ui.small, SMALL_SIZE, ry, h), rw, "right")
    end)
    love.graphics.setFont(ui.small)
    color(th.dim)
    local cur = list[g.sel]
    if g.busy then
        app.hints(x, nil, { "B", "cancel" })
    elseif cur and app.fget_installed(cur) then
        app.hints(x, nil, { "A", "read in it", "Y", "delete", "‹ ›", "filter", "B", "back" })
    else
        app.hints(x, nil, { "A", "download", "‹ ›", "filter", "B", "back" })
    end
    app.count(x, w, g.sel, #list)
end

---------------------------------------------------------------- find in book

-- Search the open book for a word or phrase (not case-sensitive). Runs a
-- little at a time between frames (app.task) so the screen stays live; the
-- results fill in as it goes. Chapters loaded only for the search are
-- unloaded again. { query, book, results, sel, top, done, pct, capped }
app.FIND_MAX = 300
function app.find_open()
    if app.task_kind == "update" then app.toast("Installing an update…"); return end
    local f = app.find
    if f and f.book == book and (f.done or f.next) then
        app.mode = "find"                       -- last results, B to search again
        if not f.done then app.find_start(f.query, f) end   -- left part way: go on from there
    else
        app.find_keyboard(f and f.book == book and f.query or "")
    end
    redraw()
end

function app.find_keyboard(text)
    app.mode = "reader"
    app.kb_open({ title = "Find in Book", text = text,
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

-- resume: a search left part way (f.next is the file it had got to).
function app.find_start(query, resume)
    local f = resume or { query = query, book = book, results = {}, sel = 1, top = 1, pct = 0 }
    app.find = f
    app.mode = "find"
    local needle = query:lower()
    app.task_kind = "find"
    app.task = coroutine.create(function()
        local t0 = love.timer.getTime()
        local n = #book.chapters
        for i = f.next or 1, n do
            local c = book.chapters[i]
            local loaded = c.blocks ~= nil
            book:chapter(i)
            for _, t in ipairs(book.toc) do
                if t.chapter == i then toc_pos(t) end
            end
            for _, b in ipairs(c.blocks or {}) do
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
            f.pct, f.next = i / n, i + 1
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
        if app.task_kind == "find" and app.find and not app.find.done then app.find.done, app.find.error = true, true end
    end
    if coroutine.status(app.task) == "dead" then app.task, app.task_kind = nil, nil end
    -- Progress shows ten times a second; each step needn't redraw both screens.
    local now = love.timer.getTime()
    if not app.task or now - (app.task_drawn or 0) > 0.1 then app.task_drawn = now; redraw() end
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
    -- The results are on the touchscreen (swipe to scroll, tap to see one,
    -- again to go there); the selected one is shown in full on the other page.
    if f.sel < f.top then f.top = f.sel end
    if f.sel >= f.top + rows then f.top = f.sel - rows + 1 end
    local status = (not f.done and ("Searching… " .. math.floor(f.pct * 100) .. "%"))
        or (f.error and "The search stopped on an error.")
        or (#f.results == 0 and "Not found in this book.")
        or (f.capped and ("The first " .. #f.results .. " matches"))
        or (#f.results == 1 and "1 match" or (#f.results .. " matches"))
    if side == "left" then app.find_draw_left(f, x, w, status) return end
    love.graphics.setFont(ui.font)
    color(th.dim)
    love.graphics.printf(status, x, 60 + ui.title:getBaseline() - ui.font:getBaseline(), w, "right")
    draw_list(side, f.results, f.sel, f.top, rows, x, 160, w, row_h, function(r, _, rx, ry, rw)
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
    app.hints(x, nil, #f.results > 0 and { "A", "go there", "B", "search again", "X", "close" }
        or { "B", "search again", "X", "close" })
    app.count(x, w, f.sel, #f.results)
end

-- The left page of Find in Book: what was searched for, then the selected
-- match in its whole paragraph (around it, if long), the match marked.
function app.find_draw_left(f, x, w, status)
    local th = theme()
    love.graphics.setFont(ui.title)
    color(th.fg)
    love.graphics.print(fit_text(ui.title, "“" .. f.query .. "”", w), x, 60)
    local r = f.results[f.sel]
    if not r then
        if f.done and #f.results == 0 then
            love.graphics.setFont(ui.font)
            color(th.dim)
            love.graphics.printf(status .. " Try fewer words, or another spelling.", x, 170, w, "left")
        end
        return
    end
    local y = 170
    love.graphics.setFont(ui.small)
    color(th.dim)
    local pct = math.floor(book:fraction(r.ch, r.off) * 100 + 0.5) .. "%"
    love.graphics.printf(pct, x, y, w, "right")
    love.graphics.setFont(ui.small_bold)
    color(th.fg)
    love.graphics.print(fit_text(ui.small_bold, app.find_label(r), w - ui.small:getWidth(pct) - 20), x, y)
    y = y + ui.small:getHeight() + 18
    -- The paragraph, cut to a window around the match at spaces.
    local text = r.text
    -- (at spaces, or at least between characters)
    local a = math.max(1, r.s0 - 450)
    if a > 1 then
        local sp = text:find(" ", a, true)
        if sp and sp < r.s0 then a = sp + 1 else while a < r.s0 and text:byte(a) >= 0x80 and text:byte(a) < 0xC0 do a = a + 1 end end
    end
    local b = math.min(#text, r.s1 + 700)
    if b < #text then
        local sp = text:sub(1, b):match(".*() ")
        if sp and sp > r.s1 then b = sp - 1 else while b > r.s1 and (text:byte(b + 1) or 0) >= 0x80 and (text:byte(b + 1) or 0) < 0xC0 do b = b - 1 end end
    end
    local lead = a > 1 and "… " or ""
    local function squash(t) return (t:gsub("%s+", " ")) end
    local pre, mid = squash(text:sub(a, r.s0 - 1)), squash(text:sub(r.s0, r.s1))
    local disp = lead .. pre .. mid .. squash(text:sub(r.s1 + 1, b)) .. (b < #text and " …" or "")
    local ms = #lead + #pre + 1
    local me = ms + #mid - 1
    local F = ui.font
    local _, lines = F:getWrap(disp, w)
    -- Where each line is in disp, and which one has the match.
    local spans, cur, hit = {}, 1, 1
    for k, line in ipairs(lines) do
        local s0 = disp:find(line, cur, true) or cur
        spans[k] = s0
        cur = s0 + #line
        if s0 <= ms then hit = k end
    end
    local lh = F:getHeight()
    local max = math.max(1, math.floor((PAGE_H - 110 - y) / lh))
    local first = math.max(1, math.min(hit - 2, #lines - max + 1))
    love.graphics.setFont(F)
    for k = first, math.min(#lines, first + max - 1) do
        local line, ls = lines[k], spans[k]
        local le = ls + #line - 1
        if me < ls or ms > le then
            color(th.fg, 0.75)
            love.graphics.print(line, x, y)
        else
            -- before, the match, after
            local i0, i1 = math.max(ms, ls) - ls + 1, math.min(me, le) - ls + 1
            local pre, mid, post = line:sub(1, i0 - 1), line:sub(i0, i1), line:sub(i1 + 1)
            local px, mw = F:getWidth(pre), F:getWidth(mid)
            color(th.sel)
            love.graphics.rectangle("fill", x + px - 3, y + 2, mw + 6, lh - 4, 4, 4)
            color(th.fg, 0.75)
            love.graphics.print(pre, x, y)
            love.graphics.print(post, x + px + mw, y)
            color(th.fg)
            love.graphics.print(mid, x + px, y)
        end
        y = y + lh
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
        app.find_stop()
        app.jump_to(r.ch, r.off)
        app.mode = "reader"
        -- Mark the words on the spread it lands on.
        app.find_mark = { query = f.query, at = spread and (spread.ch .. ":" .. spread.pi) }
    elseif a == "back" then
        app.find_stop()
        app.find_keyboard(f.query)
    elseif a == "menu" or a == "toc" then
        app.find_stop()
        app.mode = "reader"
    end
    redraw()
end

-- Pause a running search (Find in Book goes on from there next time).
function app.find_stop()
    if app.task_kind == "find" then app.task, app.task_kind = nil, nil end
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
            -- (Curly quotes first: they aren't %p, and "“word,”" must become "word".)
            local t = w.text:lower():gsub("\226\128[\152-\157]", ""):gsub("^[%p]+", ""):gsub("[%p]+$", "")
            if want[t] and (n == 1 or #t > 2) then mk.words[#mk.words + 1] = w end
        end
    end
    for _, w in ipairs(mk.words) do
        if w.side == side then note.highlight(w) end
    end
end

-- Seconds since the device started, for timing the start in the log.
function app.uptime()
    local f = io.open("/proc/uptime", "rb")
    local t = f and f:read("*l"):match("^%S+")
    if f then f:close() end
    return t or "?"
end

-- While starting up: the name on the top screen.
function app.splash_draw(side)
    if side ~= "left" then return end
    local th = theme()
    love.graphics.setFont(ui.big)
    color(th.fg)
    local y = PAGE_H / 2 - ui.big:getHeight()
    love.graphics.printf("eReaderDS", 0, y, PAGE_W, "center")
    love.graphics.setFont(ui.font)
    color(th.dim)
    love.graphics.printf("Opening…", 0, y + ui.big:getHeight() + 20, PAGE_W, "center")
end

local function draw_message(side)
    local th = theme()
    if side == "left" then
        local m = MARGINS[2]
        love.graphics.setFont(ui.font)
        color(th.fg)
        love.graphics.printf(message or "", m.outer, 200, PAGE_W - m.outer - m.inner, "left")
        app.hints(m.outer, nil, { "A", "continue" })
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
            if look.hl_start then
                -- Choosing a highlight: both pages, the words so far marked.
                reader(side)
                if side == wd.side then note.highlight(wd) end
                if side == "right" then app.hl_hint() end
            elseif side == wd.side then reader(side); note.highlight(wd) else look.draw_panel(side) end
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
    elseif app.mode == "themes" then
        local reader = draw_reader_pages()
        painter = function(side)
            if side == "right" then app.theme_draw(side) elseif book then reader(side) end
        end
    elseif app.mode == "update" then painter = app.update_draw
    elseif app.mode == "whatsnew" then painter = app.whatsnew_draw
    elseif app.mode == "find" then painter = app.find_draw
    elseif app.mode == "message" then painter = draw_message
    elseif app.mode == "splash" then painter = app.splash_draw
    elseif app.mode == "report" then painter = app.report_draw
    elseif app.mode == "fontget" then painter = app.fget_draw
    elseif app.mode == "receive" then painter = app.recv_draw
    else painter = draw_library end

    for i, side in ipairs({ "left", "right" }) do
        app.preview_theme = app.night_preview(side)
        local bg = theme().bg
        love.graphics.setCanvas(canvases[i])
        love.graphics.clear(bg[1], bg[2], bg[3], 1)
        love.graphics.origin()
        painter(side)
        if side == app.touch_side() and app.choosing then app.choose_draw() end
        if side == app.touch_side() and app.asking then app.ask_draw() end
        if (app.mode == "menu" and menu.page ~= "status" or app.mode == "jump") and side == "left" then
            love.graphics.setColor(th.bg[1], th.bg[2], th.bg[3], 0.55)
            love.graphics.rectangle("fill", 0, 0, PAGE_W, PAGE_H)
        end
    end
    app.preview_theme = nil
    love.graphics.setCanvas()
end

-- Transform so drawing happens in page coordinates (0..PAGE_W, 0..PAGE_H)
-- on the screen that shows the given side of the spread.
-- Held the other way round (Settings → Reading & Device → Hold it: turned
-- clockwise, buttons under the left hand): everything turns 180°. Pages
-- keep their reading order, so while reading the first page is on the
-- touchscreen; menus and lists keep their touch side on the touchscreen.
-- The face buttons work as a second D-pad (held this way: Y top, A bottom,
-- X right, B left): reading, X and A go forward, B and Y back; elsewhere Y is
-- up, A down, X OK and B back, and Select does Y's usual job (delete,
-- options, space). Hints show the buttons to press.
function app.flipped() return S.orient == "right" end
app.READING_MODES = { reader = true, lookup = true, note = true }
-- The page on the touchscreen: the right one, or turned round while
-- reading, the first (left) one.
function app.touch_side()
    if app.flipped() and app.READING_MODES[app.mode] then return "left" end
    return "right"
end
-- A hint's button, turned round: A's job is on X, Y's on Select, X's
-- (Settings, close) on Start; B stays B.
app.FLIP_KEYS = { A = "X", B = "B", Y = "Select", X = "Start" }
function app.key(k) return app.flipped() and app.FLIP_KEYS[k] or k end
function app.keys_text(s)
    if not app.flipped() then return s end
    s = s:gsub("%f[%w]([ABXY])%f[%W]", app.FLIP_KEYS)
    return (s:gsub("Start, Start", "Start"))
end

-- What a face button (or Select) does, turned round; nil: as usual.
function app.flip_button(button)
    if app.mode == "reader" and not app.asking and not app.choosing then
        if button == "a" or button == "x" then return "next" end
        if button == "b" or button == "y" then return "prev" end
        return nil
    end
    local pad = { y = "up", a = "down", x = "confirm", b = "back" }
    if pad[button] then return pad[button] end
    -- Select (SDL's "back") takes Y's job, except in the word cursor (highlight).
    if button == "back" and app.mode ~= "lookup" then return "toc" end
end

local function page_transform(side)
    if not app.flipped() then
        -- Device turned counter-clockwise: top screen on the left.
        love.graphics.translate(side == "left" and SCREEN_W or SCREEN_W * 2, 0)
        love.graphics.rotate(math.pi / 2)
    else
        -- Turned the other way round: the touch side's page on the bottom screen.
        love.graphics.translate(side == app.touch_side() and SCREEN_W or 0, SCREEN_H)
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

-- The E-ink theme's filter: a fixed white-noise texture (the same grain every
-- run, like a real panel's) and the shader. Made the first time it's needed,
-- so other themes don't wait for it at startup.
function app.eink_setup()
    app.eink_tried = true
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
end

local function set_theme_shader(on)
    if on and theme().eink and not app.eink_tried then app.eink_setup() end
    if on and theme().eink and eink_shader then
        love.graphics.setShader(eink_shader)
    else
        love.graphics.setShader()
    end
end

-- Draw the two page canvases onto the physical screens.
local function compose()
    local th = theme()
    love.graphics.clear(th.bg[1], th.bg[2], th.bg[3], 1)
    -- Get Books: the selected book's page (the left one) skips the E-ink
    -- filter, so covers stay in color whatever the theme.
    app.preview_theme = app.night_preview("left")         -- (the Themes page's preview)
    set_theme_shader(true)
    if app.mode == "shop" then set_theme_shader(false) end
    blit_page(canvases[1], "left")
    app.preview_theme = app.night_preview("right")        -- its E-ink filter, if any
    set_theme_shader(true)
    blit_page(canvases[2], "right")
    set_theme_shader(false)
    app.preview_theme = nil
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
    if app.dirty then render_canvases() end     -- what is on screen right now (already there unless changed)
    local ch, pi = spread.ch, spread.pi
    canvases, old_canvases = old_canvases, canvases
    fn()
    if spread.ch == ch and spread.pi == pi then     -- start/end of book: nothing to animate
        canvases, old_canvases = old_canvases, canvases
        redraw()                                    -- (a turn cut short needs its last frame)
        return
    end
    render_canvases()
    app.anim = { dir = dir, style = S.anim, start = love.timer.getTime(), dur = ANIM_TIME[S.anim] or 0.3 }
    redraw()
end

---------------------------------------------------------------- touch brightness

-- Brightness popup shown while sliding a finger on the touchscreen.
local overlay = nil        -- { pct or pinch or text, hide_at } (on the touchscreen's page)
function app.untoast() overlay = nil; redraw() end
local gesture = nil        -- current touch: { side, u0, v0, mode, p0 }

-- Bottom-screen native coordinates (0..1024 x 0..768) -> page side + page coords.
local function touch_to_page(sx, sy)
    if not app.flipped() then return "right", sy, SCREEN_W - sx end
    return app.touch_side(), SCREEN_H - sy, sx
end

local function current_brightness()
    if S.brightness >= 0 then return S.brightness end
    return Backlight.get() or 50
end

local function touch_event(kind, sx, sy)
    local now = love.timer.getTime()
    -- A touch that wakes the screens does nothing else, until the finger lifts.
    if (kind == "down" or kind == "pinch_start") and app.idle_input() then app.idle_swallow = true end
    if app.idle_swallow then
        if kind == "up" or kind == "pinch_end" then app.idle_swallow = nil end
        return
    end
    if kind == "move" or kind == "pinch" then app.idle.last = now end
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
            overlay = { pinch = size, pct = math.floor(size / gesture.size0 * 100 + 0.5),
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
        elseif not gesture.mode and math.abs(dv) > 24 and math.abs(dv) > math.abs(du) * 1.5
                and gesture.side == "right" and app.scroll_list() then
            -- On a list, a vertical slide scrolls it (brightness everywhere else).
            local l, _, _, row_h = app.scroll_list()
            gesture.mode = "scroll"
            gesture.v0, gesture.top0, gesture.row_h = v, l.top or 1, row_h
            app.asking, app.choosing = nil, nil
        elseif not gesture.mode and math.abs(dv) > 24 and math.abs(dv) > math.abs(du) * 1.5 then
            -- Mostly vertical slide: brightness. Work in sqrt space so the
            -- dim end gets finer control.
            gesture.mode = "brightness"
            gesture.v0 = v
            gesture.p0 = S.extra_dim > 0 and (0.1 - S.extra_dim * 0.05) or math.sqrt(current_brightness() / 100)
        end
        if gesture.mode == "scroll" then app.list_scroll(gesture.top0 + math.floor((gesture.v0 - v) / gesture.row_h + 0.5)) end
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
            overlay = { pct = Backlight.available() and pct or nil, extra = extra, hide_at = now + 1e9 }
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
            elseif app.mode == "whatsnew" and math.abs(du) > 60 then
                app.whatsnew_action(du < 0 and "next" or "prev")
            elseif app.mode == "menu" and math.abs(du) > 60 then
                app.menu_page(du < 0 and 1 or -1)           -- the next / previous settings page
            end
        elseif gesture.held then
            -- Already handled while the finger was down.
        elseif gesture.moved < 30 and now - gesture.t0 < 0.5 and app.on_tap then
            app.on_tap(gesture.side, gesture.u0, gesture.v0)
        end
        gesture = nil
    end
end

-- The list on screen that a slide scrolls: its state (with sel and top), the
-- number of entries, how many show at once (both pages for two-page lists) and
-- the row height; nil when this screen has no list to scroll.
function app.scroll_list()
    local m, l, n, shown, row_h = app.mode, nil, 0, 0, 96
    if m == "library" then l, n, shown = library, #library.items, select(2, app.library_layout(library.top))
    elseif m == "shop" then
        l = shop.page()
        n, shown = l and #l.entries or 0, list_rows(96)
    elseif m == "toc" and book then l, n, row_h = toc, #book.toc, 58; shown = app.toc_rows()
    elseif m == "bookmarks" and book then l, n, shown = bm, #bookmark_entries(), list_rows(96)
    elseif m == "find" and app.find then l, n, shown = app.find, #app.find.results, list_rows(96)
    elseif m == "themes" then l, n, shown, row_h = app.themes, #THEMES, list_rows(app.THEME_ROW_H), app.THEME_ROW_H
    elseif m == "fonts" and app.font_pick then
        l, n, shown, row_h = app.font_pick, #app.font_pick.list, app.font_rows(), app.FONT_ROW_H
    elseif m == "fontget" and app.fget.list then
        l, n, shown, row_h = app.fget, #app.fget.list, list_rows(app.FGET_ROW_H), app.FGET_ROW_H
    end
    if l then return l, n, shown, row_h end            -- (one that fits just doesn't move)
end

-- Scroll that list so `top` is the first row shown, keeping the selection on
-- screen (it moves along at the edge, as the D-pad would move it).
function app.list_scroll(top)
    local l, n, shown = app.scroll_list()
    if not l then return end
    top = math.max(1, math.min(math.max(1, n - shown + 1), top))
    if top == l.top then return end
    l.top = top
    l.sel = math.max(top, math.min(top + shown - 1, l.sel))
    if app.mode == "shop" then shop.move(0) end            -- near the end: load more
    redraw()
end

-- A short message popup (e.g. "Bookmark added").
-- on_tap: what tapping the toast does (it's on the touchscreen), if anything.
function app.toast(text, secs, on_tap)
    overlay = { text = text, hide_at = love.timer.getTime() + (secs or 1.2), on_tap = on_tap }
    if os.getenv("READER_DEBUG") then print(string.format("[debug] message %q at %.2f", text, love.timer.getTime())) end
    redraw()
end

local function draw_overlay()
    if not overlay then return end
    love.graphics.push()
    page_transform(app.touch_side())          -- (where the touchscreen's page is now: the mode may have changed)
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
        -- A card in the theme's colours: one line in a 460-wide box, longer
        -- messages wider and taller, the first line bold when there are two.
        local th = theme()
        local first, rest = overlay.text:match("^([^\n]*)\n(.*)$")
        local tw, lines = ui.font:getWrap(rest or overlay.text, 640 - 56)
        if first then tw = math.max(tw, ui.bold:getWidth(first)) end
        local w = math.max(460, tw + 56)
        local lh = ui.font:getHeight()
        local h = math.max(80, (#lines + (first and 1 or 0)) * lh + 40)
        local x, y = (PAGE_W - w) / 2, 120
        overlay.box = { x, y, w, h }                    -- for tapping it
        love.graphics.setColor(0, 0, 0, 0.18)           -- soft shadow
        love.graphics.rectangle("fill", x + 4, y + 7, w, h, 24, 24)
        color(th.sel)
        love.graphics.rectangle("fill", x, y, w, h, 22, 22)
        color(th.dim, 0.45)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", x, y, w, h, 22, 22)
        color(th.fg)
        if first then
            love.graphics.setFont(ui.bold)
            love.graphics.printf(first, x + 28, y + 20, w - 56, "center")
            love.graphics.setFont(ui.font)
            love.graphics.printf(rest, x + 28, y + 20 + lh, w - 56, "center")
        else
            love.graphics.setFont(ui.font)
            local ty = #lines == 1 and centered_y(ui.font, UI_SIZE, y, h) or y + 20
            love.graphics.printf(overlay.text, x + 28, ty, w - 56, "center")
        end
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
    -- Dimmed or off from being left alone: the level from before that.
    lid.pct = app.idle.state and app.idle.pct or (S.brightness >= 0 and S.brightness) or Backlight.get() or 50
    app.idle.state = nil                    -- so a press with the lid shut can't turn the screens on
    -- A touch cut off by the lid never gets its "up".
    gesture, app.idle_swallow = nil, nil
    if overlay and overlay.hide_at > love.timer.getTime() + 60 then overlay = nil end
    Backlight.power(false)
    app.sync_push(true)
    lid.since = love.timer.getTime()
    if S.lid == "sleep" then
        if not suspend() then S.lid_failed = true end
        lid.since = love.timer.getTime()
    end
end

local function lid_opened()
    if not lid.closed then return end
    lid.closed = false
    app.idle.last, app.idle.state = love.timer.getTime(), nil
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

-- Left alone (no button or touch for S.idle_min minutes), the screens dim
-- for their last half-minute, then turn off; the next button or touch turns
-- them back on (and does nothing else). Not while a book is being received or
-- downloaded, or with the lid shut.
app.IDLE_CHOICES = { 0, 2, 5, 10, 15, 30 }
app.IDLE_DIM = 30
app.idle = { last = 0 }

-- Any input: returns true if it only woke the screens (so it's not acted on).
function app.idle_input()
    local I = app.idle
    I.last = love.timer.getTime()
    if not I.state then return false end
    local was = I.state
    I.state = nil
    if was == "off" then Backlight.power(true, I.pct) else Backlight.set(I.pct) end
    print("[idle] awake")
    redraw()
    return was == "off"
end

function app.idle_tick()
    local I = app.idle
    local now = love.timer.getTime()
    if I.last == 0 or lid.closed or (S.idle_min or 0) <= 0 or app.recv or shop.dl
        or not Backlight.available() then
        I.last = I.state and I.last or now
        return
    end
    local t, limit = now - I.last, S.idle_min * 60
    if not I.state and t > limit - app.IDLE_DIM then
        I.pct = S.brightness >= 0 and S.brightness or Backlight.get() or 50
        I.state = "dim"
        Backlight.set(math.max(1, math.floor(I.pct / 3)))
        print("[idle] dimmed")
    elseif I.state == "dim" and t > limit then
        I.state = "off"
        reading_pause()
        save_progress()
        Store.flush()
        Backlight.power(false)
        print("[idle] screens off")
        app.sync_push()
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
    if app.idle_input() then return end        -- that press only woke the screens
    handle_action(a)
    -- Time outside the pages (menus, lists) doesn't count as reading.
    if app.mode ~= "reader" then reading_pause() end
end
function app.on_back() action("menu") end   -- see app.on_raw_key

function handle_action(a)
    if lid.closed then return end         -- pocket presses while the lid is shut
    local mode = app.mode
    -- Select bookmarks while reading; elsewhere it behaves like the menu button.
    if a == "bookmark" and mode ~= "reader" and mode ~= "library" and mode ~= "lookup" then a = "menu" end
    -- Pressing the stick in opens Settings while reading, and selects elsewhere.
    if a == "stick" then a = mode == "reader" and "menu" or "confirm" end
    if a == "quit" then love.event.quit() return end
    if app.asking and app.ask_action(a) then return end
    if app.choosing and app.choose_action(a) then return end

    if mode == "message" then
        if a == "confirm" or a == "back" then
            -- Back to My Books or Get Books if that's where it came from.
            local back = app.message_back
            app.mode = (back == "library" or back == "shop") and back or (book and "reader" or "library")
            app.message_back = nil
            redraw()
        end
        return
    end

    if mode == "reader" then
        if a == "next" or a == "right" or a == "down" then turn(1, next_spread)
        elseif a == "up" and app.flipped() then look.open()   -- turned round: D-pad up does Y's job
        elseif a == "prev" or a == "left" or a == "up" then turn(-1, prev_spread)
        elseif a == "bookmark" then toggle_bookmark()
        elseif a == "next_section" then jump_section(1)
        elseif a == "prev_section" then jump_section(-1)
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
                -- Rows with nothing to change: left/right turn the page.
                app.menu_page(back and -1 or 1)
            end
        elseif a == "confirm" then
            local it = items[menu.sel]
            if it.act then it.act() elseif it.adjust then it.adjust(1) end
        elseif a == "back" and menu.page ~= "main" then
            close_sub()
        elseif a == "back" or a == "menu" then app.mode = "reader"; menu.page = "main" end
        Store.save_settings(S)
        redraw()
        return
    end

    if mode == "keyboard" then app.kb_action(a) return end
    if mode == "fonts" then app.font_action(a) return end
    if mode == "themes" then app.theme_action(a) return end
    if mode == "update" then app.update_action(a) return end
    if mode == "whatsnew" then app.whatsnew_action(a) return end
    if mode == "find" then app.find_action(a) return end
    if mode == "report" then app.report_action(a) return end
    if mode == "fontget" then app.fget_action(a) return end
    if mode == "receive" then app.recv_action(a) return end

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
        elseif a == "down" then bm.sel = math.max(1, math.min(n, bm.sel + 1))
        elseif a == "left" or a == "prev" or a == "right" or a == "next" then
            app.bm_filter((a == "left" or a == "prev") and -1 or 1)
            return
        elseif a == "confirm" then
            local e = entries[bm.sel]
            if not e then
            elseif e.action then
                toggle_bookmark()
            else
                app.jump_to(e.ch, e.off); app.mode = "reader"
            end
        elseif a == "toc" and entries[bm.sel] and not entries[bm.sel].action then   -- Y: delete, once confirmed
            local e = entries[bm.sel]
            app.ask({ question = e.hl and "Delete this highlight?" or "Delete this bookmark?",
                detail = e.hl and ("“" .. e.item.text .. "”") or (e.item.title ~= "" and e.item.title or book.title),
                yes = "Delete", on_yes = function() app.bm_delete(e, n) end })
        elseif a == "back" or a == "menu" then
            app.mode = bm.from == "menu" and "menu" or "reader"
        end
        redraw()
        return
    end

    if mode == "toc" then
        local n = #book.toc
        local rows = app.toc_rows()
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
        elseif a == "bookmark" then app.hl_select()              -- Select: highlight
        elseif look.hl_start and (a == "back" or a == "toc") then look.hl_start = nil   -- cancel it
        elseif a == "confirm" then look.page = look.page + 1
            if look.pages and look.page > #look.pages then look.page = 1 end
        elseif a == "back" or a == "menu" or a == "toc" then
            look.hl_start = nil
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
        if n > 0 then
            if a == "up" then library.sel = math.max(1, library.sel - 1)
            elseif a == "down" then library.sel = math.min(n, library.sel + 1)
            elseif a == "left" or a == "right" then library.cycle_sort(a == "right" and 1 or -1)
            elseif a == "confirm" then
                open_book(library.items[library.sel].path)
            elseif a == "toc" then
                app.library_options(library.items[library.sel])
            end
        elseif a == "toc" and (library.hidden or 0) > 0 then
            app.library_options(nil)                    -- all hidden: "Show finished books"
        end
        if a == "bookmark" then shop.start() end
        if a == "menu" and not book and app.upd.state == "available" then app.update_open() end
        if a == "menu" and book then app.mode = "menu"; menu.sel = 1; menu.page = "main"; menu.top = nil end
        if a == "back" and book then app.mode = "reader" end
        redraw()
    end
end

-- Pressing and holding on the touchscreen: look up the word under the finger.
function app.on_hold(side, u, v)
    if app.mode ~= "reader" and app.mode ~= "lookup" or app.asking or app.choosing then return end
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
    -- A toast that does something when tapped (e.g. "Update available"):
    -- a tap on it does that; a tap anywhere else just dismisses it.
    local o = overlay
    if o and o.on_tap then
        overlay = nil
        if o.box and side == app.touch_side() and u >= o.box[1] - 10 and u <= o.box[1] + o.box[3] + 10
                and v >= o.box[2] - 10 and v <= o.box[2] + o.box[4] + 10 then
            o.on_tap()
        end
        redraw()
        return
    end
    if app.asking then app.ask_tap(side, u, v) return end
    if app.choosing then app.choose_tap(side, u, v) return end
    local mode = app.mode
    if mode == "reader" then
        -- (The touchscreen's page: the right one, or turned round the left;
        -- its outer corner is top right, or top left.)
        local touch = side == app.touch_side()
        local outer = side == "left" and (PAGE_W - u) or u    -- distance from the spine
        local ref = touch and note.hit(note.on_spread(), side, u, v)
        local bx, by, bw, bh = note.button()
        if ref then
            note.open(ref)                    -- a note number: show the note on the other page
        elseif touch and #note.on_spread() > 0 and u >= bx - 16 and u <= bx + bw + 16
            and v >= by - 16 and v <= by + bh + 16 then
            note.open()                       -- the Notes button
        elseif touch and outer > PAGE_W - 170 and v < 150 then
            toggle_bookmark()                 -- the outer top corner, like a Kindle
        elseif touch and v < 90 and outer > PAGE_W - 230 then
            -- A gap between the bookmark corner and the status bar strip, so a
            -- slightly-off bookmark tap does nothing rather than the wrong thing.
        elseif touch and v < 90 then
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
        local rows, page, pages = menu_layout(items)
        for _, row in ipairs(rows) do
            if row.kind == "item" and v >= row.y and v < row.y + row.h then idx = row.idx end
        end
        -- "Swipe for more options" under page 1's last row: a tap turns the page too.
        local last = rows[#rows]
        if side == "right" and not idx and menu.page == "main" and page < pages and last
                and v >= last.y + last.h and v < last.y + last.h * 2 + 20 then
            app.menu_page(1)
            return
        end
        if side == "right" and u >= m.inner - 14 and u <= PAGE_W - m.outer + 14 and idx then
            local it = items[idx]
            menu.sel = idx
            if it.adjust then
                -- Where ‹ and › are drawn: "‹  value  ›", right-aligned.
                local F, w = ui.menu, PAGE_W - m.outer - m.inner
                local right = m.inner + w
                local plus = right - F:getWidth("  ›")
                local minus = right - F:getWidth(app.menu_value_text(it, w))
                if u >= plus - 30 then it.adjust(1)
                elseif u >= minus - 30 and u <= minus + 50 then it.adjust(-1) end
                Store.save_settings(S)
                redraw()
            else
                action("confirm")
            end
        elseif side == "left" then
            action("back")            -- tapped the dimmed book page: close
        end
    elseif mode == "library" then
        if side ~= "right" then return end
        local bx, by, bw, bh = library.get_books_button()
        if u >= bx - 20 and u <= bx + bw + 20 and v >= by - 20 and v <= by + bh + 8 then
            shop.start()
            return
        end
        -- The order at the top right (Recent, Title...): the next one.
        if v < 140 and u > bx + bw + 20 and #library.items > 0 then library.cycle_sort(1); redraw(); return end
        -- The list: tap a book to see it on the top screen, again to open it.
        for _, r in ipairs((app.library_layout(library.top))) do
            if r.idx and v >= r.y and v < r.y + 96 then
                if r.idx == library.sel then action("confirm") else library.sel = r.idx; redraw() end
            end
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
        -- The list is on the touchscreen: tap a row to see it on the other
        -- screen, tap it again to open, download or read it.
        local pg = shop.page()
        if not pg or side ~= "right" then return end
        if #pg.entries == 0 then
            if pg.error then action("confirm") end        -- try again
            return
        end
        if v >= 160 then
            local idx = pg.top + math.floor((v - 160) / 96)
            if pg.entries[idx] and idx < pg.top + list_rows(96) then
                if idx == pg.sel then action("confirm") else pg.sel = idx; redraw() end
            end
        end
    elseif mode == "about" or mode == "help" or mode == "report" then
        action("back")
    elseif mode == "keyboard" then
        app.kb_tap(side, u, v)
    elseif mode == "fonts" then
        app.font_tap(side, u, v)
    elseif mode == "themes" then
        app.theme_tap(side, u, v)
    elseif mode == "fontget" then
        app.fget_tap(side, u, v)
    elseif mode == "receive" then
        app.recv_tap(side, u, v)
    elseif mode == "update" then
        app.update_tap(side, u, v)
    elseif mode == "whatsnew" then
        app.whatsnew_action("next")                 -- a tap turns to the next spread
    elseif mode == "find" then
        -- Tap a result to see it on the other screen, again to go there.
        local f, rows = app.find, list_rows(96)
        local idx = f.top + math.floor((v - 160) / 96)
        if side == "right" and v >= 160 and idx < f.top + rows and f.results[idx] then
            if idx == f.sel then action("confirm") else f.sel = idx; redraw() end
        end
    elseif mode == "bookmarks" then
        -- The All / Highlights / Bookmarks label at the top: the next one.
        if side == "right" and v < 140 and u > PAGE_W / 2 then app.bm_filter(1) return end
        -- The list: tap one to see it on the other screen, again to go there.
        local rows = list_rows(96)
        local idx = (bm.top or 1) + math.floor((v - 160) / 96)
        if side == "right" and v >= 160 and idx < (bm.top or 1) + rows and idx <= #bookmark_entries() then
            if idx == bm.sel then action("confirm") else bm.sel = idx; redraw() end
        end
    elseif mode == "toc" then
        -- Tap an entry to see it on the other screen, again to go there.
        -- Anywhere else does nothing (closing on a tap looked like a choice).
        local rows = app.toc_rows()
        local idx = (toc.top or 1) + math.floor((v - 160) / 58)
        if side == "right" and v >= 160 and idx < (toc.top or 1) + rows and book and book.toc[idx] then
            if idx == toc.sel then action("confirm") else toc.sel = idx; redraw() end
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
    if app.flipped() then
        local fa = app.flip_button(button)
        if fa then action(fa) return end
    end
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

---------------------------------------------------------------- crashes

-- When something goes wrong: a plain screen instead of LÖVE's error text,
-- the place in the book saved, and a report (version, system, error; no book
-- titles) in crash.txt. The next start offers to report it: a QR code opens
-- a GitHub bug report with the details filled in, on the reader's phone.
app.REPORT_URL = "https://github.com/casualducko/eReaderDS/issues/new"

-- The error and where it happened, without paths or book file names.
function app.crash_clean(text)
    text = tostring(text or "")
    text = text:gsub("[%w%./_%-]*/app/", "")             -- /…/eReaderDS/app/main.lua -> main.lua
    -- Book and file paths (someone's library) go; the message around them stays.
    text = ("\n" .. text):gsub("([%s\"'(=:])/[^\n\"']-%.[eE][pP][uU][bB]", "%1<book>")
        :gsub("([%s\"'(=:])/[^\n\"']-%.[tT][xX][tT]", "%1<file>"):sub(2)
    return text
end

function app.system_name()
    local f = io.open("/etc/os-release", "rb")
    local s = f and f:read("*a") or ""
    if f then f:close() end
    return s:find('ROCKNIX') and "ROCKNIX" or (s ~= "" and "stock firmware" or "computer")
end

function app.crash_save(msg, trace)
    local lines = {}
    for l in app.crash_clean(trace):gmatch("[^\n]+") do
        l = l:gsub("^%s+", "")
        -- The app's own code only: not the engine's frames or the handler's.
        if l ~= "" and not l:find("^stack traceback") and not l:find("boot%.lua") and not l:find("^%[C%]")
                and not l:find("^%(tail call%)") and #lines < 6 then
            lines[#lines + 1] = l
        end
    end
    local f = io.open(Store.data_path("crash.txt"), "wb")
    if not f then return end
    f:write("version=", VERSION, "\n", "system=", app.system_name(), "\n", "time=", os.date("%Y-%m-%d %H:%M"), "\n",
        "error=", (app.crash_clean(msg):gsub("\n", " ")), "\n", "where=", table.concat(lines, " | "), "\n")
    f:close()
end

function love.errorhandler(msg)
    msg = tostring(msg)
    local trace = debug.traceback("", 2)
    print("[crash] " .. msg .. "\n" .. trace)
    pcall(app.crash_save, msg, trace)
    pcall(function() if book then save_progress() end; Store.flush() end)   -- keep the place
    -- Screens left off or dimmed (idle, the lid): on again, to show this.
    pcall(function()
        if app.idle.state == "off" or lid.closed then Backlight.power(true, app.idle.pct or lid.pct or 50)
        elseif app.idle.state == "dim" then Backlight.set(app.idle.pct) end
    end)
    pcall(love.graphics.reset)
    pcall(love.graphics.setCanvas)
    local th = (pcall(theme) and theme()) or { bg = { 0.957, 0.925, 0.847 }, fg = { 0.357, 0.275, 0.212 }, dim = { 0.6, 0.52, 0.44 } }
    local big = ui.title or love.graphics.newFont(44)
    local body = ui.font or love.graphics.newFont(30)
    local function page(side)
        local x, w = 60, PAGE_W - 120
        love.graphics.setColor(th.fg)
        if side == "left" then
            love.graphics.setFont(big)
            love.graphics.printf("eReaderDS ran into a problem", x, 300, w, "center")
            love.graphics.setFont(body)
            love.graphics.setColor(th.dim)
            love.graphics.printf("Your place in the book is saved.\n\nNext time you open eReaderDS, you can "
                .. "report it from your phone in a few taps.", x, 420, w, "center")
        else
            love.graphics.setFont(big)
            love.graphics.printf("Press any button to quit", x, 440, w, "center")
        end
    end
    local function draw()
        love.graphics.origin()
        love.graphics.clear(th.bg[1], th.bg[2], th.bg[3], 1)
        for _, side in ipairs({ "left", "right" }) do
            love.graphics.push()
            love.graphics.scale(app.scale or 1)
            if not pcall(page_transform, side) then love.graphics.translate(side == "left" and 0 or SCREEN_W, 0) end
            pcall(page, side)
            love.graphics.pop()
        end
    end
    -- Testing: save the screen instead of waiting.
    local shot = os.getenv("READER_SHOT")
    if shot then
        pcall(function()
            local c = love.graphics.newCanvas(2048, 768)
            love.graphics.setCanvas(c)
            local s0 = app.scale
            app.scale = 1
            draw()
            app.scale = s0
            love.graphics.setCanvas()
            local f = io.open(shot, "wb"); f:write(c:newImageData():encode("png"):getString()); f:close()
        end)
        return function() return 1 end
    end
    local start = love.timer.getTime()
    local pressed = false
    return function()
        -- Left alone (maybe with the lid closed): quit rather than keep the
        -- screens on.
        if love.timer.getTime() - start > 300 then return 1 end
        love.event.pump()
        local ready = love.timer.getTime() - start > 1     -- ignore buttons still held from before
        for e in love.event.poll() do
            if e == "quit" then return 1 end
            if ready and (e == "keypressed" or e == "gamepadpressed" or e == "joystickpressed"
                    or e == "touchpressed" or e == "mousepressed") then return 1 end
        end
        pcall(function()
            if Touch.enabled then Touch.poll(function(kind) if kind == "down" then pressed = true end end) end
        end)
        if pressed and ready then return 1 end
        pressed = false
        if love.graphics.isActive() then draw(); love.graphics.present() end
        love.timer.sleep(0.05)
    end
end

-- The last crash report ({ version, system, error, where, ... }), or nil.
function app.crash_read(name)
    local f = io.open(Store.data_path(name), "rb")
    if not f then return nil end
    local r = {}
    for line in f:lines() do
        local k, v = line:match("^(%w+)=(.*)$")
        if k then r[k] = v end
    end
    f:close()
    return r.error and r or nil
end

-- On start: a crash last time (in this version) offers a report, once.
function app.crash_check()
    local r = app.crash_read("crash.txt")
    if not r then return end
    os.rename(Store.data_path("crash.txt"), Store.data_path("crash-last.txt"))
    if r.version == VERSION then
        app.toast("eReaderDS closed unexpectedly last time\nTap here to report it", 10, app.report_open)
    end
end

function app.url_encode(s)
    return (s:gsub("[^%w%-%._~ ]", function(c) return string.format("%%%02X", c:byte()) end):gsub(" ", "+"))
end

-- The bug report's address, filled in with the version and (if there was
-- one in this version) the crash.
function app.report_url()
    local r = app.crash_read("crash-last.txt")
    if r and r.version ~= VERSION then r = nil end
    local q = { "template=bug_report.yml", "version=" .. app.url_encode("v" .. VERSION) }
    local what = "System: " .. app.system_name() .. "\n\n"
    if r then
        -- Short, so the QR code stays coarse enough to scan off the screen.
        q[#q + 1] = "title=" .. app.url_encode(("Crash: " .. r.error):sub(1, 60))
        what = what .. "eReaderDS closed unexpectedly. What I was doing: "
        local where = {}
        for part in (r.where or ""):gmatch("[^|]+") do
            if #where < 2 then where[#where + 1] = part:gsub("^%s+", ""):gsub("%s+$", ""):gsub("in function ", "") end
        end
        q[#q + 1] = "log=" .. app.url_encode(table.concat(where, "\n"):sub(1, 120))
    end
    q[#q + 1] = "what=" .. app.url_encode(what)
    return app.REPORT_URL .. "?" .. table.concat(q, "&"), r
end

function app.report_open()
    if app.mode ~= "report" then app.report_back = app.mode end
    local url, r = app.report_url()
    local ok, tab = pcall(function() return select(2, require("qrencode").qrcode(url, 1)) end)
    app.report = { url = url, crash = r, qr = ok and type(tab) == "table" and tab or nil }
    overlay = nil                          -- the "closed unexpectedly" note, if it's up
    app.mode = "report"
    redraw()
end

function app.report_action(a)
    if a == "back" or a == "menu" or a == "confirm" then
        app.report = nil
        app.mode = app.report_back or (book and "menu" or "library")
        redraw()
    end
end

function app.report_draw(side)
    local th = theme()
    local r = app.report
    local m = MARGINS[2]
    local x = side == "left" and m.outer or m.inner
    local w = PAGE_W - m.outer - m.inner
    if side == "left" then
        love.graphics.setFont(ui.title)
        color(th.fg)
        love.graphics.print("Report a Problem", x, 60)
        love.graphics.setFont(ui.font)
        color(th.fg)
        local text = "Scan the code on the other screen with your phone's camera. It opens a bug report "
            .. "on GitHub with the version filled in"
            .. (r.crash and " and what went wrong" or "") .. ". Add what you were doing and send it "
            .. "(a free GitHub account is needed).\n\nNothing is sent from this device."
        love.graphics.printf(text, x, 170, w, "left")
        if r.crash then
            local _, lines = ui.font:getWrap(text, w)
            local y = 170 + #lines * ui.font:getHeight() + 40
            love.graphics.setFont(ui.small_bold)
            love.graphics.print("The problem (" .. (r.crash.time or "") .. ")", x, y)
            love.graphics.setFont(ui.small)
            color(th.dim)
            love.graphics.printf(r.crash.error, x, y + ui.small:getHeight() + 6, w, "left")
        end
        return
    end
    app.hints(x, nil, { "B", "back" })
    -- The QR code: dark modules on white (phones read it best), with the quiet
    -- border around it that scanners need.
    if not r.qr then
        love.graphics.setFont(ui.font)
        color(th.fg)
        love.graphics.printf("Couldn't make the code. Report at\ngithub.com/casualducko/eReaderDS/issues", x, 300, w, "center")
        return
    end
    local n = #r.qr
    local cell = math.floor(math.min(w, PAGE_H - 300) / (n + 8))
    local size = cell * (n + 8)
    local qx, qy = math.floor((PAGE_W - size) / 2), 150
    love.graphics.setColor(1, 1, 1)
    love.graphics.rectangle("fill", qx, qy, size, size, 12, 12)
    love.graphics.setColor(0, 0, 0)
    for cx = 1, n do
        for cy = 1, n do
            if r.qr[cx][cy] > 0 then
                love.graphics.rectangle("fill", qx + (cx + 3) * cell, qy + (cy + 3) * cell, cell, cell)
            end
        end
    end
    love.graphics.setFont(ui.small)
    color(th.dim)
    love.graphics.printf("github.com/casualducko/eReaderDS", x, qy + size + 24, w, "center")
end

---------------------------------------------------------------- send books over Wi-Fi

-- "Send Books over Wi-Fi" (in Get Books): while this screen is open, a small
-- web server (receiver.lua, on its own thread) takes books and fonts from a
-- phone or computer on the same network. The address and a QR code of it are
-- on the screens; what arrives is listed as it comes in.

-- This device's address on the network: the one a connection out would use
-- (no packet is sent), else the first from `ip`.
function app.recv_ip()
    local ok, ip = pcall(function()
        local u = require("socket").udp()
        u:setpeername("8.8.8.8", 53)
        local a = u:getsockname()
        u:close()
        return a
    end)
    if ok and ip and ip ~= "0.0.0.0" and not ip:match("^127%.") then return ip end
    local p = io.popen("ip -4 -o addr show 2>/dev/null")
    if p then
        for line in p:lines() do
            local a = line:match("inet (%d+%.%d+%.%d+%.%d+)")
            if a and not a:match("^127%.") then p:close(); return a end
        end
        p:close()
    end
end

function app.recv_open()
    if app.recv then app.mode = "receive"; redraw(); return end   -- already running
    if not shop.online(true) then app.toast("Not connected to Wi-Fi"); return end
    local ip = app.recv_ip()
    if not ip then app.toast("Couldn't find this device's address on the network"); return end
    love.thread.getChannel("recv_ctl"):clear()
    love.thread.getChannel("recv_out"):clear()
    local r = { ip = ip, files = {}, back = app.mode, books = 0, fonts = 0 }
    local books, fonts = Store.download_dir(), Fonts.user_dir()
    -- Uploads cut off by the app closing leave hidden .part files: tidy them.
    for _, d in ipairs({ books, fonts }) do
        if d then os.execute('rm -f "' .. d .. '"/.*.part 2>/dev/null') end
    end
    r.thread = love.thread.newThread("receiver.lua")
    r.thread:start({ books = books, fonts = fonts, version = VERSION })
    app.recv = r
    app.mode = "receive"
    redraw()
end

-- Stop the server (after the file arriving, if any, is cut off) and wait for it.
function app.recv_stop()
    local r = app.recv
    if not r then return end
    love.thread.getChannel("recv_ctl"):push("stop")
    r.thread:wait()
    love.thread.getChannel("recv_ctl"):clear()
    app.recv_poll()
    app.recv = nil
    love.thread.getChannel("recv_out"):clear()
    if r.fonts > 0 then
        Fonts.scan()
        build_fonts()                   -- a font in use may have been replaced
        if book and spread then goto_pos(pos.ch, pos.off) end
    end
    if r.reopen and book then
        -- The open book was replaced: let go of the old copy (it opens
        -- afresh, at the same place, from My Books).
        save_progress()
        book:close()
        book, spread = nil, nil
        app.find_stop(); app.find, app.find_mark = nil, nil
        clear_book_caches()
    end
    if r.books > 0 then
        Store.flush()
        scan_library()
        for i, it in ipairs(library.items) do                  -- the last one received
            if it.path == r.last then library.sel = i end
        end
    end
    return r
end

function app.recv_close()
    local r = app.recv_stop()
    app.mode = r and r.back or "library"
    if app.mode ~= "shop" then app.mode = "library" end
    if r and r.books > 0 then
        app.toast(r.books == 1 and "1 book received" or (r.books .. " books received"))
    end
    redraw()
end

-- Messages from the server thread; true if anything changed.
function app.recv_poll()
    local r = app.recv
    if not r then return false end
    local got = false
    local ch = love.thread.getChannel("recv_out")
    while true do
        local msg = ch:pop()
        if not msg then break end
        got = true
        if msg.kind == "ready" then
            r.port = msg.port
            r.url = "http://" .. r.ip .. (msg.port == 80 and "" or (":" .. msg.port))
            local ok, tab = pcall(function() return select(2, require("qrencode").qrcode(r.url, 1)) end)
            r.qr = ok and type(tab) == "table" and tab or nil
        elseif msg.kind == "error" then
            r.error = msg.message
        elseif msg.kind == "start" then
            table.insert(r.files, 1, { name = msg.name, got = 0, total = msg.total })
        else
            local f = r.files[1]
            if f and f.name == msg.name then
                if msg.kind == "progress" then
                    f.got, f.total = msg.got, msg.total
                elseif msg.kind == "done" then
                    f.done, f.replaced, f.font = true, msg.replaced, msg.font
                    if msg.font then r.fonts = r.fonts + 1 else r.books, r.last = r.books + 1, msg.path end
                    if msg.replaced and book and msg.path == book.path then r.reopen = true end
                elseif msg.kind == "failed" then
                    f.failed = msg.message
                end
            end
        end
    end
    if not r.error and not r.thread:isRunning() and r.thread:getError() then
        r.error = "Receiving stopped: " .. tostring(r.thread:getError()):gsub("^[^:]*:%d+: ", "")
        print("[receive] " .. r.error)
        got = true
    end
    if got then redraw() end
    return got
end

-- The Done button, on the touchscreen: x, y, w, h.
function app.recv_button()
    local w, h = 240, 60
    return math.floor((PAGE_W - w) / 2), PAGE_H - 96, w, h
end

function app.recv_action(a)
    if a == "back" or a == "menu" then app.recv_close() end
end

function app.recv_tap(side, u, v)
    if side ~= "right" then return end
    local bx, by, bw, bh = app.recv_button()
    if u >= bx - 20 and u <= bx + bw + 20 and v >= by - 20 and v <= by + bh + 30 then app.recv_close() end
end

function app.recv_draw(side)
    local th = theme()
    local r = app.recv
    local m = MARGINS[2]
    local x = side == "left" and m.outer or m.inner
    local w = PAGE_W - m.outer - m.inner
    if side == "left" then
        love.graphics.setFont(ui.title)
        color(th.fg)
        love.graphics.print("Send Books over Wi-Fi", x, 60)
        love.graphics.setFont(ui.font)
        if r.error then
            color(th.fg)
            love.graphics.printf(r.error, x, 170, w, "left")
            return
        end
        color(th.dim)
        love.graphics.printf("On a phone or computer on the same Wi-Fi, scan the code or open:", x, 160, w, "left")
        love.graphics.setFont(ui.title)
        color(th.fg)
        love.graphics.print(r.url and fit_text(ui.title, r.url:gsub("^http://", ""), w) or "Starting…", x, 250)
        love.graphics.setFont(ui.small)
        color(th.dim)
        love.graphics.printf("Books (.epub, .txt) go to My Books, fonts (.ttf, .otf) to Fonts. "
            .. "Stay on this screen until they're sent.", x, 250 + ui.title:getHeight() + 14, w, "left")
        -- What's arrived, newest first: the title (and author, as My Books
        -- shows them), and what happened to it.
        local y = 470
        if r.books + r.fonts > 0 then
            love.graphics.setFont(ui.small_bold)
            color(th.fg)
            local parts = {}
            if r.books > 0 then parts[#parts + 1] = r.books .. (r.books == 1 and " book" or " books") end
            if r.fonts > 0 then parts[#parts + 1] = r.fonts .. (r.fonts == 1 and " font" or " fonts") end
            love.graphics.print(table.concat(parts, " and ") .. " received", x, y - 50)
        end
        for _, f in ipairs(r.files) do
            if y > PAGE_H - 170 then break end
            local base = f.name:gsub("%.[^.]+$", "")
            local title, author = base:match("^(.-)%s+%-%s+(.+)$")
            title = title or base
            love.graphics.setFont(ui.font)
            color(f.failed and th.dim or th.fg)
            local tw = ui.font:getWidth(fit_text(ui.font, title, w))
            love.graphics.print(fit_text(ui.font, title, w), x, y)
            if author and tw < w - 60 then
                love.graphics.setFont(ui.small)
                color(th.dim)
                love.graphics.print(fit_text(ui.small, author, w - tw - 16), x + tw + 16,
                    y + ui.font:getBaseline() - ui.small:getBaseline())
            end
            local where = f.font and "Fonts" or "My Books"
            local line
            if f.failed then line = "Failed: " .. f.failed
            elseif f.done then
                line = "✓  " .. (f.replaced and "Replaced in " or "Added to ") .. where .. "  ·  " .. (shop.format_size(f.total) or "0 KB")
            else
                line = "Receiving…  " .. math.floor(f.got / math.max(1, f.total) * 100) .. "%"
            end
            love.graphics.setFont(ui.small)
            color(f.failed and th.fg or th.dim)
            love.graphics.print(fit_text(ui.small, line, w), x, y + 40)
            if not f.done and not f.failed then
                color(th.sel)
                love.graphics.rectangle("fill", x, y + 76, w, 6, 3, 3)
                color(th.fg)
                love.graphics.rectangle("fill", x, y + 76, w * math.min(1, f.got / math.max(1, f.total)), 6, 3, 3)
            end
            y = y + 96
        end
        if #r.files == 0 and r.url then
            love.graphics.setFont(ui.small)
            color(th.dim)
            love.graphics.print("Waiting for books…", x, y)
        end

        return
    end
    -- The QR code of the address, as on Report a Problem: dark on white, with
    -- the quiet border scanners need.
    if r.qr then
        local n = #r.qr
        local cell = math.floor(math.min(w, PAGE_H - 330) / (n + 8))
        local size = cell * (n + 8)
        local qx, qy = math.floor((PAGE_W - size) / 2), 110
        love.graphics.setColor(1, 1, 1)
        love.graphics.rectangle("fill", qx, qy, size, size, 12, 12)
        love.graphics.setColor(0, 0, 0)
        for cx = 1, n do
            for cy = 1, n do
                if r.qr[cx][cy] > 0 then
                    love.graphics.rectangle("fill", qx + (cx + 3) * cell, qy + (cy + 3) * cell, cell, cell)
                end
            end
        end
        love.graphics.setFont(ui.small)
        color(th.dim)
        love.graphics.printf(r.url, x, qy + size + 20, w, "center")
    end
    local bx, by, bw, bh = app.recv_button()
    app.button(bx, by, bw, bh, "Done", "B", "soft")
end

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
    print("[reader] eReaderDS v" .. VERSION .. " (uptime " .. app.uptime() .. ")")
    S = Store.load_settings()
    if S.chrome == false then
        -- "Page info: Off" from older versions: hide the status bar text.
        S.sb_title, S.sb_pages, S.sb_percent = "none", "hide", false
        S.chrome = true
    end
    local n = tonumber(S.theme)
    if n then S.theme = OLD_THEME_NUMBERS[n] or "Paper" end
    -- "Night" was renamed "Midnight" (the night theme setting made it confusing).
    if S.theme == "Night" then S.theme = "Midnight" end
    if S.night_theme == "Night" then S.night_theme = "Midnight" end
    -- "Green" (its name in test builds) is now "Mint".
    if S.theme == "Green" then S.theme = "Mint" end
    if S.night_theme == "Green" then S.night_theme = "Mint" end
    Timezone.apply(S.tz)
    app.night_check()
    Touch.open("gt9xx-0")
    KeyProbe.open(function(device, code) app.on_raw_key(device, code) end,
        { ["gt9xx-0"] = true, ["Goodix Capacitive TouchScreen"] = true },  -- stock, ROCKNIX
        { [LID_DEVICE] = true, [app.BACK_DEVICE] = true })
    if S.brightness >= 0 and Backlight.available() then Backlight.set(S.brightness) end
    canvases[1] = love.graphics.newCanvas(PAGE_W, PAGE_H)
    canvases[2] = love.graphics.newCanvas(PAGE_W, PAGE_H)
    old_canvases[1] = love.graphics.newCanvas(PAGE_W, PAGE_H)
    old_canvases[2] = love.graphics.newCanvas(PAGE_W, PAGE_H)
    ui.font = load_font("GentiumBookPlus-Regular.ttf", UI_SIZE)
    ui.small = load_font("GentiumBookPlus-Regular.ttf", SMALL_SIZE)
    ui.bold = load_font("GentiumBookPlus-Bold.ttf", UI_SIZE)
    ui.small_bold = load_font("GentiumBookPlus-Bold.ttf", SMALL_SIZE)
    ui.title = load_font("GentiumBookPlus-Bold.ttf", 44)
    ui.big = load_font("GentiumBookPlus-Bold.ttf", 110)
    ui.menu = load_font("GentiumBookPlus-Regular.ttf", app.MENU_SIZE)       -- Settings rows
    ui.help = load_font("GentiumBookPlus-Regular.ttf", 34)                  -- the Help pages
    ui.menu_bold = load_font("GentiumBookPlus-Bold.ttf", app.MENU_SIZE)
    -- Something on the screens straight away: loading the fonts and the
    -- book takes a moment.
    app.mode = "splash"
    love.draw()
    love.graphics.present()
    app.mode = "library"
    print("[reader] opening screen shown (uptime " .. app.uptime() .. ")")
    -- Horizontal gradient, opaque at x=0 fading to clear at x=1.
    shadow_mesh = love.graphics.newMesh({
        { 0, 0, 0, 0, 1, 1, 1, 1 }, { 1, 0, 1, 0, 1, 1, 1, 0 },
        { 1, 1, 1, 1, 1, 1, 1, 0 }, { 0, 1, 0, 1, 1, 1, 1, 1 },
    }, "fan", "static")
    turn_mesh = love.graphics.newMesh((TURN_COLS + 1) * 2, "strip", "stream")
    build_fonts()

    scan_library()
    local last = Store.get_last()
    local f = last and io.open(last, "rb")
    if f then f:close(); open_book(last) end
    -- Just updated? Offer what's new, once. (A new install has no seen_version.)
    if S.seen_version ~= VERSION then
        if S.seen_version ~= "" then
            app.toast("Updated to v" .. VERSION .. "\nTap here to see what's new", 8, app.whatsnew_open)
        end
        S.seen_version = VERSION
        Store.save_settings(S)
    end
    app.crash_check()                      -- closed unexpectedly last time?
    -- A newer version? (Only when online; quietly does nothing otherwise.)
    if S.update_notices and (not os.getenv("READER_SCRIPT") or os.getenv("READER_FAKE_VERSION")) then
        app.update_check()
    end
end

function love.quit()
    if app.recv then app.recv_stop() end
    app.sync_push(true)
    if net.thread then
        -- Stop whatever is running (a download's .part file is removed) and the thread.
        love.thread.getChannel("net_cancel"):clear()
        love.thread.getChannel("net_cancel"):push(true)
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
            elseif a:match("^type:") then app.kb_type((a:sub(6):gsub("_", " ")))
            elseif a == "update" then app.update_open()
            elseif a == "crash" then error("a test crash")       -- the crash screen
            elseif a == "untoast" then overlay = nil            -- clear a message (for screenshots)
            elseif a:match("^btn:") then love.gamepadpressed(nil, a:sub(5))   -- a button as pressed (a, b, x, y, back, start)
            elseif a == "report" then app.report_open()
            elseif a == "receive" then app.recv_open()
            elseif a == "recvpoll" then app.recv_poll()
            elseif a == "work" then                -- finish a background task
                while app.task do app.task_step() end
                while library.pending do app.library_meta_step() end
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
    if os.getenv("READER_DEBUG") and app.mode == "shop" and shop.page() then
        local pg = shop.page()
        print(string.format("[debug] shop page %q: %d entries%s", pg.title, #pg.entries,
            pg.error and (", error: " .. pg.error) or ""))
    end
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

-- Screens that show the status bar's clock.
app.CLOCK_MODES = { reader = true, menu = true, lookup = true, note = true, jump = true, themes = true }

-- Event-driven loop: sleep until input arrives and only redraw on change.
function love.run()
    love.load(love.arg.parseGameArguments(arg), arg)
    run_test_script()
    return function()
        if (app.dirty or app.anim) and love.graphics.isActive() and not lid.closed and app.idle.state ~= "off" then
            app.dirty = false
            love.graphics.origin()
            love.draw()
            love.graphics.present()
            if not app.first_shown then
                app.first_shown = true
                print("[reader] ready (uptime " .. app.uptime() .. ")")
            end
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
        if gesture and not lid.closed and not gesture.mode and not gesture.held and gesture.moved < 30
            and love.timer.getTime() - gesture.t0 > 0.6 then
            gesture.held = true                -- press and hold
            app.on_hold(gesture.side, gesture.u0, gesture.v0)
        end
        if shop.net_poll() then got = true end
        if app.recv and app.recv_poll() then got = true end
        if app.task and not lid.closed then app.task_step(); got = true end
        if library.pending and not lid.closed then app.library_meta_step(); got = true end
        if overlay and love.timer.getTime() >= overlay.hide_at then
            if os.getenv("READER_DEBUG") then print(string.format("[debug] message closed at %.2f", love.timer.getTime())) end
            overlay = nil; redraw()
        end
        if save_due and love.timer.getTime() >= save_due then save_progress() end
        if app.mode == "library" and not lid.closed then
            -- Wi-Fi coming or going changes the Get Books button.
            local was = shop.online_v
            if shop.online() ~= was and was ~= nil then redraw() end
        end
        app.idle_tick()
        if app.idle.state == "off" and not lid.closed and not (app.task or library.pending) then
            love.timer.sleep(0.1)               -- screens off: check for a press now and then
        end
        if lid.closed then
            lid_tick()
            love.timer.sleep(0.25)              -- screens are off: check rarely
        end
        local second = os.time()                -- (the clock is looked at once a second, not every frame)
        if second ~= app.clock_second then
            app.clock_second = second
            local minute = os.date("%H%M")
            if minute ~= app.clock_minute then
                app.clock_minute = minute
                app.night_check()              -- the night theme's hours
                if S.sb_show and S.sb_clock ~= "off" and app.CLOCK_MODES[app.mode] then redraw() end
            end
        end
        if app.anim or app.task or library.pending then
            love.timer.sleep(0.001)            -- animating or working: next frame
        elseif Touch.enabled or KeyProbe.enabled or overlay or net.count > 0 or app.recv or (S.idle_min or 0) > 0 then
            -- Touch, the lid and the timers don't wake love.event.wait(), so poll at a gentle rate.
            if not got and not app.dirty then love.timer.sleep(gesture and 0.008 or 0.025) end
        elseif not got then
            local r = handle(love.event.wait())
            if r then return r end
        end
    end
end
