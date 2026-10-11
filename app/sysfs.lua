-- Folders and free space without a shell, for iOS (where io.popen and
-- os.execute don't exist) and from any thread: android.lua can't be loaded in
-- a thread (it wants the graphics module), and the Wi-Fi receiver, Calibre and
-- the dictionary scan ran `ls`, `find` and `df`. On the other systems those
-- still do (df, which has no one layout to read), but folders are walked here.
--   M.ios                      true on iOS
--   M.ls(dir, hidden)          names in a folder (hidden ones too if asked), sorted
--   M.find(dir, depth, keep)   paths of the files below dir, `depth` folders deep, keep(name) true
--   M.free_bytes(dir)          available, total bytes where dir is (nil if it can't be told)
local ffi = require("ffi")
local M = {}

local ok_sys = pcall(require, "love.system")
M.ios = ok_sys and love.system.getOS() == "iOS"

-- (Declared one at a time, and the same as android.lua's, which may have been first.
-- The folder entry's layout is Linux's and Android's, or Darwin's.)
local decls = {
    "typedef struct rgds_DIR rgds_DIR;",
    ffi.os == "OSX"
        and "struct rgds_dirent { uint64_t d_ino; uint64_t d_seekoff; uint16_t d_reclen; uint16_t d_namlen; uint8_t d_type; char d_name[1024]; };"
        or "struct rgds_dirent { uint64_t d_ino; int64_t d_off; unsigned short d_reclen; unsigned char d_type; char d_name[256]; };",
    "rgds_DIR *opendir(const char *name);",
    "struct rgds_dirent *readdir(rgds_DIR *dir);",
    "int closedir(rgds_DIR *dir);",
}
if M.ios then
    -- Darwin's struct statfs (the 64-bit inode one, which is all there is on arm64).
    decls[#decls + 1] = "struct rgds_statfs { uint32_t f_bsize; int32_t f_iosize; uint64_t f_blocks; uint64_t f_bfree; uint64_t f_bavail;"
        .. " uint64_t f_files; uint64_t f_ffree; int32_t f_fsid[2]; uint32_t f_owner; uint32_t f_type; uint32_t f_flags;"
        .. " uint32_t f_fssubtype; char f_fstypename[16]; char f_mntonname[1024]; char f_mntfromname[1024];"
        .. " uint32_t f_flags_ext; uint32_t f_reserved[7]; };"
    decls[#decls + 1] = "int statfs(const char *path, struct rgds_statfs *buf);"
end
for _, decl in ipairs(decls) do pcall(ffi.cdef, decl) end
local C = ffi.C
local DT_DIR, DT_UNKNOWN = 4, 0

local function entries(dir)
    local out = {}
    local ok, d = pcall(C.opendir, dir)
    if not ok or d == nil then return out end
    while true do
        local e = C.readdir(d)
        if e == nil then break end
        local name = ffi.string(e.d_name)
        if name ~= "." and name ~= ".." then
            local isdir = e.d_type == DT_DIR
            if e.d_type == DT_UNKNOWN then
                local sub = C.opendir(dir .. "/" .. name)
                isdir = sub ~= nil
                if isdir then C.closedir(sub) end
            end
            out[#out + 1] = { name = name, dir = isdir }
        end
    end
    C.closedir(d)
    return out
end

function M.ls(dir, hidden)
    local names = {}
    for _, e in ipairs(entries(dir)) do
        if hidden or e.name:sub(1, 1) ~= "." then names[#names + 1] = e.name end
    end
    table.sort(names)
    return names
end

function M.find(dir, depth, keep)
    local found = {}
    local function walk(d, left)
        for _, e in ipairs(entries(d)) do
            if e.dir then
                if left > 1 then walk(d .. "/" .. e.name, left - 1) end
            elseif keep(e.name) then
                found[#found + 1] = d .. "/" .. e.name
            end
        end
    end
    walk(dir, depth)
    table.sort(found)
    return found
end

function M.free_bytes(dir)
    if not M.ios then return nil end
    local buf = ffi.new("struct rgds_statfs")
    local ok, rc = pcall(C.statfs, dir, buf)
    if not ok or rc ~= 0 then return nil end
    local size = tonumber(buf.f_bsize)
    return tonumber(buf.f_bavail) * size, tonumber(buf.f_blocks) * size
end

return M
