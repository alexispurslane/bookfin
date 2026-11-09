# Where the time to an EPUB's first page goes

Ticket boo-rw7u, 2026-11-09. The question was whether data parallelism over worker isolates can shorten the time from opening a book to its first drawn page. Text layout cannot move off the root isolate: Flutter's text engine answers "UI actions are only available on root isolate" in any other isolate. Prepare (parse, cascade, styled runs and hyphenation points) already runs in a worker isolate. The page source prepares each batch of sections one after another in one worker call. So the question became: does prepare take a large share of the time, and do several workers at once remove that share?

The answer is no, so this ticket did not build parallel prepare. The reasons follow the numbers.

## How the numbers were taken

- The device was a new arm64 Android 36 emulator (bookfin-rw7u: Pixel 7 profile, 4 virtual CPUs, 2 GB) on an Apple silicon Mac. Three other emulators ran on the same Mac, with a load of 6 to 17 on its 10 cores. So the numbers vary by about 20 percent between runs.
- The build was a profile build of `tool/reader/open_benchmark.dart`. The tool opens a downloaded book with the reader's own calls: `loadReadingDocument`, `EpubPager` and `EpubViewport`. It starts three seconds after the app's first frame, as a book opens in an app that is running (te-k1l3).
- Each book had 5 launches. In each launch the first open, turn and jump are cold, because they are the first in the process. Then each ran 5 more times on new pagers, which gives 25 warm samples. The tables give medians.
- An open starts at a saved place. A calibration launch finds each saved place with the pager's own `seek`, and keeps the address that the pager reports there.
- The time of the first drawn page is the end of the raster work of the first frame after the shown page (`FrameTiming`).

The books:

| Book | Why | Open at | Turn from section | Jump to |
| --- | --- | --- | --- | --- |
| Gutenberg's Frankenstein (pg-84) | Ordinary novel, plain markup | Section 6 (12,406 characters), middle | 9 | Section 25, middle |
| Standard Ebooks' Hamlet | Heavy Standard Ebooks styles, dialogue in tables | Act 1 (31,204 characters), middle | 5 | Act 5, middle |
| Standard Ebooks' Poetry of John Keats | One section of 430,000 characters | That section 2, middle | 3 | Section 2, middle |
| Gutenberg's Jane Eyre (pg-1260) | Illustrated novel, 3 MB | Section 7, middle | 10 | Section 40, middle |
| Gutenberg's Moby-Dick, Kindle KF8 (pg-2701) | A MOBI, converted to EPUB once and kept | Section 20, middle | 57 | Section 100, middle |

## The first page

All times are in milliseconds, cold and then warm. Admission is the read of the file and `Publication.admit` (or the MOBI import from its kept conversion). "To shown" runs from the new pager to the shown page. In that time, the viewport's first layout presents the settings. Then a worker call reads the spine steps from the package document. Then the shown section's prepare and its anchored layout follow. "First frame" runs from the shown page to the end of the frame that drew it.

| Book | Admission | To shown | First frame | Total | Prepare of the shown section | Anchored layout |
| --- | --- | --- | --- | --- | --- | --- |
| Frankenstein | 190 / 197 | 55 / 46 | 39 / 25 | 285 / 274 | 8 | 2 |
| Hamlet | 527 / 541 | 141 / 122 | 44 / 24 | 762 / 688 | 52 | 21 |
| Keats | 556 / 591 | 405 / 391 | 37 / 20 | 1,003 / 1,008 | 328 | 5 |
| Jane Eyre | 934 / 949 | 63 / 47 | 36 / 24 | 1,030 / 1,022 | 10 | 2 |
| Moby-Dick (MOBI) | 412 / 442 | 58 / 54 | 34 / 24 | 507 / 517 | 9 | 2 |

The last two columns come from a page source of their own after the runs (median of 5). The first open of the MOBI ever converts it. That admission took 639 ms in one sample.

Admission is 59 to 93 percent of the first page in every book. Prepare is 1 to 8 percent, except in Keats' section, where it is 33 percent. A first page needs one prepared section, so several workers cannot shorten it.

Admission decodes each PNG and JPEG in full (`_raster` in publication.dart, with package:image). On the host, these decodes took 43 to 63 percent of admission: 60 of 138 ms for Frankenstein, 169 of 285 ms for Hamlet, and 441 of 703 ms for Jane Eyre. Ticket t7-rcyp follows this up.

## A turn into an unprepared section, and a jump

The turn starts as soon as the pager shows the last page of a section. At that time, the work around the shown page did not prepare the next section yet. If a reader turns within a fraction of a second after the page appears, the reader meets this case. The jump is a scrub (`seek`) to the middle of a far section, after the work around the shown page ended.

| Book | Turn | Next section's prepare alone | Previous section's prepare | Jump | Jump target's prepare | Turn inside a laid-out section |
| --- | --- | --- | --- | --- | --- | --- |
| Frankenstein | 46 / 47 | 9 | 8 | 26 / 27 | 8 | 11 / 12 |
| Hamlet | 199 / 205 | 49 | 52 | 99 / 94 | 39 | 7 / 15 |
| Keats | 398 / 388 | 10 | 328 | 387 / 386 | 328 | 19 / 13 |
| Jane Eyre | 30 / 40 | 8 | 9 | 35 / 30 | 11 | 17 / 16 |
| Moby-Dick (MOBI) | 61 / 50 | 10 | 8 | 30 / 25 | 8 | 20 / 15 |

The turn into Keats' section 4 took 388 ms, but section 4 alone prepares in 10 ms. `PageSource.show` asks for the next section and for the previous section in the same microtask. So both go into one worker call. That call returns nothing until both sections are done. The turn waits for Keats' 430,000-character section. Hamlet shows the same effect at a smaller size. Ticket t7-bbv1 follows this up. Its fix needs no pool of workers.

A jump needs one section. Its time is that section's prepare and one page, so several workers cannot shorten it either.

## The parts of one worker call

Medians of 5, in milliseconds. "Worker call" is one `Isolate.run` that prepares one section, as the page source does today. "Reused worker" is the same prepare in an isolate that prepared before. A worker that stays alive is in that state. "Copy back" is the time to send that result through a port, because only a worker's exit hands a result over without a copy.

| Section | Characters | Empty hop | Hyphenation load | Worker call | Prepare in it | Reused worker | Copy back |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Frankenstein 6 | 12,406 | 1.2 | 1.6 | 10.3 | 7.5 | 1.1 | 0.5 |
| Jane Eyre 40 | 32,532 | 2.2 | 1.6 | 18.9 | 14.0 | 7.3 | 0.9 |
| Moby-Dick (MOBI) 58 | 36,955 | 2.1 | 4.0 | 14.8 | 9.0 | 2.8 | 0.7 |
| Hamlet act 1 | 31,204 | 1.5 | 2.7 | 52.8 | 45.8 | 37.3 | 4.6 |
| Keats 2 | 429,987 | 1.6 | 6.2 | 340.6 | 297.0 | 267.0 | 88.7 |

A new isolate pays a fixed cost of about 8 to 12 ms for each call: the spawn, the load of the hyphenation patterns, and the first use of the prepare code and its data. A worker that stays alive saves that cost. But its result comes back as a copy, which grows with the section. For Keats' section, the copy (89 ms) is larger than what the reuse saves (74 ms).

## The decision

| Technique | Its constant cost | Its gain at Bookfin's sizes |
| --- | --- | --- |
| A pool of workers that stay alive, sized from the processors | One isolate heap with the hyphenation patterns per worker, which this ticket did not measure. A port copy of each result: 0.5 to 1 ms for an ordinary section, 4.6 ms for a Hamlet act, 89 ms for Keats' section. | None for a first page or a jump, which need one section. About 8 ms for each ordinary section, which is 3 percent of the first page. Worse by about 15 ms for Keats' section. |
| Several worker calls at once, one for each section | One more spawn (about 2 ms) and 2 to 8 ms of warm-up in each new isolate, on another core | Only a turn that comes within 0.15 to 0.4 s after the page is shown. It saves the previous section's prepare: about 330 ms in Keats, 50 to 90 ms in Hamlet, about 8 ms in ordinary novels. Ticket t7-bbv1 covers this without a pool. |

Bookfin keeps one worker call for each batch. The large parts of the time are elsewhere:

- Admission: 190 to 950 ms at every open (t7-rcyp).
- A turn that waits for the previous section's prepare in the same worker call (t7-bbv1).
- The prepare of one very large section, on the path of an open or a jump in it (t7-49gt).

Two smaller costs stay as they are. The first frame after the shown page takes 20 to 44 ms. A cold frame takes 10 to 20 ms more than a warm one. The pager's spine-step worker call before the first prepare adds one more hop. t7-rcyp names it.

## How to measure again

1. Serve the books and a plan from one directory on the host, and forward the port to the device:

   ```
   python3 -m http.server 8781 --bind 127.0.0.1 --directory <directory>
   adb -s <device> reverse tcp:8781 tcp:8781
   ```

2. Build and install the profile build, and start it on a device that no one else uses:

   ```
   nix develop --command bash -c 'flutter build apk --profile --target-platform android-arm64 -t tool/reader/open_benchmark.dart'
   adb -s <device> install -r build/app/outputs/flutter-apk/app-profile.apk
   ```

3. Read the results with `adb -s <device> logcat -d | grep OPEN_BENCHMARK`. The comment at the top of the tool describes the plan and each result.

The first launch after an install only finds the saved addresses. An install clears them, because they are in the app's cache directory.

## After t7-rcyp: the kept admitted book

Ticket t7-rcyp, 2026-11-09. Three changes remove admission from the path of an open:

- Admission reads only the header of each PNG and JPEG: its width, height, pixel count and frame count. Layout needs only the size. A page draws an image's alt text when its pixels do not decode.
- The reader takes the SHA-256 digest that Downloads computed when the download completed. An open does not hash the book.
- The first open of a downloaded file keeps the admitted book in the download's `.bookfin-admitted` folder: the admitted files, every admitted fact, and the CFI spine steps. The key is the file's digest, the reading policy and `Publication.revision`. Later opens read this record in one worker call. A MOBI keeps the record of its converted EPUB under the MOBI's own digest and policy.

The emulator measurement could not run. The Mac's only disk had 5.1 GB free, and the Android 36 image needs 7.4 GB for an emulator's data partition. So the numbers below come from the host (an Apple silicon Mac, `flutter test`, a load of 30 to 37 on 10 cores). They are medians of 11 runs, in milliseconds. The runs of the three columns alternate, so the load affects all three in the same way.

| Book | Open before | First open after a download | Later open | File (KiB) | Record (KiB) | Images |
| --- | --- | --- | --- | --- | --- | --- |
| Frankenstein | 257 | 141 | 3.2 | 429 | 722 | 1 |
| Hamlet | 695 | 315 | 5.7 | 635 | 1,146 | 5 |
| Keats | 981 | 586 | 5.1 | 554 | 1,414 | 5 |
| Jane Eyre | 1,336 | 400 | 5.2 | 3,023 | 3,743 | 29 |
| Moby-Dick (MOBI) | 802 | 462 | 13.3 | 1,480 | 2,220 | 2 |

"Open before" is the work of the old open in one worker: the read, the hash, the admission and the full decode of each image. For the MOBI, it also reads its kept conversion and hashes it. "First open after a download" is a full admission without the image decodes, and the write of the record. "Later open" is the read and decode of the record in a worker.

A later open reads the whole record at once. A lazy read of each resource would save at most the 3 to 13 ms of the read, but every user of `Publication.resources` would have to wait for a file read. On the emulator, the read can take a few times longer, but it stays small next to the 190 to 950 ms of admission that it replaces.

Ticket t6-0yez measures the same five books on an emulator and on the Pixel 8 when the disk has room.
