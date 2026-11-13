#!/usr/bin/env bash
# Run through nix develop from the project root. Both real entry points must
# compile for the browser; checking imports as text would miss transitive ones.
# This checks build portability only, without launching a browser.
set -uo pipefail

result=0
for target in lib/main.dart lib/gallery.dart; do
  if flutter build web --no-pub --target="$target"; then
    if ! test -s build/web/main.dart.js; then
      printf 'FAIL: %s produced no JavaScript application.\n' "$target" >&2
      result=1
    fi
  else
    printf 'FAIL: %s does not build for the browser.\n' "$target" >&2
    result=1
  fi
done
exit "$result"
