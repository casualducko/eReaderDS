-- Battery level from Linux sysfs (/sys/class/power_supply). Readings are cached
-- for 30 seconds so drawing the status bar never touches the disk often.
local M = {}

local ROOT = os.getenv("READER_BATTERY") or "/sys/class/power_supply"
local dir              -- the battery's sysfs folder, false if none
local cache, cached_at

local function read(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local v = f:read("*l")
    f:close()
    return v
end

local function find()
    local p = io.popen('ls -1 "' .. ROOT .. '" 2>/dev/null')
    if p then
        for name in p:lines() do
            local d = ROOT .. "/" .. name
            if (read(d .. "/type") or ""):lower() == "battery" and read(d .. "/capacity") then
                p:close()
                print("[battery] " .. d)
                return d
            end
        end
        p:close()
    end
    print("[battery] none found in " .. ROOT)
    return false
end

-- { pct = 0..100, charging = bool } or nil when there's no battery.
function M.get()
    if dir == nil then dir = find() end
    if not dir then return nil end
    local now = os.time()
    if not cache or now - cached_at >= 30 then
        local pct = tonumber(read(dir .. "/capacity"))
        local status = (read(dir .. "/status") or ""):lower()
        cache = pct and { pct = math.max(0, math.min(100, pct)),
            charging = status == "charging" or status == "full" } or nil
        cached_at = now
    end
    return cache
end

return M
