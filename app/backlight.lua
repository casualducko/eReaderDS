-- Screen brightness via Linux sysfs. Every backlight found (one per screen on
-- the RG DS Plus) is set to the same percentage.
local M = {}

local ROOT = os.getenv("READER_BACKLIGHT") or "/sys/class/backlight"
-- Finer steps at the dim end, where the eye is most sensitive.
M.LEVELS = { 1, 2, 3, 5, 8, 12, 18, 25, 35, 50, 65, 80, 100 }

local devices

-- Android (GammaOS): apps can read the backlight but not set it; it's set
-- through one root shell, opened the first time (Magisk asks once).
local ANDROID = love and love.system and love.system.getOS() == "Android"
local root_shell

local function write(path, value)
    if ANDROID then
        if root_shell == nil then
            root_shell = io.popen("su", "w") or false
            if root_shell then
                root_shell:write(require("android").QUIET, "\n")
                root_shell:flush()
            end
        end
        if not root_shell then return false end
        -- If root was refused (or Magisk's question timed out), the shell is
        -- gone and writing fails: start again with the next change.
        local ok = root_shell:write(string.format("echo %s > '%s'\n", value, path))
        ok = ok and root_shell:flush()
        if not ok then
            pcall(root_shell.close, root_shell)
            root_shell = nil
            return false
        end
        return true
    end
    local f = io.open(path, "w")
    if not f then return false end
    f:write(value)
    f:close()
    return true
end

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
        -- 1% is the panel's real minimum (raw 1), 100% its maximum.
        local v = math.floor(1 + (d.max - 1) * (math.max(1, pct) - 1) / 99 + 0.5)
        if not write(d.dir .. "/brightness", tostring(v)) then
            print("[backlight] cannot write " .. d.dir .. "/brightness")
        end
    end
end

-- Turn the screens' backlights off or back on (for the lid). Uses bl_power when
-- the driver has it (4 = powered down), otherwise brightness 0; `pct` restores.
function M.power(on, pct)
    for _, d in ipairs(devices or scan()) do
        local f = io.open(d.dir .. "/bl_power", "rb")
        if f then f:close(); write(d.dir .. "/bl_power", on and "0" or "4") end
    end
    if on then
        if pct then M.set(pct) end
    else
        for _, d in ipairs(devices or scan()) do write(d.dir .. "/brightness", "0") end
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
