# Changelog

## Unreleased

- The Font setting shows each font's name in that font, as a preview. This
  also fixes fonts with non-Latin names (such as the Chinese-named fonts built
  into the firmware), which showed as empty boxes.

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
