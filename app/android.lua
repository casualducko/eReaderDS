-- Running on Android: GammaOS on the RG DS Plus (and other dual-screen
-- Android handhelds that stack both screens into one tall window).
--
-- GammaOS's "DualStack" gives an app on its list one window across both
-- screens, the top one above the bottom one (1024x1536). eReaderDS draws its
-- usual 2048x768 frame (the two screens side by side, as on Linux) into a
-- canvas and shows its halves one above the other. Without DualStack the app
-- gets only the top screen, and the setup here puts it on the list (GammaOS
-- is rooted; Magisk asks once).
local M = {}

M.active = love.system.getOS() == "Android"
M.PACKAGE = "com.casualducko.ereaderds"
M.ROOT = "/storage/emulated/0"                  -- what Android apps see as /sdcard
M.BOOKS = M.ROOT .. "/Ebook"
M.DATA = M.BOOKS .. "/.ereaderds"
M.CA_FILE = M.DATA .. "/cacerts.pem"            -- (net.lua looks for it at this path)

-- Folder helpers for every system: on Linux the usual commands, on Android
-- straight through the C library (see "without a shell" below).
function M.ls(dir)                              -- the names in a folder, sorted
    local t = {}
    if M.active then
        for _, e in ipairs(M.list_dir(dir)) do t[#t + 1] = e.name end
        table.sort(t)
        return t
    end
    local p = io.popen('ls -1 "' .. dir .. '" 2>/dev/null')
    if p then
        for n in p:lines() do t[#t + 1] = n end
        p:close()
    end
    return t
end
function M.mkdir(dir)
    if M.active then M.mkdir_p(dir) else os.execute('mkdir -p "' .. dir .. '"') end
end
function M.is_dir(dir)
    if M.active then return M.dir_exists(dir) end
    local r = os.execute('[ -d "' .. dir .. '" ]')
    return r == 0 or r == true
end

if not M.active then return M end

local function run(cmd)
    local ok = os.execute(cmd)
    return ok == true or ok == 0
end

---------------------------------------------------------------- without a shell

-- Starting a command (getprop, mkdir, ls, find) copies the whole app process
-- first, which on Android costs about a third of a second each time; startup
-- ran about ten. These do the same through the C library directly.
local ffi = require("ffi")
for _, decl in ipairs({
    "int __system_property_get(const char *name, char *value);",
    "int mkdir(const char *path, unsigned int mode);",
    "int access(const char *path, int mode);",
    "typedef struct rgds_DIR rgds_DIR;",
    "struct rgds_dirent { uint64_t d_ino; int64_t d_off; unsigned short d_reclen; unsigned char d_type; char d_name[256]; };",
    "rgds_DIR *opendir(const char *name);",
    "struct rgds_dirent *readdir(rgds_DIR *dir);",
    "int closedir(rgds_DIR *dir);",
}) do pcall(ffi.cdef, decl) end
local C = ffi.C
local DT_DIR, DT_UNKNOWN = 4, 0

-- An Android system property ("" when unset).
function M.getprop(name)
    local buf = ffi.new("char[92]")
    local ok, n = pcall(C.__system_property_get, name, buf)
    return ok and n > 0 and ffi.string(buf, n) or ""
end

function M.dir_exists(path)
    local ok, d = pcall(C.opendir, path)
    if not ok or d == nil then return false end
    C.closedir(d)
    return true
end

-- mkdir -p.
function M.mkdir_p(path)
    local p = ""
    for part in path:gmatch("[^/]+") do
        p = p .. "/" .. part
        pcall(C.mkdir, p, tonumber("775", 8))
    end
end

-- The names in a folder, with whether each is a folder: { { name, dir } }.
function M.list_dir(path)
    local out = {}
    local ok, d = pcall(C.opendir, path)
    if not ok or d == nil then return out end
    while true do
        local e = C.readdir(d)
        if e == nil then break end
        local name = ffi.string(e.d_name)
        if name ~= "." and name ~= ".." then
            local dir = e.d_type == DT_DIR
            if e.d_type == DT_UNKNOWN then
                local sub = C.opendir(path .. "/" .. name)
                dir = sub ~= nil
                if dir then C.closedir(sub) end
            end
            out[#out + 1] = { name = name, dir = dir }
        end
    end
    C.closedir(d)
    return out
end

-- Files under a folder (depth-limited) whose names pass keep(name, rel),
-- with their sizes: { { path, size } }. skip_dir(rel) leaves a folder out.
function M.find_files(root, depth, keep, skip_dir)
    local out = {}
    local function walk(dir, rel, left)
        for _, e in ipairs(M.list_dir(dir)) do
            local r = rel == "" and e.name or (rel .. "/" .. e.name)
            if e.dir then
                if left > 1 and not skip_dir(r) then walk(dir .. "/" .. e.name, r, left - 1) end
            elseif keep(e.name, r) then
                local f = io.open(dir .. "/" .. e.name, "rb")
                local size = f and f:seek("end")
                if f then f:close() end
                out[#out + 1] = { path = dir .. "/" .. e.name, size = size }
            end
        end
    end
    walk(root, "", depth)
    return out
end

-- Magisk shows a "granted" notice each time root is used, and that notice
-- makes DualStack give up the tall window (the app shrinks onto one screen);
-- and it logs each use through its own app, which it starts for that (88 MB,
-- enough to make a 1 GB handheld swap and pages turn slowly). Once root is
-- ours, turn both off for this app.
M.QUIET = 'magisk --sqlite "UPDATE policies SET notification=0, logging=0 WHERE uid=$(stat -c %u /data/data/'
    .. M.PACKAGE .. ')" >/dev/null 2>&1'

-- A command as root (GammaOS has Magisk, which asks the first time).
function M.su(cmd)
    cmd = cmd .. "\n" .. M.QUIET                  -- (a newline: cmd may end with &)
    return run("su -c '" .. cmd:gsub("'", "'\\''") .. "' </dev/null >/dev/null 2>&1")
end

-- Both screens: the window is taller than it's wide.
function M.stacked()
    local w, h = love.graphics.getDimensions()
    return h > w
end

-- Can we write to the books folder? (Needs Android's all-files access.)
function M.storage_ok()
    -- (Asking is enough when the folder is there, and quick: opening or making
    -- a file in shared storage costs Android much more.)
    local W_OK = 2
    if C.access(M.DATA, W_OK) == 0 then return true end
    M.mkdir_p(M.DATA)
    local test = M.DATA .. "/.write-test"
    local f = io.open(test, "wb")
    if not f then return false end
    f:write("ok"); f:close()
    os.remove(test)
    return true
end

-- A note on the screen before asking Magisk (its question may be hidden and
-- take a while to time out): on the top screen, turned like a page.
local function notice(text)
    if not love.graphics.isActive() then return end
    love.graphics.origin()
    love.graphics.clear(0.957, 0.925, 0.847)
    love.graphics.push()
    love.graphics.translate(1024, 0)
    love.graphics.rotate(math.pi / 2)
    love.graphics.setColor(0.357, 0.275, 0.212)
    love.graphics.setFont(love.graphics.newFont(34))
    love.graphics.printf(text, 60, 320, 648, "center")
    love.graphics.pop()
    love.graphics.present()
end

-- GammaOS turns the Anbernic button into its Control Center for every app.
-- A per-app gamepad profile for eReaderDS (GammaOS's own feature) gives it
-- back as the controller's guide button, which quits, as on Linux. Nothing
-- is changed if eReaderDS has a profile already (the reader's own).
local function prop(name)
    return M.getprop(name)
end
function M.gamepad_profile()
    local n = tonumber(prop("persist.gammaos.gamepad.pa_count")) or 0
    for i = 0, n - 1 do
        if prop("persist.gammaos.gamepad.pa" .. i .. "_pkg") == M.PACKAGE then return true, false end
    end
    local g = "persist.gammaos.gamepad.pa"
    M.su("setprop " .. g .. n .. "_pkg " .. M.PACKAGE .. "; setprop " .. g .. n .. "_btn 316:316; setprop "
        .. g .. "_count " .. (n + 1) .. "; stop gammapad; start gammapad")
    return prop(g .. n .. "_pkg") == M.PACKAGE, true
end

-- One-time setup: all-files access, and the DualStack list. Returns a
-- heading and a message when something's left for the reader to do, else nil.
function M.setup()
    if not M.storage_ok() then
        notice("Setting up eReaderDS…\n\nIf Magisk asks, tap Grant.")
        M.su("appops set " .. M.PACKAGE .. " MANAGE_EXTERNAL_STORAGE allow")
        if not M.storage_ok() then
            return "Almost there", "eReaderDS can't use the Ebook folder yet.\n\nIn Android's Settings → Apps → "
                .. "Special app access → All files access, switch eReaderDS on (or switch it on in Magisk → Superuser). "
                .. "Then press A to close eReaderDS and open it again."
        end
    end
    if not M.stacked() then
        local function listed()
            local list = M.getprop("persist.gammaos.dualstack.pkgs")
            return list, list:find(M.PACKAGE, 1, true) ~= nil
        end
        local list, ok = listed()
        if not ok then
            notice("Setting up eReaderDS for both screens…\n\nIf Magisk asks, tap Grant.")
            M.su("setprop persist.gammaos.dualstack.pkgs " .. (list ~= "" and (list .. "," .. M.PACKAGE) or M.PACKAGE))
            ok = select(2, listed())
        end
        if ok then
            M.gamepad_profile()
            return "One more step!", "Press A to close eReaderDS, then open it again.\n\n"
                .. "From then on it opens on both screens."
        end
        -- Magisk's question can end up hidden behind GammaOS's screens and
        -- time out, which Magisk remembers as a no.
        return "Almost there", "To use both screens, eReaderDS needs Magisk's permission once.\n\n"
            .. "Open Magisk → Superuser and switch eReaderDS on (or tap Grant if Magisk asks). "
            .. "Then press A to close eReaderDS and open it again."
    end
    -- (Already on DualStack, from an earlier version: the button profile on
    -- its own. The gamepad service restarts to read it, so open eReaderDS
    -- again for the buttons to be sure to work.)
    local has, added = M.gamepad_profile()
    if added and has then
        return "One more step!", "Press A to close eReaderDS, then open it again.\n\n"
            .. "From then on the Anbernic button closes it, as on Linux."
    end
    return nil
end

-- A folder bundled in the app (such as the built-in dictionary), copied out
-- to the data folder so ordinary file reads can use it. Copied again when a
-- file's size changes (a new version).
function M.bundled(dir)
    local dest = M.DATA .. "/bundled/" .. dir
    M.mkdir_p(dest)
    for _, name in ipairs(love.filesystem.getDirectoryItems(dir)) do
        local src = dir .. "/" .. name
        local info = love.filesystem.getInfo(src)
        if info and info.type == "file" then
            local out = dest .. "/" .. name
            local f = io.open(out, "rb")
            local size = f and f:seek("end")
            if f then f:close() end
            if size ~= info.size then
                local data = love.filesystem.read(src)
                local w = data and io.open(out .. ".tmp", "wb")
                if w then
                    w:write(data); w:close()
                    os.rename(out .. ".tmp", out)
                end
            end
        end
    end
    return dest
end

-- Android's trusted certificates, as one file OpenSSL can read (its own
-- lookup by hashed name doesn't match Android's naming). Made once a day at
-- most, since the system's list only changes with an update.
function M.ca_bundle()
    local stamp = M.CA_FILE .. ".day"
    local today = os.date("%Y%m%d")
    local f = io.open(stamp, "rb")
    local made = f and f:read("*l")
    if f then f:close() end
    local have = io.open(M.CA_FILE, "rb")
    if have then have:close() end
    if have and made == today then return end
    local parts = {}
    for _, dir in ipairs({ "/apex/com.android.conscrypt/cacerts", "/system/etc/security/cacerts" }) do
        for _, e in ipairs(M.list_dir(dir)) do
            local c = io.open(dir .. "/" .. e.name, "rb")
            if c then
                local text = c:read("*a"); c:close()
                local pem = text:match("(%-%-%-%-%-BEGIN CERTIFICATE%-%-%-%-%-.-%-%-%-%-%-END CERTIFICATE%-%-%-%-%-)")
                if pem then parts[#parts + 1] = pem end
            end
        end
        if #parts > 0 then break end
    end
    if #parts == 0 then return end
    local w = io.open(M.CA_FILE .. ".tmp", "wb")
    if w then
        w:write(table.concat(parts, "\n"), "\n"); w:close()
        os.rename(M.CA_FILE .. ".tmp", M.CA_FILE)
        local s = io.open(stamp, "wb")
        if s then s:write(today, "\n"); s:close() end
    end
end

-- While a frame is drawn, "the screen" is the frame's canvas: the drawing
-- code switches to page canvases and back with setCanvas(), which would
-- otherwise go straight to the real screen.
local set_canvas = love.graphics.setCanvas
local target
function love.graphics.setCanvas(c, ...)
    if c == nil and target then return set_canvas(target) end
    return set_canvas(c, ...)
end
function M.begin(canvas)
    target = canvas
    set_canvas(canvas)
end
function M.finish()
    target = nil
    set_canvas()
end

-- For testing over ADB (Android's own screenshots don't show DualStack's
-- window as the screens do): create DATA/.shot and the next frame is saved
-- as DATA/shot.png, the two screens side by side.
local shot_wanted = false
function M.shot_pending()                       -- (looked at once a second)
    local f = io.open(M.DATA .. "/.shot", "rb")
    if f then f:close() end
    shot_wanted = f ~= nil
    return shot_wanted
end
function M.shot_check(canvas)
    if not shot_wanted then return end
    shot_wanted = false
    os.remove(M.DATA .. "/.shot")
    local png = canvas:newImageData():encode("png"):getString()
    local w = io.open(M.DATA .. "/shot.png", "wb")
    if w then w:write(png); w:close() end
end

-- Testing the crash screen: create DATA/.crash.
function M.crash_check()
    local f = io.open(M.DATA .. "/.crash", "rb")
    if not f then return end
    f:close()
    os.remove(M.DATA .. "/.crash")
    error("a test crash (.crash)")
end

-- Show the 2048x768 frame: its left half (the top screen's) above its right
-- half (the bottom screen's). On one screen only (no DualStack yet), just
-- the top screen's half.
local quads
function M.present(canvas)
    local W, H = love.graphics.getDimensions()
    quads = quads or {
        love.graphics.newQuad(0, 0, 1024, 768, 2048, 768),
        love.graphics.newQuad(1024, 0, 1024, 768, 2048, 768),
    }
    love.graphics.setColor(1, 1, 1)
    love.graphics.clear(0, 0, 0)
    if M.stacked() then
        M.was_stacked = true
        local sx, sy = W / 1024, (H / 2) / 768
        love.graphics.draw(canvas, quads[1], 0, 0, 0, sx, sy)
        love.graphics.draw(canvas, quads[2], 0, H / 2, 0, sx, sy)
    else
        -- One screen only. Before DualStack (first run) the window is on the
        -- top screen: its page, with the setup message. When DualStack lets
        -- go later, the window is left on the bottom screen: its page, with
        -- the menus, messages and touch.
        love.graphics.draw(canvas, quads[M.was_stacked and 2 or 1], 0, 0, 0, W / 1024, H / 768)
    end
end

-- A touch in window coordinates -> the bottom screen's own 1024x768
-- coordinates, or nil when it isn't on the bottom screen (the top screen has
-- no touch, but a desktop-style window might).
function M.bottom_xy(x, y)
    local W, H = love.graphics.getDimensions()
    if not M.stacked() then
        if not M.was_stacked then return nil end
        return x * 1024 / W, y * 768 / H                -- (see present)
    end
    if y < H / 2 then return nil end
    return x * 1024 / W, (y - H / 2) * 768 / (H / 2)
end

return M
