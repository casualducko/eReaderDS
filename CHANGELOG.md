# Changelog

## Unreleased

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
