-- Cover thread: decodes the covers My Books shows, so moving through the list
-- never waits for a picture (a big cover takes half a second on GammaOS).
-- Jobs on "cover_jobs": { path, name, data } (the image file's bytes); replies
-- on "cover_out": { path, image = ImageData } or { path, error }.
require("love.filesystem")
require("love.image")
require("love.timer")

-- (Started with other channels' names, the same work for a comic's next
-- pages: "page_jobs", "page_out".)
local jobs_name, out_name = ...
-- LÖVE runs Lua without its compiler on Android; shrinking a page here walks
-- every pixel, many times faster with it.
if jit and not jit.status() then pcall(jit.on) end
print(string.format("[thread] %s: compiler %s", jobs_name or "cover_jobs", jit and (jit.status() and "on" or "off") or "none"))
local jobs = love.thread.getChannel(jobs_name or "cover_jobs")
local out = love.thread.getChannel(out_name or "cover_out")

while true do
    local job = jobs:demand()
    if job == "quit" then break end
    local ok, id = pcall(function()
        local t0 = love.timer and love.timer.getTime()
        local id = love.image.newImageData(love.filesystem.newFileData(job.data, job.name))
        local t1 = love.timer and love.timer.getTime()
        -- Shrunk here (job.fit: { w, h, wide: a spread may be twice as wide }),
        -- so only the small copy goes back: the full picture can be 20 MB.
        if job.fit then
            local w, h = id:getDimensions()
            local mw = job.fit.w * ((job.fit.wide and w > h * 1.1) and 2 or 1)
            local small = require("imgscale").fit(id, mw, job.fit.h)
            if small ~= id then id:release(); id = small end
            if t0 then
                print(string.format("[thread] %s: decoded in %.2fs, shrunk in %.2fs", tostring(job.name):match("[^/]*$"):sub(-40),
                    t1 - t0, love.timer.getTime() - t1))
            end
        end
        return id
    end)
    job.data = nil
    if ok then out:push({ path = job.path, name = job.name, image = id })
    else out:push({ path = job.path, name = job.name, error = tostring(id) }) end
end
