eReaderDS v@VERSION@ - two-page ebook reader for the Anbernic RG DS Plus
Created by casualducko. For the RG DS Plus on its stock firmware or ROCKNIX.

INSTALL / UPDATE
  1. Copy "eReaderDS.sh" and the "eReaderDS" folder (inside this zip's Ports
     folder) into the Ports folder on the SD card. When updating, replace the
     old ones; your settings and reading positions are kept.
  2. Put .epub or .txt books in the card's "Ebook" folder.
  3. On the device: Ports > eReaderDS.
  Copy the two items, not the whole Ports folder, or you may lose other ports.
  ROCKNIX: copy over Wi-Fi, not with the card in your computer (its roms
  folder is on a Linux part of the card that Mac and Windows can't open; if
  asked to initialize or format the card, choose Ignore). On a Mac: Finder >
  Go > Connect to Server > smb://<device address>; on Windows: \\<address>.
  Copy both into the games-roms share's "ports" folder, books into "ebook",
  then Start > Game settings > Update gamelists.

  Updates install themselves over Wi-Fi: eReaderDS says when a new version
  is out (or use Settings > About eReaderDS > Check for updates).

CONTROLS (hold it turned counter-clockwise; directions as held)
  D-pad ................. turn pages; in menus up/down move, left/right change
  A ..................... select; while reading: show footnotes
  Press stick in ........ settings while reading; select in menus
  B ..................... settings / back (after a jump: go back)
  Select ................ bookmark this page (press again to remove);
                          in the library: get books over Wi-Fi
  Start, X, ↩ ........... open / close settings
  Y ..................... look up a word
  Menu (Anbernic) ....... quit
  Analog stick .......... like the D-pad

TOUCH (bottom screen)
  Swipe left/right ...... turn pages
  Slide up/down ......... brightness
  Tap right/left half ... next/previous page (Settings > Reading & device > Tap)
  Tap top-right corner .. bookmark this page
  Pinch ................. text size
  Hold a word ........... look it up

YOUR OWN FONTS
  Copy .ttf/.otf files into Ebook/Fonts, then pick them in Settings > Font.

PROBLEMS?
  Send Ports/eReaderDS/log.txt, the version (top of Settings) and what
  happened to whoever gave you eReaderDS, or open an issue at
  https://github.com/casualducko/eReaderDS-beta/issues
