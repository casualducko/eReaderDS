-- Comparing your themes on this device with the copy on your sync server.
-- Pure (no screen, no network): main.lua draws the result and applies it.
local M = {}

-- "L:a:b" as numbers; two colours match when every part is within a hair.
local function parts(s)
    local t = {}
    for n in tostring(s):gmatch("[^:]+") do t[#t + 1] = tonumber(n) end
    return t
end
local function same_colour(a, b)
    local p, q = parts(a), parts(b)
    if #p ~= 3 or #q ~= 3 then return a == b end
    for i = 1, 3 do
        if not p[i] or not q[i] or math.abs(p[i] - q[i]) > 0.0005 then return false end
    end
    return true
end

-- Whole entries from the server only: { name, fg, bg } as short strings.
function M.clean(list)
    local out, seen = {}, {}
    if type(list) ~= "table" then return out end
    for _, e in ipairs(list) do
        if type(e) == "table" and type(e.name) == "string" and type(e.fg) == "string" and type(e.bg) == "string"
                and #e.name > 0 and #e.name <= 60 and not e.name:find("[%c]")
                and e.fg:match("^[%d,/:%-]+$") and e.bg:match("^[%d,/:%-]+$")
                and #e.fg <= 60 and #e.bg <= 60 and not seen[e.name:lower()] then
            seen[e.name:lower()] = true
            out[#out + 1] = { name = e.name, fg = e.fg, bg = e.bg }
        end
    end
    return out
end

-- Both lists are { name, fg, bg }. Returns rows in a steady order (by name):
--   { name, kind = "remote" | "local" | "differs", mine = entry, theirs = entry }
-- and the count of themes that already match.
function M.diff(mine, theirs)
    local by_mine, by_theirs = {}, {}
    for _, e in ipairs(mine) do by_mine[e.name:lower()] = e end
    for _, e in ipairs(theirs) do by_theirs[e.name:lower()] = e end
    local rows, same = {}, 0
    for key, a in pairs(by_mine) do
        local b = by_theirs[key]
        if not b then
            rows[#rows + 1] = { name = a.name, kind = "local", mine = a }
        elseif same_colour(a.fg, b.fg) and same_colour(a.bg, b.bg) then
            same = same + 1
        else
            rows[#rows + 1] = { name = a.name, kind = "differs", mine = a, theirs = b }
        end
    end
    for key, b in pairs(by_theirs) do
        if not by_mine[key] then rows[#rows + 1] = { name = b.name, kind = "remote", theirs = b } end
    end
    table.sort(rows, function(x, y)
        if x.name:lower() ~= y.name:lower() then return x.name:lower() < y.name:lower() end
        return x.name < y.name
    end)
    return rows, same
end

-- What each kind of row can be set to, the first being the default.
M.CHOICES = {
    remote  = { "add", "server_delete", "skip" },
    ["local"] = { "upload", "delete", "skip" },
    differs = { "mine", "theirs", "skip" },
}
M.LABELS = {
    add = "Add here", server_delete = "Delete from server", upload = "Upload",
    delete = "Delete here", mine = "Keep mine", theirs = "Use server's", skip = "Skip",
}

-- Each row gets its choice (row.choice); differing themes start on Skip.
function M.defaults(rows)
    for _, r in ipairs(rows) do r.choice = r.kind == "differs" and "skip" or M.CHOICES[r.kind][1] end
    return rows
end

function M.cycle(row, dir)
    local c = M.CHOICES[row.kind]
    for i, v in ipairs(c) do
        if v == row.choice then row.choice = c[(i - 1 + (dir or 1)) % #c + 1] return row.choice end
    end
    row.choice = c[1]
    return row.choice
end

-- Turns the choices into the work to do:
--   here   = the themes this device ends up with (all of them, in order),
--   server = the list to send, or nil if the server stays as it is,
--   counts = { add, upload, delete, server_delete, mine, theirs }
function M.plan(mine, theirs, rows)
    local pick = {}
    for _, r in ipairs(rows) do pick[r.name:lower()] = r end
    local here, server, counts = {}, {}, { add = 0, upload = 0, delete = 0, server_delete = 0, mine = 0, theirs = 0 }
    local server_changed = false
    for _, e in ipairs(mine) do
        local r = pick[e.name:lower()]
        local c = r and r.choice
        if c == "delete" then
            counts.delete = counts.delete + 1
        else
            if c == "theirs" then
                here[#here + 1] = { name = e.name, fg = r.theirs.fg, bg = r.theirs.bg }
                counts.theirs = counts.theirs + 1
            else
                here[#here + 1] = e
                if c == "mine" then counts.mine = counts.mine + 1 end
            end
        end
    end
    for _, e in ipairs(theirs) do
        local r = pick[e.name:lower()]
        local c = r and r.choice
        if c == "add" then
            here[#here + 1] = e
            counts.add = counts.add + 1
            server[#server + 1] = e
        elseif c == "server_delete" then
            counts.server_delete = counts.server_delete + 1
            server_changed = true
        elseif c == "mine" then
            server[#server + 1] = { name = e.name, fg = r.mine.fg, bg = r.mine.bg }
            server_changed = true
        else
            server[#server + 1] = e
        end
    end
    for _, r in ipairs(rows) do
        if r.kind == "local" and r.choice == "upload" then
            server[#server + 1] = r.mine
            counts.upload = counts.upload + 1
            server_changed = true
        end
    end
    return here, server_changed and server or nil, counts
end

-- "Add 3, upload 1, delete 1 here" for the confirm card; nil if nothing to do.
function M.summary(counts)
    local bits = {}
    local function add(n, s) if n > 0 then bits[#bits + 1] = s:format(n) end end
    add(counts.add, "add %d here")
    add(counts.upload, "upload %d")
    add(counts.theirs, "use the server's version of %d")
    add(counts.mine, "send your version of %d")
    add(counts.delete, "delete %d here")
    add(counts.server_delete, "delete %d from the server")
    if #bits == 0 then return nil end
    local s = table.concat(bits, ", ")
    return s:sub(1, 1):upper() .. s:sub(2)
end

-- What the chosen changes are, one line per kind, for the confirm card and the
-- result page: "Add to this device: Ducko, My Dracula". `done` is past tense.
local WHAT = {
    { "add", "Add to this device", "Added to this device" },
    { "upload", "Upload to your server", "Uploaded to your server" },
    { "theirs", "Use the server's version of", "Now using the server's version of" },
    { "mine", "Send your version of", "Sent your version of" },
    { "delete", "Delete from this device", "Deleted from this device" },
    { "server_delete", "Delete from your server", "Deleted from your server" },
}
function M.describe(rows, done)
    local lines = {}
    for _, w in ipairs(WHAT) do
        local names = {}
        for _, r in ipairs(rows) do if r.choice == w[1] then names[#names + 1] = r.name end end
        if #names > 0 then
            local shown = {}
            for i = 1, math.min(3, #names) do shown[i] = names[i] end
            local more = #names > 3 and (" and " .. (#names - 3) .. " more") or ""
            lines[#lines + 1] = (done and w[3] or w[2]) .. ": " .. table.concat(shown, ", ") .. more
        end
    end
    return lines
end

return M
