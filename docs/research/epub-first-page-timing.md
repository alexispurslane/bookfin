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

The emulator measurement could not run. At first, the Mac's only disk had 5.1 GB free, and the Android 36 image needs 7.4 GB for an emulator's data partition. Later the new emulator started, but T3's device tool refused each app launch with DEVICE_IN_USE: another thread's session still held the emulator's serial. So the numbers below come from the host (an Apple silicon Mac, `flutter test`, a load of 30 to 37 on 10 cores). They are medians of 11 runs, in milliseconds. The runs of the three columns alternate, so the load affects all three in the same way.

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

## After tf-focn: a faster prepare

Ticket tf-focn, 2026-11-09. Before it built parts of a section (t7-49gt), the order of work asked for a faster prepare of every section. Two changes to the cascade stay:

- The cascade reads each rule bucket in place, expands each declaration into its longhands once for the whole section, and builds its regular expressions once.
- Elements that the cascade styles the same share one style object, as browsers share styles. An element's computed style depends only on its parent's style, the rules that match it, its style attribute, its overrides, its language attribute, whether it is the root, and the root's font size (`_ShareKey` in css.dart). So each set of declarations applies once per parent style.

Three other changes did not pay, and the branch leaves them out:

- A hyphenation of a paragraph without a list entry for each code unit, and a cache of the hyphenation breaks of each word for one section. In four paired corpus rounds, neither moved the corpus total or the four slow sections beyond the noise (1 to 5 percent, and both signs).
- An XHTML parser that reads package:xml's events into Bookfin's DOM, without package:xml's tree. It uses the same tokenizer and the same checks, so it accepts and rejects the same documents. On Keats' section 2 it saved about 5 percent of the prepare (the parse went from about 29 to about 25 percent of it).

`test/reader/epub/corpus_prepare_test.dart` (with `BOOKFIN_EPUB_CORPUS_PREPARE=<name>`) dumps every prepared section of the corpus in three page settings values, as a hash of its DOM, flow items, run styles and faces, and times each prepare at the reader's page. `tool/reader/compare_corpus_prepare.py` compares runs. Every run of every change had the same hashes as the base: the prepared sections are the same.

### Host

`flutter test` on the Mac, with a load of 7 to 30 on 10 cores. The base and the branch ran one after the other in each of three rounds, so the load affects both in the same way. Each time is the fastest of 3 prepares of a section in a run, and the median of the three rounds, in milliseconds.

| Section | Base | Branch | Branch / base |
| --- | --- | --- | --- |
| Roget's Thesaurus (pg) 1 | 505 | 345 | 0.68 |
| Plato's Dialogues (SE) 30 | 296 | 249 | 0.84 |
| Keats' Poetry (SE) 2 | 321 | 195 | 0.61 |
| Van Dyke's Poetry (SE) 2 | 217 | 151 | 0.70 |
| Median section (4,573 sections) | 1.08 | 0.87 | 0.89 (median ratio) |
| Median of the sections of 10 ms or more (271) | | | 0.73 (median ratio) |
| Median book, all sections | 78 | 62 | 0.79 (median ratio) |
| The whole corpus | 15,333 | 11,995 | 0.78 |

The cheaper matching took 11 percent off the corpus total, and the shared styles 12 percent more.

### Emulator

A new arm64 Android 36 emulator (bookfin-49gt: Pixel 7 profile, 4 virtual CPUs, host graphics) with a profile build of `tool/reader/open_benchmark.dart` and the Keats plan of t7-bbv1 (open at the middle of section 2, jump from section 5 to the middle of section 2). The base build and the branch's build alternated, each with a calibration launch and 2 or 3 measuring launches. The tables give warm medians in milliseconds.

This emulator was 3 to 5 times slower than the emulators of the sections above: other agents loaded the Mac, and a fresh boot without a snapshot runs Google services for many minutes. With 2.5 GB of memory, the guest swapped and its Bluetooth service crashed again and again. So only the ratios are useful, not the times.

| Run | Open, to the shown page | Jump, to the shown page | Prepare of section 2 in a worker |
| --- | --- | --- | --- |
| 2.5 GB, base | 1,979 (25 samples) | 1,825 | 1,476 (5 samples) |
| 2.5 GB, branch | 1,457 (25 samples) | 1,356 | 1,177 (5 samples) |
| 4 GB, base | 2,251 (15 samples) | 95 | 1,420 (3 samples) |
| 4 GB, branch | 1,467 (15 samples) | 59 | 1,304 (3 samples) |

On this emulator the open of Keats' section 2 took 26 to 35 percent less time. In the 4 GB run, the jump found its section already prepared and laid out, so its time shows no prepare. The prepare samples are few and vary by up to 2 times.

### What t7-49gt still needs

The open of Keats' section 2 drops by about a third, not by half. On the host, Keats' prepare takes 61 percent of its time before. On the emulator of t7-bbv1 (328 ms prepare, 391 ms to the shown page), that gives about 200 ms of prepare and about 265 ms to the shown page, against a goal of less than 196 ms. So t7-49gt still needs a part of the section before the whole (Design 1 in its notes) to reach half of the time.

## After t5-xw4w and t7-49gt: a part of a large section

Tickets t5-xw4w and t7-49gt, 2026-11-09. Two changes on top of tf-focn shorten the time to a page deep inside a large section.

### The XHTML event parser (t5-xw4w)

`DomSection.parse` now reads package:xml's events straight into Bookfin's DOM, without package:xml's tree. It uses the same tokenizer and the same checks (`validateNesting`, `validateDocument`), so it accepts and rejects the same documents. For the few documents that package:xml's tree rejects with its own exception, it falls back to `XmlDocument.parse` for that exception.

The prepared sections did not change: the corpus prepare hashes of all 93 books in all three page settings values equal the base's (13,719 prepared sections, 0 errors, six runs). The times are from three paired corpus prepare rounds on the host. Each time is the fastest of 3 prepares in a run, and the median of the rounds.

| Measure | Before | After | After / before |
| --- | --- | --- | --- |
| Keats' Poetry (SE) 2 | 209.5 ms | 183.6 ms | 0.88 |
| The whole corpus | 11,836 ms | 11,020 ms | 0.93 |
| Median section | | | 0.94 (median ratio) |
| Median of the sections of 10 ms or more | | | 0.95 (median ratio) |

### A part of the section (t7-49gt)

A jump or an open deep inside a section of at least 256 KiB of XHTML no longer waits for the whole section's prepare. A worker isolate (`preparePart` in prepare.dart) does these steps:

1. It parses the whole section and finds the place.
2. It styles the elements and builds the boxes up to the end of the part. The part ends about 10,000 visible characters after the place. If the `p` element or the table that holds the place ends later, the part ends with it.
3. It makes text runs and hyphenation only from about 6,000 visible characters before the place to the end of the part.

The part's flow items keep the numbers that the whole section gives them. The items before the part are placeholders (`SkippedItem`). So the page source lays out the place's page with its true start, and the pager does not change. When the part arrives, the page source starts the whole section's prepare. When the whole section arrives, it replaces the part. A layout run that needs an item after the part waits for the whole section (`LayoutRun.starved`).

A part only helps a section of many blocks. A section that is one block, such as Roget's section 1 (one table) or Ulysses' section 18 (one paragraph), gains nothing. Another block can also be longer than the part, for example a long `div` of text. A place in it gets the whole section from the same worker and the same parse.

### The same pages and saved places

`test/reader/epub/corpus_prepare_test.dart` now also prepares parts. It checks each corpus section of at least 30,000 bytes in all three page settings values. For each, it prepares the parts around the places in the middle (0.5) and near the end (0.97). Each part must meet these conditions:

- Each flow item of the part equals the whole section's flow item of the same number.
- The line start of the place in the part equals the line start in the whole section.
- The first two pages from that line start equal the whole section's pages.
- A part that `preparePart` gives as the whole section equals the section that `prepareSections` gives.

All 93 books passed: 4,782 parts gave the same pages, and 456 places got the whole section. No line search needed the whole section. The whole sections did not change: the corpus prepare hashes of the branch equal those of the base 7e3fcd8 (0 differences).

### When a part pays

A part costs CPU time beside the whole section's prepare, which still runs after the part. On the emulator, this extra work delays the turns just after the first page (see below). So the page source uses a part only for a section of at least 256 KiB of XHTML (`PageSource._partBytes`). The table compares two times from the corpus prepare run on the host, at the reader's page. One is the fastest of 3 part prepares, and the other is the whole prepare of the same section.

| Section size | Places | Median whole prepare (ms) | Median part / whole | Median time saved (ms) |
| --- | --- | --- | --- | --- |
| 30 to 128 KiB | 1,320 | 3.5 to 12.6 | 0.52 to 0.77 | 0.6 to 2.5 |
| 128 to 256 KiB | 300 | 7.6 to 11.3 | 0.57 to 0.92 | 0.6 to 1.3 |
| 256 to 512 KiB | 40 | 57.9 | 0.47 | 31.0 |
| 512 KiB and more | 18 | 141.9 | 0.50 | 50.8 |

Below 256 KiB, no whole prepare took more than 35 ms. From 256 KiB, 54 of the 58 places were in sections that took 35 ms or more to prepare whole. The median part there saved 33 ms, and one part saved 192 ms.

### Host: the time to a page deep in a large section

`test/reader/epub/part_open_benchmark_test.dart` (with `BOOKFIN_EPUB_PART_BENCHMARK=1`) times a jump from a new page source to the anchored page of a place. The base (7e3fcd8, before t5-xw4w) asks for the prepared section and finds the place in it. The branch asks the page source to find the place (`PageSource.findPlace`), which prepares a part. The base and the branch ran one after the other in each of three rounds, with a load of 5 to 11 on 10 cores. Each time is the median of 3 opens in a round, and the median of the three rounds, in milliseconds.

| Section | Place | Base | Branch | Branch / base |
| --- | --- | --- | --- | --- |
| Keats' Poetry (SE) 2, 966 KiB | Middle (0.5) | 259.6 | 120.9 | 0.47 |
| Keats' Poetry (SE) 2 | Near the end (0.97) | 257.7 | 153.2 | 0.59 |
| Plato's Dialogues (SE) 30, 1,758 KiB | Middle | 317.4 | 118.2 | 0.37 |
| Plato's Dialogues (SE) 30 | Near the end | 406.3 | 240.7 | 0.59 |
| Van Dyke's Poetry (SE) 2, 712 KiB | Middle | 205.3 | 104.7 | 0.51 |
| Van Dyke's Poetry (SE) 2 | Near the end | 205.1 | 127.4 | 0.62 |

Near its end, Plato's section 30 is a sequence of tables of 100 to 280 rows. The first build ended each part about 10,000 visible characters after the place. So a part cut the place's table and fell back to the whole section (1.10 of the base). Now the part goes on to the end of the place's table. The part's prepare takes about 71 ms of the 241 ms. This ticket did not measure where the rest goes.

### Emulator

A new arm64 Android 36 emulator (bookfin-t7part: Pixel 7 profile, 4 virtual CPUs, 4 GB, host graphics) ran a profile build of `tool/reader/open_benchmark.dart` with the Keats plan: open at the middle of section 2, a turn in section 3, and a jump from section 5 to 0.97 of section 2. The base and the branch alternated, each with a calibration launch and 3 measuring launches of 5 warm opens each. The times are medians in milliseconds, to the shown page.

| Run | Base | Branch | Branch / base |
| --- | --- | --- | --- |
| Open, warm, cycle 4 (15 samples each) | 301.1 | 187.2 | 0.62 |
| Jump, warm, cycle 4 | 286.4 | 169.5 | 0.59 |
| Open, cold, cycles 4 and 5 (6 samples each) | 327.3 | 168.5 | 0.51 |
| Open, warm, cycle 5 | 302.0 | 228.2 | 0.76 |
| Turn, warm, cycles 4 and 5 (30 samples each) | 17.1 | 24.4 | 1.42 |

The branch's launches of cycle 5 ran while the load of the Mac rose to 16 on 10 cores. Their warm opens took 168 to 481 ms, and the base's launches before them took 287 to 333 ms. Three earlier cycles of the first build gave the same picture: an open of 186 ms against 301 ms (0.62), and a turn of 25.5 ms against 17.6 ms.

The emulator of t7-bbv1 took 391 ms to the shown page before tf-focn. The goal of this ticket was half of that, under 196 ms. On this emulator, the branch opens in 187 ms warm and 168 ms cold. A build from before tf-focn (3ac7734) took 376 ms warm on this emulator, so the branch takes 0.47 of that time (cycle 3).

The turn right after a part open takes about 7 ms more. This ticket did not find the whole cause. After the part arrives, the whole section's prepare still runs in a worker isolate during the turn. But a plan that opens a small section, with no part, also gave a slower turn on the branch: 22.6 ms against 19.6 ms. The base's turn varied from 17.1 to 22.4 ms between periods of the same day. A warm open on a new pager can also run beside the whole prepare of the pager before it. The page source cannot stop a worker that it started.
