# EPUB page-preparation timing

The user requested a fresh run ending when the page picture is ready, because
display scheduling, drawing, and screenshot capture can obscure engine costs.
This extends the completed comparison in `epub-engine-comparison.md`.

## Measurement contract

Keep the same public books, selected destinations, pinned engine versions,
release shells, cache preparation, font sizes, viewport, and balanced order.
Use the existing Android instrumentation runner on local `emulator-5556`.
No physical-phone work is authorized for this task.

Audit each engine's actual completion event before changing timing. The old
`engine_ready_ns` is diagnostic: Bookfin has a recorded Flutter picture with
decoded page images, KOReader has drawn a bitmap, and WebView has layout,
fonts, and images ready. Those are not identical amounts of work.

Prefer a documented page-preparation endpoint before final pixel rendering,
composition, display, and capture. It must identify the requested destination
and include the work needed to establish its layout and required resources.
Record separate preparation and bitmap/raster milestones where available.
Do not invent an engine API, call DOM readiness a completed bitmap, or compare
Flutter drawing commands with KOReader pixel rendering as equal work.
If an engine cannot expose a defensible corresponding endpoint, report the
specific limitation and the nearest truthful measurements to the parent before
publishing comparative claims. This is a measurement question, not permission
to replace any engine or weaken layout quality.

Record the end timestamp at the actual completion event, before bridge
serialization and diagnostic text extraction where possible. Document clock
domains, conversions and any unavoidable scheduling inside the interval.
Do not subtract a guessed constant from elapsed times. Preserve both elapsed
preparation time and the existing display/copy interval when feasible.

## Correctness and execution

Screenshot/reference, source-text, destination, image, font and cache-state
checks still run after timing. Accept a timing sample only after those checks
succeed. Keep the engine state stable until verification completes, and make
stale events, rejected content and incomplete runs explicit in results.
Tests must show that delayed capture cannot change the preparation endpoint
and failed content cannot enter successful timing aggregates.

Use a new evidence directory and run prefix. Preserve all original evidence.
Run fresh measurements, not merely a recalculation of old readiness fields.
Finish builds before the timed schedule and run one heavy command at a time.
Keep process-start counts, actual sample counts, host load, emulator graphics,
cache lifetimes, whole-book pagination differences, and warm-operation scope.

Report equal-weight arithmetic means across the three books, per-book median
and p90, counts, and exact endpoint definitions. Do not change `index.html` as
part of the measurement task. The parent will inspect the report and decide
how the new measurements fit the existing concise homepage.

## Review

One fresh read-only Sol xhigh reviewer checks endpoint comparability, clocks,
content validation, sample selection, raw-to-summary arithmetic, scope, and
design. The lead resolves findings with evidence. The parent owns integration
and ticket closure. No production renderer optimization belongs in this run.

## Revised goal (user, 2026-11-11)

The user restated the goal. Work that the emulator makes disproportionately
slow or fast, compared with a real phone, must be excluded from every
engine's timed interval in the same way. Software rasterization (the
emulator draws with the CPU where a phone uses the GPU) is the example the
user gave. Work that costs about the same on the emulator and on a phone,
such as parsing, layout, shaping, pagination, and image decoding on the CPU,
stays inside every engine's interval.

This replaces the Option A scope above. The aim is again one symmetric
interval per engine. For each engine, classify each step as emulator-skewed
or not, from the engine's source and the emulator's graphics configuration.
Exclude the skewed steps for all three engines. When an engine fuses a
skewed step with an unskewed one (KOReader decodes images inside its CPU
Draw), measure or isolate the unskewed part if you can, and state the
remaining asymmetry in the report. Note that KOReader rasterizes on the CPU
on a phone too, so its drawing is not emulator-skewed in the same way as
Flutter or WebView GPU rasterization. Decide this classification with
evidence and report it to the parent before publishing claims.
