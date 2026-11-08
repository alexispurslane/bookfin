---
id: tf-4fv5
status: open
deps: []
links: []
created: 2026-11-08T16:40:03Z
type: bug
priority: 3
assignee: Alexis Purslane
parent: boo-fs0n
---
# Close the engine test browser and fixture when Chromium fails to start

Found in boo-duaq (2026-11-08). In packages/flutter_epub_viewer/engine/test/layout.test.cjs, withReader and other tests call fixture() and then browser() before their try block. Under heavy host load, browser() failed with 'fetch failed' while it read the DevTools address. The spawned Chromium and the fixture HTTP server then stayed open, so 'node --test' never ended until their processes were stopped by hand. Start both inside try/finally, and close a Chromium whose start failed.

