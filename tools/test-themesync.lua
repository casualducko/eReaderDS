-- Checks for app/themesync.lua (the diff and plan behind Sync themes).
--   luajit tools/test-themesync.lua
package.path = "app/?.lua;" .. package.path
local T = require("themesync")
local function eq(a, b, m) if a ~= b then error((m or "") .. " expected " .. tostring(b) .. " got " .. tostring(a), 2) end end

local mine = { { name = "Rose", fg = "30:10:5", bg = "92:0:0" }, { name = "Moss", fg = "20:0:0", bg = "80:0:0" },
    { name = "Same", fg = "50:0:0", bg = "60:0:0" } }
local theirs = { { name = "same", fg = "50:0:0", bg = "60:0:0" }, { name = "Sky", fg = "10:0:0", bg = "70:0:0" },
    { name = "Moss", fg = "20:1:0", bg = "80:0:0" } }

local rows, same = T.diff(mine, theirs)
eq(same, 1, "same"); eq(#rows, 3, "rows")
eq(rows[1].name, "Moss"); eq(rows[1].kind, "differs")
eq(rows[2].name, "Rose"); eq(rows[2].kind, "local")
eq(rows[3].name, "Sky"); eq(rows[3].kind, "remote")

T.defaults(rows)
eq(rows[1].choice, "skip", "a difference starts on skip"); eq(rows[2].choice, "upload"); eq(rows[3].choice, "add")
local here, server, c = T.plan(mine, theirs, rows)
eq(#here, 4, "here"); eq(#server, 4, "server"); eq(c.add, 1); eq(c.upload, 1)
eq(T.summary(c), "Add 1 here, upload 1")
local d = T.describe(rows)
eq(d[1], "Add to this device: Sky"); eq(d[2], "Upload to your server: Rose")
eq(T.describe(rows, true)[1], "Added to this device: Sky")

rows[1].choice = "theirs"; rows[2].choice = "delete"; rows[3].choice = "server_delete"
here, server, c = T.plan(mine, theirs, rows)
eq(#here, 2); eq(here[1].fg, "20:1:0", "the server's version wins"); eq(#server, 2); eq(c.delete, 1); eq(c.server_delete, 1)

rows[1].choice, rows[2].choice, rows[3].choice = "skip", "skip", "skip"
here, server, c = T.plan(mine, theirs, rows)
eq(server, nil, "the server stays as it is"); eq(#here, 3); eq(T.summary(c), nil)

eq(T.cycle(rows[1]), "mine"); eq(T.cycle(rows[1]), "theirs"); eq(T.cycle(rows[1]), "skip")
eq(T.cycle(rows[1], -1), "theirs", "backwards")

-- Colours the store could not read back are not accepted (no decimal points).
eq(#T.clean({ { name = "a", fg = "1:2:3", bg = "1:2:3" }, { name = "A", fg = "1:2:3", bg = "1:2:3" },
    { name = "x", fg = "bad!", bg = "1" }, { name = "d", fg = "1.5:2:3", bg = "1:2:3" }, 5 }), 1)
print("themesync: ok")
