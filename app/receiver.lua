-- Receive books over Wi-Fi: a small web server, run on its own thread only
-- while the "Send books over Wi-Fi" screen is open. A phone or computer on the
-- same network opens the page it serves, picks files, and they're uploaded
-- one at a time (POST /upload?name=…, the file as the body) straight into the
-- books folder (.epub, .cbz, .txt) or the fonts folder (.ttf, .otf).
--
-- Started with { books = dir, fonts = dir, version }. Control on "recv_ctl" ("stop");
-- reports on "recv_out":
--   { kind = "ready", port }                  listening
--   { kind = "error", message }               couldn't start
--   { kind = "start", name, total }           a file is arriving
--   { kind = "progress", name, got, total }   a few times a second
--   { kind = "done", name, path, font, replaced }
--   { kind = "failed", name, message }
require("love.timer")
require("love.filesystem")
local socket = require("socket")

local dirs = ...
local ctl = love.thread.getChannel("recv_ctl")
local out = love.thread.getChannel("recv_out")

local MAX_SIZE = 300 * 1024 * 1024
local STALL = 20            -- seconds without data before giving up on a connection
local CHUNK = 64 * 1024

local PAGE = [==[<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light dark">
<title>Send to eReaderDS</title>
<style>
@font-face { font-family: Crimson; src: url(/font/r.ttf); font-weight: 400; }
@font-face { font-family: Crimson; src: url(/font/b.ttf); font-weight: 700; }
:root { --bg: #f1e7d0; --card: #faf4e6; --fg: #3b3024; --dim: #86765f; --line: #e0d3b8; --accent: #7a5c3a;
  --ok: #3f7a45; --okbg: #e3eed9; --bad: #b0412f; --badbg: #f5dfd6; --btn: #3b3024; --btnfg: #faf4e6; --shadow: 0 1px 2px rgba(59,48,36,.08), 0 6px 20px rgba(59,48,36,.06); }
@media (prefers-color-scheme: dark) { :root { --bg: #1b1814; --card: #25211b; --fg: #ebe2d0; --dim: #9d917d; --line: #383128; --accent: #d1b287;
  --ok: #8ccf8f; --okbg: #22321f; --bad: #ee8a78; --badbg: #3a221d; --btn: #ebe2d0; --btnfg: #1b1814; --shadow: 0 1px 2px rgba(0,0,0,.3); } }
* { box-sizing: border-box; }
html { -webkit-text-size-adjust: 100%; }
body { margin: 0; background: var(--bg); color: var(--fg); font: 19px/1.45 Crimson, Georgia, "Times New Roman", serif; }
main { max-width: 600px; margin: 0 auto; padding: 28px 16px 64px; }
header { display: flex; align-items: center; gap: 14px; margin-bottom: 22px; }
header svg { flex: none; color: var(--accent); }
h1 { font-size: 30px; line-height: 1.1; margin: 0; font-weight: 700; letter-spacing: -.01em; }
#conn { font-size: 15px; color: var(--dim); margin-top: 3px; display: flex; align-items: center; gap: 7px; }
#conn i { width: 8px; height: 8px; border-radius: 50%; background: var(--dim); display: inline-block; }
#conn.on i { background: var(--ok); } #conn.off { color: var(--bad); } #conn.off i { background: var(--bad); }
#drop { background: var(--card); border: 2px dashed var(--line); border-radius: 18px; padding: 30px 18px 26px; text-align: center;
  box-shadow: var(--shadow); transition: border-color .15s, transform .15s; }
#drop.over { border-color: var(--accent); transform: scale(1.01); }
.btn { display: inline-flex; align-items: center; gap: 8px; background: var(--btn); color: var(--btnfg); border: 0; padding: 13px 28px;
  border-radius: 999px; cursor: pointer; font: 700 19px Crimson, Georgia, serif; }
.btn:active { transform: translateY(1px); }
input[type=file] { display: none; }
.hint { margin: 12px 0 14px; color: var(--dim); font-size: 16px; }
.chips { display: flex; gap: 6px; justify-content: center; flex-wrap: wrap; }
.chips span { font-size: 13px; letter-spacing: .06em; color: var(--dim); border: 1px solid var(--line); border-radius: 999px; padding: 2px 10px; }
#summary { display: none; margin: 22px 0 0; padding: 14px 18px; border-radius: 14px; background: var(--okbg); color: var(--ok); }
#summary.bad { background: var(--badbg); color: var(--bad); }
#summary b { display: block; font-size: 20px; }
#summary span { font-size: 16px; color: var(--fg); opacity: .8; }
ul { list-style: none; padding: 0; margin: 18px 0 0; display: grid; gap: 10px; }
li { background: var(--card); border-radius: 14px; padding: 14px 16px; box-shadow: var(--shadow); display: grid;
  grid-template-columns: 40px 1fr; gap: 0 14px; align-items: center; animation: in .25s ease-out; }
@keyframes in { from { opacity: 0; transform: translateY(6px); } }
.ic { width: 40px; height: 40px; border-radius: 50%; display: grid; place-items: center; background: var(--bg); color: var(--dim); grid-row: span 2; }
li.ok .ic { background: var(--okbg); color: var(--ok); } li.bad .ic { background: var(--badbg); color: var(--bad); }
.t { font-weight: 700; overflow-wrap: anywhere; line-height: 1.25; }
.t small { font-weight: 400; color: var(--dim); font-size: 16px; }
.st { font-size: 15px; color: var(--dim); display: flex; gap: 10px; align-items: center; flex-wrap: wrap; }
li.ok .st { color: var(--ok); } li.bad .st { color: var(--bad); }
.bar { grid-column: 2; height: 5px; background: var(--line); border-radius: 3px; margin-top: 8px; overflow: hidden; }
.bar i { display: block; height: 100%; width: 0; background: var(--accent); border-radius: 3px; transition: width .2s; }
li.ok .bar, li.bad .bar, li.wait .bar { display: none; }
.retry { font: inherit; font-size: 14px; color: var(--fg); background: none; border: 1px solid var(--line); border-radius: 999px; padding: 1px 12px; cursor: pointer; }
footer { margin-top: 28px; font-size: 15px; color: var(--dim); text-align: center; }
</style></head><body><main>
<header>
<svg width="46" height="46" viewBox="0 0 48 48" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linejoin="round" aria-hidden="true">
<path d="M24 13c-4-3-10-4-17-3v26c7-1 13 0 17 3 4-3 10-4 17-3V10c-7-1-13 0-17 3z"/><path d="M24 13v26"/></svg>
<div><h1>Send to eReaderDS</h1><div id="conn"><i></i><span>Connecting…</span></div></div>
</header>
<div id="drop">
<label class="btn"><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round"><path d="M12 5v14M5 12h14"/></svg>Choose books<input id="pick" type="file" multiple accept=".epub,.cbz,.txt,.ttf,.otf"></label>
<div class="hint">or drop them here</div>
<div class="chips"><span>EPUB</span><span>TXT</span><span>TTF</span><span>OTF</span></div>
</div>
<div id="summary"></div>
<ul id="list"></ul>
<footer>Books go to My Books and fonts to Settings → Fonts.<br>Keep eReaderDS on its Send Books screen until they're sent.</footer>
</main><script>
var OK = /\.(epub|cbz|txt|ttf|otf)$/i, FONT = /\.(ttf|otf)$/i, queue = [], busy = false, have = {}, tally = { books: 0, fonts: 0, bad: 0 };
var list = document.getElementById('list'), conn = document.getElementById('conn');
var ICON = {
  book: '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"><path d="M12 6.5C10 5 7 4.5 3.5 5v13c3.5-.5 6.5 0 8.5 1.5 2-1.5 5-2 8.5-1.5V5C17 4.5 14 5 12 6.5zM12 6.5v13"/></svg>',
  font: '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 19 9.5 5h1L16 19M6.3 14h7.4M17 19v-6m0 0a2.5 2.5 0 1 1 3 2.4"/></svg>',
  ok: '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.8" stroke-linecap="round" stroke-linejoin="round"><path d="m5 12.5 4.5 4.5L19 7.5"/></svg>',
  bad: '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.8" stroke-linecap="round"><path d="M6 6l12 12M18 6 6 18"/></svg>'
};
function esc(s) { return s.replace(/[&<>"]/g, function (c) { return '&#' + c.charCodeAt(0) + ';'; }); }
function size(n) { return n >= 1048576 ? (n / 1048576).toFixed(1) + ' MB' : Math.max(1, Math.round(n / 1024)) + ' KB'; }
// "Title - Author.epub", as My Books shows it.
function title(name) {
  var base = name.replace(/\.[^.]+$/, ''), m = base.match(/^(.+?)\s+-\s+(.+)$/);
  return m ? esc(m[1]) + ' <small>' + esc(m[2]) + '</small>' : esc(base);
}
function info() {
  var x = new XMLHttpRequest();
  x.open('GET', '/info'); x.timeout = 5000;
  x.onload = function () {
    try { var r = JSON.parse(x.responseText); } catch (e) { return x.onerror(); }
    have = {}; (r.books || []).concat(r.fonts || []).forEach(function (n) { have[n.toLowerCase()] = true; });
    conn.className = 'on';
    conn.lastChild.textContent = 'Connected to eReaderDS v' + r.version + ' · ' + r.books.length + (r.books.length == 1 ? ' book' : ' books');
  };
  x.onerror = x.ontimeout = function () {
    conn.className = 'off';
    conn.lastChild.textContent = "Can't reach eReaderDS. Open Send books on it and reload this page.";
  };
  x.send();
}
function add(files) {
  for (var i = 0; i < files.length; i++) {
    var f = files[i], li = document.createElement('li');
    li.innerHTML = '<div class="ic"></div><div class="t"></div><div class="st"></div><div class="bar"><i></i></div>';
    li.querySelector('.ic').innerHTML = FONT.test(f.name) ? ICON.font : ICON.book;
    li.querySelector('.t').innerHTML = title(f.name);
    list.insertBefore(li, list.firstChild);
    if (!OK.test(f.name)) { finish(li, false, 'Not a book or font (eReaderDS takes .epub, .cbz, .txt, .ttf and .otf)'); tally.bad++; continue; }
    if (f.size > 300 * 1024 * 1024) { finish(li, false, 'Too big (the limit is 300 MB)'); tally.bad++; continue; }
    var job = { f: f, li: li };
    wait(job);
    queue.push(job);
  }
  document.getElementById('summary').style.display = 'none';
  next();
}
function wait(job) {
  job.li.className = 'wait';
  job.li.querySelector('.st').textContent = size(job.f.size) + (have[job.f.name.toLowerCase()] ? ' · already on eReaderDS, will be replaced' : '') + ' · waiting';
}
function finish(li, ok, text, job) {
  li.className = ok ? 'ok' : 'bad';
  li.querySelector('.ic').innerHTML = ok ? ICON.ok : ICON.bad;
  var st = li.querySelector('.st'); st.textContent = text;
  if (!ok && job) {
    var b = document.createElement('button'); b.className = 'retry'; b.textContent = 'Try again';
    b.onclick = function () { tally.bad--; wait(job); queue.push(job); next(); };
    st.appendChild(b);
  }
}
function summary() {
  var el = document.getElementById('summary'), n = tally.books + tally.fonts;
  if (!n && !tally.bad) return;
  var parts = [];
  if (tally.books) parts.push(tally.books + (tally.books == 1 ? ' book' : ' books') + ' in My Books');
  if (tally.fonts) parts.push(tally.fonts + (tally.fonts == 1 ? ' font' : ' fonts') + ' in Fonts');
  el.className = n ? '' : 'bad';
  el.innerHTML = '<b>' + (n ? 'Sent! ' + parts.join(' and ') + '.' : 'Nothing was sent.') + '</b><span>'
    + (tally.bad ? tally.bad + (tally.bad == 1 ? " file wasn't" : " files weren't") + ' sent. ' : '')
    + (n ? 'Tap Done on eReaderDS when you’ve finished, or send more.' : '') + '</span>';
  el.style.display = 'block';
}
function next() {
  if (busy) return;
  if (!queue.length) { summary(); info(); return; }
  busy = true;
  var job = queue.shift(), li = job.li, st = li.querySelector('.st'), bar = li.querySelector('.bar i'), x = new XMLHttpRequest();
  li.className = ''; bar.style.width = '0';
  st.textContent = 'Sending…';
  x.open('POST', '/upload?name=' + encodeURIComponent(job.f.name));
  x.upload.onprogress = function (e) {
    if (!e.lengthComputable) return;
    var p = Math.floor(e.loaded / e.total * 100);
    bar.style.width = p + '%';
    st.textContent = p < 100 ? 'Sending… ' + p + '% of ' + size(e.total) : 'Saving to the SD card…';
  };
  x.onload = function () {
    var r = {}; try { r = JSON.parse(x.responseText); } catch (e) {}
    if (x.status == 200 && r.ok) {
      var font = FONT.test(job.f.name);
      if (font) tally.fonts++; else tally.books++;
      have[job.f.name.toLowerCase()] = true;
      finish(li, true, (r.replaced ? 'Replaced in ' : 'Added to ') + (font ? 'Fonts' : 'My Books') + ' · ' + size(r.size || job.f.size) + ' saved');
    } else { tally.bad++; finish(li, false, r.error || ('Failed (' + x.status + ')')); }
    busy = false; next();
  };
  x.onerror = function () { tally.bad++; finish(li, false, "Couldn't reach eReaderDS. Is its Send Books screen still open?", job); busy = false; next(); };
  x.send(job.f);
}
document.getElementById('pick').onchange = function () { add(this.files); this.value = ''; };
var drop = document.getElementById('drop');
['dragenter', 'dragover'].forEach(function (t) { document.addEventListener(t, function (e) { e.preventDefault(); drop.className = 'over'; }); });
['dragleave', 'drop'].forEach(function (t) { document.addEventListener(t, function (e) { e.preventDefault(); drop.className = ''; }); });
document.addEventListener('drop', function (e) { add(e.dataTransfer.files); });
window.addEventListener('beforeunload', function (e) { if (busy || queue.length) { e.preventDefault(); e.returnValue = ''; } });
info();
</script></body></html>
]==]

local STATUS = { [200] = "OK", [400] = "Bad Request", [404] = "Not Found", [411] = "Length Required",
    [413] = "Payload Too Large", [415] = "Unsupported Media Type", [500] = "Internal Server Error" }

local function send(client, code, ctype, body, cache)
    local data = "HTTP/1.1 " .. code .. " " .. (STATUS[code] or "") .. "\r\nContent-Type: " .. ctype
        .. "\r\nContent-Length: " .. #body .. "\r\nCache-Control: " .. (cache or "no-store")
        .. "\r\nConnection: close\r\n\r\n" .. body
    -- A second at a time (see handle), until it's all gone or the phone stops taking it.
    local i, moved = 1, love.timer.getTime()
    while i <= #data do
        local last, e, partial = client:send(data, i)
        if last then return end
        if (partial or 0) >= i then i, moved = partial + 1, love.timer.getTime() end
        if e ~= "timeout" or ctl:peek() == "stop" or love.timer.getTime() - moved > STALL then return end
    end
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
        local stem = name:sub(1, 200 - #ext):gsub("[\192-\255][\128-\191]*$", "")   -- not half a character
        name = stem .. ext
    end
    return name
end

local function exists(path)
    local f = io.open(path, "rb")
    if f then f:close() return true end
    return false
end

local function file_size(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local n = f:seek("end")
    f:close()
    return n
end

-- The books and fonts already there (so the page can say a file will replace one).
local function names(dir, exts)
    local list = {}
    local p = dir and io.popen('ls -1 "' .. dir .. '" 2>/dev/null')
    if not p then return list end
    for n in p:lines() do
        local ext = (n:match("%.([^.]+)$") or ""):lower()
        if exts[ext] and not n:match("^%.") then list[#list + 1] = json_str(n) end
    end
    p:close()
    return list
end

-- The page is set in the app's own font.
local FONT_FILES = { ["/font/r.ttf"] = "fonts/CrimsonPro-Regular.ttf", ["/font/b.ttf"] = "fonts/CrimsonPro-Bold.ttf" }

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
    if name == "" or not (ext == "epub" or ext == "cbz" or ext == "txt" or font) then
        return reply(client, 415, false, { error = "Only books (.epub, .cbz, .txt) and fonts (.ttf, .otf)" })
    end
    local dir = font and dirs.fonts or dirs.books
    if not dir then return reply(client, 500, false, { error = "There's no fonts folder" }) end
    local total = tonumber((headers["content-length"] or ""):match("^%d+$") or "")
    if not total then return reply(client, 411, false, { error = "The browser didn't say how big it is" }) end
    if total > MAX_SIZE then return reply(client, 413, false, { error = "Too big (the limit is 300 MB)" }) end

    local path = dir .. "/" .. name
    local part = dir .. "/." .. name .. ".part"
    local f = io.open(part, "wb")
    if not f then return reply(client, 500, false, { error = "Couldn't write to the SD card" }) end
    out:push({ kind = "start", name = name, total = total })
    local got, last, err = 0, 0, nil
    local moved = love.timer.getTime()
    while got < total do
        if ctl:peek() == "stop" then err = "eReaderDS stopped receiving"; break end
        local data, e, partial = client:receive(math.min(CHUNK, total - got))
        data = data or partial
        if data and #data > 0 then
            if not f:write(data) then err = "The SD card is full"; break end
            got = got + #data
            moved = love.timer.getTime()
        end
        -- (Waits are a second at a time, so Done is never kept waiting.)
        if e == "timeout" then
            if love.timer.getTime() - moved > STALL then err = "The connection stalled"; break end
        elseif e then
            err = "The connection was lost"; break
        end
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
        if not os.rename(part, path) and not (os.remove(path) and os.rename(part, path)) then
            err = "Couldn't save it on the SD card"
        elseif file_size(path) ~= total then err = "It didn't save properly (is the SD card full?)"; os.remove(path) end
    end
    if err then
        os.remove(part)
        out:push({ kind = "failed", name = name, message = err })
        return pcall(reply, client, 500, false, { error = err })
    end
    out:push({ kind = "done", name = name, path = path, font = font, replaced = replaced })
    reply(client, 200, true, { name = name, replaced = replaced, size = total })
end

-- A line of the request, until the deadline (love.timer time) or "stop":
-- one slow or silent connection mustn't hold up the others (browsers open
-- spare connections that send nothing).
local function receive_line(client, deadline)
    local got = ""
    while true do
        local line, e, partial = client:receive("*l")
        if line then return got .. line end
        got = got .. (partial or "")
        if e ~= "timeout" or ctl:peek() == "stop" or love.timer.getTime() > deadline or #got > 16384 then return nil end
    end
end

local function handle(client)
    client:settimeout(0.5)
    local t0 = love.timer.getTime()
    local line = receive_line(client, t0 + 4)             -- (the first line: 4 s)
    client:settimeout(1)
    if not line then return end
    local method, target = line:match("^(%u+)%s+(%S+)")
    local headers, n = {}, 0
    while true do
        local h = receive_line(client, t0 + 10)            -- (all the headers: 10 s)
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
    elseif method == "GET" and p == "/info" then
        send(client, 200, "application/json", '{"version":' .. json_str(dirs.version or "") .. ',"books":['
            .. table.concat(names(dirs.books, { epub = true, cbz = true, txt = true }), ",") .. '],"fonts":['
            .. table.concat(names(dirs.fonts, { ttf = true, otf = true }), ",") .. "]}")
    elseif method == "GET" and FONT_FILES[p] then
        local data = love.filesystem.read(FONT_FILES[p])
        if data then send(client, 200, "font/ttf", data, "max-age=86400")
        else send(client, 404, "text/plain", "Not found") end
    elseif method == "POST" and p == "/upload" then
        if (headers["transfer-encoding"] or ""):lower():find("chunked") then
            return reply(client, 411, false, { error = "The browser didn't say how big it is" })
        end
        upload(client, target, headers)
    else
        send(client, 404, "text/plain", "Not found")
    end
end

-- An uncommon port, so it won't clash with other servers; the next if it's taken.
local server, port
for _, p in ipairs({ 2045, 2046, 2047 }) do
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
