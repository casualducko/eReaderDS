# Changelog

## Unreleased

- **Sync tells you your place is saved.** When the server already has this
  device's current place (often because it was sent on its own when the book
  opened), Sync with KOReader now says "Your place is saved on the sync
  server · 53% · Chapter 25 · sent 2 minutes ago" instead of "Already in
  sync"; that stays for when the other device is at the same place. A place
  also counts as new when only the percentage moved (a long paragraph can
  span pages), so reading on inside one is sent too.

## v1.15.0

- **Send my place / Get my place from the server** (Settings → KOReader
  Sync), like KOReader's Push and Pull, for choosing the direction yourself;
  they replace "Sync this book now". **Send** puts this device's place on the
  server under both of the book's names, over whatever is there. **Get** goes
  to the latest place another device saved (a new one first), even if you've
  read past it here; going back more than half a percent asks first ("Go back
  to 20%?"). Both say what happened ("Sent your place to the sync server ·
  22% · VII: The Way of Love · CrossPoint"). **Sync with KOReader** on
  Settings' first page stays the one-button smart sync. (The shared steps,
  checking the server's answers, reading its places, finding a place in the
  book and going there, are now one function each.)

## v1.14.0

- **KOReader Sync checks both of a book's names.** A book is known on the
  server by an ID made from its file name or from its contents, and a device
  set to one never saw a place saved under the other: an Xteink X4 (file
  name) at Chapter 5 and this device set to File contents gave "Already in
  sync" at Chapter 4. Now each sync looks the book up under both IDs and
  sends your place under both, so KOReader and CrossPoint devices stay in
  step whatever they're set to. A place from another device that hasn't been
  dealt with wins over one that has, under either ID; not by timestamp (the
  X4's Chapter 5 carried an earlier time than this device's Chapter 4). What
  has been dealt with is remembered per ID. A 404 counts as "nothing there
  yet" (some servers answer that way). Checked end to end against a stand-in
  server with the reported case and the book from it.
- **Sync messages say more.** Each leads with what happened, then where:
  "Already in sync · 10% · IV: The Clouded Moon", "Sent your place to the
  sync server · 22% · VII: The Way of Love · CrossPoint was at 20%", "Moved to
  where you were on CrossPoint · 21% · VII: The Way of Love · just now". The
  question names the chapter too ("V: The Weissen Rössl, where you were on
  CrossPoint 8 minutes ago. You're at 10% here."), and a question card's
  detail now wraps to three lines instead of being cut off. Syncing by hand
  shows "Syncing with CrossPoint…"; problems name the server and the reason
  (and a refused password says to log in again); logging in or making an
  account says which server.
- **No more boxes by dashes** in Standard Ebooks books: their invisible word
  joiners (U+FEFF, U+2060) and zero-width spaces are left out when drawing
  (the fonts have no glyph for them). The text itself is unchanged, so places
  and highlights stay where they were.
- **README:** new screenshots (reading, My Books, Contents, Settings, the
  Themes page, looking up a word), an On-screen keyboard section, the Themes
  page and pictured letters under Features, and a KOReader Sync
  troubleshooting row.

## v1.13.1

- **KOReader sync remembers what it's dealt with.** The server's timestamp
  for a place you've jumped to, stayed away from, or sent is now saved per
  account, server and book (`sync-seen.txt`), not just kept until quitting.
  Before, after a restart an old place from another device looked new again
  and could be offered ("Continue from 40%?") even when you'd read past it.
- **A place read offline goes out.** If the server's record is this device's
  own but older than where you are (read on offline, then quit), it's sent
  when the book opens, instead of waiting for a page turn.
- Paging back now counts for sync's regular check, like paging forward.
- Checked end to end against a stand-in server: a new place is offered,
  Jump is remembered across restarts, a newer place is offered again, Stay
  sends this place, and an out-of-date own record is replaced.
- **README:** how KOReader Sync works, what File name and File contents mean
  (and why every device must use the same), what Send book details sends, and
  the settings for an Xteink X4.

## v1.13.0

- **Keyboards made consistent.** All six text fields (Find in Book, Get
  Books search, the KOReader account, password, server address and name)
  already shared one keyboard; now what's around it matches too. The button
  list on the top screen names the confirm key each field really has (it
  said "Start, X: Search" even where the key read Next, Log in or Save),
  says B cancels when the field is empty, and on a password explains the
  eye. Titles are in Title Case like the app's pages: **KOReader Sync
  Account**, **Your Own Sync Server**, **Server Address**, **Server Name**.
- **Web address keys:** typing a server address, a row above the numbers
  holds **https://**, **http://**, **www.**, **.com**, **:** and **/**. The
  first two set the address's start (replacing one already there), **www.**
  goes in after it, and the rest type at the end, so no trip to the #@ layer.
- **Shift is for one letter**, then it's back to small letters, as on a
  phone; press it again for caps lock (a bar under the arrow), and again to
  turn it off.
- **A cursor:** tap in the typed text to put it there, or press D-pad up
  from the top row of keys to reach the text, then left/right move it (down
  goes back to the keys). Typing, Delete and Space work at the cursor, and
  the text scrolls to keep it in view. On a password, A there shows or hides
  it, like the eye. (A `draw` test action draws the screen mid-script, so
  scripted taps have something to measure.)
- **Log out** of KOReader Sync asks first ("Log out of KOReader Sync?").

## v1.12.0

- **Settings reorganised around why you open it mid-book.** Page 1, **This
  book:** Table of Contents, Bookmarks and Highlights, Find in Book, Jump to
  %, and **Sync with KOReader** when sync is on (it used to be three levels
  down); **Reading:** Brightness first (the change most often wanted, at
  night), Text size, Theme, Fonts; then **My Books**, leaving the book, on its
  own at the end. Page 2 holds what's set once: **Page layout** (Line spacing,
  the two margin rows together, Justify, Hyphenation), **More settings**
  (Night Theme, which had a group to itself, Status Bar, Reading & Device,
  KOReader Sync), then Help (moved off page 1), About and Quit. The vague
  "Main" and "Other" groups are gone. Every Settings page now uses one row
  height (58 px; rows used to be 74 px on roomy pages and shrink on full
  ones, so page 1's text looked bigger than page 2's).
- **Night Theme is now Night Mode** (the row, its page, and the Themes page
  while choosing for night); inside, the row is just **Theme**.
- **KOReader Sync → Server** opens its own page (tap or A): CrossPoint,
  KOReader or Your own, the current one ticked; picking one goes back.
  ‹ › no longer changes it (two presses used to land on typing an address).
  **Your own server** has a name as well as an address: **Add your own
  server** asks for the address, then a name (empty: the address). Once
  saved it's listed by name; A (or a tap) opens a card to **Use this
  server**, **Edit address**, **Rename** or **Delete** it (deleting the one in
  use goes back to CrossPoint).
- **On-screen keyboard:** the shift key is an up arrow (filled while capitals
  are on) instead of "Aa"; a password field has an **eye** at its end to show
  or hide what's typed: tap it, or press up from the top row of keys and A.

## v1.11.0

- **Eight more dark themes**, after what readers and programmers pick for
  long dark-screen sessions: **Dark Sepia** (warm brown paper at night),
  **Gruvbox**, **Nord**, **Solarized Dark**, **Dracula**, **Catppuccin**,
  **Everforest**, and **Red Night** (red on black, which keeps your eyes used
  to the dark). Their text is a little softer than the originals' for
  reading.
- **Five more light themes:** **Gruvbox Light**, **Catppuccin Latte** and
  **Rosé Pine Dawn** (the light versions of favourite palettes), **Parchment**
  (warm, deeper cream) and **Sky** (pale blue: tinted pages some readers,
  dyslexic readers especially, find easier than white), and **Mint** (the
  Kindle app's pale mint page with dark gray-green text, restful at low brightness;
  greener than Sage). All 25 themes are on
  the Themes page (tap Theme in Settings) and can be the night theme.
- **Letters drawn as pictures stay in the line.** Some older EPUBs spell
  characters their fonts lacked with tiny images (Daemon's "dē′mən":
  `d<img src="ebar.jpg"/>’m<img src="e.jpg"/>n`); each one used to break the
  line and sit on its own. An image glued to the text (no space) now stays in
  its word: letter-sized ones grow with the text size, sit on the baseline and
  take the theme's ink; a large one still gets a block of its own. Other
  images are handled as before, and KOReader positions are unchanged (checked
  on 100,000 positions). Tiny gray images count as line art even when cropped
  tight, so they don't show a white box on dark themes.

## v1.10.1

Full code review (every module), fixes only:

- **Crashes and hangs:** tapping the options card (My Books, Y) crashed
  (`choose_row` read the card after it closed). A damaged EPUB could crash the
  library scan on every start (unchecked zip directory; `Book.meta` now
  protected); a damaged dictionary crashed look-up (now left out). Quitting
  could wait minutes on an update or font download or a slow catalog (the
  network thread now stops at once, `Net.abort`); Done on Send Books could
  freeze for 20 s while a browser held a connection open (1 s waits).
- **Data safety:** a full SD card could replace progress, bookmarks or
  settings with an empty file (errors show at `close`, which wasn't checked;
  the written size is now verified), and an update could install cut-off
  files the same way. Two copies of one book (same title and author) shared
  a Highlights file and one could delete the other's; each file now says
  which book it belongs to. Settings edited on Windows (CRLF) are read
  correctly. Update zips with odd paths are refused; pre-releases skipped.
- **Turned round:** question cards (e.g. KOReader sync's "Continue from…")
  and the options card are drawn and tapped on the touchscreen; toasts
  follow the touchscreen when the screen changes.
- **Closing the lid** while idle had dimmed or turned off the screens: a
  button press could turn the backlight on inside the closed lid, and
  opening restored the dim level. A touch cut off by the lid no longer opens
  the word cursor or leaves a popup up.
- **Books:** a `>` inside an attribute (`alt="a > b"`) or a bare `<` in text
  no longer swallows text; `@media` blocks (Kindle-only rules) no longer hide
  paragraphs; a later `display:block` shows a class again; more named
  characters (&ntilde;, &euro; …); invalid character codes become U+FFFD
  instead of crashing the text drawing; long words, web addresses and text
  without spaces (Chinese, Japanese) wrap instead of running off the page;
  `<br><br>` leaves a blank line (verse); TXT files with a paragraph per
  line, UTF-16 and Windows-1252 files read properly; TOC entries whose file
  name case differs are kept; the author sort name is found in EPUB 3 files
  that also have a cover `<meta/>`; `.ttc` fonts get their names.
- **Speed:** a chapter of thousands of `<span>`s parses in a fraction of the
  time (no repeated string copies); KOReader positions resolve in linear
  time (a file with unclosed `<p>`s took seconds); changing the My Books
  order no longer rescans the SD card; titles are shortened by halving;
  background work redraws ten times a second, not every step; the clock is
  looked at once a second.
- **Memory:** covers dropped from the library, Get Books and Contents caches
  are released at once; font previews (pinch) are capped; TLS objects are
  freed when a connection closes.
- **Smaller fixes:** Find in Book left part way carries on from there instead
  of showing partial results as complete, and one unreadable file no longer
  stops it; the update page no longer says "up to date" when the check
  failed; Get Books search and "load more" failures can be retried; section
  jumps count as moving for KOReader sync, and a sync server error (5xx)
  counts as failing; What's New's wrapped lines line up; the Search row
  looks selectable; the bookmarks count leaves out the "this page" row;
  footnote marks are matched exactly (not — or …); crash reports keep the
  error text while hiding book paths; a book replaced over Wi-Fi while open
  is reopened fresh; web addresses with spaces, `?query` or `user@` work;
  HTTPS redirects never downgrade or carry the sync login to another host;
  Digest logins pick an MD5 challenge; the launcher lists an update's files
  before moving them.
- Dead code removed (`SB.time`, `action_text`, `pg.more`, …) and stale
  comments corrected.

## v1.10.0

- **Hold it the other way round:** Settings → Reading & Device → **Hold it
  with buttons** ‹ On the right / On the left ›. On the left, everything turns
  180° (the device turned clockwise). Pages keep their reading order, so while
  reading the first page is on the touchscreen (tap its right half to go on,
  its outer top corner, now top left, to bookmark; the Notes button and the
  ribbon follow it); menus and lists stay on the touchscreen, now on the left.
  The face buttons act by where they are, like the D-pad: the button where A
  was does A's job (A↔Y, B↔X), and every hint shows the letter on the button
  to press. Done at the edges (`app.flipped`, `app.touch_side`, `app.key`,
  `page_transform`, `touch_to_page`, the gamepad mapping), not screen by
  screen. The code for the old "Flip for other hand" (removed in v0.3) was the
  starting point.
- Turned round, while reading the face buttons turn pages like the D-pad: A
  and X forward, B and Y back (as printed); Start or the curved arrow opens
  Settings, a held word looks it up. In menus they keep their jobs by
  position, and a question card still takes its answer from them. Help shows
  the buttons (and the bookmark's top-left corner) for this grip.
- Turned round, D-pad up (as you hold it) does what Y does normally: the
  word cursor, to look a word up or highlight (Select at the first and last
  word). Left, right and down still turn pages.
- Turned round, the face buttons are a second D-pad everywhere (held that
  way: Y top, A bottom, X right, B left): in menus Y is up, A down, X OK and
  B back, and Select does Y's usual job (delete, options, the keyboard's
  space); in the word cursor Select still highlights. Hints and Help show
  these buttons (`app.flip_button`, `app.FLIP_KEYS`). A `btn:` test action
  presses a button as the gamepad would.

## v1.9.3

- **Themes page:** tap Settings → Theme (or press A on it) for every theme on
  the touchscreen, each with a swatch in its colours and ✓ on the one in use,
  and your book's page on the other screen in the one highlighted (E-ink's
  grain included), like the Fonts page. A or a second tap uses it. The
  Settings row ("Sepia", like Fonts) only opens the page now: no ‹ › (with them, a tap
  on the row did nothing). With the night theme on, it chooses the night
  theme.

## v1.9.2

- **Line art on the page, not in a white box** (from a beta tester's Star
  Wars and Ranger's Apprentice books): images that are mostly grayscale and
  white with a pale edge (chapter numbers, ornaments, title pages, drawings)
  are drawn in the theme's text colour, white becoming clear
  (`app.is_line_art` samples ~4000 pixels when the image loads;
  `app.INK_SHADER`), so they sit on Sepia, dark themes and E-ink like the
  text. Photos and colour pictures are drawn as they are.

## v1.9.1

- **KOReader Sync with CrossPoint:** after saving on an Xteink X4 a page or two
  further on, "Sync this book now" here said "Already in sync". The X4 sends
  just its chapter (`/body/DocFragment[19]/body/p[1]`) and a percentage, and
  "the same place" was anything within 0.2% of the book, a spread or two.
  Now the same place means on the spread you're looking at; otherwise, asked
  by hand and not having read on here, it goes to the other device's place
  (even one it has seen before). The log records each decision with the
  server's timestamps.

## v1.9.0

- **Review of everything since v1.2.0** (Send Books, Standard Ebooks,
  scrolling lists, the new list screens, My Books folders, titles, finished
  and series, highlight files, screens off, KOReader Sync). Fixed:
  - KOReader Sync: once a "Continue from…?" question had been answered, the
    regular 5-minute check stopped for the rest of the session. It goes on
    now.
  - KOReader Sync: quitting or closing the lid waits for the send, briefly;
    the limit now covers connecting and the secure handshake too (it could
    take 20 s on a server that didn't answer), and after a failure the
    waiting send is skipped for 10 minutes. All sync requests give up after
    8 s (quitting waits for one that's running).
  - Send Books: a very long file name was cut in the middle of a character
    (Japanese titles, say); uploads cut off by the app closing left hidden
    .part files behind, now removed when receiving starts.
  - Find in Book: the paragraph shown could start or end halfway through a
    character when there was no space nearby.

- **KOReader Sync:** share your place in a book with KOReader through its
  progress sync server (Settings → KOReader Sync: account, server, match
  books by file contents or file name, sync this book now, log out). The
  kosync protocol as KOReader's plugin speaks it (`kosync.lua`): the partial
  MD5 of the file (checked against KOReader's util.partialMD5) or of its name,
  x-auth-user / x-auth-key (the password's MD5), /users/auth, /users/create,
  GET and PUT /syncs/progress. Opening a book asks the server first and, if
  another device has been reading it since, offers to jump there (Jump /
  Stay); nothing is sent for a book until that's settled, so an older place
  here never overwrites a newer one there (the bug other readers hit). Sent
  when leaving the book (My Books, another book, Quit, lid, screens off) and
  every 5 minutes of reading. Places are to the paragraph: `Book:xpointer`
  gives KOReader's /body/DocFragment[n]/body/... path of the paragraph at the
  top of the page (the parser now keeps the element tree, numbered as
  KOReader's engine does), and `Book:resolve_xpointer` finds one (tested
  against KOReader's own pointers for five EPUBs: the right chapter always,
  the word within the landing paragraph 99.8-100%), else by chapter and
  percentage. `net.call` sends any method with a body; the keyboard gained
  capitals ("Aa"), symbols ("#@") and hidden passwords.
- KOReader Sync's **Server** is a choice (‹ ›): **CrossPoint**
  (sync.crosspointreader.com, the default: open-source, standard KOSync, and
  where CrossPoint/Xteink readers already are; KOReader's own was down for
  hours while this was built), **KOReader** (sync.koreader.rocks) or **Your
  own** (A types the address). Choosing one sets **Match books by** to that
  reader's default: File name for CrossPoint, File contents for KOReader.
  **Send book details** (off by default) adds KOReader's metadata (filename,
  title, authors) to what's sent.
- **Smart sync** (found testing with an Xteink X4: "Sync this book now" after
  reading on here took the book back to the X4's older place, since this
  device's pages hadn't been sent yet). Every check now decides like
  CrossPoint's smart sync, without trusting either device's clock: "new
  there" is a place from another device with a server timestamp we haven't
  seen; "moved here" is pages turned here since the last sync. Nothing new
  there: this device's place is sent (if it moved). New there, not moved
  here: go there (asked when opening a book). Both: ask, "Continue from 23%?
  Where you were on Xteink X4, just now. Here you're at 19%." (Jump / Stay).
  Practically the same place: sent only if this one is ahead. While a
  question is unanswered nothing is sent, not even on quitting. The regular
  5-minute send checks the server first the same way (it used to send
  blindly and could overwrite a newer place from another device).

## v1.8.0

- **Screens off when left alone:** Settings → Reading & Device → **Screens
  off after** (Never, 2, 5, 10, 15 or 30 minutes; 10 by default). With no
  button or touch for that long, the screens dim to a third for the last 30
  seconds, then turn off (progress saved; the app checks for input less
  often). The next button or touch turns them back on and does nothing else,
  so waking never turns a page. Not while sending books over Wi-Fi, during a
  Get Books download, or with the lid shut (`app.idle_tick`, `app.idle_input`).

## v1.7.0

- **Highlights and bookmarks as a file** (like a Kindle's "My Clippings"):
  `Ebook/Highlights/<Title - Author>.md`, one per book, in reading order under
  each chapter heading (a highlight as "“words” (16%)", a bookmark as
  "Bookmark (16%): first words…"). Written again whenever they change
  (`app.export_notes`), removed when a book has none, and written on opening
  a book that has some but no file yet (highlights made before this). My
  Books skips the Highlights folder. The Bookmarks and Highlights page says
  where it is.
- **Bookmarks and Highlights: All / Highlights / Bookmarks,** chosen with
  left/right or a tap on the label at the top right (like My Books' order,
  whose label can now be tapped too); All each time the page opens. The counts
  moved under the title on the top screen. Y deletes the selected entry in
  any view (it keyed on the row number, which broke without the "Bookmark
  this page" row).

## v1.6.0

- **Finished books:** reaching the last page marks a book finished (once;
  "Finished! It's marked as finished in My Books"). My Books shows "Reading · 16%" or "Finished ✓" beside the
  author, and the top screen "✓ Finished Sep 28, 2026". **Y** in My Books
  opens an options card on the touchscreen (`app.choose`): Mark as finished /
  not finished, Hide / Show finished books (the count says "· 3 finished
  hidden"; if all are, the top screen says so and Y shows them), and Delete
  from the SD card (still confirmed). Sorting by progress groups the books
  under headers, READING, NOT STARTED and FINISHED, like the sections in
  Settings (`app.library_layout`; the top book's group keeps its header while
  scrolling). Stored in `.ereaderds/finished.txt` (path, time);
  `lib_hide_finished` in settings.
- **Series:** a Series order in My Books (after Author): a header for each
  series with its books in order ("Book 1", "Book 1.5", "Book 2" beside the
  author), then "Not in a series"; the top screen says "The Expanse, book 2".
  Read with the title and author (`Book.meta`): Calibre's calibre:series and
  calibre:series_index, else EPUB 3 belongs-to-collection when its
  collection-type is "series" (Standard Ebooks' curated sets aren't). Saved in
  library.txt (two more columns; older lines are read again once).

## v1.5.0

- **Books in folders, and their real titles** (from a tester coming from
  Calibre and CrossPoint): My Books finds books in folders inside `Ebook`
  (6 levels; `find … -exec stat`), so a copied Calibre library
  (`Author/Title (id)/book.epub`) or your own folders work; hidden folders,
  `Fonts` and `Dictionaries` are skipped. The list shows each EPUB's own title
  and author (`Book.meta`: dc:title, the first dc:creator and its file-as,
  EPUB 2 or 3), not the file name, and sorting by author uses that sort name
  ("Follett, Ken"). They're read in the background a few books per frame
  (the file name shows until then), then the list is sorted again and saved
  in `.ereaderds/library.txt` (path, size, title, author, sort name), so later
  starts don't open the books. TXT files still use "Title - Author".
- **A tidier, more consistent UI** (every screen checked on the device):
  - Button hints look the same everywhere (`app.hints`): the button in the text
    colour, what it does dimmed, with even spacing; "3 / 12" counts the same
    way (`app.count`). They're on the touchscreen, once (Table of Contents,
    Bookmarks and Highlights and Find in book no longer repeat them on the top
    screen), and say what A does to the selected entry: Get books says
    download, read, open, search, start or try again (it said "open" for a
    book); Get more fonts says download or read in it; Bookmarks says bookmark
    this page or go there.
  - One confirmation card on the touchscreen (`app.ask`) before deleting a
    book, a bookmark or highlight, or a font; it was a card in Bookmarks, a box
    on the top screen in My Books, and a line in Get more fonts.
  - One button style (`app.button`): the label, then its button in small
    text ("Get books  Select", "Get more fonts  Y", "Done  B", "Delete  A").
  - My Books: Get books sits beside the title (like Get more fonts on the
    Fonts page), the hints are at the foot of the touchscreen, and the list
    shows two more books.
  - Settings shows the version on its main page only.
  - Find in book with no matches suggests fewer words or another spelling.
  - Page names are in title case: Find in Book, Get Books, Get More Fonts,
    What's New, Check for Updates, Report a Problem, About & Credits, Status
    Bar, Reading & Device, Night Theme, Send Books over Wi-Fi, Send from Your
    Phone or Computer, Add a Catalog (settings stay in sentence case).

## v1.4.0

- **Lists scroll with a finger:** sliding up/down on the touchscreen scrolls
  the list on screen: My Books, Get books, Table of Contents, Bookmarks and
  highlights, Find in book, Fonts and Get more fonts (the selection moves
  along at the edge, as with the D-pad; Get books loads more near the end).
  On the book pages and other screens a vertical slide is still brightness;
  on a list it never is, even one that fits. Help says so.
- **Bookmarks and Highlights** (now capitalized, in Settings and on its page) is one list on the touchscreen (swipe or D-pad
  to scroll, with counts at the top), and the other screen shows the selected
  one in full under a drawing of an open book with a ribbon: a highlight's
  whole passage marked as on the page, a bookmark's words, or this page (A
  bookmarks it). A tap selects an entry and a second tap goes there, as in My
  Books.
- **Table of Contents** and **Find in book** work the same way: one list on the
  touchscreen (swipe to scroll, tap to see, tap again to go there). Table of
  Contents shows the book (cover, title, author) and the selected entry: its
  full title and a bar of the book with its stretch and your place ("here"
  marks the current one in the list). Find shows the selected match in its
  whole paragraph, the match marked, with the chapter and %. Nothing to pick
  on the top screen any more.

## v1.3.1

- **Standard Ebooks: the full catalog.** Standard Ebooks has allowed
  eReaderDS's User-Agent through to its OPDS catalog, so Get books → Standard
  Ebooks now opens it: Newest, by Subject, by Collection, by Author, and
  Search. Its "All" list is left out (1,500 books in one 7 MB page; search
  finds them instead).
- Catalog pages are parsed on the network thread (new `feed` job in
  networker.lua) instead of the screen's: a big page (Standard Ebooks' Fiction,
  912 books, 4.5 MB) took 1.5 s on the device, during which the screen froze.
- Checked on ROCKNIX: Send books works with its default firewall.

## v1.3.0

- **Send books from a phone or computer:** Get books → **Send from your phone
  or computer** starts a small web server (`receiver.lua`, on its own thread,
  port 2045, or 2046/2047 if taken) while the screen is open. It shows the address and a
  QR code; the page it serves uploads books (.epub, .txt) to the books folder
  and fonts (.ttf, .otf) to the fonts folder, one at a time, with progress on
  both ends. Names are cleaned (no folders or odd characters), EPUBs are checked
  whole, files are written to a hidden `.part` and renamed, and a file with the
  same name is replaced. Closing the screen rescans the library (selecting the
  last book received) and fonts.
- The Send to eReaderDS page is set in Crimson Pro (served by the device), in
  light and dark, and says it's connected (version, how many books). Each file
  is a card with its title and author, progress, then "Added to My Books ·
  4.0 MB saved", "Replaced in …" or the reason it failed (Try again if the
  connection dropped); files already there are flagged before sending, and a
  summary follows each batch. The device checks the saved file's size before
  saying it's done. On the device, each file shows its title and author and
  "✓ Added to My Books · size" (or Replaced, or Failed: why), with a count.

## v1.2.1

- Settings: tapping "Swipe for more options" turns to page 2. Taps on ‹ and ›
  find them where they're drawn, even when a long value is shortened.
- A font that's gone from the SD card falls back to the default (Crimson Pro),
  not the first font in the list.
- Guards: the bookmark row's page words before the page is laid out; down on
  an empty Fonts filter; deleting a font with no fonts folder. Old unused
  Settings constants removed.

## v1.2.0

- **Crimson Pro** is built in and is new readers' default font (40 pt, as
  before), and the fallback font; readers keep the font they chose. It's no
  longer in Get more fonts (13 there now). `tools/build-fonts.py` can build
  just the families named.
- Get more fonts is in alphabetical order and has the All · Serif · Sans
  switch (tap it, or left/right), like the Fonts page. The Settings row is
  **Fonts** too.
- The font page is titled **Fonts**, with its **Get more fonts** button beside
  the title (no "+"); the list moves back up.

## v1.1.0

- **Settings: bigger rows, in pages.** The main page is two pages of rows
  about 66–74 px tall (were 37) in a larger font (36 px): 1. Contents,
  Bookmarks and highlights, Find in book, Jump to %, Library, Font, Text
  size, Theme, Brightness, Help (Update to v… on top when one is
  waiting); 2. line spacing, justify, hyphenation, margins, top/bottom
  margins, Night theme, Status bar, Reading & device, About eReaderDS, Quit. Dots show
  the page; swipe left/right, or up/down past the end, or left/right on a
  row with nothing to change. Sub-pages use the same rows, shrinking a
  little (to 58 px) to stay on one page, else spreading over pages.
- Settings names: **Table of Contents** (was Contents) and **My Books** (was
  Library), with the screens' titles to match. Quit is the last row of page
  2; page 1 ends with a "Swipe for more options ›" note (not a row, so the
  cursor never stops on it).
- Settings headings: **Main** above Table of Contents (so both pages start
  with a heading in the same place) and **Other** above Status bar.
- Help's text is larger (34 px, was 30), with the rows a little closer.
- Bookmarks and highlights: the first row says which page it bookmarks, like
  the bookmark rows ("Chapter 1 · 9% · I am by birth a Genevese…"); when it's
  bookmarked it reads "Remove the bookmark on this page". Bookmark snippets
  start at the text, not the chapter heading (which is shown beside them).
- Tapping **‹** or **›** on a row steps its value down or up (a tap used to
  always step it up); tapping the label selects the row. Tested on the
  device: 40 → 42 (›), 40 → 38 (‹), label leaves it.

## v1.0.0

The first full release (no longer a pre-release).

- The repository is now **casualducko/eReaderDS** (renamed from
  eReaderDS-beta; GitHub redirects the old addresses, so installed copies
  keep finding updates, fonts and What's new; checked on the device). The
  updater, Get more fonts, Report a problem and the readmes use the new name.
- Releases are normal GitHub releases now; a tag with a suffix
  (`v1.3.0-beta`) becomes a pre-release, which the updater never offers.
  The README's download link goes straight to the latest release, and the
  "test release" note is gone.
- Requests send a fixed user agent, `eReaderDS
  (+https://github.com/casualducko/eReaderDS)` (was `eReaderDS`), which
  Standard Ebooks is allowing through to its full catalog.

## v0.3.32

Review of the day's changes:
- Fonts from the fonts folder (now including downloaded ones) were read into
  memory and kept for good: only the 12 most recent font files are kept now,
  and the caches are cleared when fonts are added or removed (a deleted font
  was held until restart).
- A Contents entry in a file that can't be read no longer crashes the page
  (the chapter length across files looks at other files, so this came up
  more often).
- The crash screen quits by itself after 5 minutes (e.g. with the lid
  closed) instead of keeping the screens on.
- Get more fonts tidies away a download cut short by quitting (a hidden
  partial zip in the fonts folder).

## v0.3.31

- **Get more fonts:** a row at the end of the font list opens 14 free reading
  fonts to download over Wi-Fi (Alegreya, Cardo, Crimson Pro, Gelasio, IBM
  Plex Serif, Libre Baskerville, Newsreader, Noticia Text, Zilla Slab,
  Alegreya Sans, Fira Sans, IBM Plex Sans, Lato, Source Sans 3). The list and
  files are in the repo's `fontpack/` (built by `tools/build-font-pack.py`
  from a pinned Google Fonts commit; variable-only families cut into static
  regular / italic / bold / bold-italic like the bundled ones), fetched from
  raw.githubusercontent.com. Each row shows the family's name set in it (a
  white preview tinted to the theme); A downloads its zip into the fonts
  folder and it joins the font list; A then reads in it, Y deletes it (after
  asking). Tested on the device: list, download, reading in it, deleting.
  A **+ Get more fonts** button at the top of the font list (always in view)
  opens it; so does Y.
- README and the download's README: ROCKNIX installs over Wi-Fi, step by
  step (the card's `roms` is on a Linux partition Mac and Windows can't open;
  never let the computer format it): the device's address, Connect to Server
  (Mac) or `\\address` (Windows), the `games-roms` share's `ports` and `ebook`
  folders, then Update gamelists. Troubleshooting has a row for it.

## v0.3.30

- **Standard Ebooks** in Get books: its newest releases (the free
  New Releases feed) and Search over the whole collection (its OpenSearch
  Atom results; the full catalog feeds are for its patrons). Checked the
  other well-known free catalogs first: Feedbooks (gone), Internet Archive
  (times out), ManyBooks (blocked), unglue.it (10 s responses), Wikisource
  (one unsorted 700-item list) weren't good enough. Tested on the device:
  list, covers, search, download (the real SE edition).
- OPDS: Atom `enclosure` links count as downloads and `media:thumbnail` as a
  cover (plain Atom feeds like Standard Ebooks'); a search address's
  `{count}` is filled with 24.
- eReaderDS is now under the MIT License (LICENSE; copied into the
  download's LICENSES folder as eReaderDS-LICENSE.txt).
- opds.txt: `standardebooks = off` hides it; `gutenberg = off` now hides only
  Project Gutenberg.

## v0.3.29

- Pages are centred on their screens: equal side margins (Narrow 32/32, Normal
  52/52, Wide 77/77; were 36/28, 60/44, 90/64). The screens are apart, so a
  book-style narrow gutter pushed the left page's text toward the hinge. The
  totals are the same, so line lengths and page breaks don't change.
- Deleting from **Bookmarks and highlights** asks first: Y opens a card on the
  touchscreen ("Delete this highlight?" with its words, or the bookmark's
  chapter) with **Delete (A)** and **Keep (B)** buttons; tapping Delete
  deletes, a tap anywhere else or B keeps it.
- No more "‹ Back to …% (B)" after a jump (Contents, a bookmark or
  highlight, Jump to %, Find): B always opens Settings while reading.
- Test hooks: an `untoast` script action clears a message (for screenshots);
  with READER_DEBUG the log notes when a message opens and closes.

## v0.3.28

- **Highlights.** In look-up (Y), Select at the first word starts a
  highlight; moving extends it (shown as you go, on both pages, with a hint
  in place of the definition); Select saves it, B cancels. Select on a
  highlighted word removes it. They're a band in the theme's selection colour
  behind the words (drawn before the text, joined across the spaces), saved
  as chapter text offsets in `highlights.txt` (so they survive font and size
  changes; removed with the book), and listed in reading order on the
  **Bookmarks and highlights** page (A goes there, Y deletes; the Settings row
  has the same name). Layout items
  now carry their word's text offset. Tested on ROCKNIX: choosing, saving,
  the list, text size 40 → 30, removing.
- Help: a "Y, then Select" row explains highlighting, and the touchscreen side
  says a tap on a word while highlighting extends it; so does the README.

## v0.3.27

- **Chapters that span several EPUB files:** pages left, time left, "Page x
  of y" and the chapter progress bar now cover the whole chapter (from its
  Contents entry to the next), not just the current file. Files already laid
  out are counted exactly (their page starts are kept after the pages are
  dropped); others are estimated from their size and the text-per-byte and
  characters-per-page seen so far. Tested with a chapter over three files:
  60 pages, 57 estimated from the start, exact from the files read. A
  Contents that's just a title entry (the "chapter" would be most of the
  book) keeps the per-file count.
- **Crash handling:** an error now shows a plain screen in the theme ("eReaderDS
  ran into a problem… Press any button to quit") instead of LÖVE's error
  text, saves the reading position, and writes `crash.txt` (version, system,
  time, the error and where in the app's code; paths and book file names
  removed) to the data folder.
- **Report a problem:** the next start (same version) offers "eReaderDS
  closed unexpectedly last time / Tap here to report it"; the page shows a QR
  code that opens a GitHub bug report on the reader's phone with the version,
  system, title and code location filled in. Nothing is sent from the device.
  Also in Settings → About eReaderDS → Report a problem (version filled in).
  The link is kept short (~300 characters) so the code scans off the screen.
  QR encoding: qrencode.lua (BSD). The bug form lists ROCKNIX.

## v0.3.26

- **Settings reorganised.** The main page's Page section has a **Night
  theme** row next to Theme ("Dusk · 9 PM–7 AM" or "Off") that opens its
  own page. "Page turns & device" is now **Reading & device** (page turns,
  dictionary, the lid, and the time zone, moved from Status bar since it
  also sets the night theme's hours). A new **About eReaderDS** page holds
  What's new, Check for updates, Update notices and About & credits (and
  "Update to v…" when one is waiting; the bold "Update" moved to its row).
  Help stays on the main page.
- The main page's Night theme row ends in "›" like the other rows that open
  a page ("Off  ›"); on its page, the Night theme row shows just the theme
  (no "on now" / "from 9 PM").
- On the Night theme page the touchscreen shows the menu in the chosen
  night theme (E-ink filter included), so ‹ › previews each one; the top
  screen keeps the current theme.
- Keyboard: Cancel, Space, Delete and Search share one bottom row (2/4/2/2
  columns, lined up with the keys above) instead of two staggered rows;
  Search is filled as the main action, and the keys are a little taller.
- Help: the "In the library: …" line under the buttons is gone (the
  library shows its own button hints).

## v0.3.25

- **Night theme:** Settings → Page turns & device → Night → Night theme: pick a
  theme (e.g. Midnight or Amber) to use automatically between two hours (9 PM
  to 7 AM to start, in the clock's 12/24-hour style), by the device's clock
  and time zone. Checked once a minute, so it switches on the hour. While
  it's on, the Theme row changes the night theme and says "(night)". The
  Night theme row says whether it's on now ("Dusk · on now", "· from 9 PM",
  "· never on" when From and Until are the same hour).
- The "Night" theme is now called **Midnight** (so the night theme setting
  doesn't read "Night theme: Night"); a saved "Night" becomes Midnight.
- Clock: "Device clock" now uses the system's own time zone instead of
  forcing UTC. ROCKNIX runs its clock on UTC with a real zone (e.g. New
  York), so the status bar was 4 hours ahead there; the stock firmware's
  zone is UTC, so nothing changes on stock.

## v0.3.24

- **Delta updates:** the updater still downloads the release zip, but
  writes only the files that differ from the installed ones (a typical
  release: ~9 files, ~0.4 MB instead of 125 files, 41 MB) into `.delta`,
  with the installed `app/` files the new version dropped listed in
  `.delta/DELETE`. On ROCKNIX's SD card saving went from ~40 s to ~2 s.
- The launcher moves each changed file over the installed one (a rename,
  instant), deletes the dropped ones, and moves itself last. A moved file
  leaves `.delta` and READY is removed only at the end, so a start cut
  short (power off) finishes the job next time. Tested: normal apply,
  interrupted apply, a dropped file, result identical to the new release.
- The old whole-folder swap (`.update`) stays for an update downloaded by
  an older version. This release itself installs that way; deltas start
  with the update after it.

## v0.3.23

- The E-ink theme's filter (grain texture and shader) is made the first
  time that theme is shown, so other themes don't prepare it at startup.

## v0.3.22

- An opening screen ("eReaderDS / Opening…", in your theme) appears as
  soon as the window is up, instead of nothing until the book is ready.
  On the stock firmware it shows 1.6 s after launch (the page was 3.6 s).
- Faster start: the bundled fonts' names are read from their name tables
  alone instead of loading every font file in full (26 MB); the book now
  appears after 2.9 s instead of 3.6 s.
- The opening screen is drawn before the E-ink filter and page-turn
  meshes are set up (0.1 s sooner).
- The log records start-up timing (uptime when the launcher starts, when
  the app starts, when the opening screen shows and when it's ready).

## v0.3.21

- Installing an update no longer freezes on "Installing… 100%" while the
  files are saved to the SD card (about 40 s on ROCKNIX): the saving runs on
  a thread and the screen says "Saving to the SD card…". The downloaded zip
  is deleted before saving, so it isn't written out for nothing, and the
  files are saved before the READY marker, which is then saved on its own.

## v0.3.20

- Updating from v0.3.10 or older (which didn't record the version last
  run) now shows the "Updated, tap to see what's new" note too, instead of
  being taken for a new install.

## v0.3.19

- Find in book results are dropped when another book is opened or the book
  is deleted, instead of keeping the old book in memory.
- The library's book cover is a little smaller while the "v… is available"
  line is showing, so a long title and the progress bar don't run into it.
- The launcher removes an update folder it couldn't put in place, instead
  of trying it again on every launch.
- Tidied comments in the settings defaults and the OPDS module.

## v0.3.18

- The About page no longer has its own Check for updates button (it
  repeated the row just above it in Settings → Page turns & device).

## v0.3.17

- **Check for updates** on the About page too (tap it, or A), with where
  things stand ("Up to date", "v0.3.17 available", "v0.3.17 skipped").
- **Skip this version** on the update screen (tap it, or Y): no more notes
  about that version; the next one is offered as usual. Check for updates
  still finds it ("skipped").

## v0.3.16

- **Updates cope with trouble:** no Wi-Fi, a dropped connection, a busy
  GitHub or a cut-off download each give a plain message and **Try again**,
  and nothing half-downloaded is kept (leftovers from quitting mid-update are
  cleared the next time eReaderDS starts). The check at launch stays silent
  when it can't reach GitHub.
- The **update** screen shows what's coming in plain words, as on What's
  new (every version since yours), in the same, larger text.

## v0.3.15

- **Update notices** (Settings → Page turns & device): turn off the check for
  a new version at launch, and its notes. Check for updates still works.

## v0.3.14

- The version number at the top of Settings is a little bigger.

## v0.3.13

- Tapping anywhere but the **update** (or "what's new") note just dismisses
  it, instead of also turning the page.

## v0.3.12

- **What's new:** swipe to turn its pages, and the latest version stands out
  (a bigger heading, a "Latest" tag and a bar beside its notes).

## v0.3.11

- **What's new** (Settings → Page turns & device): the changes in each
  version, in plain words. After an update, a note offers it once ("Updated
  to v…: tap here to see what's new").
- Messages (toasts) are drawn in the theme's colours, with the first line in
  bold, instead of a black box.

## v0.3.10

- The **"Update available"** note can be tapped to go straight to the update
  (it stays up a little longer, 8 seconds).
- When an update is waiting, **Update** is in bold on the Page turns & device
  row in Settings.

## v0.3.9

- **Updates over Wi-Fi:** each time eReaderDS starts online, it checks for a
  newer version and says so, showing the new version and yours. Update from
  **Settings → Page turns & device** (or **Start** in the library with no book
  open): it downloads the release, unpacks it beside the app, and restarts into
  it. The launcher swaps it in, so the running app is never overwritten; your
  books, settings and progress aren't touched. "Check for updates" is there too.
- **Jump to %** is tidier: no "you are here" label (the marker stays) and no
  "Drag the bar" hint.
- The **library** list is on the touchscreen too, with Get books still at the
  bottom: tap a book to see its cover on the top screen, tap it again to
  open it.
- **Get books** lists are on the touchscreen: tap a catalog or book to see
  it on the other screen, tap it again to open or download it. The cover
  and details are on the top screen.
- The search keyboard starts with **no key highlighted**. The first D-pad
  press shows the highlight (on q); taps type without highlighting anything.
- **Gutenberg is fast again:** eReaderDS now goes straight to
  www.gutenberg.org. The old m.gutenberg.org address only redirects there,
  and lately answers slowly or with errors (504) much of the time.
- Gutenberg search results no longer list **Authors** and **Subjects**
  (Gutenberg refuses those lists to apps), and **Latest** no longer starts
  with "Follow new books on Facebook / Bluesky / Mastodon" (links to those
  sites, which can't be opened here).
- A catalog that's slow to start answering, or busy, is tried again at once
  (up to twice) instead of waiting out its errors.
- The font list is **alphabetical** (your own fonts included), with an
  **All · Serif · Sans** switch at the top (left/right, or tap it). The sample
  page says where your own fonts go.
- **Font** in Settings opens its own spread: the fonts on the touchscreen,
  each in its own typeface, and a sample page on the other screen that
  changes as you scroll (at a fixed size, so fonts compare fairly). A or a
  second tap uses it. (Left/right on the Font row no longer switch fonts:
  select it to choose.)
- **Seven more fonts:** EB Garamond, Lora, Merriweather, PT Serif, Spectral,
  Vollkorn and Andika (all SIL Open Font License), for 17 built in.
- **Find in book** results stand out more: each one's chapter is in bold,
  and so is the matched text.

## v0.3.8

- **Find in book** (Settings): type a word or phrase on an on-screen keyboard
  and every match is listed with its chapter and the words around it. Opening
  one marks the words on the page, and B goes back to where you were.
- **Search** in Get books, for catalogs that support it (Gutenberg and
  Calibre do): the same keyboard, then the results as a catalog page.
- The keyboard is on the touchscreen: tap the keys, or use the D-pad and A.
  B deletes, Y types a space, Start or X searches.
- A catalog that's briefly busy (Gutenberg's search sometimes is) is tried
  once more before showing an error.
- Stock firmware: the launcher also puts the device back (brightness,
  touchscreen mode) straight away if it's stopped from outside.

## v0.3.7

- ROCKNIX: if eReaderDS takes a while to open (a first run, a big library),
  it still spreads over both screens (the launcher used to give up after 10
  seconds). If it's stopped from outside (e.g. an exit hotkey), the bottom
  screen, the menu's focus and the brightness are still put back.
- **Help** follows the Tap setting: with taps set to open Settings, it says so.
- If the saved theme is ever unknown, eReaderDS falls back to Sepia (the
  default), not E-ink.

## v0.3.6

- **Contents** and **Bookmarks**: tapping an entry on the touchscreen opens
  it (it used to close the list, as if B had been pressed). Taps elsewhere do
  nothing.
- New installs start at **20% brightness** on the stock firmware and **40%**
  on ROCKNIX, whose screens are dimmer at the same level (your own setting is
  kept, and the system brightness comes back when you quit).

## v0.3.5

- Stock firmware: if the menu icon wasn't copied to `Ports/Imgs`, eReaderDS
  puts it there itself, so it appears when you quit.

## v0.3.4

- Messages name the right folder on each system: `Ebook` on the stock
  firmware's SD card, `roms/ebook` on ROCKNIX (for books, dictionaries and
  catalogs). ROCKNIX also gets a `roms/ebook/Dictionaries` folder.
- **Help** in Settings: the buttons and the touchscreen on one page.
- The empty library says how to quit: **Press the Anbernic button to quit**.
- ROCKNIX: the **menu icon** now reliably appears a few seconds after the
  first run, without the menu redrawing: the launcher hands it to
  EmulationStation directly instead of editing its game list, which its play
  stats overwrote.

## v0.3.3

- New defaults for new installs (your own settings are kept): **Sepia**
  theme, text size 40, tighter line spacing (0.85), narrow side margins, and
  a 12-hour **clock** in the status bar.
- **Get books** shows book covers in color on every theme (the E-ink filter
  now leaves the selected book's page alone).
- A **menu icon** for Ports: the device's two screens as an open book
  (`Ports/Imgs/eReaderDS.png` on the stock firmware; on ROCKNIX the launcher
  adds it to the Ports list the first time it runs).

## v0.3.2

- **Runs on ROCKNIX** as well as the stock firmware: install to `roms/ports`,
  books in `roms/ebook`. The launcher turns the bottom screen on and spreads
  the pages over both screens, then gives the screens back to ROCKNIX's menu
  on exit. Buttons go by their printed letters, and the curved-arrow button
  opens Settings as on the stock firmware.
- The status bar no longer estimates **time left in the book**, which was
  often well off (it had to guess at chapters not yet opened). It shows the
  percentage read instead; time left in the chapter stays.
- **Clock fix:** the stock firmware keeps the device clock on local time, so
  applying a time zone on top shifted it by hours. The new default time zone,
  **Device clock**, shows the time as set in the device's own settings (the
  old "UTC" default becomes this); pick a named zone only if the clock is on UTC.

## v0.3.1

- **E-ink** is the default theme for new installs (your chosen theme is kept).
- **Tap the top edge** of the bottom screen (left of the bookmark corner) to
  show or hide all the status bars at once.
- Themes are listed alphabetically in Settings.
- **Pinch to change the text size** on the touchscreen: spread two fingers
  for bigger text, pinch for smaller. While pinching, a panel shows the new
  size, the percentage and a sample line; the page changes when you let go.

## v0.3.0

### New
- **Get books over Wi-Fi.** Press Select in the library (or tap Get books on
  the touchscreen) to browse Project Gutenberg, which is built in, or your own
  Calibre, Calibre-Web or other OPDS catalog (set up in
  `Ebook/.ereaderds/opds.txt`). See covers and descriptions, then download
  EPUBs straight to the SD card; B cancels. Works over HTTPS, with Basic or
  Digest logins. The button is greyed out when there's no Wi-Fi.
- **Dictionary on the facing page.** Press Y while reading, or press and hold
  a word on the touchscreen. Left/right move word by word, up/down line by
  line, and the definition shows on the other page. It finds base forms
  ("ran" → run, "mice" → mouse). English (WordNet 3.1) is built in; add
  StarDict dictionaries to `Ebook/Dictionaries` and choose one or all in
  Settings → Page turns & device → Dictionary.
- **Footnotes on the facing page.** Press A, tap a note number, or tap the
  Notes button: the note appears on the other page and the text stays put.
  Left/right step through the notes on the spread. Works with EPUB 3 notes and
  the numbered notes in older books; note numbers are drawn as superscripts.
- **Bookmarks.** Select (or a tap on the top-right corner) bookmarks the page,
  marked with a ribbon. Settings → Bookmarks lists them; A opens, Y deletes.
- **Time left** in the chapter and book, learned from your reading speed
  ("12 pages left in chapter (9m)", "45% read (4h 10m left in book)"). Show or
  hide each in Settings → Status bar.
- **Jump to %** picker: left/right 1%, up/down 10%, or drag the bar; it shows
  the chapter you'd land in.
- **Go back after a jump:** after Contents, Bookmarks or Jump to %, "‹ Back to
  34% (B)" returns you once. It's forgotten after 5 spreads.
- **Library:** sort by Recent, Title, Author or Progress (left/right), and
  delete books (Y, then A).
- **Hyphenation** for English books (Settings → Hyphenation, off by default).

### Changed
- **Settings fits on one screen:** places to go, then Text and Page settings.
  Page-turn animation, tap, the lid, the dictionary and About are under
  **Page turns & device**. B closes Settings ("Resume reading" is gone).
- **Buttons:** Y looks up words (Contents is in Settings); A shows footnotes;
  pressing the stick in opens Settings while reading. The L/R and L2/R2
  shoulder buttons are no longer used.
- Uses about half the memory on long reading sessions, and writes to the SD
  card only when something changed.

### Fixed
- Settings and progress files can't be lost to a power cut during a save.
- A broken EPUB no longer leaves its file open.

## v0.2.10

- **Closing the lid** now sleeps the device while eReaderDS is open: it saves
  your place, turns the screens off and suspends; opening the lid wakes it on
  the same page. Settings → Page turns & device → Closing the lid can switch to "Screen off" (screens
  off without suspending) if sleep misbehaves. Buttons and touches are
  ignored while the lid is closed.

## v0.2.9

- Even top and bottom margins: the space left under the last line is now split
  between top and bottom instead of all landing at the bottom.
- Settings are reordered into sections (Text, Layout, Display, Page turns)
  with small headers; the Status bar page is split into Top of page and
  Bottom of page. "Page turn" is now "Animation" under Page turns.
- With **Show status bar** off, the text uses the space the status bar took at
  the top and bottom (the book re-flows and keeps your place).
- Dimmer: 1% brightness now uses the backlight's true minimum, and three
  **Extra dim** levels below 1% darken the page further (press left past 1% in
  Settings → Brightness, or keep sliding down on the touchscreen).

## v0.2.8

- **Clock** in the top left of the right page (Settings → Status bar → Clock:
  12-hour or 24-hour), with a **Time zone** setting. Named zones follow
  daylight saving automatically.
- **Show status bar** switch to hide or show all status bar items at once.

## v0.2.7

- The chapter progress bar is on by default (Settings → Status bar →
  Progress bar).
- The book percentage reads "45% read".
- Status bar layout: the battery sits in the top outer corner of the right
  page, and with Title set to Chapter the chapter name shows at the top of the
  left page (with Both: book title left, chapter title right).
- Faster: books and library covers load without reading the whole EPUB into
  memory (large, illustrated books open much faster), and library previews are
  cached.
- Fewer SD card writes: reading position is saved after you pause rather than
  on every page turn (and always on quit), and button logging stops after the
  first presses of each session.
- Holding the curved-arrow button no longer flips Settings open and closed.
- Small fixes: status bar footer position with narrow margins, a leaked file
  handle, and code tidy-ups.
- **Status bar settings** (Settings → Status bar, replacing Page info), with a
  live preview: title (none, book, chapter or both); chapter pages (hide,
  pages left, or page X of Y); book percentage; a progress bar for the chapter
  or book that runs across both pages, in three thicknesses; and battery level.

## v0.2.6

- The analog stick turns pages in all four directions again, like the D-pad
  (down/right forward, up/left back).
- New **About** page in Settings: version, "Created by casualducko", and
  credits for the fonts and engine.

## v0.2.5

- Shorter, up-to-date README and in-download README.txt; problem reports can
  go to whoever sent you the zip.

## v0.2.4

- **Font previews:** the Font setting shows each font's name in that font.
  This also fixes fonts with non-Latin names (such as the Chinese-named fonts
  built into the firmware), which showed as empty boxes.
- **Analog stick:** pressing it in selects (like A) instead of opening
  Settings. While reading, only left/right (as held) turn pages; up/down as
  held no longer flips pages. It still moves through menus.
- The log now lists the device's input devices and each raw key press, to
  help identify buttons.

## v0.2.3

- **Ten built-in fonts.** Serif: Gentium Book Plus, Literata, Charis SIL,
  Source Serif 4, Crimson Text, Bitter. Sans-serif: Atkinson Hyperlegible Next
  (replaces Atkinson Hyperlegible), Inter, Lexend. Plus OpenDyslexic.
- **Analog stick** works like the D-pad, one push per press.
- **Curved-arrow button** (right of the Anbernic button) opens and closes
  Settings.
- **D-pad in menus:** on Settings rows with nothing to change (like Resume
  reading), left/right move the selection; in the Library they move through
  the list (A opens a book).
- Removed **Flip for other hand**: held that way, the buttons end up under the
  wrong hand. Anyone who had it on is switched back to the normal grip.
- Button, key and stick input is written to `log.txt`, to help diagnose
  problems.

## v0.2.2

- New **E-ink** theme that mimics an e-ink screen: everything, including
  covers, is shown in grayscale with 16 gray levels and a fine speckled grain
  on cool gray paper.

## v0.2.1

- Clarified that eReaderDS is for the RG DS Plus on its stock firmware (not
  the original RG DS or custom firmware), in the README included in the
  download and in the bug report form.

## v0.2.0

- Renamed from "Book Reader" to **eReaderDS**. The Ports entry is now
  `eReaderDS.sh` and the folder `Ports/eReaderDS`. Settings and reading
  positions are copied over from Book Reader automatically; delete
  `Ports/Book Reader.sh` and `Ports/BookReader` afterwards.

## v0.1.1

- Tapping the touchscreen now turns pages by default (right half forward,
  left half back). Choose **Settings → Tap → Open menu** for the old behavior.

## v0.1.0

First test release.

- Two-page reading across both screens, held sideways like a book, for either hand
- EPUB and plain text, with italics, bold, headings, images, covers and contents
- Library with covers and progress; remembers your place in every book
- Settings: text size, font, line spacing, side and top/bottom margins,
  justification, brightness, ten themes, page-turn animation, page info
- Fonts: Gentium Book Plus, Crimson Text, Atkinson Hyperlegible, plus your own
  from `Ebook/Fonts`
- Page turns: 3D flip, fade or off
- Touch (bottom screen): swipe to turn pages, slide for brightness, tap to open
  settings or turn pages
