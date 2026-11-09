---
id: t7-hufl
status: open
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

