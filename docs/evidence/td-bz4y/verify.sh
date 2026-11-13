#!/usr/bin/env bash
set -euo pipefail
# Invoke from the repository root with nix develop --command bash <this file>.
record=docs/evidence/td-bz4y/run.py
python3 "$record" 12-engines-focused bash -c 'cd tool/research/epub_engines && python3 -m unittest -v test_prepare test_calibrate'
python3 "$record" 13-sync-focused python3 docs/evidence/td-bz4y/diagnostic/sync_suite.py focused
python3 "$record" 14-compat-focused bash -c 'cd tool/research/readers/dart_compat && dart test --concurrency=2 --reporter=expanded test/compat_test.dart'
python3 "$record" 15-engines-full bash -c 'cd tool/research/epub_engines && python3 -m unittest discover -v'
python3 "$record" 16-sync-full python3 docs/evidence/td-bz4y/diagnostic/sync_suite.py all
python3 "$record" 17-compat-full bash -c 'cd tool/research/readers/dart_compat && dart test --concurrency=2 --reporter=expanded'
python3 "$record" 18-compat-analysis bash -c 'cd tool/research/readers/dart_compat && dart analyze'
python3 "$record" 19-format-check dart format --output=none --set-exit-if-changed tool/research/readers/dart_compat/test/compat_test.dart
