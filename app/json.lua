-- A small JSON decoder (objects, arrays, strings, numbers, true/false/null),
-- enough for GitHub's release list. null becomes nil.
local M = {}

local escapes = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }

local function utf8(cp)
    if cp < 0x80 then return string.char(cp) end
    if cp < 0x800 then return string.char(0xC0 + math.floor(cp / 64), 0x80 + cp % 64) end
    if cp < 0x10000 then
        return string.char(0xE0 + math.floor(cp / 4096), 0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
    end
    return string.char(0xF0 + math.floor(cp / 262144), 0x80 + math.floor(cp / 4096) % 64,
        0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
end

function M.decode(s)
    local pos = 1
    local value

    local function skip() pos = s:find("[^ \t\r\n]", pos) or #s + 1 end
    local function fail(what) error("bad JSON (" .. what .. " at " .. pos .. ")", 0) end

    local function str()
        pos = pos + 1                                  -- opening quote
        local out = {}
        while true do
            local a, b = s:find('["\\]', pos)
            if not a then fail("unterminated string") end
            out[#out + 1] = s:sub(pos, a - 1)
            if s:sub(a, a) == '"' then pos = a + 1; break end
            local c = s:sub(a + 1, a + 1)
            if c == "u" then
                local cp = tonumber(s:sub(a + 2, a + 5), 16) or 63
                pos = a + 6
                -- A surrogate pair (characters outside the basic plane).
                if cp >= 0xD800 and cp < 0xDC00 and s:sub(pos, pos + 1) == "\\u" then
                    local lo = tonumber(s:sub(pos + 2, pos + 5), 16) or 0
                    cp = 0x10000 + (cp - 0xD800) * 1024 + (lo - 0xDC00)
                    pos = pos + 6
                end
                out[#out + 1] = utf8(cp)
            else
                out[#out + 1] = escapes[c] or c
                pos = a + 2
            end
        end
        return table.concat(out)
    end

    function value()
        skip()
        local c = s:sub(pos, pos)
        if c == "{" then
            local obj = {}
            pos = pos + 1
            skip()
            if s:sub(pos, pos) == "}" then pos = pos + 1; return obj end
            while true do
                skip()
                if s:sub(pos, pos) ~= '"' then fail("key") end
                local k = str()
                skip()
                if s:sub(pos, pos) ~= ":" then fail("colon") end
                pos = pos + 1
                obj[k] = value()
                skip()
                local d = s:sub(pos, pos)
                pos = pos + 1
                if d == "}" then return obj end
                if d ~= "," then fail("object") end
            end
        elseif c == "[" then
            local arr = {}
            pos = pos + 1
            skip()
            if s:sub(pos, pos) == "]" then pos = pos + 1; return arr end
            while true do
                arr[#arr + 1] = value()
                skip()
                local d = s:sub(pos, pos)
                pos = pos + 1
                if d == "]" then return arr end
                if d ~= "," then fail("array") end
            end
        elseif c == '"' then
            return str()
        elseif s:find("^true", pos) then pos = pos + 4; return true
        elseif s:find("^false", pos) then pos = pos + 5; return false
        elseif s:find("^null", pos) then pos = pos + 4; return nil
        else
            local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
            if not num or num == "" then fail("value") end
            pos = pos + #num
            return tonumber(num)
        end
    end

    return value()
end

return M
