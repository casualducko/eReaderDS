-- Running on Android: GammaOS on the RG DS Plus (and other dual-screen
-- Android handhelds that stack both screens into one tall window).
--
-- GammaOS's "DualStack" gives an app on its list one window across both
-- screens, the top one above the bottom one (1024x1536). eReaderDS draws its
-- usual 2048x768 frame (the two screens side by side, as on Linux) into a
-- canvas and shows its halves one above the other. Without DualStack the app
-- gets only the top screen, and the setup here puts it on the list (a GammaOS
-- setting any app may change: no root needed).
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

---------------------------------------------------------------- without a shell

-- Starting a command (getprop, mkdir, ls, find) copies the whole app process
-- first, which on Android costs about a third of a second each time; startup
-- ran about ten. These do the same through the C library directly.
local ffi = require("ffi")
for _, decl in ipairs({
    "int __system_property_get(const char *name, char *value);",
    "int __system_property_set(const char *name, const char *value);",
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

-- Set one; true if it took. (GammaOS lets any app change its own settings,
-- the persist.gammaos.* ones, and restart its services.)
function M.setprop(name, value)
    local ok = pcall(C.__system_property_set, name, value)
    return ok and (name:sub(1, 4) == "ctl." or M.getprop(name) == value)
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

-- Our own bits of Java (android/smali/), called through JNI: LÖVE has no
-- hook for what they do. Each is a static method taking the activity first.
pcall(ffi.cdef, [[
    typedef union { int32_t i; float f; void *l; int64_t j; } rgds_jvalue;
    void *SDL_AndroidGetJNIEnv(void);
    void *SDL_AndroidGetActivity(void);
]])
local jni
local function jni_setup()
    local ok, love_lib = pcall(ffi.load, "love")
    if not ok then return false end
    local env = love_lib.SDL_AndroidGetJNIEnv()
    if env == nil then return false end
    local fn = ffi.cast("void ***", env)[0]
    local function f(i, sig) return ffi.cast(sig, fn[i]) end
    return {
        env = env, lib = love_lib, methods = {}, args = ffi.new("rgds_jvalue[4]"),
        FindClass = f(6, "void *(*)(void *, const char *)"),
        ExceptionClear = f(17, "void (*)(void *)"),
        NewGlobalRef = f(21, "void *(*)(void *, void *)"),
        DeleteLocalRef = f(23, "void (*)(void *, void *)"),
        GetStaticMethodID = f(113, "void *(*)(void *, void *, const char *, const char *)"),
        CallStaticVoidMethodA = f(143, "void (*)(void *, void *, void *, const rgds_jvalue *)"),
        NewStringUTF = f(167, "void *(*)(void *, const char *)"),
        ExceptionCheck = f(228, "uint8_t (*)(void *)"),
    }
end
-- The class and method, looked up once; nil if they aren't there.
local function jni_method(class, name, sig)
    if jni == nil then
        local ok, J = pcall(jni_setup)
        jni = ok and J or false
        if not jni then print("[android] JNI unavailable") end
    end
    if not jni then return nil end
    local J, env, key = jni, jni.env, class .. "." .. name
    if J.methods[key] == nil then
        J.methods[key] = false
        local cls = J.FindClass(env, class)
        if cls ~= nil and J.ExceptionCheck(env) == 0 then
            local id = J.GetStaticMethodID(env, cls, name, sig)
            if id ~= nil and J.ExceptionCheck(env) == 0 then
                J.methods[key] = { cls = J.NewGlobalRef(env, cls), id = id }
            end
            J.DeleteLocalRef(env, cls)
        end
        if J.ExceptionCheck(env) ~= 0 then J.ExceptionClear(env) end
        if not J.methods[key] then print("[android] no " .. key) end
    end
    return J.methods[key] or nil
end
-- Call one: the activity, then each argument (a string, or a number passed
-- as a float). True if it ran without a Java exception.
local function jni_call(class, name, sig, ...)
    local m = jni_method(class, name, sig)
    if not m then return false end
    local J, env = jni, jni.env
    local act = J.lib.SDL_AndroidGetActivity()
    if act == nil then return false end
    local refs = { act }
    J.args[0].l = act
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if type(v) == "string" then
            local str = J.NewStringUTF(env, v)
            refs[#refs + 1] = str
            J.args[i].l = str
        else
            J.args[i].f = v
        end
    end
    J.CallStaticVoidMethodA(env, m.cls, m.id, J.args)
    local failed = J.ExceptionCheck(env) ~= 0
    if failed then J.ExceptionClear(env) end
    for _, r in ipairs(refs) do J.DeleteLocalRef(env, r) end
    return not failed
end

-- The screens' brightness, without root: Android lets an app set it for its
-- own window while that's showing (the system's own setting is back once it
-- closes). value 0..1, or -1 for the system's own; false if it couldn't be done.
local BRIGHT = { "com/casualducko/ereaderds/Bright", "set", "(Landroid/app/Activity;F)V" }
function M.window_brightness_ok()
    return jni_method(BRIGHT[1], BRIGHT[2], BRIGHT[3]) ~= nil
end
function M.window_brightness(value)
    return jni_call(BRIGHT[1], BRIGHT[2], BRIGHT[3], value)
end

-- Install a downloaded update (an APK) without root: Android's installer,
-- which lets an app update itself without asking (android/smali/.../Install).
-- It works on in the background; M.install_status() says how it's going:
-- "installing", "confirm" (Android asked the reader after all), or "error"
-- and a message. When it's done Android stops the app.
M.INSTALL_STATUS = M.DATA .. "/.update.status"
function M.install_update(apk)
    os.remove(M.INSTALL_STATUS)
    return jni_call("com/casualducko/ereaderds/Install", "start",
        "(Landroid/app/Activity;Ljava/lang/String;Ljava/lang/String;)V", apk, M.INSTALL_STATUS)
end
function M.install_status()
    local f = io.open(M.INSTALL_STATUS, "rb")
    if not f then return "installing" end
    local s = f:read("*a") or ""
    f:close()
    if s == "" or s == "committed" or s:match("^0 ") then return "installing" end
    if s:match("^%-1 ") then return "confirm" end
    local msg = s:match("^error (.*)") or s:match("^%-?%d+ (.*)") or s
    return "error", (msg == "null" or msg == "") and "Android couldn't install it." or msg
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

-- GammaOS turns the Anbernic button into its Control Center for every app.
-- A per-app gamepad profile for eReaderDS (GammaOS's own feature) gives it
-- back as the controller's guide button, which quits, as on Linux. Nothing
-- is changed if eReaderDS has a profile already (the reader's own).
-- Returns whether there's one now, and whether it was just added.
function M.gamepad_profile()
    local g = "persist.gammaos.gamepad.pa"
    local n = tonumber(M.getprop(g .. "_count")) or 0
    for i = 0, n - 1 do
        if M.getprop(g .. i .. "_pkg") == M.PACKAGE then return true, false end
    end
    local ok = M.setprop(g .. n .. "_pkg", M.PACKAGE) and M.setprop(g .. n .. "_btn", "316:316")
        and M.setprop(g .. "_count", tostring(n + 1))
    if ok then M.setprop("ctl.restart", "gammapad") end   -- (it reads profiles when it starts)
    return ok, ok
end

-- GammaOS's front end sometimes comes back from an app with its icons gone;
-- asking it to refresh its apps list (a new value each time) redraws them.
function M.refresh_front_end()
    M.setprop("sys.gammaos.nano.apps_refresh_req", tostring(os.time()))
end

-- DualStack's list: persist.gammaos.dualstack.pkgs, comma-separated, and when
-- that's full (a setting holds 91 characters) pkgs_1, pkgs_2, ... after it.
local function dualstack_add()
    local base = "persist.gammaos.dualstack.pkgs"
    local names, i = { base }, 1
    while true do
        local n = base .. "_" .. i
        if M.getprop(n) == "" then break end
        names[#names + 1] = n
        i = i + 1
    end
    for _, n in ipairs(names) do
        for p in M.getprop(n):gmatch("[^,%s]+") do
            if p == M.PACKAGE then return true end
        end
    end
    local last = M.getprop(names[#names])
    local joined = last ~= "" and (last .. "," .. M.PACKAGE) or M.PACKAGE
    if #joined <= 91 then return M.setprop(names[#names], joined) end
    return M.setprop(base .. "_" .. i, M.PACKAGE)
end

-- One-time setup: all-files access, and the DualStack list. Returns a
-- heading and a message when something's left for the reader to do, else nil.
function M.setup()
    -- An update installed since the last launch: its download isn't needed.
    for _, f in ipairs({ M.DATA .. "/.update.apk", M.INSTALL_STATUS }) do
        if C.access(f, 0) == 0 then os.remove(f) end
    end
    if not M.storage_ok() then
        return "Almost there", "eReaderDS can't use the Ebook folder yet.\n\n"
            .. "Open the Quick Menu → System Settings → Apps → eReaderDS → Permissions, "
            .. "and allow access to all files. Then press A to close eReaderDS and open it again."
    end
    if not M.stacked() then
        if dualstack_add() then
            M.gamepad_profile()
            return "One more step!", "Press A to close eReaderDS, then open it again.\n\n"
                .. "From then on it opens on both screens."
        end
        -- (GammaOS wouldn't take the setting: the reader can add it by hand.)
        return "Almost there", "To use both screens, add eReaderDS to GammaOS's DualStack list.\n\n"
            .. "Open the Quick Menu → System Settings → GammaOS Toolbox → Allowed packages, and add "
            .. "a comma and " .. M.PACKAGE .. " to the end. Then press A to close eReaderDS and open it again."
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
