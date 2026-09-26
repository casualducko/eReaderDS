-- A small HTTP/1.1 client for OPDS catalogs: GET only, with redirects, Basic
-- and Digest logins, chunked bodies, and HTTPS through the system's OpenSSL
-- (loaded with LuaJIT's FFI, since LÖVE's LuaSocket has no TLS). Blocking, so
-- it runs on the download thread (networker.lua), never the UI thread.
local socket = require("socket")
local ffi = require("ffi")

local M = {}
local TIMEOUT = 20            -- seconds without progress before giving up

---------------------------------------------------------------- URLs

function M.parse_url(url)
    local scheme, rest = url:match("^(%a[%w+.-]*)://(.*)$")
    if not scheme then return nil end
    scheme = scheme:lower()
    local authority, path = rest:match("^([^/?#]*)(.*)$")
    local host, port = authority:match("^(.-):(%d+)$")
    host = host or authority
    if path == "" then path = "/" end
    path = path:gsub("#.*$", "")
    return {
        scheme = scheme, host = host,
        port = tonumber(port) or (scheme == "https" and 443 or 80),
        path = path,
    }
end

-- Resolve an href found in a page at `base` (absolute, root-relative or relative).
function M.resolve(base, href)
    if not href or href == "" then return base end
    if href:match("^%a[%w+.-]*://") then return href end
    local scheme, authority, path = base:match("^(%a[%w+.-]*://)([^/?#]*)([^?#]*)")
    if not scheme then return href end
    if href:sub(1, 2) == "//" then return scheme:match("^(.-:)") .. href end
    if href:sub(1, 1) == "/" then return scheme .. authority .. href end
    if href:sub(1, 1) == "?" then return scheme .. authority .. path .. href end
    local dir = path:match("^(.*/)") or "/"
    -- Collapse "." and ".." segments.
    local parts = {}
    local joined = (dir .. href):sub(2)
    for p in (joined .. "/"):gmatch("([^/]*)/") do parts[#parts + 1] = p end
    local stack = {}
    for i, p in ipairs(parts) do
        if p == ".." then
            if #stack > 0 then table.remove(stack) end
        elseif p ~= "." and not (p == "" and i < #parts) then
            stack[#stack + 1] = p
        end
    end
    return scheme .. authority .. "/" .. table.concat(stack, "/")
end

---------------------------------------------------------------- TLS

local ssl, ctx_cache
local SSL_ERROR_WANT_READ, SSL_ERROR_WANT_WRITE, SSL_ERROR_ZERO_RETURN = 2, 3, 6
local SSL_ERROR_SYSCALL = 5
local SSL_OP_IGNORE_UNEXPECTED_EOF = 0x80
local CA_FILES = {
    "/etc/ssl/certs/ca-certificates.crt", "/etc/ssl/cert.pem", "/etc/pki/tls/certs/ca-bundle.crt",
    "/opt/homebrew/etc/openssl@3/cert.pem", "/usr/local/etc/openssl@3/cert.pem",
}

local function load_ssl()
    if ssl ~= nil then return ssl end
    pcall(ffi.cdef, [[
        typedef struct ssl_st SSL;
        typedef struct ssl_ctx_st SSL_CTX;
        typedef struct ssl_method_st SSL_METHOD;
        int OPENSSL_init_ssl(uint64_t opts, const void *settings);
        const SSL_METHOD *TLS_client_method(void);
        SSL_CTX *SSL_CTX_new(const SSL_METHOD *meth);
        uint64_t SSL_CTX_set_options(SSL_CTX *ctx, uint64_t op);
        int SSL_CTX_set_default_verify_paths(SSL_CTX *ctx);
        int SSL_CTX_load_verify_locations(SSL_CTX *ctx, const char *file, const char *path);
        void SSL_CTX_set_verify(SSL_CTX *ctx, int mode, void *cb);
        SSL *SSL_new(SSL_CTX *ctx);
        void SSL_free(SSL *s);
        int SSL_set_fd(SSL *s, int fd);
        long SSL_ctrl(SSL *s, int cmd, long larg, void *parg);
        int SSL_set1_host(SSL *s, const char *hostname);
        int SSL_connect(SSL *s);
        int SSL_read(SSL *s, void *buf, int num);
        int SSL_write(SSL *s, const void *buf, int num);
        int SSL_get_error(const SSL *s, int ret);
        int SSL_shutdown(SSL *s);
        long SSL_get_verify_result(const SSL *s);
        const char *X509_verify_cert_error_string(long n);
        unsigned long ERR_get_error(void);
        void ERR_error_string_n(unsigned long e, char *buf, size_t len);
    ]])
    -- macOS's own libssl aborts the process when loaded, so use Homebrew's there.
    local names = ffi.os == "OSX"
        and { "/opt/homebrew/opt/openssl@3/lib/libssl.3.dylib", "/usr/local/opt/openssl@3/lib/libssl.3.dylib" }
        or { "libssl.so.3", "ssl" }
    for _, name in ipairs(names) do
        local ok, lib = pcall(ffi.load, name)
        if ok and pcall(function() return lib.TLS_client_method end) then
            -- libcrypto's symbols (X509_*, ERR_*) resolve through libssl's handle.
            ssl = lib
            ssl.OPENSSL_init_ssl(0, nil)
            return ssl
        end
    end
    ssl = false
    return ssl
end

local function ssl_context(verify)
    ctx_cache = ctx_cache or {}
    local key = verify and "v" or "n"
    if ctx_cache[key] then return ctx_cache[key] end
    local ctx = ssl.SSL_CTX_new(ssl.TLS_client_method())
    if ctx == nil then error("could not start TLS") end
    ssl.SSL_CTX_set_options(ctx, SSL_OP_IGNORE_UNEXPECTED_EOF)
    if verify then
        ssl.SSL_CTX_set_default_verify_paths(ctx)
        for _, f in ipairs(CA_FILES) do
            local h = io.open(f, "rb")
            if h then h:close(); ssl.SSL_CTX_load_verify_locations(ctx, f, nil); break end
        end
        ssl.SSL_CTX_set_verify(ctx, 1, nil)          -- SSL_VERIFY_PEER
    end
    ctx_cache[key] = ctx
    return ctx
end

local function wait(sock, writing)
    local r, w = socket.select(not writing and { sock } or nil, writing and { sock } or nil, TIMEOUT)
    if #(writing and w or r) == 0 then error("the server stopped responding") end
end

local function ssl_error_text(s, ret)
    local e = ssl.SSL_get_error(s, ret)
    local ok, code = pcall(function() return ssl.ERR_get_error() end)
    if ok and code ~= 0 then
        local buf = ffi.new("char[256]")
        ssl.ERR_error_string_n(code, buf, 256)
        return ffi.string(buf)
    end
    return "TLS error " .. e
end

-- Wrap a connected LuaSocket TCP socket in TLS. Returns recv(n), send(s), close().
local function tls_wrap(sock, host, verify)
    if not load_ssl() then error("HTTPS isn't available (OpenSSL not found)") end
    local s = ssl.SSL_new(ssl_context(verify))
    if s == nil then error("could not start TLS") end
    ffi.gc(s, ssl.SSL_free)
    ssl.SSL_set_fd(s, sock:getfd())
    ssl.SSL_ctrl(s, 55, 0, ffi.cast("void *", host))           -- SNI: SSL_CTRL_SET_TLSEXT_HOSTNAME
    if verify then ssl.SSL_set1_host(s, host) end
    while true do
        local ret = ssl.SSL_connect(s)
        if ret == 1 then break end
        local e = ssl.SSL_get_error(s, ret)
        if e == SSL_ERROR_WANT_READ then wait(sock, false)
        elseif e == SSL_ERROR_WANT_WRITE then wait(sock, true)
        else
            local v = tonumber(ssl.SSL_get_verify_result(s))
            if v ~= 0 then
                error("the server's certificate couldn't be verified (" ..
                    ffi.string(ssl.X509_verify_cert_error_string(v)) .. ")")
            end
            error("secure connection failed: " .. ssl_error_text(s, ret))
        end
    end
    local buf = ffi.new("uint8_t[?]", 65536)
    local t = {}
    function t.recv(n)
        while true do
            local ret = ssl.SSL_read(s, buf, math.min(n, 65536))
            if ret > 0 then return ffi.string(buf, ret) end
            local e = ssl.SSL_get_error(s, ret)
            if e == SSL_ERROR_WANT_READ then wait(sock, false)
            elseif e == SSL_ERROR_WANT_WRITE then wait(sock, true)
            elseif e == SSL_ERROR_ZERO_RETURN or (e == SSL_ERROR_SYSCALL and ret == 0) then return nil
            else error("secure connection failed: " .. ssl_error_text(s, ret)) end
        end
    end
    function t.send(data)
        local i = 0
        while i < #data do
            local ret = ssl.SSL_write(s, ffi.cast("const char *", data) + i, #data - i)
            if ret > 0 then i = i + ret
            else
                local e = ssl.SSL_get_error(s, ret)
                if e == SSL_ERROR_WANT_READ then wait(sock, false)
                elseif e == SSL_ERROR_WANT_WRITE then wait(sock, true)
                else error("secure connection failed: " .. ssl_error_text(s, ret)) end
            end
        end
    end
    function t.close() pcall(ssl.SSL_shutdown, s); sock:close() end
    return t
end

local function plain_wrap(sock)
    local t = {}
    function t.recv(n)
        while true do
            local d, err, part = sock:receive(n)
            if d then return d end
            if part and #part > 0 then return part end
            if err == "closed" then return nil end
            if err ~= "timeout" then error(err) end
            wait(sock, false)
        end
    end
    function t.send(data)
        local i = 1
        while i <= #data do
            local sent, err, last = sock:send(data, i)
            if sent then i = sent + 1
            else
                if err ~= "timeout" then error(err) end
                i = (last or i - 1) + 1
                wait(sock, true)
            end
        end
    end
    function t.close() sock:close() end
    return t
end

---------------------------------------------------------------- HTTP

local function connect(u, verify)
    local sock = socket.tcp()
    sock:settimeout(TIMEOUT)
    local ok, err = sock:connect(u.host, u.port)
    if not ok then
        sock:close()
        if err == "host not found" or tostring(err):find("not known") then
            error("couldn't find " .. u.host .. " (is Wi-Fi on?)")
        end
        error("couldn't connect to " .. u.host .. " (" .. tostring(err) .. ")")
    end
    sock:settimeout(0)
    if u.scheme == "https" then return tls_wrap(sock, u.host, verify) end
    return plain_wrap(sock)
end

-- Buffered reading on top of a connection's recv(n).
local function reader(conn)
    local buf = ""
    local r = {}
    function r.line()
        while true do
            local i = buf:find("\n", 1, true)
            if i then
                local line = buf:sub(1, i - 1):gsub("\r$", "")
                buf = buf:sub(i + 1)
                return line
            end
            local d = conn.recv(4096)
            if not d then error("the connection closed early") end
            buf = buf .. d
        end
    end
    -- Up to n bytes (at least one), or nil at the end of the stream.
    function r.some(n)
        if #buf > 0 then
            local d = buf:sub(1, n)
            buf = buf:sub(n + 1)
            return d
        end
        return conn.recv(n)
    end
    return r
end

local function hex_md5(s) return love.data.encode("string", "hex", love.data.hash("md5", s)) end

local function parse_challenge(h)
    local scheme, rest = h:match("^%s*(%a+)%s*(.*)$")
    if not scheme then return nil end
    local params = {}
    for k, v in rest:gmatch('([%w_-]+)%s*=%s*"([^"]*)"') do params[k:lower()] = v end
    for k, v in rest:gmatch('([%w_-]+)%s*=%s*([^",%s]+)') do params[k:lower()] = params[k:lower()] or v end
    return scheme:lower(), params
end

local function auth_header(auth, opts, path)
    if not auth or not opts.user then return nil end
    if auth.scheme == "basic" then
        return "Basic " .. love.data.encode("string", "base64", opts.user .. ":" .. (opts.password or ""))
    end
    local p = auth.params
    auth.nc = (auth.nc or 0) + 1
    local nc = string.format("%08x", auth.nc)
    local cnonce = hex_md5(tostring(os.time()) .. tostring(math.random())):sub(1, 16)
    local ha1 = hex_md5(opts.user .. ":" .. (p.realm or "") .. ":" .. (opts.password or ""))
    local ha2 = hex_md5("GET:" .. path)
    local qop = p.qop and (p.qop:match("auth%-int") and not p.qop:match("auth[^-]") and nil or "auth")
    local response
    if qop then
        response = hex_md5(ha1 .. ":" .. p.nonce .. ":" .. nc .. ":" .. cnonce .. ":" .. qop .. ":" .. ha2)
    else
        response = hex_md5(ha1 .. ":" .. p.nonce .. ":" .. ha2)
    end
    local parts = {
        string.format('username="%s"', opts.user), string.format('realm="%s"', p.realm or ""),
        string.format('nonce="%s"', p.nonce or ""), string.format('uri="%s"', path),
        string.format('response="%s"', response), 'algorithm="MD5"',
    }
    if qop then
        parts[#parts + 1] = "qop=" .. qop
        parts[#parts + 1] = "nc=" .. nc
        parts[#parts + 1] = string.format('cnonce="%s"', cnonce)
    end
    if p.opaque then parts[#parts + 1] = string.format('opaque="%s"', p.opaque) end
    return "Digest " .. table.concat(parts, ", ")
end

-- One request/response. Returns status, headers (lower-case keys), and reads
-- the body into sink(chunk) when the status is 200.
local function request(url, opts, auth, sink)
    local u = M.parse_url(url)
    if not u or (u.scheme ~= "http" and u.scheme ~= "https") then error("not a web address: " .. tostring(url)) end
    local conn = connect(u, opts.verify ~= false)
    local ok, status, headers = pcall(function()
        local host = u.host
        if (u.scheme == "https" and u.port ~= 443) or (u.scheme == "http" and u.port ~= 80) then
            host = host .. ":" .. u.port
        end
        local lines = {
            "GET " .. u.path .. " HTTP/1.1", "Host: " .. host, "User-Agent: eReaderDS",
            "Accept: */*", "Accept-Encoding: identity", "Connection: close",
        }
        local a = auth_header(auth, opts, u.path)
        if a then lines[#lines + 1] = "Authorization: " .. a end
        conn.send(table.concat(lines, "\r\n") .. "\r\n\r\n")

        local r = reader(conn)
        local status
        repeat                                   -- skip "100 Continue" style responses
            status = tonumber(r.line():match("^HTTP/%d[.%d]*%s+(%d+)"))
            if not status then error("the server sent something that isn't a web page") end
            local headers = {}
            while true do
                local line = r.line()
                if line == "" then break end
                local k, v = line:match("^([^:]+):%s*(.-)%s*$")
                if k then
                    k = k:lower()
                    headers[k] = headers[k] and (headers[k] .. ", " .. v) or v
                    if k == "www-authenticate" then
                        headers.challenges = headers.challenges or {}
                        table.insert(headers.challenges, v)
                    end
                end
            end
            if status >= 200 then
                if status ~= 200 then return status, headers end
                local total = tonumber(headers["content-length"])
                if (headers["transfer-encoding"] or ""):lower():find("chunked") then
                    while true do
                        local size = tonumber(r.line():match("^%s*(%x+)"), 16)
                        if not size then error("bad chunked response") end
                        if size == 0 then break end
                        local left = size
                        while left > 0 do
                            local d = r.some(math.min(left, 65536))
                            if not d then error("the download was cut off") end
                            left = left - #d
                            sink(d, nil)
                        end
                        r.line()
                    end
                elseif total then
                    local left = total
                    while left > 0 do
                        local d = r.some(math.min(left, 65536))
                        if not d then error("the download was cut off") end
                        left = left - #d
                        sink(d, total)
                    end
                else
                    while true do
                        local d = r.some(65536)
                        if not d then break end
                        sink(d, nil)
                    end
                end
                return status, headers
            end
        until false
    end)
    conn.close()
    if not ok then error(status, 0) end
    return status, headers
end

local auth_cache = {}      -- host -> { scheme, params } learned from the last challenge

-- GET a URL. opts: user, password, verify (default true), sink(chunk, total)
-- (without one the body is returned as a string). Follows redirects and
-- answers login challenges. Returns body-or-true, final url; errors on failure.
function M.get(url, opts)
    opts = opts or {}
    local parts
    local sink = opts.sink
    if not sink then
        parts = {}
        sink = function(d) parts[#parts + 1] = d end
    end
    local tried_auth = false
    for _ = 1, 8 do
        local u = M.parse_url(url)
        local host = u and u.host or ""
        local status, headers = request(url, opts, auth_cache[host], sink)
        if status == 200 then
            return parts and table.concat(parts) or true, url
        elseif status == 301 or status == 302 or status == 303 or status == 307 or status == 308 then
            if not headers.location then error("the server redirected nowhere") end
            url = M.resolve(url, headers.location)
        elseif status == 401 then
            if not opts.user then error("this catalog needs a user name and password (add them to opds.txt)") end
            if tried_auth and not (auth_cache[host] and auth_cache[host].stale) then
                error("the server didn't accept the user name or password")
            end
            tried_auth = true
            local chosen
            for _, c in ipairs(headers.challenges or {}) do
                local scheme, params = parse_challenge(c)
                if scheme == "digest" then chosen = { scheme = "digest", params = params }; break end
                if scheme == "basic" then chosen = chosen or { scheme = "basic", params = params } end
            end
            if not chosen then error("the server asked for a login this reader doesn't support") end
            chosen.stale = chosen.params.stale and chosen.params.stale:lower() == "true"
            auth_cache[host] = chosen
        elseif status == 403 then error("the server refused access (403)")
        elseif status == 404 then error("not found on the server (404)")
        else error("the server answered " .. status) end
    end
    error("too many redirects")
end

return M
