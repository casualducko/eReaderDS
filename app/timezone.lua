-- Time zones for the status bar clock. A chosen zone is applied by setting TZ
-- to a POSIX rule string (which carries its own daylight-saving rules, no tz
-- database needed) and calling tzset(); os.date() then returns local time.
local M = {}

-- "Device clock" shows the device's time as it is. The stock firmware keeps
-- the clock on local time (set in its own settings) while calling it UTC, so
-- that's the right choice there; the named zones are for a clock that really
-- runs on UTC. Then zones with daylight saving, then fixed UTC offsets.
M.ZONES = {
    { "Device clock", "UTC0" },
    { "UTC", "UTC0" },
    { "US Eastern", "EST5EDT,M3.2.0,M11.1.0" },
    { "US Central", "CST6CDT,M3.2.0,M11.1.0" },
    { "US Mountain", "MST7MDT,M3.2.0,M11.1.0" },
    { "Arizona", "MST7" },
    { "US Pacific", "PST8PDT,M3.2.0,M11.1.0" },
    { "Alaska", "AKST9AKDT,M3.2.0,M11.1.0" },
    { "Hawaii", "HST10" },
    { "Atlantic Canada", "AST4ADT,M3.2.0,M11.1.0" },
    { "Newfoundland", "NST3:30NDT,M3.2.0,M11.1.0" },
    { "Mexico City", "CST6" },
    { "Brazil (São Paulo)", "<-03>3" },
    { "Argentina", "<-03>3" },
    { "UK / Ireland", "GMT0BST,M3.5.0/1,M10.5.0" },
    { "Central Europe", "CET-1CEST,M3.5.0,M10.5.0/3" },
    { "Eastern Europe", "EET-2EEST,M3.5.0/3,M10.5.0/4" },
    { "Moscow", "MSK-3" },
    { "India", "IST-5:30" },
    { "China / Singapore", "CST-8" },
    { "Japan / Korea", "JST-9" },
    { "Sydney / Melbourne", "AEST-10AEDT,M10.1.0,M4.1.0/3" },
    { "Brisbane", "AEST-10" },
    { "New Zealand", "NZST-12NZDT,M9.5.0,M4.1.0/3" },
}
for h = -12, 14 do
    if h ~= 0 then
        local name = string.format("UTC%+d", h)
        -- POSIX offsets are the opposite sign: UTC+2 is "<+02>-2".
        M.ZONES[#M.ZONES + 1] = { name, string.format("<%+03d>%d", h, -h) }
    end
end

M.NAMES = {}
for i, z in ipairs(M.ZONES) do M.NAMES[i] = z[1] end

local ok_ffi, ffi = pcall(require, "ffi")
if ok_ffi then
    pcall(ffi.cdef, [[
        int setenv(const char *name, const char *value, int overwrite);
        void tzset(void);
    ]])
end

function M.apply(name)
    local rule = "UTC0"
    for _, z in ipairs(M.ZONES) do
        if z[1] == name then rule = z[2] end
    end
    if ok_ffi and pcall(function() ffi.C.setenv("TZ", rule, 1); ffi.C.tzset() end) then
        return true
    end
    print("[clock] could not set time zone")
    return false
end

return M
