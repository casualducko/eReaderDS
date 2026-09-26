-- Network thread: runs one job at a time from the "net_jobs" channel so the
-- UI never blocks on Wi-Fi. Jobs: { id, kind = "fetch" | "download", url,
-- user, password, verify, dest }. Replies on "net_out":
--   { id, kind = "progress", got, total }   (downloads, a few times a second)
--   { id, kind = "done", body }             (fetch: the body; download: none)
--   { id, kind = "error", message }
-- Pushing anything to "net_cancel" stops the running download.
require("love.filesystem")
require("love.data")
require("love.timer")
local Net = require("net")

local jobs = love.thread.getChannel("net_jobs")
local out = love.thread.getChannel("net_out")
local cancel = love.thread.getChannel("net_cancel")

local function run(job)
    local opts = { user = job.user, password = job.password, verify = job.verify }
    if job.kind == "fetch" then
        local body, final = Net.get(job.url, opts)
        out:push({ id = job.id, kind = "done", body = body, url = final })
        return
    end

    -- download: write to dest..".part", then rename once it's complete.
    local part = job.dest .. ".part"
    local f, err = io.open(part, "wb")
    if not f then error("couldn't write to the SD card (" .. tostring(err) .. ")", 0) end
    local got, last = 0, 0
    opts.sink = function(chunk, total)
        if cancel:pop() then error("cancelled", 0) end
        f:write(chunk)
        got = got + #chunk
        local now = love.timer.getTime()
        if now - last > 0.2 then
            last = now
            out:push({ id = job.id, kind = "progress", got = got, total = total or job.size or 0 })
        end
    end
    local ok, e = pcall(Net.get, job.url, opts)
    f:close()
    if not ok then os.remove(part); error(e, 0) end
    os.remove(job.dest)
    if not os.rename(part, job.dest) then
        os.remove(part)
        error("couldn't save the book on the SD card", 0)
    end
    out:push({ id = job.id, kind = "done", got = got })
end

while true do
    local job = jobs:demand()
    if job.kind == "quit" then break end
    cancel:clear()
    local ok, err = pcall(run, job)
    if not ok then
        out:push({ id = job.id, kind = "error", message = tostring(err):gsub("^[^:]*:%d+: ", "") })
    end
end
