-- Screen brightness via Linux sysfs. Every backlight found (one per screen on
-- the RG DS Plus) is set to the same percentage.
local M = {}

local ROOT = os.getenv("READER_BACKLIGHT") or "/sys/class/backlight"
-- Finer steps at the dim end, where the eye is most sensitive.
M.LEVELS = { 1, 2, 3, 5, 8, 12, 18, 25, 35, 50, 65, 80, 100 }

local devices

local function read_num(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local v = tonumber((f:read("*l") or ""):match("%d+"))
    f:close()
    return v
end

local function scan()
    devices = {}
    local p = io.popen('ls -1 "' .. ROOT .. '" 2>/dev/null')
    if not p then return devices end
    for name in p:lines() do
        local dir = ROOT .. "/" .. name
        local max = read_num(dir .. "/max_brightness")
        if max and max > 0 and read_num(dir .. "/brightness") then
            devices[#devices + 1] = { name = name, dir = dir, max = max }
        end
    end
    p:close()
    for _, d in ipairs(devices) do
        print(string.format("[backlight] %s max=%d now=%d", d.name, d.max, read_num(d.dir .. "/brightness")))
    end
    if #devices == 0 then print("[backlight] none found in " .. ROOT) end
    return devices
end

function M.available()
    return #(devices or scan()) > 0
end

-- Current brightness in percent (of the first backlight).
function M.get()
    local d = (devices or scan())[1]
    if not d then return nil end
    local v = read_num(d.dir .. "/brightness")
    return v and math.floor(v * 100 / d.max + 0.5)
end

function M.set(pct)
    for _, d in ipairs(devices or scan()) do
        local v = math.max(1, math.floor(d.max * pct / 100 + 0.5))
        local f = io.open(d.dir .. "/brightness", "w")
        if f then
            f:write(tostring(v))
            f:close()
        else
            print("[backlight] cannot write " .. d.dir .. "/brightness")
        end
    end
end

-- Step to the next level up (dir = 1) or down (dir = -1) from pct.
function M.step(pct, dir)
    local L = M.LEVELS
    if dir > 0 then
        for _, v in ipairs(L) do if v > pct then return v end end
        return L[#L]
    end
    for k = #L, 1, -1 do if L[k] < pct then return L[k] end end
    return L[1]
end

return M
