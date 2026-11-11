# Android EPUB shell measurement method

This document describes the resumed harness. The completed dataset and its limits are in `epub-engine-results.md`.

## Execution and scope

The target is `bookfin-api36`, Android emulator `emulator-5556` on host `local`. These are engine shells, not complete reader applications. The Bookfin shell imports the unchanged production EPUB loader, pager, viewport, image pipeline, admission cache, and page-map cache. The other shells use epub.js 0.3.93 in the actual Android WebView and KOReader v2026.07.1's real `cre` library.

The resumed T3 binding succeeded. KOReader launch and the prescribed diagnostic retry failed because its built APK was not installed. The harness owner stopped agent-device launches and input under the host rule. The parent then authorized genuine project test runners, not another external UI driver. The harness uses `EngineWorkloadTest` through AndroidJUnitRunner. This test starts the target Activity, asserts the complete operation sequence, checks destination changes, and checks the retained results. It does not invoke external UI commands or simulate gestures. Device screenshots still use T3 `device_screenshot`.

Both target and test APKs use pinned build inputs. The target APKs are optimized release builds. AndroidJUnitRunner adds a test thread and process initialization. The first-process measurement therefore includes the test runner, and is not a normal launcher-start measurement. The operation timers start inside the already initialized shell. The test thread polls for workload completion every 100 milliseconds. That polling is outside the operation controller, but its device cost remains part of this instrumented environment.

The Bookfin shell uses Flutter's texture render mode so that the same window-region PixelCopy operation includes its content. Production Flutter normally uses a separate surface. Texture composition can add work. This comparison therefore measures instrumented shell operations, not production application display latency. Java shrinking is disabled in all shells because release instrumentation needs tracing classes. Bookfin's Dart remains release AOT code and the native bridge uses `-O3`.

## Completion boundary

The primary boundary is `request_to_reference_window_copy`. Its duration starts when the shell dispatches an engine operation. It ends when Android PixelCopy finishes a window-region copy whose pixels match an independently prepared reference for that engine, book, and destination. This boundary includes engine work, rendering, scheduling, acquisition of the window buffer, and the PixelCopy copy cost. It is not physical display latency. The record includes the last copy's duration and the number of attempts. PNG encoding and storage follow the ending timestamp and are outside that duration.

The calibration process is separate from timed process runs. It retains actual page PNGs. Source checks compare rendered text with the hashed EPUB's source section. OCR checks compare text read from the PNG with that same independent source. Image review binds observations to the reference PNG's pixel hash. A timed capture cannot certify itself. Both the device and host bind measurements to the complete reference manifest's SHA-256. A mismatch, blank text, wrong location, failed copy, missing reference, or missing content review excludes a sample.

Alice's second chapter starts with a short title page. Its complete title, taken independently from the source heading, is valid content despite containing fewer than eight words. The calibration accepts that complete title, not an arbitrary short excerpt. The workload test also checks the chapter destination. OCR can place the Roman numeral before or after the title. The corresponding PNGs retain that evidence.

The timing also includes operation-specific content extraction and earlier unsuccessful copy/hash attempts. The final hash calculation happens after its copy timestamp. These costs cannot be subtracted as a constant. They are another reason not to label these measurements pure engine CPU time.

The `engine_ready_ns` field is diagnostic, not a second cross-engine speed metric. Bookfin reaches it after its real page picture has decoded images. KOReader reaches it after drawing its bitmap. WebView reaches it after the DOM location, fonts, and images are ready. These different internal boundaries are not equivalent displayed-frame measurements.

## Operations and caches

Every independent process uses the same selected source chapter. An open ends at that chapter's first page, rather than opening the book's front matter and timing a later jump. Bookfin uses the production pager's initial saved-location interface. WebView displays the chapter resource. KOReader resolves the chapter's actual contents entry.

| Operation | Starting state | Requested work |
| --- | --- | --- |
| Fresh open | New process, no document or derived cache | Load the EPUB and open the selected chapter |
| Cached reopen | Prepared cache, different chapter visible | Close the old document/view and reopen the selected chapter |
| Page turn | Selected chapter, size 18 | Turn forward once, three consecutive pages per process |
| Chapter crossing | Last page before the next chapter | Turn forward once, not a contents jump |
| Font change | Selected chapter's first page, size 18 | Change to size 20 while retaining the reading place |

Fresh means that the shell removes only its own fixture-derived caches before opening the EPUB. It does not flush Android filesystem caches. WebView clears its own resource cache before shell initialization, then uses normal resource caching with cacheable offline assets. A new process has no admitted epub.js document. KOReader starts with an empty `crengine` cache directory. Bookfin starts with a new fixture directory, including no admitted-book or page-map sidecars. Bookfin and KOReader copy the fixture to their private files before the timer. WebView reads the same EPUB bytes through an offline APK asset response during open. There is no fixture server or network request.

After a fresh open, Bookfin waits for production background pagination and verifies that the completed page map is readable from disk. This preparation time remains in raw records. KOReader performs whole-book pagination eagerly during open. WebView lays out chapters lazily and does not produce a whole-book page map in this workload. The report must keep these facts beside open times. They prevent treating time-to-selected-page as equal amounts of total pagination work.

Font changes have the same difference in work scope. KOReader reflows the whole book before its requested page. Bookfin can continue background pagination after the requested page. WebView reflows the current chapter. The common requested outcome is a correct page at the retained reading place, not completion of equal whole-book work.

Warm operations run three times per process. The first size-20 change can create layout data that later size-20 changes reuse. This mixture is the same for all engines and remains identifiable by operation sequence. Different engines cut different page boundaries. Sequential turns therefore cover each engine's next page, not identical character ranges. Bookfin and WebView report EPUB CFI source locations. KOReader reports its native XPointer source location, not an invented CFI. These identifiers are checked within each engine, not compared across engines.

Chapter crossings are warm crossings. Preparation visits the following chapter and moves back to the actual last page of the selected chapter. The measured operation then turns forward once. The following chapter was also visited during reopen preparation. These numbers do not measure first-time access to an unseen chapter. Each engine keeps its real prefetch and layout caches.

## Display configuration and limits

The viewport is 360 by 640 logical pixels. The shared font file is Source Serif 4, with body sizes 18 and 20, line spacing 1.65, cream paper, and brown text. Bookfin retains its real reader CSS. WebView applies the corresponding epub.js theme. KOReader uses its EPUB stylesheet with the same body line height. Its render DPI is 96 times the emulator density so that a CSS pixel has the same physical scale. Its body font size and page margins use physical pixels directly. Legacy image zoom modes are disabled, as in KOReader's own document adapter, in favor of render DPI.

Author styles, embedded fonts, shaping, hyphenation, image sizing, and pagination remain engine behavior. KOReader rounds font sizes and margins to physical pixels. Bookfin and WebView use logical-pixel layout. These are limits of a real-engine comparison, not evidence that one engine has the same typography or image layout as another. The report must name visible differences and failed content cases before any timing conclusion.

The inspected references show different heading alignment and small-cap styling. KOReader justifies text differently. Its White Rabbit illustration is smaller than Bookfin's and WebView's, even with the matched CSS pixel scale. KOReader and WebView retain a white illustration background, while Bookfin shows it on cream. KOReader fits the tall-Alice illustration below the second chapter title, while the other engines put that image after the title page. All show the expected source text and illustration identities. Their next pages do not cover identical character counts or equal image areas. No result here establishes equivalent rendering quality.

## Aggregation

The schedule contains 12 rounds and 108 independent process jobs. For each book, every engine appears in each of the three order positions four times. All builds and installations finish before the final timed schedule. Engines run sequentially, without concurrent heavy work. Calibration runs are excluded.

Each book/engine cell aims at 12 fresh opens and 36 samples for each warm operation. The median is the ordinary sample median. The p90 is the nearest-rank value at `ceil(0.9 × count)`. Raw records retain every preparation step, error, exclusion, operation sequence, destination, clock, and cache label. The summary reports actual counts per book and operation. A complete count matrix does not replace the content and methodology checks.
