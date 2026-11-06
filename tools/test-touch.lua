-- luajit tools/test-touch.lua   (from the repo root): feeds the touch layer simulated fingers (as an Android phone would) and prints the events.
package.path = "app/?.lua;" .. package.path
local now = 0
love = { system = { getOS = function() return "Android" end }, timer = { getTime = function() return now end },
    graphics = { getHeight = function() return 1800 end } }
package.loaded["android"] = { duo = true, phone = true, book_xy = function(x, y) return x, y end, bottom_xy = function(x, y) return x, y end,
    window_dist = function(x1, y1, x2, y2) return math.sqrt((x1 - x2) ^ 2 + (y1 - y2) ^ 2) end }
local Touch = require("touch")
local function events()
    local out = {}
    Touch.poll(function(kind) out[#out + 1] = kind end)
    return out
end
local function run(name, steps)
    -- Starts clean: lift everything first.
    local seen = {}
    for _, st in ipairs(steps) do
        now = st.t
        if st.down then love.touchpressed(st.id, st.x, st.y) elseif st.move then love.touchmoved(st.id, st.x, st.y) else love.touchreleased(st.id, st.x, st.y) end
        for _, e in ipairs(events()) do seen[#seen + 1] = e end
    end
    local counts = {}
    for _, e in ipairs(seen) do counts[e] = (counts[e] or 0) + 1 end
    local list = {}
    for k, v in pairs(counts) do list[#list + 1] = k .. "x" .. v end
    table.sort(list)
    print(string.format("%-34s %s", name, table.concat(list, " ")))
end
-- parallel two-finger swipe up: 200 apart, up 500 px in 0.4 s
local s = { { t = 0, id = 1, x = 500, y = 1400, down = true }, { t = 0.01, id = 2, x = 700, y = 1400, down = true } }
for i = 1, 10 do
    s[#s + 1] = { t = 0.01 + i * 0.04, id = 1, x = 500, y = 1400 - i * 50, move = true }
    s[#s + 1] = { t = 0.01 + i * 0.04, id = 2, x = 700, y = 1400 - i * 50, move = true }
end
s[#s + 1] = { t = 0.5, id = 1, x = 500, y = 900 }; s[#s + 1] = { t = 0.5, id = 2, x = 700, y = 900 }
run("two-finger swipe up", s)
-- a pinch: spread from 200 to 500 apart
s = { { t = 0, id = 1, x = 500, y = 1000, down = true }, { t = 0.01, id = 2, x = 700, y = 1000, down = true } }
for i = 1, 10 do
    s[#s + 1] = { t = 0.01 + i * 0.04, id = 1, x = 500 - i * 15, y = 1000, move = true }
    s[#s + 1] = { t = 0.01 + i * 0.04, id = 2, x = 700 + i * 15, y = 1000, move = true }
end
s[#s + 1] = { t = 0.5, id = 1, x = 350, y = 1000 }; s[#s + 1] = { t = 0.5, id = 2, x = 850, y = 1000 }
run("pinch (spread)", s)
-- two-finger tap
run("two-finger tap", { { t = 0, id = 1, x = 500, y = 1000, down = true }, { t = 0.01, id = 2, x = 700, y = 1000, down = true },
    { t = 0.15, id = 1, x = 500, y = 1000 }, { t = 0.16, id = 2, x = 700, y = 1000 } })
-- three-finger tap
run("three-finger tap", { { t = 0, id = 1, x = 400, y = 1000, down = true }, { t = 0.01, id = 2, x = 600, y = 1000, down = true },
    { t = 0.02, id = 3, x = 800, y = 1000, down = true }, { t = 0.15, id = 1, x = 400, y = 1000 }, { t = 0.16, id = 2, x = 600, y = 1000 },
    { t = 0.17, id = 3, x = 800, y = 1000 } })
-- sideways two-finger slide (not up)
s = { { t = 0, id = 1, x = 300, y = 1000, down = true }, { t = 0.01, id = 2, x = 500, y = 1000, down = true } }
for i = 1, 10 do
    s[#s + 1] = { t = 0.01 + i * 0.04, id = 1, x = 300 + i * 40, y = 1000, move = true }
    s[#s + 1] = { t = 0.01 + i * 0.04, id = 2, x = 500 + i * 40, y = 1000, move = true }
end
s[#s + 1] = { t = 0.5, id = 1, x = 700, y = 1000 }; s[#s + 1] = { t = 0.5, id = 2, x = 900, y = 1000 }
run("two-finger slide sideways", s)
-- short upward drift (under the distance needed)
s = { { t = 0, id = 1, x = 500, y = 1400, down = true }, { t = 0.01, id = 2, x = 700, y = 1400, down = true } }
for i = 1, 4 do
    s[#s + 1] = { t = 0.01 + i * 0.04, id = 1, x = 500, y = 1400 - i * 20, move = true }
    s[#s + 1] = { t = 0.01 + i * 0.04, id = 2, x = 700, y = 1400 - i * 20, move = true }
end
s[#s + 1] = { t = 0.3, id = 1, x = 500, y = 1320 }; s[#s + 1] = { t = 0.3, id = 2, x = 700, y = 1320 }
run("two-finger short drift up", s)
-- parallel two-finger swipe down
s = { { t = 0, id = 1, x = 500, y = 600, down = true }, { t = 0.01, id = 2, x = 700, y = 600, down = true } }
for i = 1, 10 do
    s[#s + 1] = { t = 0.01 + i * 0.04, id = 1, x = 500, y = 600 + i * 50, move = true }
    s[#s + 1] = { t = 0.01 + i * 0.04, id = 2, x = 700, y = 600 + i * 50, move = true }
end
s[#s + 1] = { t = 0.5, id = 1, x = 500, y = 1100 }; s[#s + 1] = { t = 0.5, id = 2, x = 700, y = 1100 }
run("two-finger swipe down", s)
