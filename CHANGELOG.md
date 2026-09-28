# Changelog

## Unreleased

- **Get books** lists are on the touchscreen: tap a catalog or book to see
  it on the other screen, tap it again to open or download it. The cover
  and details are on the top screen.
- The search keyboard starts with **no key highlighted**. The first D-pad
  press shows the highlight (on q); taps type without highlighting anything.
- **Gutenberg is fast again:** eReaderDS now goes straight to
  www.gutenberg.org. The old m.gutenberg.org address only redirects there,
  and lately answers slowly or with errors (504) much of the time.
- Gutenberg search results no longer list **Authors** and **Subjects**:
  Gutenberg refuses those lists to apps (403).
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
