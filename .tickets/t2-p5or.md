---
id: t2-p5or
status: open
deps: []
links: []
created: 2026-11-12T00:43:50Z
type: task
priority: 2
assignee: Alexis Purslane
parent: boo-z3is
---
# Go to a chapter start without waiting through the narrator's spoken preamble

On the emulator (t2-4ci0), Go to on a reading place at the start of chapter VIII waited 36.9 s: the reading-place loop heard four urgent windows 8 s apart, because LibriVox speaks about 20 s of preamble ("Chapter 8 of The Time Machine. This is a LibriVox recording...") that the ebook does not hold, and the loop steps past a refused window by one window length. Find a rule that reaches the first sentence of a chapter in fewer windows, such as a larger step after a refused window at a chapter start, or a first window placed after the audio chapter's start by the typical preamble length, and measure it on the fixture (tool/showcase_fixture.dart --narrated).

