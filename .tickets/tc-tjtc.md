---
id: tc-tjtc
status: open
deps: [tc-acl5, tc-nang, tc-nh0b]
links: []
created: 2026-11-08T19:23:12Z
type: feature
priority: 1
assignee: Alexis Purslane
parent: boo-b2ey
---
# Make pages in a page source that lays out between frames and keeps a bounded cache

Goal: the one owner of prepared sections, layout runs, page starts, laid pages, decoded images and embedded fonts for an open book. It works from the shown place outward, in steps between frames, and keeps memory bounded.

Design sections: "Pages", "Layout off the frame path" (Steps, Order of work, Cache policy, Settings changes), "State and owners".

Files: lib/reader/epub/page_source.dart (new), test/reader/epub/page_source_test.dart.

Interfaces:

```dart
typedef StepScheduler = void Function(void Function() step, {required bool urgent});

class PageSource {
  PageSource(Publication publication,
      {StepScheduler? schedule, Duration budget = const Duration(milliseconds: 4)});
  /// Pages for [value] from now on. The previous settings' prepared
  /// sections and page starts stay until the next change.
  set settings(PageSettings value);
  /// Section [index] prepared for the current settings, in a worker.
  Future<PreparedSection> section(int index);
  /// The true page that holds [place] if the main run passed it; else, when
  /// [anchored], the page that starts at the line that holds it; else waits
  /// for the true page. [urgent] work goes first. [abandon] stops a wait.
  Future<LaidPage> pageAt(EpubPlace place,
      {required bool anchored, bool urgent = false, Future<void>? abandon});
  /// The page cut after [page], the next section's first page, or null.
  Future<LaidPage?> after(LaidPage page);
  /// The true page before [page] (waits for the main run), the previous
  /// section's last page, or null.
  Future<LaidPage?> before(LaidPage page);
  bool isTrue(LaidPage page);
  /// A picture now, with outlines for images not decoded yet.
  ui.Picture draft(LaidPage page);
  /// A picture once the page's images are decoded at [scale].
  Future<ui.Picture> picture(LaidPage page, {double scale = 1});
  /// The shown page: pin it and its neighbors, and plan work around it.
  void show(LaidPage page);
  void dispose();
  /// On-demand invariant check, usable in every build.
  void checkInvariants();
}
```

Rules:
- Prepare with prepareSections inside Isolate.run, a batch of sections per call. SectionSource gets Publication.bookStyles for linked and imported sheets and Publication.imageSizes.
- Await BookFonts.load (tc-nh0b) before the first step of a section whose prepared fonts list is not empty.
- Default scheduler: SchedulerBinding.instance.scheduleTask. Urgent steps use Priority.animation, other steps Priority.idle. One task runs one LayoutRun.step with the budget.
- Order of work and cache limits exactly as the design's tables. Eviction disposes paragraphs and pictures. Never evicted: the shown page and its two neighbors, the shown section's prepared section, the images of the shown page.
- At most one anchored run per section. Drop it once the main run passes its start and none of its pages shows.
- Decode images with ui.instantiateImageCodec at the drawn size times scale.
- Invariants: every cached page belongs to a cached section and to the current or previous settings. The page starts of a section increase. No pinned page is evicted. Each cache is within its limit.

## Design

docs/plans/native-epub-reader.md (epic boo-b2ey). Read the sections named in the description. The design decides the owners, interfaces and order. Ask the orchestrator before changing them.

## Acceptance Criteria

- With a test scheduler: opening at a place deep in a 400,000-character fixture section gives its anchored page after the prepare plus the steps for one paragraph and one page, long before the main run ends.
- Urgent steps run before idle steps. Idle steps wait while the test scheduler reports an animation.
- A page dropped from the cache and asked for again is identical (start, end, line starts).
- After a settings change, pages come for the new settings. A change back reuses the previous settings' prepared sections without a worker call.
- after crosses into the next section. before crosses into the previous section's last true page.
- pageAt with anchored false waits for the true page.
- In a scripted scrub over a whole book, checkInvariants passes after every step.
- Fonts are registered before the first paragraph that uses them.
- An on-demand host benchmark shows no step longer than the budget plus the longest paragraph.

