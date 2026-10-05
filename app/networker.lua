-- Network thread: runs one job at a time from the "net_jobs" channel so the
-- UI never blocks on Wi-Fi. Jobs: { id, kind = "fetch" | "feed" | "download",
-- url, user, password, verify, dest }. Replies on "net_out":
--   { id, kind = "progress", got, total }   (downloads, a few times a second)
--   { id, kind = "done", body }             (fetch: the body; download: none)
--   { id, kind = "done", feed, url }        (feed: the catalog page, parsed
--                                            here so a big one doesn't stall the screen)
--   { id, kind = "error", message }
-- Pushing a download's job id to "net_cancel" stops that download; pushing
-- true (on quitting) stops whatever is running.
require("love.filesystem")
require("love.data")
require("love.timer")
local Net = require("net")
local Opds = require("opds")

local jobs = love.thread.getChannel("net_jobs")
local out = love.thread.getChannel("net_out")
local cancel = love.thread.getChannel("net_cancel")
-- Quitting pushes true: stop waiting on any server at once. Cancelling the
-- running job (its id) does too, even while the server sends nothing.
local running
-- (Cancels for jobs already over are dropped here: one left at the head
-- would hide a later cancel until the next job's data arrived.)
Net.abort = function()
    local c = cancel:peek()
    while type(c) == "number" and running ~= nil and c < running do
        cancel:pop()
        c = cancel:peek()
    end
    return c == true or (running ~= nil and c == running)
end

local function run(job)
    local opts = { user = job.user, password = job.password, verify = job.verify }
    if job.kind == "fetch" then
        local body, final = Net.get(job.url, opts)
        out:push({ id = job.id, kind = "done", body = body, url = final })
        return
    end
    if job.kind == "call" then           -- any method and body: { status, body }
        local status, body = Net.call(job.method, job.url, { headers = job.headers, body = job.body, verify = job.verify,
            timeout = job.timeout })
        out:push({ id = job.id, kind = "done", status = status, body = body })
        return
    end
    if job.kind == "feed" then
        local body, final = Net.get(job.url, opts)
        local ok, feed = pcall(Opds.parse_feed, body, final or job.url)
        body = nil
        if not ok then error(tostring(feed):gsub("^[^:]*:%d+: ", ""), 0) end
        out:push({ id = job.id, kind = "done", feed = feed, url = final })
        return
    end

    -- download: write to dest..".part", then rename once it's complete.
    local part = job.dest .. ".part"
    local f, err = io.open(part, "wb")
    if not f then error("couldn't write to the SD card (" .. tostring(err) .. ")", 0) end
    local got, last = 0, 0
    opts.sink = function(chunk, total)
        -- Cancels for earlier jobs are stale; one for a later job waits.
        while true do
            local c = cancel:peek()
            if not c or (type(c) == "number" and c > job.id) then break end
            cancel:pop()
            if c == job.id or c == true then error("cancelled", 0) end
        end
        if not f:write(chunk) then error("couldn't write to the SD card (is it full?)", 0) end
        got = got + #chunk
        local now = love.timer.getTime()
        if now - last > 0.2 then
            last = now
            out:push({ id = job.id, kind = "progress", got = got, total = total or job.size or 0 })
        end
    end
    local ok, e = pcall(Net.get, job.url, opts)
    if not f:close() and ok then ok, e = false, "couldn't write to the SD card (is it full?)" end
    -- An EPUB is a zip: it must start with a zip header and end with the zip
    -- directory, or the download was cut short.
    if ok and job.dest:lower():match("%.epub$") then
        local chk = io.open(part, "rb")
        local head = chk and chk:read(4)
        local size = chk and chk:seek("end") or 0
        local tail = ""
        if chk then chk:seek("set", math.max(0, size - 65557)); tail = chk:read("*a") or ""; chk:close() end
        if head ~= "PK\3\4" or not tail:find("PK\5\6", 1, true) then
            ok, e = false, "the download was incomplete"
        end
    end
    if not ok then os.remove(part); error(e, 0) end
    -- rename() replaces an old copy in one step (removing it first only if
    -- that isn't allowed), so a failure never leaves neither.
    if not os.rename(part, job.dest) and not (os.remove(job.dest) and os.rename(part, job.dest)) then
        os.remove(part)
        error("couldn't save the book on the SD card", 0)
    end
    out:push({ id = job.id, kind = "done", got = got })
end

while true do
    local job = jobs:demand()
    if job.kind == "quit" then break end
    running = job.id
    local ok, err = pcall(run, job)
    running = nil
    -- This job's cancel (it may have stopped it before any data came) and
    -- any older ones: done with.
    while type(cancel:peek()) == "number" and cancel:peek() <= job.id do cancel:pop() end
    if not ok then
        out:push({ id = job.id, kind = "error", message = tostring(err):gsub("^[^:]*:%d+: ", "") })
    end
end
