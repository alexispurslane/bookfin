---
id: t4-kdc8
status: open
deps: []
links: [boo-f4xm]
created: 2026-11-13T03:09:52Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-fs0n
---
# Move large personal-record wire payloads off the UI isolate

Found during boo-f4xm transport extraction. RecordTransport still JSON-encodes each upload and JSON-decodes discovery payload strings on the UI isolate, as LocalResumeStore.synchronize did before extraction. The current plugin limits a discovery page to four objects, but one bookmark note or action can still carry a large payload. No frame cost was measured. Bound inline work by encoded payload size and move large payload encoding/decoding to a worker, keeping validation, server-copy recovery, and ordering unchanged. Coordinate with boo-s11s when larger discovery pages and batch upload arrive. This is separate from boo-f4xm ownership extraction; no batching, expiry, or protocol changes are authorized here.
