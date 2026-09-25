# Changelog

## Unreleased

- New **E-ink** theme: light gray paper, soft black text and a faint paper
  grain, like an e-ink reader's screen.

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
