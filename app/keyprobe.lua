-- Input diagnostics: logs the input device list, and every raw key press with
-- the device it came from. SDL merges all keyboards, so two buttons that send
-- the same key (e.g. Back) can only be told apart here.
local M = { enabled = false }
-- Stubs for systems without evdev (e.g. testing on a computer).
function M.open() return false end
function M.poll() return false end

local ok_ffi, ffi = pcall(require, "ffi")
if not ok_ffi or ffi.os ~= "Linux" then return M end

pcall(ffi.cdef, [[
    int open(const char *path, int flags);
    long read(int fd, void *buf, unsigned long count);
    struct rgds_input_event { long tv_sec; long tv_usec; unsigned short type; unsigned short code; int value; };
]])
local C = ffi.C
local O_NONBLOCK, EV_KEY = 2048, 1

local devices = {}     -- { fd, name }
local buf
-- Log the first presses of a session, then stop reading these devices so the
-- probe costs nothing while reading.
local LIMIT, logged = 40, 0

-- Parse /proc/bus/input/devices into { name, event } entries (and log it).
local function list_devices()
    local f = io.open("/proc/bus/input/devices", "r")
    if not f then return {} end
    local text = f:read("*a")
    f:close()
    local out = {}
    for block in (text .. "\n\n"):gmatch("(.-)\n\n") do
        local name = block:match('N: Name="([^"]*)"')
        local ev = block:match("H: Handlers=[^\n]-(event%d+)")
        local keys = block:match("B: KEY=([%x ]+)")
        if name and ev then
            print(string.format("[inputdev] %s %s keys=%s", ev, name, keys or "-"))
            out[#out + 1] = { name = name, event = ev, has_keys = keys ~= nil }
        end
    end
    return out
end

-- Open every key-capable device except the touchscreen; route presses to
-- handler(device_name, code) and log them.
function M.open(handler, skip)
    for _, d in ipairs(list_devices()) do
        if d.has_keys and d.name ~= skip then
            local fd = C.open("/dev/input/" .. d.event, O_NONBLOCK)
            if fd >= 0 then devices[#devices + 1] = { fd = fd, name = d.name } end
        end
    end
    buf = ffi.new("struct rgds_input_event[32]")
    M.handler = handler
    M.enabled = #devices > 0
    return M.enabled
end

function M.poll()
    local any = false
    for _, d in ipairs(devices) do
        while true do
            local n = tonumber(C.read(d.fd, buf, ffi.sizeof(buf)))
            if not n or n <= 0 then break end
            for k = 0, math.floor(n / ffi.sizeof("struct rgds_input_event")) - 1 do
                local e = buf[k]
                if e.type == EV_KEY and e.value == 1 then
                    print(string.format("[evdev] %q key %d", d.name, e.code))
                    if M.handler then M.handler(d.name, e.code) end
                    logged = logged + 1
                    any = true
                end
            end
        end
    end
    if logged >= LIMIT and not M.handler then
        print("[evdev] (further presses not logged)")
        M.enabled = false
    end
    return any
end

return M
