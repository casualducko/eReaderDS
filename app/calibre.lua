-- Calibre's "wireless device" connection, run on its own thread while the
-- "Connect to Calibre" screen is open. Calibre (Connect/share → Start wireless
-- device connection) is the server: this finds it (a UDP "hello" on the ports
-- it listens to for that, or an address typed in), connects, and answers what
-- it asks. Books it sends are saved under <books>/Calibre/, as Calibre names
-- them (its lpath); a small record in calibre.json (the data folder) remembers
-- them, so Calibre shows them as on the device and can delete them.
--
-- Messages both ways are "<length>[opcode, {…}]" (JSON); a book's bytes follow
-- its SEND_BOOK message as they are.
--
-- Started with { books = dir, data = dir, version, device }. Control on
-- "calibre_ctl" ("stop"); reports on "calibre_out":
--   { kind = "searching" }                      looking for Calibre
--   { kind = "connected", name }                talking to Calibre on <name>
--   { kind = "start", title, this, total, size }  a book is arriving
--   { kind = "progress", got, size }
--   { kind = "done", title, path }
--   { kind = "failed", title, message }
--   { kind = "deleted", path, title }
--   { kind = "message", text }                  Calibre's own message
--   { kind = "password" }                       Calibre wants a (different) password
--   { kind = "busy", name }                     Calibre is busy with another device
--   { kind = "lost", message }                  the connection went (looking again)
require("love.timer")
require("love.data")
local socket = require("socket")
local json = require("json")
local ffi = require("ffi")
pcall(ffi.cdef, "int mkdir(const char *path, unsigned int mode);")

local args = ...
local ctl = love.thread.getChannel("calibre_ctl")
local out = love.thread.getChannel("calibre_out")

local OP = { OK = 0, SET_CALIBRE_DEVICE_INFO = 1, SET_CALIBRE_DEVICE_NAME = 2, GET_DEVICE_INFORMATION = 3,
    TOTAL_SPACE = 4, FREE_SPACE = 5, GET_BOOK_COUNT = 6, SEND_BOOKLISTS = 7, SEND_BOOK = 8,
    GET_INITIALIZATION_INFO = 9, BOOK_DONE = 11, NOOP = 12, DELETE_BOOK = 13, GET_BOOK_FILE_SEGMENT = 14,
    GET_BOOK_METADATA = 15, SEND_BOOK_METADATA = 16, DISPLAY_MESSAGE = 17, CALIBRE_BUSY = 18,
    SET_LIBRARY_INFO = 19, ERROR = 20 }
local BROADCAST_PORTS = { 54982, 48123, 39001, 44044, 59678 }
local PACKET = 64 * 1024                       -- how much of a book Calibre sends at a time
local ROOT = args.books .. "/Calibre"           -- where its books go (and the only place it may delete)
local STORE = args.data .. "/calibre.json"

local function stopping()
    local c = ctl:pop()
    return c == "stop"
end

---------------------------------------------------------------- the record

-- { uuid = this device's id, info = what Calibre calls it, password,
--   servers = { { name, address = "host:port" }, ... } (computers saved to try
--   when Calibre can't be found by itself), last = the address used last,
--   books = { [lpath] = its metadata } }
local store
local function load_store()
    local f = io.open(STORE, "rb")
    local ok, s = false, nil
    if f then ok, s = pcall(json.decode, f:read("*a")); f:close() end
    store = ok and type(s) == "table" and s or {}
    store.books = type(store.books) == "table" and store.books or {}
    if type(store.uuid) ~= "string" or store.uuid == "" then      -- (none, or cleared by a restore from another system)
        local h = love.data.encode("string", "hex", love.data.hash("md5", tostring(os.time()) .. tostring(math.random())))
        store.uuid = h:sub(1, 8) .. "-" .. h:sub(9, 12) .. "-" .. h:sub(13, 16) .. "-" .. h:sub(17, 20) .. "-" .. h:sub(21, 32)
    end
end
-- (Written whole, then put in place: a full card mustn't leave a cut-short
-- file, which would lose the login and the list of books Calibre sent.)
local function save_store()
    local text = json.encode(store)
    local f = io.open(STORE .. ".tmp", "wb")
    if not f then return end
    local ok = f:write(text)
    ok = f:close() and ok
    local chk = ok and io.open(STORE .. ".tmp", "rb")
    ok = chk and chk:seek("end") == #text
    if chk then chk:close() end
    if ok then os.rename(STORE .. ".tmp", STORE) else os.remove(STORE .. ".tmp") end
end

-- What's kept of a book's metadata: enough for Calibre to recognise it (the
-- cover picture it sends along is left out).
local KEEP = { "title", "authors", "author_sort", "title_sort", "series", "series_index", "uuid",
    "last_modified", "size", "lpath", "languages", "tags", "pubdate", "timestamp", "publisher" }
local function brief(m)
    local b = {}
    for _, k in ipairs(KEEP) do b[k] = m[k] end
    return b
end

-- A Calibre path made safe to use under ROOT (no "..", no leading "/").
local function clean(lpath)
    local parts = {}
    for p in tostring(lpath or ""):gsub("\\", "/"):gmatch("[^/]+") do
        if p ~= "." and p ~= ".." then parts[#parts + 1] = p:gsub('[%c<>:"|%?%*]', "_") end
    end
    return table.concat(parts, "/")
end

local function mkdir_p(dir)
    local acc = ""
    for p in dir:gmatch("[^/]+") do
        acc = acc .. "/" .. p
        pcall(ffi.C.mkdir, acc, 493)             -- 0755; already there is fine
    end
end

local function exists(path)
    local f = io.open(path, "rb")
    if f then f:close() end
    return f ~= nil
end

-- Free and total space where the books go, in bytes.
local function space()
    local p = io.popen('df -k "' .. args.books .. '" 2>/dev/null | tail -1')
    local line = p and p:read("*a") or ""
    if p then p:close() end
    -- Size, used and available after the device's name (which busybox puts on
    -- a line of its own when it's long: then the line starts with the numbers).
    local nums = {}
    for n in (" " .. line):gmatch("%s(%d+)") do nums[#nums + 1] = tonumber(n) end
    return (nums[1] or 0) * 1024, (nums[3] or 0) * 1024
end

---------------------------------------------------------------- finding Calibre

-- This device's address on the network (for its subnet's broadcast address).
local function own_ip()
    local u = socket.udp()
    u:setpeername("8.8.8.8", 53)
    local a = u:getsockname()
    u:close()
    return a
end

-- Ask on the local network; Calibre answers
-- "calibre wireless device client (on <computer>);<content port>,<wireless port>".
local function discover()
    local u = socket.udp()
    u:setoption("broadcast", true)
    u:settimeout(0)
    local targets = { "255.255.255.255" }
    local ok, ip = pcall(own_ip)
    if ok and ip and ip:match("^%d+%.%d+%.%d+%.%d+$") then
        targets[#targets + 1] = ip:gsub("%.%d+$", ".255")
    end
    for _, t in ipairs(targets) do
        for _, port in ipairs(BROADCAST_PORTS) do u:sendto("hello", t, port) end
    end
    local deadline = love.timer.getTime() + 1.5
    while love.timer.getTime() < deadline do
        local data, from = u:receivefrom()
        if data then
            local name, ports = data:match("calibre wireless device client %(on (.-)%);(.*)")
            local port = ports and tonumber(ports:match("(%d+)%s*$"))
            if port then u:close(); return from, port, name end
        end
        love.timer.sleep(0.05)
    end
    u:close()
end

---------------------------------------------------------------- talking

local sock, buf = nil, ""

local function send(op, arg)
    local s = json.encode({ op, arg or {} })
    local data = #s .. s
    local i = 1
    while i <= #data do
        local sent, err, last = sock:send(data, i)
        if sent then i = sent + 1
        elseif err == "timeout" then i = (last or i - 1) + 1
        else error("lost: " .. tostring(err), 0) end
    end
end

-- More bytes from Calibre into buf; false on a quiet moment, error when it's gone.
local function fill()
    local data, err, partial = sock:receive(PACKET)
    local got = data or partial
    if got and #got > 0 then buf = buf .. got; return true end
    if err == "closed" then error("lost: Calibre closed the connection", 0) end
    if err and err ~= "timeout" then error("lost: " .. tostring(err), 0) end     -- (a reset, say: not a quiet moment)
    return false
end

-- The next message: opcode and its argument, or nil if told to stop.
local function receive()
    while true do
        local b = buf:find("[", 1, true)
        if b then
            local len = tonumber(buf:sub(1, b - 1))
            -- (Messages are small: a huge length isn't Calibre's.)
            if not len or len > 64 * 1024 * 1024 then error("lost: Calibre sent something unexpected", 0) end
            while #buf - b + 1 < len do
                if not fill() and stopping() then return nil end
            end
            local s = buf:sub(b, b + len - 1)
            buf = buf:sub(b + len)
            local ok, msg = pcall(json.decode, s)
            if not ok or type(msg) ~= "table" then error("lost: Calibre sent something unexpected", 0) end
            return msg[1], msg[2] or {}
        end
        if not fill() and stopping() then return nil end
    end
end

-- A book's bytes, straight into a file; true when it's all there (every
-- byte written, the size right, and an EPUB whole).
local function receive_book(path, size, title)
    local part = path .. ".part"
    local f = io.open(part, "wb")
    local got, last, wrote = 0, 0, true
    local function take(s)
        got = got + #s
        if f and wrote and not f:write(s) then wrote = false end
        local now = love.timer.getTime()
        if now - last > 0.3 then last = now; out:push({ kind = "progress", got = got, size = size }) end
    end
    local n = math.min(#buf, size)
    if n > 0 then take(buf:sub(1, n)); buf = buf:sub(n + 1) end
    while got < size do
        local data, err, partial = sock:receive(math.min(PACKET, size - got))
        local s = data or partial
        if s and #s > 0 then take(s)
        elseif err == "closed" then
            if f then f:close() end
            os.remove(part)
            error("lost: Calibre closed the connection", 0)
        end
        if stopping() then
            if f then f:close() end
            os.remove(part)
            return nil, "stopped"
        end
    end
    if not f then return false, "couldn't write to the books folder" end
    if not f:close() then wrote = false end
    local check = io.open(part, "rb")
    local ok = wrote and size > 0 and check ~= nil
    if check then
        ok = ok and check:seek("end") == size
        if ok and path:lower():match("%.epub$") then
            -- A zip: its header at the start and its directory at the end.
            check:seek("set", 0)
            local head = check:read(4)
            check:seek("set", math.max(0, size - 65557))
            local tail = check:read("*a") or ""
            ok = head == "PK\3\4" and tail:find("PK\5\6", 1, true) ~= nil
        end
        check:close()
    end
    if not ok then os.remove(part); return false, "couldn't save it (is the SD card full?)" end
    os.remove(path)
    if not os.rename(part, path) then os.remove(part); return false, "couldn't save it" end
    return true
end

-- One connection, until it ends; returns why ("unreachable" if it couldn't
-- connect at all).
local function session(ip, port, name, timeout, address)
    buf = ""
    sock = socket.tcp()
    sock:settimeout(timeout or 5)
    local ok = sock:connect(ip, port)
    if not ok then sock:close(); sock = nil; return "unreachable" end
    sock:settimeout(0.25)
    if address then store.last = address; save_store() end
    out:push({ kind = "connected", name = name or ip })
    while true do
        local op, arg = receive()
        if not op then return "stopped" end
        if op == OP.GET_INITIALIZATION_INFO then
            local challenge = arg.passwordChallenge or ""
            local hash = ""
            if challenge ~= "" then
                hash = love.data.encode("string", "hex", love.data.hash("sha1", (store.password or "") .. challenge))
                if (store.password or "") == "" then out:push({ kind = "password" }) end
            end
            send(OP.OK, {
                versionOK = true, maxBookContentPacketLen = PACKET,
                acceptedExtensions = { "epub", "txt" }, extensionPathLengths = { epub = 42, txt = 42 },
                canStreamBooks = true, canStreamMetadata = true, canReceiveBookBinary = true,
                canDeleteMultipleBooks = true, canSendOkToSendbook = true, canUseCachedMetadata = false,
                cacheUsesLpaths = true, canAcceptLibraryInfo = false, useUuidFileNames = false,
                coverHeight = 240, deviceKind = "RG DS Plus", deviceName = "eReaderDS",
                appName = "eReaderDS", ccVersionNumber = args.version, passwordHash = hash,
            })
        elseif op == OP.GET_DEVICE_INFORMATION then
            local info = type(store.info) == "table" and store.info or {}
            info.device_store_uuid = store.uuid
            info.device_name = info.device_name or "eReaderDS"
            send(OP.OK, { device_info = info, version = "1", device_version = "eReaderDS " .. args.version })
        elseif op == OP.SET_CALIBRE_DEVICE_INFO or op == OP.SET_CALIBRE_DEVICE_NAME then
            if op == OP.SET_CALIBRE_DEVICE_INFO then store.info = arg else
                store.info = type(store.info) == "table" and store.info or {}
                store.info.device_name = arg.name
            end
            save_store()
            send(OP.OK, {})
        elseif op == OP.TOTAL_SPACE or op == OP.FREE_SPACE then
            local total, free = space()
            send(OP.OK, op == OP.TOTAL_SPACE and { total_space_on_device = total } or { free_space_on_device = free })
        elseif op == OP.GET_BOOK_COUNT then
            -- The books it sent before that are still here.
            local list = {}
            for lpath, m in pairs(store.books) do
                if exists(ROOT .. "/" .. clean(lpath)) then list[#list + 1] = m else store.books[lpath] = nil end
            end
            send(OP.OK, { count = #list, willStream = true, willScan = true })
            for _, m in ipairs(list) do send(OP.OK, m) end
        elseif op == OP.SEND_BOOKLISTS then
            -- Metadata updates follow, one message per book, none answered.
            for _ = 1, tonumber(arg.count) or 0 do
                local op2, arg2 = receive()
                if not op2 then return "stopped" end
                local m = type(arg2.data) == "table" and arg2.data
                if op2 == OP.SEND_BOOK_METADATA and m and m.lpath and store.books[m.lpath] then
                    store.books[m.lpath] = brief(m)
                end
            end
            save_store()
        elseif op == OP.SEND_BOOK then
            -- Calibre names books "Title - Author (id).epub" by default; keep
            -- them as "Title - Author.epub" unless another book has that name
            -- (Calibre is told, and uses the name given from then on).
            local lpath = clean(arg.lpath)
            local plain = lpath:gsub(" %(%d+%)(%.%w+)$", "%1")
            if plain ~= lpath and arg.canSupportLpathChanges then
                local other = store.books[plain]
                local mine = type(arg.metadata) == "table" and arg.metadata.uuid
                local same = other and mine and other.uuid == mine      -- this book, sent again
                if same or (not other and not exists(ROOT .. "/" .. plain)) then lpath = plain end
            end
            arg.lpath = lpath
            local m = type(arg.metadata) == "table" and arg.metadata or {}
            local title = m.title or lpath:match("([^/]+)$") or "Book"
            local size = tonumber(arg.length) or 0
            out:push({ kind = "start", title = title, this = (tonumber(arg.thisBook) or 0) + 1,
                total = tonumber(arg.totalBooks) or 1, size = size })
            local path = ROOT .. "/" .. lpath
            mkdir_p(path:match("^(.*)/[^/]*$"))
            if arg.wantsSendOkToSendbook then send(OP.OK, { lpath = arg.lpath }) end
            local done, why = receive_book(path, size, title)
            if done == nil then return "stopped" end
            if done then
                m.lpath, m.size = arg.lpath, size
                store.books[arg.lpath] = brief(m)
                save_store()
                out:push({ kind = "done", title = title, path = path })
            else
                out:push({ kind = "failed", title = title, message = why })
            end
        elseif op == OP.DELETE_BOOK then
            send(OP.OK, {})
            for _, lp in ipairs(type(arg.lpaths) == "table" and arg.lpaths or {}) do
                local m = store.books[lp]
                local path = ROOT .. "/" .. clean(lp)
                -- (Only a book Calibre itself sent here.)
                if m and os.remove(path) then
                    out:push({ kind = "deleted", path = path, title = m and m.title or clean(lp):match("([^/]+)%.%w+$") })
                end
                store.books[lp] = nil
                send(OP.OK, { uuid = m and m.uuid or "" })
            end
            save_store()
        elseif op == OP.NOOP then
            if arg.ejecting then
                send(OP.OK, {})
                return "Calibre disconnected"
            elseif arg.count == nil and arg.priKey == nil then
                send(OP.OK, {})
            end
        elseif op == OP.DISPLAY_MESSAGE then
            if arg.messageKind == 1 then out:push({ kind = "password" })
            elseif arg.message then out:push({ kind = "message", text = tostring(arg.message) }) end
            send(OP.OK, {})
        elseif op == OP.CALIBRE_BUSY then
            out:push({ kind = "busy", name = arg.otherDevice })
            return "Calibre is busy with another device"
        elseif op == OP.GET_BOOK_FILE_SEGMENT then
            send(OP.ERROR, { message = "eReaderDS doesn't send books back" })
        else
            send(OP.OK, {})           -- (library info and anything newer: nothing to do)
        end
    end
end

---------------------------------------------------------------- main loop

-- The saved computers, the one used last first (an older single "address"
-- becomes the first of them).
local function saved()
    local list = {}
    if type(store.servers) == "table" then
        for _, sv in ipairs(store.servers) do
            if type(sv) == "table" and type(sv.address) == "string" and sv.address ~= "" then list[#list + 1] = sv end
        end
    end
    if type(store.address) == "string" and store.address ~= "" then
        table.insert(list, 1, { name = store.address:match("^[^:]+"), address = store.address })
        store.servers, store.address = list, nil
        save_store()
    end
    for i, sv in ipairs(list) do
        if sv.address == store.last and i > 1 then table.insert(list, 1, table.remove(list, i)) break end
    end
    return list
end

local function host_port(address)
    return address:match("^([^:]+)"), tonumber(address:match(":(%d+)$")) or 9090
end

load_store()
math.randomseed(os.time())
while true do
    if stopping() then break end
    out:push({ kind = "searching" })
    -- Calibre announcing itself first, then each saved computer.
    local tries = {}
    local ip, port, name = discover()
    local list = saved()
    if ip then
        for _, sv in ipairs(list) do
            if host_port(sv.address) == ip then name = sv.name end        -- (the name it was given)
        end
        tries[1] = { ip = ip, port = port, name = name }
    end
    for _, sv in ipairs(list) do
        local h, p = host_port(sv.address)
        if h ~= ip then tries[#tries + 1] = { ip = h, port = p, name = sv.name, address = sv.address } end
    end
    local finished = false
    for _, t in ipairs(tries) do
        if ctl:peek() == "stop" then break end
        local ok, why = pcall(session, t.ip, t.port, t.name, t.address and 2 or 5, t.address)
        if sock then sock:close(); sock = nil end
        if not (ok and why == "unreachable") then
            save_store()
            if why == "stopped" then finished = true; break end
            out:push({ kind = "lost", message = ok and why or tostring(why):gsub("^lost: ", "") })
            break
        end
    end
    if finished then break end
    -- Before looking again: two seconds, a little at a time.
    for _ = 1, 8 do
        if ctl:peek() == "stop" then break end
        love.timer.sleep(0.25)
    end
end
