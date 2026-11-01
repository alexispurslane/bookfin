#!/usr/bin/env bash
set -euo pipefail

test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT
sdk_root="$test_root/existing-sdk"
mkdir -p "$sdk_root/platform-tools"
printf 'existing SDK' > "$sdk_root/platform-tools/marker"

bash tool/link-t3-sdk "$sdk_root"
if [[ ! -L "$sdk_root/cmdline-tools/latest" ]]; then
  printf 'FAIL: T3 must discover the project command-line tools through an additive link.\n' >&2
  exit 1
fi
[[ $(readlink "$sdk_root/cmdline-tools/latest") == "$ANDROID_HOME/cmdline-tools/latest" ]]
[[ $(cat "$sdk_root/platform-tools/marker") == 'existing SDK' ]]
bash tool/link-t3-sdk "$sdk_root"

rm "$sdk_root/cmdline-tools/latest"
mkdir "$sdk_root/cmdline-tools/latest"
printf 'owned elsewhere' > "$sdk_root/cmdline-tools/latest/marker"
if bash tool/link-t3-sdk "$sdk_root"; then
  printf 'FAIL: SDK linking must refuse to replace existing command-line tools.\n' >&2
  exit 1
fi
[[ $(cat "$sdk_root/cmdline-tools/latest/marker") == 'owned elsewhere' ]]

if bash tool/link-t3-sdk "$test_root/missing-sdk"; then
  printf 'FAIL: SDK linking must refuse a missing host SDK.\n' >&2
  exit 1
fi
printf 'PASS: SDK discovery link is additive, repeatable, and refuses existing tools or a missing SDK.\n'
