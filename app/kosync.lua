-- KOReader sync: the progress-sync protocol of KOReader's sync server
-- (sync.koreader.rocks, or your own), so a book read here and in KOReader on
-- a phone or e-reader picks up where the other left off. The same rules as
-- KOReader's kosync plugin (plugins/kosync.koplugin):
--   a book is known by its "document": the MD5 of eleven 1 KB samples of the
--   file (util.partialMD5), or the MD5 of its file name;
--   the account's key is the MD5 of the password; requests carry
--   x-auth-user and x-auth-key;
--   GET /users/auth (200 = logged in), POST /users/create (201 = made,
--   402 = the name is taken), GET /syncs/progress/<document>,
--   PUT /syncs/progress { document, progress, percentage, device, device_id }.
local M = {}

-- The servers to choose from: CrossPoint's (the default: the Xteink crowd
-- is already on it, and it has been the more reliable) and KOReader's own.
-- Any other address is "your own". Both devices must use the same one.
M.SERVERS = { crosspoint = "https://sync.crosspointreader.com", koreader = "https://sync.koreader.rocks" }
M.SERVER_NAMES = { crosspoint = "CrossPoint", koreader = "KOReader", custom = "Your own" }
M.DEFAULT_SERVER = M.SERVERS.crosspoint
M.DEVICE = "RG DS Plus"
M.TIMEOUT = 8        -- seconds to connect and to start answering (quitting waits for a request)

local function md5hex(s) return love.data.encode("string", "hex", love.data.hash("md5", s)) end
M.md5 = md5hex

-- KOReader's util.partialMD5: 1 KB at 0, then at 1024 << 2i for i = 0..10
-- (1 KB, 4 KB, 16 KB ... 1 GB), until past the end of the file.
function M.partial_md5(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local parts = {}
    for i = -1, 10 do
        f:seek("set", i < 0 and 0 or 1024 * 4 ^ i)
        local s = f:read(1024)
        if not s then break end
        parts[#parts + 1] = s
    end
    f:close()
    return md5hex(table.concat(parts))
end

-- The book's "document" name on the server. method: "binary" (the file's
-- contents, KOReader's default) or "filename".
function M.document(path, method)
    if method == "filename" then return md5hex(path:match("([^/]+)$") or path) end
    return M.partial_md5(path)
end

-- The server's address without a trailing slash: for "crosspoint",
-- "koreader", "custom" (then `custom` is the address) or an address.
function M.server(s, custom)
    if M.SERVERS[s] then return M.SERVERS[s] end
    if s == "custom" then s = custom end
    s = (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if s == "" then s = M.DEFAULT_SERVER end
    if not s:match("^https?://") then s = "https://" .. s end
    return (s:gsub("/+$", ""))
end

function M.headers(user, key)
    return { Accept = "application/vnd.koreader.v1+json", ["x-auth-user"] = user, ["x-auth-key"] = key }
end

-- A network job (for shop.net_job) for each request.
function M.auth_job(server, user, key)
    return { kind = "call", method = "GET", url = M.server(server) .. "/users/auth", headers = M.headers(user, key),
        timeout = M.TIMEOUT }
end

function M.register_job(server, user, key)
    local h = { Accept = "application/vnd.koreader.v1+json" }
    return { kind = "call", method = "POST", url = M.server(server) .. "/users/create", headers = h,
        body = require("json").encode({ username = user, password = key }), timeout = M.TIMEOUT }
end

function M.get_job(server, user, key, doc)
    return { kind = "call", method = "GET", url = M.server(server) .. "/syncs/progress/" .. doc,
        headers = M.headers(user, key), timeout = M.TIMEOUT }
end

-- metadata (optional, "Send book details"): { filename, title, authors },
-- as KOReader sends it; its own server ignores it, others may show it.
function M.put_job(server, user, key, doc, progress, percentage, device_id, metadata)
    return { kind = "call", method = "PUT", url = M.server(server) .. "/syncs/progress", headers = M.headers(user, key),
        body = require("json").encode({ document = doc, progress = progress,
            percentage = math.floor(percentage * 10000 + 0.5) / 10000,
            device = M.DEVICE, device_id = device_id, metadata = metadata }), timeout = M.TIMEOUT }
end

return M
