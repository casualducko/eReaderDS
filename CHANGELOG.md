# Changelog

## Unreleased

- **Library sorting**: left/right on the D-pad or stick (or a tap on the
  order at the top) switches between
  Recent (last opened first, the default), Title, Author (by last name) and
  Progress (books you're reading first, then unread, then finished).
- **Hyphenation** for English books (Settings → Hyphenation, off by default).
  Long words break at the line end when the line would otherwise be
  stretched, using TeX's US English patterns, and never more than two lines
  in a row.
- Pressing the stick in opens Settings while reading (it still selects in menus).
- **Delete books** from the library: Y on a book, then A to confirm. Its
  progress and bookmarks are forgotten too.
- **Get books over Wi-Fi** from Calibre, Calibre-Web or any OPDS catalog,
  set up in `Ebook/.ereaderds/opds.txt`. Browse with covers and
  descriptions, and download EPUBs to the SD card with a progress bar
  (B cancels). Works over HTTPS, with Basic or Digest logins.
- **Jump to %** opens a picker: choose the percentage first (left/right 1%,
  up/down 10%, or drag the bar on the touchscreen), see the chapter
  you'd land in, then A jumps once (B cancels).
- **Go back after a jump.** After jumping with Contents, Bookmarks, Jump to %
  or the chapter buttons, the bottom right shows "‹ Back to 34% (B)": press B
  or tap it to return there. It goes away once used, or after you read on
  5 spreads.
- **Time left** in the chapter and book ("12 pages left in chapter (9m)",
  "45% read (4h 10m left in book)"), learned from how fast you actually read.
  Quick flips, long pauses, jumps and time in menus are ignored; it starts at
  about 250 words a minute. Show or hide each in Settings → Status bar →
  Chapter time left / Book time left.
- **Bookmarks.** Press Select (or tap the top-right corner of the page) to
  bookmark a page; press again to remove it. Bookmarked pages show a ribbon
  in that top-right corner, so tapping the ribbon removes it. The battery
  indicator moves to the top of the left page, by the hinge. Settings → Bookmarks lists them with chapter, percentage and
  opening words: A opens one, Y deletes it. Bookmarks follow the text, so they
  survive font and size changes.
- Uses much less memory on long reading sessions: only the last few chapters'
  layouts and the most recently shown illustrations are kept (about half the
  memory in testing), and layout reads image sizes from file headers instead
  of decoding every illustration.
- Fewer SD card writes: settings and progress are only written when they
  change (not on every menu move).
- Input diagnostics stop reading devices other than the lid once logging ends.
- A broken EPUB no longer leaves its file open.

## v0.2.10

- **Closing the lid** now sleeps the device while eReaderDS is open: it saves
  your place, turns the screens off and suspends; opening the lid wakes it on
  the same page. Settings → Closing the lid can switch to "Screen off" (screens
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
