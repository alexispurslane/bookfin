---
id: td-fkhd
status: open
deps: []
links: []
created: 2026-11-09T18:54:32Z
type: task
priority: 3
assignee: Alexis Purslane
parent: boo-fs0n
tags: [reader, ocr]
---
# Remember the pages where recognition found no usable text

Found in boo-981b on 2026-11-09. The text supply caches only recognized text that is a candidate. A page where recognition finds no text, or text out of reading order, is recognized again each time the reflow view or a search asks for it. Since boo-981b, reflow and search also recognize pages whose text layer is out of order, so this repeats more often. Each run takes seconds of the single native worker. Decide whether to cache these results under the same key and version, and keep a recognition failure (an error) out of that cache.

## Acceptance Criteria

Revisiting a page whose recognition found no usable text, in reflow or in search, does not run recognition again while the engine and model version stay the same.

