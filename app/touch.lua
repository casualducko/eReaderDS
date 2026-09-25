-- Raw touchscreen input via Linux evdev. SDL doesn't deliver the RG DS Plus
-- touchscreen to apps, so read the gt9xx device directly (non-blocking).
--
-- Reports one finger (the first slot) in the bottom screen's native landscape
-- coordinates, 0..1024 x 0..768:
--   M.poll(handler)   handler(kind, x, y) with kind = "down" | "move" | "up"
local M = { enabled = false }

-- Stubs for systems without evdev (e.g. testing on a computer).
function M.open() return false end
function M.poll() return false end
function M.close() end

local ok_ffi, ffi = pcall(require, "ffi")
if not ok_ffi or ffi.os ~= "Linux" then return M end

pcall(ffi.cdef, [[
    int open(const char *path, int flags);
    long read(int fd, void *buf, unsigned long count);
    int close(int fd);
    int ioctl(int fd, unsigned long request, ...);
    struct rgds_input_event { long tv_sec; long tv_usec; unsigned short type; unsigned short code; int value; };
    struct rgds_input_absinfo { int value, minimum, maximum, fuzz, flat, resolution; };
]])
local C = ffi.C

local O_NONBLOCK = 2048
local EV_SYN, EV_KEY, EV_ABS = 0, 1, 3
local BTN_TOUCH = 0x14a
local ABS_X, ABS_Y = 0x00, 0x01
local ABS_MT_SLOT, ABS_MT_X, ABS_MT_Y, ABS_MT_ID = 0x2f, 0x35, 0x36, 0x39

local SCREEN_W, SCREEN_H = 1024, 768

local fd, buf
local range = { x = { 0, SCREEN_W }, y = { 0, SCREEN_H } }
local slot = 0
local st = { x = 0, y = 0, down = false }       -- slot 0 state
local was_down = false
local logged = 0

local function find_device(name)
    local f = io.open("/proc/bus/input/devices", "r")
    if not f then return nil end
    local text = f:read("*a")
    f:close()
    for block in (text .. "\n\n"):gmatch("(.-)\n\n") do
        local n = block:match('N: Name="([^"]*)"')
        local ev = block:match("H: Handlers=[^\n]-(event%d+)")
        if n == name and ev then return "/dev/input/" .. ev end
    end
end

local function absinfo(code)
    local info = ffi.new("struct rgds_input_absinfo")
    -- EVIOCGABS(code) = _IOR('E', 0x40 + code, struct input_absinfo)
    local req = 0x80184540 + code
    if C.ioctl(fd, req, info) == 0 and info.maximum > info.minimum then
        return { info.minimum, info.maximum }
    end
end

function M.open(name)
    local path = os.getenv("READER_TOUCH_DEV") or find_device(name or "gt9xx-0")
    if not path then print("[touch] no touchscreen found"); return false end
    fd = C.open(path, O_NONBLOCK)
    if fd < 0 then print("[touch] cannot open " .. path); fd = nil; return false end
    buf = ffi.new("struct rgds_input_event[64]")
    range.x = absinfo(ABS_MT_X) or absinfo(ABS_X) or range.x
    range.y = absinfo(ABS_MT_Y) or absinfo(ABS_Y) or range.y
    print(string.format("[touch] opened %s x %d..%d y %d..%d", path, range.x[1], range.x[2], range.y[1], range.y[2]))
    M.enabled = true
    return true
end

local function scale(v, r, size)
    return (v - r[1]) * size / (r[2] - r[1])
end

function M.poll(handler)
    if not fd then return false end
    local any = false
    while true do
        local n = tonumber(C.read(fd, buf, ffi.sizeof(buf)))
        if not n or n <= 0 then break end
        for k = 0, math.floor(n / ffi.sizeof("struct rgds_input_event")) - 1 do
            local e = buf[k]
            local t, c, v = e.type, e.code, e.value
            if t == EV_ABS then
                if c == ABS_MT_SLOT then slot = v
                elseif slot == 0 then
                    if c == ABS_MT_X or c == ABS_X then st.x = v
                    elseif c == ABS_MT_Y or c == ABS_Y then st.y = v
                    elseif c == ABS_MT_ID then st.down = v >= 0 end
                end
            elseif t == EV_KEY and c == BTN_TOUCH then
                if v == 0 then st.down = false end
            elseif t == EV_SYN and c == 0 then
                local x, y = scale(st.x, range.x, SCREEN_W), scale(st.y, range.y, SCREEN_H)
                if st.down and not was_down then handler("down", x, y); any = true
                elseif st.down then handler("move", x, y); any = true
                elseif was_down then handler("up", x, y); any = true end
                if logged < 6 and (st.down ~= was_down) then
                    logged = logged + 1
                    print(string.format("[touch] %s raw=%d,%d -> %.0f,%.0f", st.down and "down" or "up", st.x, st.y, x, y))
                end
                was_down = st.down
            end
        end
    end
    return any
end

function M.close()
    if fd then C.close(fd); fd = nil end
end

return M
