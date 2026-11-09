---
id: t0-u3nc
status: open
deps: [t0-i4kg]
links: []
created: 2026-11-09T21:19:35Z
type: task
priority: 2
assignee: Alexis Purslane
parent: t0-t799
---
# Build the speech text of a section: sentences and words with their places

On a worker isolate, walk a section's DOM and produce sentences and words, each with its EpubPlace range. Use the DOM's own characters, skip what the renderer hides, footnote marks and image text. Split sentences with book abbreviations and quotations in mind. Independent of page settings. See 'Text from the renderer' in docs/research/on-device-tts.md.

