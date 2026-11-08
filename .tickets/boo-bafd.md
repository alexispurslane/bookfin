---
id: boo-bafd
status: in_progress
deps: []
links: []
created: 2026-11-08T02:56:28Z
type: bug
priority: 0
assignee: Alexis Purslane
parent: boo-fs0n
---
# Launch shows the sign-in form for about 17 seconds while the saved library loads

Found on the Pixel 8 on Nov 7 with build 1abdb6b (debug APK) and the user's real library of about 1,500 books. After a cold start, the app shows the sign-in form ('Your library starts here.') with a disabled Sign in button and a Cancel button for about 17 seconds, then the library appears. Cancel there calls catalog.signOut(), so a tap signs the user out. Cause seen in lib/catalog/controller.dart _restore: it sets _session from the saved credentials, then awaits _readSaved (read and build of the saved library), and notifies only in finally. Until then the shell sees no session and shows _SignInForm, which shows Cancel because catalog.busy is true. This breaks engine rule 2: the saved library must be the first useful frame. Find where the 17 seconds go (secure storage read, catalog store read, the hop, the build, covers) by measurement on emulator-5556, which is signed in to the same real server. Then: never show the sign-in form while a restore runs with saved credentials, publish the signed-in state as soon as the credentials are read, show the saved library as soon as it is built, and make the restore itself fast. Measure the time to the first library frame before and after, in a debug and a profile or release build.


## Notes

Nov 7, first part (commit on branch t3/restore-launch-state):

- The restore publishes the saved account as soon as the credentials are read. `CatalogAccount.restoring` is true while a restore runs. Without a session, the credentials are still being read. With a session, the saved catalog is still being read.
- While the credentials are read, the shell shows only the page surface, so the sign-in form and its Cancel never show. While the saved catalog is read, the Library tab shows the signed-in shell with an empty page, not the library selector and not "No books found." The thin progress line shows after 1.5 s of a restore, as for a refresh.
- Description cleanup (`_plainText` in lib/catalog/model.dart) took about 185 ms of the 230 ms `buildBooks` time for 1478 books in AOT on an M-series Mac. Each pass now runs only when its text can match, and the blank pass leaves single spaces alone. The output is unchanged: 3,000,000 random strings gave the same result with the old and new code. Timings on a made-up library of 1478 books shaped like the real one (3.9 million characters of saved text):

| Step | Before, AOT | After, AOT | Before, JIT | After, JIT |
|---|---|---|---|---|
| Description cleanup, plain text | 185 ms | under 10 ms | 177 ms | not timed alone |
| Description cleanup, HTML text | 166 ms | 47 ms | 177 ms | 49 ms |
| Decode, build and library, total (median of 15) | 287 ms | 81 ms | 615 ms | 465 ms |

Open: the device measurement. On the first attempt, T3 device support failed ("Device list failed: Could not communicate with device support."). On the second attempt, emulator-5556 (AVD bookfin-accept-20261103-db111f95) was held by another agent-device session, t3-130af3b15755d2b73cadb1b2, created at 1794072132916 ms, and stayed busy for a 120 s wait. Still to do: find where the 17 s go on the device (credentials read, store read, hop, build), and measure the time to the first library frame before and after, in a debug and a profile build. The old-code debug APK with temporary BAFD timing printouts is installed on that emulator. /tmp/bafd-instrument.py adds the printouts to a checkout, and /tmp/bafd-measure.sh does the cold starts and prints the times.
