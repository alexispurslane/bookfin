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

## After t7-bbv1: the whole book, in two directions

Ticket t7-bbv1 changed the order of work (docs/plans/native-epub-reader.md, "Order of work"). Each section now has a worker call of its own. Two directions lay out the sections after and before the shown one until the whole book is laid out. An idle layout step also waits while a frame is scheduled.

The device was a new arm64 Android 36 emulator (bookfin-bbv1: Pixel 7 profile, 4 virtual CPUs, 2 GB) with host graphics (`-gpu host`). With software graphics, the raster thread took 64 ms per frame, so frame times showed only the raster thread. Other agents loaded the Mac (a load of 7 to 21 on 10 cores), so times vary by 20 to 50 percent between runs. Each build had 3 launches per book, which gives 15 warm samples. The tables give warm medians in milliseconds. The jump plans used the place's section as jumpFrom, except Keats (5). Hamlet's place is act 1 (section 4), and its turn goes from act 2 (section 5) into act 3.

| Book | Turn before | Turn after | Turn to the shown page after | Jump before | Jump after | Open before | Open after |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Frankenstein | 35 | 15 | 10 | 33 | 21 | 305 | 219 |
| Hamlet | 214 | 184 | 115 | 100 | 90 | 733 | 689 |
| Keats | 492 | 51 | 23 | 532 | 521 | 1,439 | 1,679 |
| Jane Eyre | 30 | 33 | 22 | 38 | 36 | 1,011 | 1,160 |
| Moby-Dick (MOBI) | 37 | 27 | 17 | 33 | 24 | 525 | 495 |

The turn into Keats' section 4 no longer waits for section 2. Hamlet's turn reaches the shown page in about the time of act 3's own prepare (46 to 68 ms) and its first page (24 ms). The open and the jump do not change: the new order starts only after the first page is shown, and the open's differences follow admission, which the change does not touch.

The stay opens each book at its place and stays there, while the app asks for a frame every 50 ms. A frame is late when its UI part, from the vsync to the end of its build, takes more than 16.7 ms.

| Book | Sections | Whole book laid out | Frames, late, late frames that waited for an idle step | Peak resident memory (MB) | Baseline: late frames in its first 5 s |
| --- | --- | --- | --- | --- | --- |
| Frankenstein | 32 | 0.7 to 1.0 s | 50, 0, 0 | 274 to 289 | 0 of 201 |
| Hamlet | 12 | 1.3 to 1.5 s | 85, 3, 0 | 276 to 277 | 4 of 198 |
| Keats | 6 | 2.6 to 3.5 s | 155, 50, 0 | 305 to 308 | 22 of 185 |
| Jane Eyre | 57 | 2.1 to 2.2 s | 131, 0, 0 | 284 to 285 | 0 of 200 |
| Moby-Dick (MOBI) | 144 | 2.6 to 4.9 s | 208, 3, 0 | 285 to 288 | 0 of 202 |
| Ulysses (Standard Ebooks) | 25 | 4.7 to 4.9 s | 191, 6, 0 | 295 | 14 of 194 |

No late frame waited for an idle step. Every late frame in Hamlet, Keats and Ulysses waited for urgent steps: the main run up to the shown page, which the previous page needs. The baseline has the same frames. Moby-Dick's 3 late frames waited for no step. Ticket tc-yxhv follows up the urgent steps. Before the new rule for idle steps, a requested frame waited for about five idle steps in a row (20 to 44 ms), and Keats missed 53 to 64 vsyncs while its book was laid out.

Ulysses gives the clean comparison of memory, because both builds ran its stay alone in a new process. Its peak resident memory was 279 to 280 MB in the baseline's first 5 s, which laid out 3 sections, and 295 MB with the whole book laid out (25 sections). In the other books, the stay followed the open, turn and jump runs in the same process, so their peaks also hold what those runs left. They stayed from 273 to 308 MB. The page starts of every section stay, but a section more than one section away from the shown one lets go of its prepared text once its main run ends.

A worker call per section costs the calling isolate 0.1 to 3 ms to start (`startCall`, the copy of its arguments). Its result comes back through the worker's exit without a copy. A long-lived worker per direction would copy each result back on the UI isolate: 89 ms for Keats' section 2 (see above). So each direction is a chain of `Isolate.run` calls, one section each.
