#!/usr/bin/env bash
# Usage: device-check.sh <evidence dir> <run prefix> <engine:book[:variant]>...
# Runs one instrumented workload per engine and book on emulator-5562, this
# ticket's own emulator.
set -u
out=$1; prefix=$2; shift 2
mkdir -p "$out"
declare -A packages=([bookfin]=dev.bookfin.bench.bookfin_epub_shell [webview]=dev.bookfin.bench.epub.webview [koreader]=dev.bookfin.bench.epub.koreader)
for triple in "$@"; do
  IFS=: read -r engine book variant <<< "$triple"; package=${packages[$engine]}
  run="$prefix-$book-$engine${variant:+-$variant}"; remote="/sdcard/Android/data/$package/files/runs/$run"
  echo "$run: load $(uptime | sed 's/.*averages*: //')"
  adb -s emulator-5562 shell rm -rf "$remote"
  adb -s emulator-5562 shell am instrument -w -r -e class dev.bookfin.bench.epub.EngineWorkloadTest \
    -e book "$book" -e run "$run" -e round 0 ${variant:+-e variant $variant} "$package.test/androidx.test.runner.AndroidJUnitRunner" > "$out/$run-instrumentation.txt" 2>&1
  adb -s emulator-5562 pull "$remote" "$out/$run" > /dev/null 2>&1
  echo "$run: $(grep -E '^(OK|FAILURES)' "$out/$run-instrumentation.txt") $(grep -m1 -o 'AssertionError: .*\|Error: .*' "$out/$run-instrumentation.txt")"
done
