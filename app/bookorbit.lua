-- BookOrbit (a self-hosted book server): turns what its catalog API answers into
-- Get Books entries. Pure (no screen, no network): main.lua fetches and draws.
-- The API is the one its KOReader plugin uses, under <server>/api/v1/koreader/plugin,
-- with the same login as KOReader sync (x-auth-user and x-auth-key headers).
local M = {}

M.API = "/api/v1/koreader"

-- The server's address from a KOReader Sync address ("https://books.example.com/api/v1/koreader"),
-- or nil if it isn't one.
function M.base(sync_url)
    return type(sync_url) == "string" and sync_url:match("^(https?://[^/]+)" .. M.API:gsub("%-", "%%-") .. "/*$") or nil
end

-- A path from the API ("/api/v1/...") on the server, or an address as it is.
function M.url(base, path)
    if type(path) ~= "string" or path == "" then return nil end
    if path:match("^https?://") then return path end
    return base .. (path:sub(1, 1) == "/" and "" or "/") .. path
end

function M.plugin(path) return M.API .. "/plugin/" .. path end

-- "Kirsten Raymonde, Jane Doe" and so on.
local function names(list)
    if type(list) ~= "table" then return "" end
    local out = {}
    for i, n in ipairs(list) do if type(n) == "string" and n ~= "" then out[#out + 1] = n end end
    return table.concat(out, ", ")
end

local function plural(n, one, many) return n .. " " .. (n == 1 and one or many) end

-- One book from a list or the dashboard, as a Get Books entry. Its download
-- address isn't known until its details are fetched (`bo.detail`).
function M.book(b, base)
    if type(b) ~= "table" or not b.id or type(b.title) ~= "string" then return nil end
    local author = names(b.authors)
    local pct = tonumber(b.progressPercentage)
    local note = {}
    if b.seriesName and b.seriesName ~= "" then
        note[#note + 1] = b.seriesName .. (b.seriesIndex and (" #" .. b.seriesIndex) or "")
    end
    if pct and pct > 0 and b.readStatus ~= "read" then note[#note + 1] = string.format("%d%% read", math.floor(pct + 0.5)) end
    if b.readStatus == "read" then note[#note + 1] = "Finished" end
    local formats, epub = {}, false
    for _, f in ipairs(type(b.formats) == "table" and b.formats or {}) do
        local ext = tostring(f):lower()
        if ext == "epub" or ext == "txt" then epub = ext else formats[#formats + 1] = ext:upper() end
    end
    local it = { title = b.title, author = author, summary = table.concat(note, "  ·  "), formats = epub and {} or formats,
        bo = { id = b.id, detail = M.url(base, b.detailUrl) or (base .. M.plugin("catalog/books/" .. b.id)) } }
    if b.hasCover ~= false and b.thumbnailUrl then it.cover = M.url(base, b.thumbnailUrl) end
    -- Only EPUB and TXT can be read here: those get the download paths.
    if epub then it.book = { ext = epub, href = false, size = nil } end
    return it
end

function M.books(list, base)
    local out = {}
    for _, b in ipairs(type(list) == "table" and list or {}) do
        local e = M.book(b, base)
        if e then out[#out + 1] = e end
    end
    return out
end

-- The files in a book's details, as { ext, href, size } for the first one this
-- reader can open, or nil.
function M.file(detail, base)
    for _, f in ipairs(type(detail) == "table" and type(detail.files) == "table" and detail.files or {}) do
        local ext = tostring(f.format or ""):lower()
        if (ext == "epub" or ext == "txt") and f.downloadUrl then
            return { ext = ext, href = M.url(base, f.downloadUrl), size = tonumber(f.sizeBytes) }
        end
    end
end

-- The first page: what you're reading, then a row for each way in.
--   dash = the answer of catalog/dashboard.
function M.home(dash, base)
    local out = {}
    dash = type(dash) == "table" and dash or {}
    local reading = M.books(dash.continueReading, base)
    for _, e in ipairs(reading) do
        e.summary = "Continue reading" .. (e.summary ~= "" and ("  ·  " .. e.summary) or "")
        out[#out + 1] = e
    end
    local function tile(title, sub, bo, summary)
        out[#out + 1] = { title = title, author = sub or "", summary = summary or "", formats = {}, bo = bo }
    end
    local disc = M.books(dash.discover, base)
    if #disc > 0 then tile("Discover", plural(#disc, "book", "books"), { kind = "list", entries = disc, title = "Discover" },
        "A handful of books from your library you haven't opened.") end
    local done = M.books(dash.finishedThisYear, base)
    if #done > 0 then tile("Finished this year", plural(#done, "book", "books"), { kind = "list", entries = done, title = "Finished this year" }) end
    for _, s in ipairs(type(dash.sections) == "table" and dash.sections or {}) do
        if s.id ~= "continue-reading" and s.title then
            if s.booksHref then
                tile(s.title, "", { kind = "books", href = s.booksHref, title = s.title })
            elseif s.href then
                tile(s.title, "", { kind = "sections", href = s.href, title = s.title })
            end
        end
    end
    local goal, streak = dash.readingGoal, dash.readingStreak
    if type(goal) == "table" and tonumber(goal.goalBooks) and tonumber(goal.goalBooks) > 0 then
        out[#out + 1] = { title = "Reading goal " .. tostring(goal.year or ""),
            author = (goal.completedBooks or 0) .. " of " .. goal.goalBooks .. " books",
            summary = type(streak) == "table" and tonumber(streak.currentStreak) and ("Reading streak: " ..
                plural(streak.currentStreak, "day", "days") .. " (longest " .. (streak.longestStreak or 0) .. ").") or "",
            formats = {}, info = true }
    end
    return out
end

-- A list of authors, series, libraries and so on: each a way into a list of books.
function M.sections(resp, base)
    local out = {}
    for _, s in ipairs(type(resp) == "table" and type(resp.items) == "table" and resp.items or {}) do
        if type(s.title) == "string" and s.booksHref then
            local sub = tonumber(s.count) and plural(s.count, "book", "books") or ""
            local who = type(s.authorNames) == "table" and names(s.authorNames) or ""
            if who ~= "" then sub = sub .. "  ·  " .. who end
            local cover
            local p = type(s.previewBooks) == "table" and s.previewBooks[1]
            if p and p.hasCover ~= false and p.thumbnailUrl then cover = M.url(base, p.thumbnailUrl) end
            out[#out + 1] = { title = s.title, author = sub, summary = "", formats = {}, cover = cover,
                bo = { kind = "books", href = s.booksHref, title = s.title } }
        end
    end
    return out
end

return M
