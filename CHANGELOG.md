# Changelog

## Unreleased

- The book percentage shows what's left, like the chapter count: "55% left in
  book".
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
