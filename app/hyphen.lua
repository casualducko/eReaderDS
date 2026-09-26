-- Word hyphenation with Liang's algorithm (the one TeX uses) and the US
-- English patterns in hyph/en-us.txt. Patterns load on first use.
local M = {}

local LEFT, RIGHT = 2, 3            -- keep at least 2 letters before and 3 after a break
local pats, exceptions, maxlen
local cache, cache_n = {}, 0

local function load()
    pats, exceptions, maxlen = {}, {}, 0
    local data = love.filesystem.read("hyph/en-us.txt") or ""
    for line in data:gmatch("[^\n]+") do
        local c = line:sub(1, 1)
        if c == "=" then
            local word = line:sub(2)
            local points, n = {}, 0
            for ch in word:gmatch(".") do
                if ch == "-" then points[#points + 1] = n else n = n + 1 end
            end
            exceptions[(word:gsub("%-", ""))] = points
        elseif c ~= "#" then
            -- "a1bc3d": letters "abcd", values before each letter and at the end.
            local letters = line:gsub("%d", "")
            local vals, i = {}, 1
            for k = 1, #letters + 1 do vals[k] = 0 end
            for ch in line:gmatch(".") do
                if ch:match("%d") then vals[i] = tonumber(ch) else i = i + 1 end
            end
            pats[letters] = vals
            if #letters > maxlen then maxlen = #letters end
        end
    end
end

-- Break points for a word of ASCII letters, as prefix lengths in ascending
-- order ("hyphenation" -> {2, 6}: hy-phen-ation).
function M.points(word)
    if #word < LEFT + RIGHT then return {} end
    local lower = word:lower()
    local hit = cache[lower]
    if hit then return hit end
    if not pats then load() end
    local points = exceptions[lower]
    if not points then
        local w = "." .. lower .. "."
        local n = #w
        local v = {}
        for k = 1, n + 1 do v[k] = 0 end
        for i = 1, n do
            for j = i, math.min(n, i + maxlen - 1) do
                local p = pats[w:sub(i, j)]
                if p then
                    for k = 1, #p do
                        if p[k] > v[i + k - 1] then v[i + k - 1] = p[k] end
                    end
                end
            end
        end
        -- v[x] is the value before character x of w; w has a leading ".".
        points = {}
        for m = LEFT, #word - RIGHT do
            if v[m + 2] % 2 == 1 then points[#points + 1] = m end
        end
    end
    if cache_n > 5000 then cache, cache_n = {}, 0 end
    cache[lower] = points
    cache_n = cache_n + 1
    return points
end

local function accented(c) return c and c >= 0xC3 and c <= 0xC9 end

-- Places a word of text may be broken: { at = bytes in the first part,
-- hyphen = whether to add "-" }, ascending. Existing hyphens and dashes
-- break without adding one; runs of 5+ ASCII letters use the patterns.
function M.breaks(text)
    local out = {}
    local i, n = 1, #text
    while i <= n do
        local s, e = text:find("%a+", i)
        if not s then break end
        -- Skip runs that are part of a word with accented letters (e.g.
        -- "naïveté"): the patterns only know plain letters. Accented Latin
        -- letters start with bytes 0xC3-0xC9 in UTF-8; curly quotes don't.
        local b = s - 1
        while b > 0 and text:byte(b) >= 0x80 and text:byte(b) < 0xC0 do b = b - 1 end
        local lead_before, lead_after = b < s - 1 and text:byte(b), text:byte(e + 1)
        if e - s + 1 >= LEFT + RIGHT and not accented(lead_before) and not accented(lead_after) then
            for _, p in ipairs(M.points(text:sub(s, e))) do
                out[#out + 1] = { at = s - 1 + p, hyphen = true }
            end
        end
        i = e + 1
    end
    -- After a hyphen or dash inside the word (not at either end).
    for pos, dash in text:gmatch("()([%-\226]\128?[\147\148]?)") do
        local last = pos + #dash - 1
        if (dash == "-" or dash == "\226\128\147" or dash == "\226\128\148") and pos > 1 and last < n then
            out[#out + 1] = { at = last, hyphen = false }
        end
    end
    table.sort(out, function(a, b) return a.at < b.at end)
    return out
end

return M
