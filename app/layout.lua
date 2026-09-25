-- Paginates a chapter's blocks into fixed-size pages.
--
-- page = { off = first char offset, items = { ... } }
-- item = { kind = "text", x, y, text, font }
--      | { kind = "image", x, y, w, h, src }
--      | { kind = "rule", x, y, w }
local utf8 = require("utf8")

local M = {}

local function sanitize(s)
    if utf8.len(s) then return s end
    -- Treat invalid bytes as Latin-1.
    return (s:gsub("[\128-\255]", function(c)
        local b = c:byte()
        return string.char(0xC0 + math.floor(b / 64), 0x80 + b % 64)
    end))
end

-- ctx: { fonts = {r,i,b,bi,h}, w, h, spacing, justify, indent, image_size = fn(src) -> w,h }
function M.paginate(chapter, ctx)
    local F = ctx.fonts
    local W, H = ctx.w, ctx.h
    local pages = {}
    local page = { items = {} }
    local y = 0
    local base_lh = math.floor(F.r:getHeight() * ctx.spacing + 0.5)

    local function new_page()
        if #page.items > 0 or page.off then pages[#pages + 1] = page end
        page = { items = {} }
        y = 0
    end
    local function mark(off)
        if not page.off then page.off = off end
    end

    local prev_kind = "start"   -- used for first-line indent decisions

    -- Start a new page at each section start (e.g. chapters listed in the TOC).
    local breaks, bi = ctx.breaks or {}, 1

    for _, blk in ipairs(chapter.blocks) do
        while breaks[bi] and breaks[bi] <= blk.off do
            if breaks[bi] > 0 and y > 0 then new_page(); prev_kind = "start" end
            bi = bi + 1
        end
        if blk.kind == "blank" then
            if y > 0 then y = y + base_lh end
            if y >= H then new_page() end
            prev_kind = "blank"

        elseif blk.kind == "rule" then
            if y + base_lh > H then new_page() end
            mark(blk.off)
            page.items[#page.items + 1] = { kind = "rule", x = W * 0.35, y = y + base_lh / 2, w = W * 0.3 }
            y = y + base_lh
            prev_kind = "rule"

        elseif blk.kind == "image" then
            local iw, ih = ctx.image_size(blk.src)
            if iw and iw > 0 then
                local s = math.min(W / iw, H / ih, ctx.max_image_scale or 3)
                local dw, dh = math.floor(iw * s), math.floor(ih * s)
                -- Small inline images (icons, ornaments) stay small.
                if iw < 64 and ih < 64 then
                    s = math.min(W / iw, H / ih, 1.5); dw, dh = math.floor(iw * s), math.floor(ih * s)
                end
                if y + dh > H then new_page() end
                mark(blk.off)
                page.items[#page.items + 1] = { kind = "image", src = blk.src,
                    x = math.floor((W - dw) / 2), y = y, w = dw, h = dh }
                y = y + dh + math.floor(base_lh / 3)
                prev_kind = "image"
            end

        elseif blk.kind == "text" then
            local heading = blk.heading or 0
            local big = heading == 2
            local function font_for(i, b)
                if big then return F.h end
                if heading == 1 then b = true end
                if i and b then return F.bi elseif i then return F.i elseif b then return F.b end
                return F.r
            end
            local lh = big and math.floor(F.h:getHeight() * ctx.spacing + 0.5) or base_lh
            local space_w = (big and F.h or F.r):getWidth(" ")

            -- Break runs into words made of styled fragments.
            local words, cur = {}, nil
            local function end_word()
                if cur then words[#words + 1] = cur; cur = nil end
            end
            for _, run in ipairs(blk.runs) do
                if run.br then
                    end_word()
                    words[#words + 1] = { br = true, off = run.off }
                else
                    local t, font = run.text, font_for(run.i, run.b)
                    local i, n = 1, #t
                    while i <= n do
                        local a, b = t:find(" +", i)
                        if a == i then
                            end_word(); i = b + 1
                        else
                            local e = a and a - 1 or n
                            local frag = sanitize(t:sub(i, e))
                            local fw = font:getWidth(frag)
                            if not cur then cur = { frags = {}, w = 0, off = run.off + i - 1 } end
                            cur.frags[#cur.frags + 1] = { text = frag, font = font, w = fw }
                            cur.w = cur.w + fw
                            i = e + 1
                        end
                    end
                end
            end
            end_word()

            if #words > 0 then
                local center = blk.center or big
                local indent = 0
                if ctx.indent and not center and heading == 0 and prev_kind == "text" then
                    indent = math.floor(F.r:getWidth("M") * 1.5)
                end
                local prefix
                if blk.list then prefix = { text = "•", font = F.r, w = F.r:getWidth("• ") } end

                -- Headings: spacing and keep-with-next.
                if heading > 0 then
                    if y > 0 then y = y + math.floor(base_lh * 0.8) end
                    if y + lh * 3 > H then new_page() end
                elseif ctx.para_gap and y > 0 and prev_kind == "text" then
                    y = y + math.floor(base_lh * 0.4)
                end

                local line, lw, first = {}, 0, true
                local function emit(last_line)
                    if #line == 0 then return end
                    if y + lh > H then new_page() end
                    mark(line[1].off)
                    local avail = W - (first and indent or 0) - (prefix and prefix.w or 0)
                    local x0 = (first and indent or 0) + (prefix and prefix.w or 0)
                    local gap = space_w
                    if center then
                        x0 = math.floor((W - lw) / 2)
                    elseif ctx.justify and not last_line and #line > 1 then
                        gap = space_w + (avail - lw) / (#line - 1)
                    end
                    if first and prefix then
                        page.items[#page.items + 1] = { kind = "text", x = x0 - prefix.w, y = y,
                            text = prefix.text, font = prefix.font }
                    end
                    local x = x0
                    for k, wd in ipairs(line) do
                        for _, fr in ipairs(wd.frags) do
                            page.items[#page.items + 1] = { kind = "text", x = math.floor(x + 0.5), y = y,
                                text = fr.text, font = fr.font }
                            x = x + fr.w
                        end
                        if k < #line then x = x + gap end
                    end
                    y = y + lh
                    line, lw, first = {}, 0, false
                end

                for _, wd in ipairs(words) do
                    if wd.br then
                        emit(true)
                    else
                        local avail = W - (first and indent or 0) - (prefix and prefix.w or 0)
                        local need = (#line > 0) and (lw + space_w + wd.w) or wd.w
                        if #line > 0 and need > avail then
                            emit(false)
                            need = wd.w
                        end
                        line[#line + 1] = wd
                        lw = need
                    end
                end
                emit(true)

                if heading > 0 then y = y + math.floor(base_lh * 0.5) end
                prev_kind = heading > 0 and "heading" or "text"
            end
        end
    end
    if #page.items > 0 or #pages == 0 then
        page.off = page.off or 0
        pages[#pages + 1] = page
    end
    -- Make sure every page has an offset and offsets never decrease.
    local last = 0
    for _, p in ipairs(pages) do
        p.off = math.max(p.off or last, last)
        last = p.off
    end
    return pages
end

-- Index of the page containing char offset `off`.
function M.find_page(pages, off)
    local lo, hi = 1, #pages
    while lo < hi do
        local mid = math.floor((lo + hi + 1) / 2)
        if pages[mid].off <= off then lo = mid else hi = mid - 1 end
    end
    return lo
end

return M
