-- Paginates a chapter's blocks into fixed-size pages.
--
-- page = { off = first char offset, items = { ... } }
-- item = { kind = "text", x, y, text, font, off (the word's text offset) }
--      | { kind = "image", x, y, w, h, src }
--      | { kind = "rule", x, y, w }
local utf8 = require("utf8")
local Hyphen = require("hyphen")

local M = {}

-- Invisible characters the fonts don't have (drawn as boxes): word joiners
-- (Standard Ebooks puts one, U+FEFF or U+2060, before each dash) and the
-- zero-width space. Only left out when drawing, so places in the text stay
-- the same.
local function sanitize(s)
    if s:find("[\226\239]") then s = s:gsub("\226\129\160", ""):gsub("\226\128\139", ""):gsub("\239\187\191", "") end
    -- UTF-16 halves written as UTF-8 (ED A0..BF ..) pass utf8.len but can't be drawn.
    if s:find("\237[\160-\191]") then s = s:gsub("\237[\160-\191][\128-\191]", "\239\191\189") end
    if utf8.len(s) then return s end
    -- Treat invalid bytes as Latin-1.
    return (s:gsub("[\128-\255]", function(c)
        local b = c:byte()
        return string.char(0xC0 + math.floor(b / 64), 0x80 + b % 64)
    end))
end

-- ctx: { fonts = {r,i,b,bi,h}, w, h, spacing, justify, indent, hyphenate,
--        image_size = fn(src) -> w,h }
function M.paginate(chapter, ctx)
    local F = ctx.fonts
    local W, H = ctx.w, ctx.h
    local pages = {}
    local page = { items = {} }
    local y = 0
    -- Line height follows the text size, so switching fonts keeps the same
    -- density even when fonts report very different line gaps.
    local size = ctx.size or F.r:getHeight()
    local base_lh = math.floor(math.max(F.r:getHeight(), size * 1.4) * ctx.spacing + 0.5)

    local function new_page()
        if #page.items > 0 or page.off then pages[#pages + 1] = page end
        page = { items = {} }
        y = 0
    end
    local function mark(off)
        if not page.off then page.off = off end
    end

    local prev_kind = "start"   -- used for first-line indent decisions

    -- A picture on its own, centred, as big as fits (small ones, icons and
    -- ornaments, stay small). false if its size can't be read.
    local function place_image(src, off)
        local iw, ih = ctx.image_size(src)
        if not (iw and iw > 0) then return false end
        local s = math.min(W / iw, H / ih, ctx.max_image_scale or 3)
        local dw, dh = math.floor(iw * s), math.floor(ih * s)
        if iw < 64 and ih < 64 then
            s = math.min(W / iw, H / ih, 1.5); dw, dh = math.floor(iw * s), math.floor(ih * s)
        end
        if y + dh > H then new_page() end
        mark(off)
        page.items[#page.items + 1] = { kind = "image", src = src,
            x = math.floor((W - dw) / 2), y = y, w = dw, h = dh }
        y = y + dh + math.floor(base_lh / 3)
        return true
    end

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
            if place_image(blk.src, blk.off) then prev_kind = "image" end

        elseif blk.kind == "text" then
            local heading = blk.heading or 0
            local big = heading == 2
            local function font_for(i, b)
                if big then return F.h end
                if heading == 1 then b = true end
                if i and b then return F.bi elseif i then return F.i elseif b then return F.b end
                return F.r
            end
            local lh = big and math.floor(math.max(F.h:getHeight(), size * 1.45 * 1.4) * ctx.spacing + 0.5) or base_lh
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
                elseif run.img then
                    -- A picture in the line. Letter-sized ones (made for text
                    -- of about 16 px) grow with the text and join the word
                    -- they're in; a bigger one gets a block of its own.
                    local iw, ih = ctx.image_size(run.img)
                    if iw and iw > 0 and ih > 0 and iw <= 64 and ih <= 48 then
                        local s = size / 16
                        local dh = math.min(ih * s, lh * 0.9)
                        local dw = math.floor(iw * dh / ih + 0.5)
                        dh = math.floor(dh + 0.5)
                        if not cur then cur = { frags = {}, w = 0, off = run.off } end
                        cur.frags[#cur.frags + 1] = { img = run.img, w = dw, h = dh, font = font_for(run.i, run.b) }
                        cur.w = cur.w + dw
                    elseif iw and iw > 0 then
                        end_word()
                        words[#words + 1] = { block_img = run.img, off = run.off }
                    end
                else
                    local t, font = run.text, font_for(run.i, run.b)
                    -- Superscripts (mostly note numbers): smaller and raised.
                    local rise = 0
                    if run.sup and F.sup and not big then font, rise = F.sup, math.floor(size * 0.38) end
                    local i, n = 1, #t
                    while i <= n do
                        local a, b = t:find(" +", i)
                        if a == i then
                            end_word(); i = b + 1
                        else
                            local e = a and a - 1 or n
                            local frag = sanitize(t:sub(i, e))
                            -- Non-breaking hyphens (U+2011, in words like "y‑your"): an
                            -- ordinary hyphen where the font has none (else a box), and
                            -- the word is never split there (split() below).
                            local nobreak = frag:find("\226\128\145", 1, true) ~= nil
                            if nobreak and not font:hasGlyphs("\226\128\145") then
                                frag = frag:gsub("\226\128\145", "-")
                            end
                            local fw = font:getWidth(frag)
                            if not cur then cur = { frags = {}, w = 0, off = run.off + i - 1 } end
                            cur.frags[#cur.frags + 1] = { text = frag, font = font, w = fw, link = run.link, rise = rise,
                                nobreak = nobreak }
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
                        page.items[#page.items + 1] = { kind = "text", x = x0 - prefix.w,
                            y = y + math.floor((lh - F.r:getHeight()) / 2),
                            text = prefix.text, font = prefix.font }
                    end
                    local x = x0
                    local ty = y + math.floor((lh - (big and F.h or F.r):getHeight()) / 2)
                    for k, wd in ipairs(line) do
                        for _, fr in ipairs(wd.frags) do
                          if fr.img then
                            -- Sitting on the baseline, like a letter.
                            local base = ty + (big and F.h or F.r):getBaseline()
                            page.items[#page.items + 1] = { kind = "image", src = fr.img, x = math.floor(x + 0.5),
                                y = math.floor(base - fr.h), w = fr.w, h = fr.h }
                            x = x + fr.w
                          else
                            -- Line up baselines (a smaller font has a shorter ascent), then raise.
                            local by = ty
                            if fr.font ~= (big and F.h or F.r) then
                                by = ty + (big and F.h or F.r):getBaseline() - fr.font:getBaseline() - (fr.rise or 0)
                            end
                            -- off: where the word starts in the chapter's text (highlights).
                            page.items[#page.items + 1] = { kind = "text", x = math.floor(x + 0.5), y = math.floor(by),
                                text = fr.text, font = fr.font, link = fr.link, off = wd.off }
                            x = x + fr.w
                          end
                        end
                        if k < #line then x = x + gap end
                    end
                    y = y + lh
                    line, lw, first = {}, 0, false
                end

                -- Split a word so its first part (plus a hyphen) fits in
                -- `room`; returns the two parts, or nil.
                local function split(wd, room)
                    if #wd.frags ~= 1 or wd.frags[1].img then return nil end    -- mixed styles: keep whole
                    if wd.frags[1].nobreak then return nil end                  -- non-breaking hyphens: keep whole
                    local fr = wd.frags[1]
                    local best
                    for _, b in ipairs(Hyphen.breaks(fr.text)) do
                        local head = fr.text:sub(1, b.at) .. (b.hyphen and "-" or "")
                        local hw = fr.font:getWidth(head)
                        if hw > room then break end
                        best = { text = head, w = hw, at = b.at }
                    end
                    if not best then return nil end
                    local rest = fr.text:sub(best.at + 1)
                    local rw = fr.font:getWidth(rest)
                    return { frags = { { text = best.text, font = fr.font, w = best.w, link = fr.link, rise = fr.rise } }, w = best.w, off = wd.off },
                        { frags = { { text = rest, font = fr.font, w = rw, link = fr.link, rise = fr.rise } }, w = rw, off = wd.off + best.at }
                end

                -- A word wider than a whole line (a web address, text with no
                -- spaces such as Chinese or Japanese): break it between
                -- characters, as much as fits in `room` (at least one).
                local function hard_split(wd, room)
                    if #wd.frags ~= 1 or wd.frags[1].img then return nil end
                    local fr = wd.frags[1]
                    local cuts = {}                  -- byte offsets where a character ends
                    for p in fr.text:gmatch("()[\1-\127\192-\255][\128-\191]*") do
                        if p > 1 then cuts[#cuts + 1] = p - 1 end
                    end
                    if #cuts == 0 then return nil end
                    local lo, hi = 1, #cuts
                    while lo < hi do
                        local mid = math.ceil((lo + hi) / 2)
                        if fr.font:getWidth(fr.text:sub(1, cuts[mid])) <= room then lo = mid else hi = mid - 1 end
                    end
                    local at = cuts[lo]
                    local head, rest = fr.text:sub(1, at), fr.text:sub(at + 1)
                    local hw, rw = fr.font:getWidth(head), fr.font:getWidth(rest)
                    return { frags = { { text = head, font = fr.font, w = hw, link = fr.link, rise = fr.rise } }, w = hw, off = wd.off },
                        { frags = { { text = rest, font = fr.font, w = rw, link = fr.link, rise = fr.rise } }, w = rw, off = wd.off + at }
                end

                local hyphen_run = 0      -- consecutive lines ending in a hyphen
                local after_br = false    -- the line so far ended with a <br>
                for _, wd in ipairs(words) do
                    if wd.block_img then
                        emit(true)
                        if place_image(wd.block_img, wd.off) then first = false end
                        after_br = false
                    elseif wd.br then
                        if #line == 0 and after_br and y > 0 then
                            -- <br><br>: an empty line (a gap between verses)
                            if y + lh > H then new_page() else y = y + lh end
                        else
                            emit(true)
                        end
                        after_br = true
                    else
                        after_br = false
                        while wd do
                            local avail = W - (first and indent or 0) - (prefix and prefix.w or 0)
                            local need = (#line > 0) and (lw + space_w + wd.w) or wd.w
                            if need <= avail then
                                line[#line + 1] = wd
                                lw = need
                                wd = nil
                            else
                                -- Hyphenate when the line would otherwise be
                                -- noticeably loose, or the word is wider than a line.
                                local head, tail
                                local slack = avail - lw
                                if ctx.hyphenate and not center and hyphen_run < 2
                                    and (#line == 0 or slack > space_w * 0.4 * math.max(1, #line - 1)
                                        or (not ctx.justify and slack > space_w * 3)) then
                                    head, tail = split(wd, avail - (#line > 0 and lw + space_w or 0))
                                end
                                if head then
                                    line[#line + 1] = head
                                    lw = lw + (#line > 1 and space_w or 0) + head.w
                                    hyphen_run = hyphen_run + 1
                                    emit(false)
                                    wd = tail
                                elseif #line == 0 then
                                    head, tail = hard_split(wd, avail)
                                    if head then
                                        line[1], lw = head, head.w
                                        emit(false)
                                        wd = tail
                                    else
                                        line[1] = wd          -- mixed styles: let it overflow
                                        lw = wd.w
                                        wd = nil
                                    end
                                else
                                    hyphen_run = 0
                                    emit(false)
                                end
                            end
                        end
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
