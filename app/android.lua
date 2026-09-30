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

if not M.active then return M end

local function run(cmd)
    local ok = os.execute(cmd)
    return ok == true or ok == 0
end

-- Magisk shows a "granted" notice each time root is used, and that notice
-- makes DualStack give up the tall window (the app shrinks onto one screen).
-- Once root is ours, turn the notices off for this app.
M.QUIET = 'magisk --sqlite "UPDATE policies SET notification=0 WHERE uid=$(stat -c %u /data/data/'
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
    run('mkdir -p "' .. M.DATA .. '" 2>/dev/null')
    local test = M.DATA .. "/.write-test"
    local f = io.open(test, "wb")
    if not f then return false end
    f:write("ok"); f:close()
    os.remove(test)
    return true
end

-- One-time setup: all-files access, and the DualStack list. Returns a
-- message to show when something's left for the reader to do, else nil.
function M.setup()
    if not M.storage_ok() then
        M.su("appops set " .. M.PACKAGE .. " MANAGE_EXTERNAL_STORAGE allow")
        if not M.storage_ok() then
            return "eReaderDS can't use the Ebook folder yet.\n\nIn Android's Settings → Apps → Special app access → "
                .. "All files access, switch eReaderDS on (or switch it on in Magisk → Superuser), then open eReaderDS again."
        end
    end
    if not M.stacked() then
        local function listed()
            local p = io.popen("getprop persist.gammaos.dualstack.pkgs 2>/dev/null")
            local list = p and p:read("*l") or ""
            if p then p:close() end
            return list or "", (list or ""):find(M.PACKAGE, 1, true) ~= nil
        end
        local list, ok = listed()
        if not ok then
            M.su("setprop persist.gammaos.dualstack.pkgs " .. (list ~= "" and (list .. "," .. M.PACKAGE) or M.PACKAGE))
            ok = select(2, listed())
        end
        if ok then
            return "eReaderDS uses both screens, and GammaOS will now give it them.\n\n"
                .. "Close eReaderDS (Quit, at the end of Settings) and open it again."
        end
        -- Magisk's question can end up hidden behind GammaOS's screens and
        -- time out, which Magisk remembers as a no.
        return "eReaderDS uses both screens. To set that up once, it needs Magisk's permission.\n\n"
            .. "Open Magisk → Superuser and switch eReaderDS on (or tap Grant if Magisk asks). "
            .. "Then open eReaderDS again."
    end
    return nil
end

-- A folder bundled in the app (such as the built-in dictionary), copied out
-- to the data folder so ordinary file reads can use it. Copied again when a
-- file's size changes (a new version).
function M.bundled(dir)
    local dest = M.DATA .. "/bundled/" .. dir
    run('mkdir -p "' .. dest .. '"')
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
    local f = io.open(M.CA_FILE, "rb")
    if f then
        f:close()
        local p = io.popen('find "' .. M.CA_FILE .. '" -mtime -1 2>/dev/null')
        local fresh = p and p:read("*l")
        if p then p:close() end
        if fresh then return end
    end
    local parts = {}
    for _, dir in ipairs({ "/apex/com.android.conscrypt/cacerts", "/system/etc/security/cacerts" }) do
        local p = io.popen('ls -1 "' .. dir .. '" 2>/dev/null')
        if p then
            for name in p:lines() do
                local c = io.open(dir .. "/" .. name, "rb")
                if c then
                    local text = c:read("*a"); c:close()
                    local pem = text:match("(%-%-%-%-%-BEGIN CERTIFICATE%-%-%-%-%-.-%-%-%-%-%-END CERTIFICATE%-%-%-%-%-)")
                    if pem then parts[#parts + 1] = pem end
                end
            end
            p:close()
        end
        if #parts > 0 then break end
    end
    if #parts == 0 then return end
    local w = io.open(M.CA_FILE .. ".tmp", "wb")
    if w then
        w:write(table.concat(parts, "\n"), "\n"); w:close()
        os.rename(M.CA_FILE .. ".tmp", M.CA_FILE)
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
