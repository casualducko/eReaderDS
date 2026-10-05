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
    for _, name in ipairs(require("android").ls(ROOT)) do
        local d = ROOT .. "/" .. name
        if (read(d .. "/type") or ""):lower() == "battery" and read(d .. "/capacity") then
            print("[battery] " .. d)
            return d
        end
    end
    print("[battery] none found in " .. ROOT)
    return false
end

-- Re-read now (at most every 5 seconds); true when the level or charging
-- state changed since last, so the status bar can be redrawn. Cheap: two
-- small sysfs reads. The reader only redraws on events, so without this the
-- bolt wouldn't change until the next page turn.
local last_poll = -1
function M.poll()
    if dir == nil then dir = find() end
    if not dir then return false end
    local now = love.timer.getTime()
    if last_poll >= 0 and now - last_poll < 5 then return false end
    last_poll = now
    local pct = tonumber(read(dir .. "/capacity"))
    local status = (read(dir .. "/status") or ""):lower()
    local new = pct and { pct = math.max(0, math.min(100, pct)),
        charging = status == "charging" or status == "full" } or nil
    local changed = (cache == nil) ~= (new == nil)
        or (cache ~= nil and new ~= nil and (cache.pct ~= new.pct or cache.charging ~= new.charging))
    cache, cached_at = new, now
    return changed
end

-- { pct = 0..100, charging = bool } or nil when there's no battery.
function M.get()
    if dir == nil then dir = find() end
    if not dir then return nil end
    local now = love.timer.getTime()          -- (not the clock, which can be set back)
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
