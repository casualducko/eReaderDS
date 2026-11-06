-- luajit tools/test-bookorbit.lua   (from the repo root)
package.path = "app/?.lua;" .. package.path
local B = require("bookorbit")
local n = 0
local function eq(a, b, what) n = n + 1; if a ~= b then error(what .. ": got " .. tostring(a) .. ", want " .. tostring(b), 2) end end

eq(B.base("https://books.example.com/api/v1/koreader"), "https://books.example.com", "base")
eq(B.base("http://192.168.1.5:3000/api/v1/koreader/"), "http://192.168.1.5:3000", "base with port and slash")
eq(B.base("https://sync.koreader.rocks"), nil, "not BookOrbit")
eq(B.url("https://x", "/api/v1/a"), "https://x/api/v1/a", "url path")
eq(B.url("https://x", "https://y/z"), "https://y/z", "url absolute")

local b = B.book({ id = 7, title = "Dune", authors = { "Frank Herbert" }, seriesName = "Dune", seriesIndex = "1",
    progressPercentage = 25.2, readStatus = "reading", formats = { "epub", "pdf" }, hasCover = true,
    thumbnailUrl = "/t/7", detailUrl = "/d/7" }, "https://x")
eq(b.title, "Dune", "title"); eq(b.author, "Frank Herbert", "author")
eq(b.summary, "Dune #1  ·  25% read", "note")
eq(b.cover, "https://x/t/7", "cover"); eq(b.bo.detail, "https://x/d/7", "detail")
eq(b.book.ext, "epub", "epub is readable"); eq(#b.formats, 0, "no 'only as' warning when an epub exists")

local pdf = B.book({ id = 8, title = "Scan", authors = {}, formats = { "pdf" }, hasCover = false }, "https://x")
eq(pdf.book, nil, "pdf only: no download"); eq(pdf.formats[1], "PDF", "pdf listed"); eq(pdf.cover, nil, "no cover")
eq(B.book({ title = "no id" }, "https://x"), nil, "bad entry")

local f = B.file({ files = { { format = "pdf", downloadUrl = "/p" }, { format = "epub", downloadUrl = "/f/1", sizeBytes = 99 } } }, "https://x")
eq(f.href, "https://x/f/1", "file href"); eq(f.size, 99, "file size"); eq(f.ext, "epub", "file ext")
eq(B.file({ files = { { format = "pdf", downloadUrl = "/p" } } }, "https://x"), nil, "no readable file")

local home = B.home({ continueReading = { { id = 1, title = "A", authors = { "X" }, progressPercentage = 40, readStatus = "reading", formats = { "epub" } } },
    discover = { { id = 2, title = "B", authors = {}, formats = { "epub" } } }, finishedThisYear = {},
    sections = { { id = "continue-reading", title = "Continue reading", booksHref = "/c" },
        { id = "recent", title = "Recently added", booksHref = "/r" }, { id = "authors", title = "Authors", href = "/a" } },
    readingGoal = { goalBooks = 12, completedBooks = 3, year = 2026 }, readingStreak = { currentStreak = 1, longestStreak = 5 } }, "https://x")
eq(home[1].title, "A", "continue reading first"); eq(home[1].summary, "Continue reading  ·  40% read", "continue note")
eq(home[2].title, "Discover", "discover tile"); eq(#home[2].bo.entries, 1, "discover books")
eq(home[3].title, "Recently added", "recent"); eq(home[3].bo.kind, "books", "recent kind")
eq(home[4].title, "Authors", "authors"); eq(home[4].bo.kind, "sections", "authors kind")
eq(home[5].author, "3 of 12 books", "goal"); eq(home[5].info, true, "goal is not a link")
eq(#B.home(nil, "https://x"), 0, "empty dashboard")

local sec = B.sections({ items = { { title = "Joe", count = 1, booksHref = "/b?a=Joe", previewBooks = { { thumbnailUrl = "/t/1", hasCover = true } } },
    { title = "bad" } } }, "https://x")
eq(#sec, 1, "sections need a booksHref"); eq(sec[1].author, "1 book", "count"); eq(sec[1].cover, "https://x/t/1", "section cover")
print("bookorbit: " .. n .. " checks ok")
