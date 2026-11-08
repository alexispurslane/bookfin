---
id: boo-8v53
status: open
deps: []
links: []
created: 2026-11-08T03:50:12Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-fs0n
---
# Find where the saved-library restore spends its time on Android

Split from boo-bafd. Since boo-bafd, launch shows the signed-in app at once, but on the Pixel 8 the saved library took about 17 seconds to appear. On the host, the restore build of 1478 books takes 81 ms in AOT, so the time is in device steps that nobody measured: the secure-storage read, the 3.9 MB catalog read through SharedPreferences, or the isolate hop. Measure cold starts on an emulator in debug and profile builds, before and after. /tmp/bafd-instrument.py adds timing printouts and /tmp/bafd-measure.sh runs the cold starts (see boo-bafd notes); they live in /tmp, so recreate them if they are gone. Then fix the slow step, under the engine rule 'start from the cache'.

