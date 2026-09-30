-- Cover thread: decodes the covers My Books shows, so moving through the list
-- never waits for a picture (a big cover takes half a second on GammaOS).
-- Jobs on "cover_jobs": { path, name, data } (the image file's bytes); replies
-- on "cover_out": { path, image = ImageData } or { path, error }.
require("love.filesystem")
require("love.image")

local jobs = love.thread.getChannel("cover_jobs")
local out = love.thread.getChannel("cover_out")

while true do
    local job = jobs:demand()
    if job == "quit" then break end
    local ok, id = pcall(function()
        return love.image.newImageData(love.filesystem.newFileData(job.data, job.name))
    end)
    job.data = nil
    if ok then out:push({ path = job.path, image = id })
    else out:push({ path = job.path, error = tostring(id) }) end
end
