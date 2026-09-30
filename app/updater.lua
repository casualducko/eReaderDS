-- Updates from GitHub releases: find a newer release, and unpack the files
-- that changed into a waiting folder beside the app (APP_DIR/.delta). The
-- launcher moves them into place the next time eReaderDS starts (launch.sh),
-- so the running app is never overwritten. Settings, progress and books live
-- elsewhere.
local Json = require("json")
local Zip = require("zip")

local M = {}

M.RELEASES = "https://api.github.com/repos/casualducko/eReaderDS/releases?per_page=5"

-- The folder the app runs from (Ports/eReaderDS or roms/ports/eReaderDS).
function M.app_dir()
    return (love.filesystem.getSource():gsub("/app/?$", ""))
end

-- "0.3.10" > "0.3.9".
function M.newer(a, b)
    local pa, pb = {}, {}
    for n in tostring(a):gmatch("%d+") do pa[#pa + 1] = tonumber(n) end
    for n in tostring(b):gmatch("%d+") do pb[#pb + 1] = tonumber(n) end
    for i = 1, math.max(#pa, #pb) do
        local x, y = pa[i] or 0, pb[i] or 0
        if x ~= y then return x > y end
    end
    return false
end

-- Release notes as plain text (the changelog's Markdown, lightly cleaned).
local function plain(md)
    md = (md or ""):gsub("\r", "")
    md = md:gsub("%*%*(.-)%*%*", "%1"):gsub("`([^`]*)`", "%1")
    md = md:gsub("%[([^%]]*)%]%([^)]*%)", "%1")
    md = md:gsub("\n%s*%- ", "\n• "):gsub("^%s*%- ", "• ")
    md = md:gsub("\n  +", " ")                      -- wrapped list lines
    return (md:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- The newest release that's newer than `current` and has the app's zip (or,
-- on Android, its APK): { version, url, size, notes } or nil. Tags with a
-- suffix (v1.3.0-beta, pre-releases for testing) don't match, so they're
-- never offered.
M.ASSET = type(love) == "table" and love.system and love.system.getOS() == "Android" and "^eReaderDS%-v.*%-android%.apk$" or "^eReaderDS%-v.*%.zip$"
function M.parse(body, current)
    local ok, list = pcall(Json.decode, body)
    if not ok or type(list) ~= "table" then return nil, "couldn't read the release list" end
    local best
    for _, r in ipairs(list) do
        local v = type(r) == "table" and not r.draft and not r.prerelease and tostring(r.tag_name or ""):match("^v?(%d[%d%.]*)$")
        if v and M.newer(v, current) and (not best or M.newer(v, best.version)) then
            for _, a in ipairs(r.assets or {}) do
                if tostring(a.name or ""):match(M.ASSET) and a.browser_download_url then
                    best = { version = v, url = a.browser_download_url, size = a.size, notes = plain(r.body) }
                end
            end
        end
    end
    return best
end

-- The plain-words notes (whatsnew.txt) for a release, to show before updating.
function M.whatsnew_url(version)
    return "https://raw.githubusercontent.com/casualducko/eReaderDS/v" .. version .. "/app/whatsnew.txt"
end

-- The versions in a whatsnew.txt newer than `current`, newest first:
-- { { version = "0.3.12", items = { "...", ... } }, ... }
function M.whatsnew_since(text, current)
    local out, cur = {}, nil
    for line in (text or ""):gmatch("[^\n]+") do
        if not line:match("^#") and line:match("%S") then
            local v = line:match("^v(%d[%d%.]*)%s*$")
            if v then
                cur = M.newer(v, current) and { version = v, items = {} } or nil
                if cur then out[#out + 1] = cur end
            elseif cur then
                cur.items[#cur.items + 1] = line
            end
        end
    end
    return out
end

local function mkdir(p) os.execute('mkdir -p "' .. p .. '"') end

-- Flush everything to the SD card on a thread, yielding meanwhile (the
-- screen stays live: on a slow card this takes a while).
local function sync_yielding()
    -- (A code string needs a newline, or LÖVE takes it for a file name.)
    local t = love.thread.newThread('os.execute("sync")\n')
    t:start()
    while t:isRunning() do coroutine.yield(1, "saving") end
end

-- Write a file and check it's all there (a full card shows up at close).
local function write_file(path, data)
    local f = io.open(path, "wb")
    if not f then return false end
    local ok = f:write(data)
    ok = f:close() and ok
    if not ok then return false end
    local chk = io.open(path, "rb")
    local size = chk and chk:seek("end")
    if chk then chk:close() end
    return size == #data
end

local function read_file(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    return data
end

-- Unpack the files of the release zip that differ from the installed ones
-- into dest (APP_DIR/.delta): Ports/eReaderDS/... -> dest/eReaderDS/...,
-- Ports/eReaderDS.sh and Ports/Imgs/eReaderDS.png beside it. Most of the app
-- (fonts, dictionary, engine) rarely changes, and a slow SD card can take a
-- minute to save all of it. Files of the installed app/ folder that the new
-- version doesn't have are listed in dest/DELETE. Meant to run in a
-- coroutine: yields after each file with the fraction done. Checks that it's
-- a whole app for the expected version.
function M.unpack(zip_path, dest, version)
    local app_dir = dest:match("^(.*)/[^/]+$")
    local ports = app_dir:match("^(.*)/[^/]+$")
    local z, err = Zip.open(zip_path)
    if not z then error("the download isn't a zip file (" .. tostring(err) .. ")", 0) end
    local names = {}
    for name in pairs(z.entries) do
        if name:match("^Ports/") and not name:match("/$") and not name:match("/%._") then
            -- Only plain paths inside Ports/ (they go into shell commands too).
            if name:match("%.%.") or name:find("[%c\\\"`$]") then
                z:close(); error("the download has a file with a strange name", 0)
            end
            names[#names + 1] = name
        end
    end
    table.sort(names)
    local need = { ["Ports/eReaderDS/app/main.lua"] = true, ["Ports/eReaderDS/launch.sh"] = true,
        ["Ports/eReaderDS/app/version.lua"] = true }
    for _, n in ipairs(names) do need[n] = nil end
    if next(need) then z:close(); error("the download is missing parts of the app", 0) end
    local vfile = z:read("Ports/eReaderDS/app/version.lua") or ""
    if vfile:match('"(.-)"') ~= version then z:close(); error("the download is a different version", 0) end
    os.execute('rm -rf "' .. dest .. '"')
    mkdir(dest)
    local made, in_zip = {}, {}
    for i, name in ipairs(names) do
        local rel = name:gsub("^Ports/", "")             -- eReaderDS/app/main.lua, eReaderDS.sh, ...
        local installed = rel:match("^eReaderDS/") and (app_dir .. rel:gsub("^eReaderDS", ""))
            or (ports .. "/" .. rel)
        in_zip[installed] = true
        local data, rerr = z:read(name)
        if not data then z:close(); error("couldn't unpack " .. name .. ": " .. tostring(rerr), 0) end
        if read_file(installed) ~= data then
            local out = dest .. "/" .. rel
            local dir = out:match("^(.*)/")
            if not made[dir] then mkdir(dir); made[dir] = true end
            if not write_file(out, data) then
                z:close()
                error("couldn't write to the SD card (is it full?)", 0)
            end
        end
        coroutine.yield(i / #names)
    end
    z:close()
    -- Files of the old app/ folder that aren't in the new version.
    local gone = {}
    local ls = io.popen('cd "' .. app_dir .. '" && find app -type f 2>/dev/null')
    if ls then
        for line in ls:lines() do
            if not in_zip[app_dir .. "/" .. line] then gone[#gone + 1] = line end
        end
        ls:close()
    end
    if #gone > 0 then
        if not write_file(dest .. "/DELETE", table.concat(gone, "\n") .. "\n") then
            error("couldn't write to the SD card", 0)
        end
    end
    -- The zip first, so its unsaved data needn't be written to the card at all.
    os.remove(zip_path)
    -- The files, then the marker that tells the launcher they're complete
    -- (so it never finds the marker without them).
    sync_yielding()
    if not write_file(dest .. "/READY", version .. "\n") then error("couldn't write to the SD card", 0) end
    sync_yielding()
end

return M
