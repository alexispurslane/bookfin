#!/usr/bin/env bash
set -euo pipefail

if [[ ${BOOKFIN_NIX_SHELL:-} != 1 ]]; then
  printf 'Run through the pinned project Nix development shell.\n' >&2
  exit 1
fi
device=${1:?Pass the Android device ID returned by T3.}
flutter pub get
exec flutter test --no-pub integration_test/interrupted_pause_test.dart \
  -d "$device" --reporter expanded
