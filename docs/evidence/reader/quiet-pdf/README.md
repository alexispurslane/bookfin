# Quiet PDF reading, page swipes, and full screen

Evidence for boo-981b and boo-hcxq, taken on 2026-11-09 at commit `c765141`.

## Setup

- Device: a new Android emulator, `bookfin-hcxq` (Android 36, Google APIs, arm64, 1080 by 2400 pixels). The emulator was deleted after the pictures.
- App: the debug APK of the branch, installed with `adb install`.
- Books: the sample library fixture (`tool/showcase_fixture.dart`) on the Mac. The emulator reached it through an `adb reverse` port. Windfall is a PDF with two text pages and one scanned page. First Frost is an EPUB.
- Every tap, swipe, and picture went through the T3 device command.

## Pictures

| File | What it shows |
|---|---|
| `01-opens-on-original-page.png` | Windfall opens on its original page 1. No prompt, no notice, and no top bar. The glass bottom bar lies over the page. |
| `02-full-screen-on.png` | A tap in the middle of the page. Only the page shows, and Android hides its system bars. The page keeps its place and size. |
| `03-full-screen-off.png` | A second tap brings the bottom bar and the system bars back. |
| `04-swipe-to-page-2-in-full-screen.png` | A swipe to the left in full screen turns to page 2. |
| `05-swipe-to-scanned-page-3.png` | A second swipe turns to the scanned page 3. The original view starts no recognition and shows no prompt. |
| `06-scanned-page-reflowed-without-asking.png` | Reflow chosen on the scanned page. The page is recognized without a question, and its text shows with no notice. |
| `07-text-page-reflowed-without-recognition.png` | Two swipes to the right go back to the text page 1, which reflows from its text layer. The bottom bar lies over the text. |
| `08-reflowed-page-full-screen-unchanged.png` | The same reflowed page in full screen. Every line stays where it was. |
| `09-epub-controls-shown.png` | First Frost, an EPUB, with the bottom bar shown. |
| `10-epub-full-screen-page-unchanged.png` | The same EPUB page in full screen. |
| `11-epub-swipe-in-full-screen.png` | A swipe in full screen turns the EPUB page. |

## Page area comparison

The rows from 150 to 1550 of each pair were compared pixel by pixel with `magick compare -metric AE`.

| Pair | Different pixels |
|---|---|
| `01` and `02` (PDF page, controls shown and full screen) | 40 of 1,512,000 |
| `09` and `10` (EPUB page, controls shown and full screen) | 0 of 1,512,000 |

The cause of the 40 different PDF pixels is not known. The text and the page edges are at the same place in both pictures.

## Android's own notice

The first time an app hides the system bars, Android shows its own "Viewing full screen" card with a "Got it" button. Bookfin does not draw it. After "Got it", Android does not show it again for this app. Pictures 02 and later were taken after "Got it". Pictures 01 and 03 do not show the card.
