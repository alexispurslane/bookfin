---
id: boo-snng
status: closed
deps: []
links: []
created: 2026-11-11T19:51:50Z
type: task
priority: 1
assignee: Alexis Purslane
parent: boo-z3is
---
# Prototype speech search to correct a whole-book place estimate

User decision 2026-11-11 after t3-a4fi: chapter matching refuses most of the real library. Prototype the user's idea: a whole-book progress estimate, corrected by on-device speech recognition and a text search near the estimate. Audio to text: transcribe about 15 s at the listening place, search the ebook text within the estimate's error window (p90 22 pages). Text to audio: transcribe at the estimated time, find those words in the text, correct the time, repeat 2 to 3 rounds. Fail early when the words are not found, then fall back. Fetch only the needed audio range from the server when not downloaded. Emulator only, no Pixel. Measure speed per jump and accuracy. The user accepts the speech approach only if it is fast.


## Notes

**2026-11-11T22:09:19Z**

Prototype and measurement done (docs/plans/cross-edition-places.md, 'Speech search prototype'). Listening place into the ebook: 239/240 LibriVox and 148/148 server places landed, 94% in the sentence, never a wrong page. Reading place into the audiobook: 145/147 converge from whole-book share in a median of 3 windows, 90th percentile error 0.89 s. Anchor map at 5 min: within 0.23 pages / 12 s at the 90th percentile, 0.03 to 0.09% battery per listening hour (estimate). Phone times are Mac x 2.0 to 2.7, not measured. Two build designs (S1 speech at the tap, S2 anchor map) and four questions for the user wait in the doc. Harness: tool/research/cross_edition/speech_probe, nix develop .#speech.

**2026-11-11T22:37:05Z**

Prototype merged (0ad948a7). User chose S2; build epic boo-vh77.
