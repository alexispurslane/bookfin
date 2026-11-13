#!/usr/bin/env bash
set -euo pipefail
# Only ignored package prerequisites from pinned sources and checked-in MOBIs.
# Do not invoke readers/run: it also runs unrelated packages and reports.
cd tool/research/readers
mkdir -p _out/epubx-compat _out/pdfium-host
tar xf "$EPUBX_ARCHIVE" -C _out/epubx-compat
patch --fuzz=0 -p1 -d _out/epubx-compat < epubx-compat.patch
tar xf "$PDFIUM_HOST_ARCHIVE" -C _out/pdfium-host
for name in mobi6-plain mobi6-palmdoc; do
  mobitool -e -o _out "fixtures/$name.mobi"
done
cp fixtures/pg11-kf8.mobi _out/alice.mobi
mobitool -e -o _out _out/alice.mobi
cd dart_compat
dart pub get --enforce-lockfile
