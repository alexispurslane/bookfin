---
id: t0-bv9p
status: open
deps: [t0-i4kg]
links: []
created: 2026-11-09T21:19:35Z
type: task
priority: 2
assignee: Alexis Purslane
parent: t0-t799
---
# Read book text aloud correctly: English normalization and G2P without espeak-ng

Bookfin-owned front end for the chosen voice: normalize Roman numeral headings, dates, numbers, currency (including pre-decimal), abbreviations such as St., Dr., Nos., i.e., and times. For Kokoro, turn words into phoneme tokens with misaki's Apache-2.0 lexicons and Bookfin rules, keep each word's token span, and handle common homographs. No GPL code. The book-text test in docs/research/on-device-tts.md lists the failures to fix. Skip the G2P part if the user chooses design B.

