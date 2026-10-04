-- The backup thread: makes or restores one backup (backup.lua), so a big one
-- doesn't stop the screens. Started with { kind = "backup", out, root,
-- data_dir, whole, manifest }, { kind = "restore", zip, root, data_dir,
-- before (a backup of the current settings to make first) }, or { kind =
-- "reset", root, data_dir, before }: the settings backed up, then cleared
-- (only if that backup was made).
-- Reports on "backup_out": { kind = "step", text } (what it's doing now),
-- { kind = "progress", done, total },
-- { kind = "done" }, or { kind = "failed", message }.
require("love.data")
require("love.timer")
local Backup = require("backup")

local job = ...
local out = love.thread.getChannel("backup_out")
local last = 0
local function progress(done, total)
    local now = love.timer.getTime()
    if now - last > 0.25 then
        last = now
        out:push({ kind = "progress", done = done, total = total })
    end
end

local function step(text) out:push({ kind = "step", text = text }) end

local ok, err, skipped, partial
if job.kind == "reset" then
    step("Backing up your settings first…")
    local files = Backup.collect(job.root, job.data_dir, false)
    Backup.mkdir_p(job.before.out:match("^(.*)/"))
    ok, err = Backup.write(job.before.out, files, job.before.manifest, job.root)
    if ok then
        Backup.prune(job.before.out:match("^(.*)/"), 3, { job.before.out })
        step("Clearing…")
        for _, f in ipairs(files) do os.remove(f.path); os.remove(f.path .. ".bak") end    -- (their safety copies too)
    else
        err = "the backup couldn't be made first, so nothing was cleared (" .. tostring(err) .. ")"
    end
elseif job.kind == "backup" then
    local files = Backup.collect(job.root, job.data_dir, job.whole)
    Backup.mkdir_p(job.out:match("^(.*)/"))
    ok, err = Backup.write(job.out, files, job.manifest, job.root, progress)
else
    -- First, what's here now (settings and reading), in case it was the
    -- wrong backup.
    -- (Not restored without it: it's the way back. Nor ever over, or pruning,
    -- the backup being restored.)
    if job.before then
        step("Backing up your settings first…")
        Backup.mkdir_p(job.before.out:match("^(.*)/"))
        if job.before.out == job.zip then job.before.out = job.before.out:gsub("%.zip$", "-2.zip") end
        ok, err = Backup.write(job.before.out, Backup.collect(job.root, job.data_dir, false), job.before.manifest, job.root)
        if ok then Backup.prune(job.before.out:match("^(.*)/"), 3, { job.before.out, job.zip }) end
    else
        ok = true
    end
    if not ok then
        err = "a copy of your settings couldn't be made first, so nothing was restored (" .. tostring(err) .. ")"
    else
        step("Restoring…")
        ok, err, partial = Backup.restore(job.zip, job.root, job.data_dir, progress, job.same_system)
        skipped = ok and err or 0
    end
end
-- (Onto the card now, while it says so, rather than as the app closes.)
if ok and job.kind ~= "backup" and not job.android then
    step("Saving to the SD card…")
    os.execute("sync")
end
if ok then out:push({ kind = "done", skipped = skipped })
else out:push({ kind = "failed", message = tostring(err), partial = partial }) end
