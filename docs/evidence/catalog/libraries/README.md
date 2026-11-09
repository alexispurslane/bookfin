# Every book library shows, and Settings hides one (boo-j1lm)

Recorded on 2026-11-09 on a disposable Android emulator (API 36, Pixel 7, arm64), with a debug APK of this branch. The server was the synthetic fixture with its second book library:

```
nix develop --command dart run tool/showcase_fixture.dart 8213 --ebooks-library
```

With `--ebooks-library`, the fixture lists three user views: Audiobooks and Ebooks (both `CollectionType` books), and Movies (`CollectionType` movies). The audiobook items are in Audiobooks, and the ebook items are in Ebooks.

| Screenshot | What it shows |
|---|---|
| `1-sign-in-lands-on-library.png` | Sign-in goes straight to the library. There is no library choice step. |
| `2-ebooks-library-books.png` | The Ebooks filter lists the ebooks, so the Ebooks library loaded without any action. |
| `3-settings-all-libraries-shown.png` | Settings reads "Audiobooks, Ebooks · 2 of 2 shown". Movies is not a book library, so it is absent. |
| `4-settings-untick-ebooks.png` | The Libraries page with Ebooks unticked, before Save libraries. |
| `5-settings-ebooks-hidden.png` | After Save libraries, the page closes and the row reads "Audiobooks · 1 of 2 shown". |
| `6-after-restart-ebooks-stay-hidden.png` | After a relaunch of the app, the Ebooks filter finds no books, so the hidden library stays hidden. |
