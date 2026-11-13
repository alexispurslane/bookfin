---
id: t2-p0cc
status: open
deps: []
links: []
created: 2026-11-13T02:25:13Z
type: bug
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Free the native speech model when an abandoned worker dies

lib/speech/native.dart:80-96 and lib/speech/speech.dart:191 (_Model). Every worker abandoned at its time limit skips the end job that calls bs_close. The model has no finalizer, so about 100 MB remains allocated even when the native call returns and the isolate dies. Attach a NativeFinalizer, which runs native cleanup when the model object is collected or its isolate dies, to the model object. It must call bs_close and detach on normal close. Check that native calls that still run cannot use freed memory.
