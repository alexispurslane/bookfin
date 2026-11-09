---
id: t7-hufl
status: closed
deps: []
links: []
created: 2026-11-09T00:24:12Z
type: bug
priority: 3
assignee: Alexis Purslane
parent: boo-b2ey
---
# Keep idle layout steps from spinning the event loop while an animation runs

PageSource schedules main runs and other far work with SchedulerBinding.scheduleTask at Priority.idle. While an animation runs (for example the scrub deck, a slider or a sheet), Flutter's defaultSchedulingStrategy holds such a task back, and _runTasks asks again at once with Timer.run. So the UI isolate runs a zero timer loop between frames for as long as the animation runs and idle work waits: CPU and battery cost, and other event loop work waits behind it. Under the widget test clock the same loop never ends, so the reader widget tests set schedulingStrategy to allow every task (test/reader/native_reader.dart runIdleStepsDuringAnimations). Found in tc-1yif. Measure the cost on the phone first (E20); a fix can hold idle steps in the page source and wake them after the animation, for example from a post-frame callback.


## Notes

**2026-11-09T01:51:21Z**

Cause, as measured: the default StepScheduler queued idle steps at Priority.idle. While transient frame callbacks are registered, defaultSchedulingStrategy holds such a task at the head of Flutter's task queue, and _runTasks asks again at once with Timer.run. In a widget test, 10 animation frames with idle work waiting made 1020 queue polls before a cap of 1000 let the tasks run.

Fix: both kinds of step use Priority.animation, so the queue never holds them. An idle step that runs while an animation is registered does no layout. It waits in a post-frame callback and goes back into the queue at the end of the next frame. So it wakes the event loop at most once a frame, and it runs after the first frame that ends with no animation. Urgent steps run as before.

Device measurement, own disposable AVD (android-36 google_apis arm64, swiftshader, host under load from other emulators), profile build of a temporary probe that held an indeterminate LinearProgressIndicator for 10 s with a PageSource main run waiting. CPU time of the Dart UI thread (Android main thread, /proc/self/task/<pid>/stat) and task polls, two rounds:
- Animation only: 680 and 430 ms CPU (first run of the probe: 740 and 1600 ms).
- Old scheduler: 3950 and 3800 ms CPU, 3842 and 5071 polls in 29 frames (first run: 3590 and 4720 ms, 5318 and 1551 polls).
- New scheduler: 690 and 1500 ms CPU, 22 polls in 22 frames and 23 polls in 23 frames (first run: 840 and 1030 ms, 24 and 23 polls).
The emulator drew only 2 to 3 frames a second, so the numbers show the busy loop and its end, not phone frame rates. On a phone with short frames, the old loop fills more of each gap between frames.

The reader widget tests no longer need runIdleStepsDuringAnimations, which is removed. The two shared_appearance tests that ended with the reader open now leave the reader at their end: layout that waited for the last animation is woken at the end of that frame, and its zero timer must run before Flutter checks for pending timers.

While frames are disabled (the app in the background), a waiting idle step waits until frames resume. Before, the busy loop went on in the background.
