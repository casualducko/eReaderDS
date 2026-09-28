-- Receive books over Wi-Fi: a small web server, run on its own thread only
-- while the "Send books over Wi-Fi" screen is open. A phone or computer on the
-- same network opens the page it serves, picks files, and they're uploaded
-- one at a time (POST /upload?name=…, the file as the body) straight into the
-- books folder (.epub, .txt) or the fonts folder (.ttf, .otf).
--
-- Started with { books = dir, fonts = dir }. Control on "recv_ctl" ("stop");
-- reports on "recv_out":
--   { kind = "ready", port }                  listening
--   { kind = "error", message }               couldn't start
--   { kind = "start", name, total }           a file is arriving
--   { kind = "progress", name, got, total }   a few times a second
--   { kind = "done", name, path, font, replaced }
--   { kind = "failed", name, message }
require("love.timer")
local socket = require("socket")

local dirs = ...
local ctl = love.thread.getChannel("recv_ctl")
local out = love.thread.getChannel("recv_out")

local MAX_SIZE = 300 * 1024 * 1024
local CHUNK = 64 * 1024

local PAGE = [[<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Send to eReaderDS</title>
<style>
:root { --bg: #f4ecd8; --fg: #3b3024; --dim: #8a7a66; --line: #d9ccb0; --ok: #3d7a3d; --bad: #b8382f; --btn: #3b3024; --btnfg: #f4ecd8; }
@media (prefers-color-scheme: dark) { :root { --bg: #1d1a16; --fg: #e8dfcf; --dim: #9a8f7e; --line: #3a342c; --ok: #7cbf7c; --bad: #e0776d; --btn: #e8dfcf; --btnfg: #1d1a16; } }
* { box-sizing: border-box; }
body { margin: 0; background: var(--bg); color: var(--fg); font: 17px/1.5 Georgia, "Times New Roman", serif; }
main { max-width: 560px; margin: 0 auto; padding: 32px 16px 48px; }
h1 { font-size: 28px; margin: 0 0 6px; font-weight: normal; }
p { margin: 0 0 20px; color: var(--dim); }
#drop { border: 2px dashed var(--line); border-radius: 14px; padding: 28px 16px; text-align: center; }
#drop.over { border-color: var(--fg); }
label.btn { display: inline-block; background: var(--btn); color: var(--btnfg); padding: 12px 26px; border-radius: 999px; cursor: pointer; font-size: 18px; }
input[type=file] { display: none; }
.hint { margin: 12px 0 0; font-size: 15px; }
ul { list-style: none; padding: 0; margin: 24px 0 0; }
li { padding: 12px 0; border-bottom: 1px solid var(--line); }
.row { display: flex; gap: 12px; justify-content: space-between; align-items: baseline; }
.name { overflow-wrap: anywhere; }
.st { flex: none; color: var(--dim); font-size: 15px; }
.st.ok { color: var(--ok); } .st.bad { color: var(--bad); }
.bar { height: 4px; background: var(--line); border-radius: 2px; margin-top: 8px; overflow: hidden; }
.bar i { display: block; height: 100%; width: 0; background: var(--fg); }
</style></head><body><main>
<h1>Send to eReaderDS</h1>
<p>Books (.epub or .txt) go to My Books; fonts (.ttf or .otf) to Fonts. Keep eReaderDS on its Send books screen until they're done.</p>
<div id="drop">
<label class="btn">Choose files<input id="pick" type="file" multiple accept=".epub,.txt,.ttf,.otf"></label>
<div class="hint">or drop them here</div>
</div>
<ul id="list"></ul>
</main><script>
var OK = /\.(epub|txt|ttf|otf)$/i, queue = [], busy = false, list = document.getElementById('list');
function add(files) {
  for (var i = 0; i < files.length; i++) {
    var f = files[i], li = document.createElement('li');
    li.innerHTML = '<div class="row"><span class="name"></span><span class="st"></span></div><div class="bar"><i></i></div>';
    li.querySelector('.name').textContent = f.name;
    list.appendChild(li);
    if (!OK.test(f.name)) { done(li, false, 'Not a book or font'); continue; }
    li.querySelector('.st').textContent = 'Waiting';
    queue.push({ f: f, li: li });
  }
  next();
}
function done(li, ok, text) {
  var st = li.querySelector('.st'); st.textContent = text; st.className = 'st ' + (ok ? 'ok' : 'bad');
  li.querySelector('.bar').style.display = 'none';
}
function next() {
  if (busy || !queue.length) return;
  busy = true;
  var job = queue.shift(), li = job.li, x = new XMLHttpRequest();
  li.querySelector('.st').textContent = 'Sending';
  x.open('POST', '/upload?name=' + encodeURIComponent(job.f.name));
  x.upload.onprogress = function (e) {
    if (e.lengthComputable) {
      var p = Math.floor(e.loaded / e.total * 100);
      li.querySelector('.bar i').style.width = p + '%';
      li.querySelector('.st').textContent = p + '%';
    }
  };
  x.onload = function () {
    var r = {}; try { r = JSON.parse(x.responseText); } catch (e) {}
    if (x.status == 200 && r.ok) done(li, true, r.replaced ? 'Replaced ✓' : 'Sent ✓');
    else done(li, false, r.error || ('Failed (' + x.status + ')'));
    busy = false; next();
  };
  x.onerror = function () { done(li, false, "Couldn't reach eReaderDS"); busy = false; next(); };
  x.send(job.f);
}
document.getElementById('pick').onchange = function () { add(this.files); this.value = ''; };
var drop = document.getElementById('drop');
['dragenter', 'dragover'].forEach(function (t) { document.addEventListener(t, function (e) { e.preventDefault(); drop.className = 'over'; }); });
['dragleave', 'drop'].forEach(function (t) { document.addEventListener(t, function (e) { e.preventDefault(); drop.className = ''; }); });
document.addEventListener('drop', function (e) { add(e.dataTransfer.files); });
</script></body></html>
]]

local STATUS = { [200] = "OK", [400] = "Bad Request", [404] = "Not Found", [411] = "Length Required",
    [413] = "Payload Too Large", [415] = "Unsupported Media Type", [500] = "Internal Server Error" }

local function send(client, code, ctype, body)
    client:send("HTTP/1.1 " .. code .. " " .. (STATUS[code] or "") .. "\r\nContent-Type: " .. ctype
        .. "\r\nContent-Length: " .. #body .. "\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n" .. body)
end

local function json_str(s)
    return '"' .. s:gsub('[%c"\\]', function(c) return string.format("\\u%04x", c:byte()) end) .. '"'
end

local function reply(client, code, ok, fields)
    local parts = { '"ok":' .. tostring(ok) }
    for k, v in pairs(fields or {}) do
        parts[#parts + 1] = json_str(k) .. ":" .. (type(v) == "string" and json_str(v) or tostring(v))
    end
    send(client, code, "application/json", "{" .. table.concat(parts, ",") .. "}")
end

local function url_decode(s)
    return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

-- A safe file name from what the browser sent: no folders, no characters a
-- shell or FAT card would trip on, no leading dot (hidden).
local function clean_name(raw)
    local name = url_decode(raw or ""):match("([^/\\]*)$") or ""
    name = name:gsub("[%c\"`$\\:*?<>|]", ""):gsub("^[%s%.]+", ""):gsub("%s+$", "")
    if #name > 200 then
        local ext = name:match("(%.[^.]+)$") or ""
        name = name:sub(1, 200 - #ext) .. ext
    end
    return name
end

local function exists(path)
    local f = io.open(path, "rb")
    if f then f:close() return true end
    return false
end

-- An EPUB is a zip: it starts with a zip header and ends with the zip directory.
local function whole_epub(path)
    local f = io.open(path, "rb")
    if not f then return false end
    local head = f:read(4)
    local size = f:seek("end")
    f:seek("set", math.max(0, size - 65557))
    local tail = f:read("*a") or ""
    f:close()
    return head == "PK\3\4" and tail:find("PK\5\6", 1, true) ~= nil
end

local function upload(client, query, headers)
    local name = clean_name(query:match("[?&]name=([^&]*)"))
    local ext = (name:match("%.([^.]+)$") or ""):lower()
    local font = ext == "ttf" or ext == "otf"
    if name == "" or not (ext == "epub" or ext == "txt" or font) then
        return reply(client, 415, false, { error = "Only books (.epub, .txt) and fonts (.ttf, .otf)" })
    end
    local dir = font and dirs.fonts or dirs.books
    if not dir then return reply(client, 500, false, { error = "There's no fonts folder" }) end
    local total = tonumber(headers["content-length"] or "")
    if not total then return reply(client, 411, false, { error = "The browser didn't say how big it is" }) end
    if total > MAX_SIZE then return reply(client, 413, false, { error = "Too big (the limit is 300 MB)" }) end

    local path = dir .. "/" .. name
    local part = dir .. "/." .. name .. ".part"
    local f = io.open(part, "wb")
    if not f then return reply(client, 500, false, { error = "Couldn't write to the SD card" }) end
    out:push({ kind = "start", name = name, total = total })
    local got, last, err = 0, 0, nil
    while got < total do
        if ctl:peek() == "stop" then err = "eReaderDS stopped receiving"; break end
        local data, e, partial = client:receive(math.min(CHUNK, total - got))
        data = data or partial
        if data and #data > 0 then
            if not f:write(data) then err = "The SD card is full"; break end
            got = got + #data
        end
        if e then err = e == "timeout" and "The connection stalled" or "The connection was lost"; break end
        local now = love.timer.getTime()
        if now - last > 0.2 then
            last = now
            out:push({ kind = "progress", name = name, got = got, total = total })
        end
    end
    if not f:close() and not err then err = "The SD card is full" end
    if not err and ext == "epub" and not whole_epub(part) then err = "That isn't a whole EPUB file" end
    local replaced = exists(path)
    if not err then
        os.remove(path)
        if not os.rename(part, path) then err = "Couldn't save it on the SD card" end
    end
    if err then
        os.remove(part)
        out:push({ kind = "failed", name = name, message = err })
        return pcall(reply, client, 500, false, { error = err })
    end
    out:push({ kind = "done", name = name, path = path, font = font, replaced = replaced })
    reply(client, 200, true, { name = name, replaced = replaced })
end

local function handle(client)
    client:settimeout(20)
    local line = client:receive("*l")
    if not line then return end
    local method, target = line:match("^(%u+)%s+(%S+)")
    local headers, n = {}, 0
    while true do
        local h = client:receive("*l")
        if not h or h == "" then break end
        n = n + 1
        if n > 100 then return end
        local k, v = h:match("^([^:]+):%s*(.-)%s*$")
        if k then headers[k:lower()] = v end
    end
    if not method then return end
    local p = target:match("^[^?]*")
    if method == "GET" and (p == "/" or p == "/index.html") then
        send(client, 200, "text/html; charset=utf-8", PAGE)
    elseif method == "POST" and p == "/upload" then
        if (headers["transfer-encoding"] or ""):lower():find("chunked") then
            return reply(client, 411, false, { error = "The browser didn't say how big it is" })
        end
        upload(client, target, headers)
    else
        send(client, 404, "text/plain", "Not found")
    end
end

-- Port 80 gives the plainest address; if something has it, 8080.
local server, port
for _, p in ipairs({ 80, 8080, 8088 }) do
    server = socket.bind("*", p)
    if server then port = p break end
end
if not server then
    out:push({ kind = "error", message = "Couldn't start receiving (the network ports are busy)" })
    return
end
server:settimeout(0.25)
out:push({ kind = "ready", port = port })
while ctl:peek() ~= "stop" do
    local client = server:accept()
    if client then
        local ok, e = pcall(handle, client)
        if not ok then print("[receive] " .. tostring(e)) end
        client:close()
    end
end
ctl:pop()
server:close()
