# Short-page placement correction

Base: 2b53a7a5fe89d5f60fdac7557f00712e6ded4f27.

Independent review R1 identified that backward entry into a short source page
could retain its text-end address when placement left scroll offset zero.
The regression first failed with expected character 0, actual 217 (red.txt).

The existing post-layout placement path now measures the visible address after
jumpTo, even when no scroll notification fires. No new position owner or
navigation path was added. The real Flutter viewport regression verifies the
short page has zero scroll extent, crosses forward then backward, checks the
published source page, character zero and beginning quote, and reopens from
that address at font size 40 in a 300-by-600 logical-pixel window. The reopened
page has positive scroll extent but remains at offset and character zero.
The earlier long-page backward and held-image tests also pass (focused.txt).

Commands (pinned project shell):

    nix develop --command bash -c 'flutter test test/reader/pdf_navigation_test.dart --reporter expanded'
    nix develop --command bash -c 'flutter test --concurrency=1 --reporter expanded && flutter analyze'

This is host viewport evidence. It does not establish Android acceptance,
production format fidelity, native replacement or compliance acceptance.

Final results: 406 Flutter tests passed with one optional actual-plugin skip.
Flutter analysis reports no issues. See full-tests.txt and analysis.txt.
