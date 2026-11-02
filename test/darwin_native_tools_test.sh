#!/usr/bin/env bash
set -euo pipefail
: "${BOOKFIN_NIX_SHELL:?Run this test through nix develop.}"

test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT
sdk=$(env -u DEVELOPER_DIR -u SDKROOT xcrun --show-sdk-path --sdk macosx) || {
  printf 'FAIL: Native hook SDK discovery failed: %s\n' "$sdk" >&2
  exit 1
}
test -f "$sdk/System/Library/Frameworks/Foundation.framework/Headers/Foundation.h"
case "$sdk" in
  /nix/store/*) ;;
  *) printf 'FAIL: Native hooks must use the pinned macOS SDK.\n' >&2; exit 1 ;;
esac
test "$sdk" = "$(env -u DEVELOPER_DIR -u SDKROOT xcrun --sdk macosx --show-sdk-path)"
test "$sdk" = "$(DEVELOPER_DIR="$test_root" SDKROOT="$test_root" xcrun --sdk macosx --show-sdk-path)"
for unavailable_sdk in iphoneos iphonesimulator bookfin-missing-sdk; do
  if env -u DEVELOPER_DIR -u SDKROOT xcrun --sdk "$unavailable_sdk" --show-sdk-path \
    > "$test_root/sdk-stdout" 2> "$test_root/sdk-stderr"; then
    printf 'FAIL: An unavailable SDK must not resolve to the macOS SDK.\n' >&2
    exit 1
  else
    test "$?" -eq 1
  fi
  if [[ -s "$test_root/sdk-stdout" || ! -s "$test_root/sdk-stderr" ]]; then
    printf 'FAIL: SDK discovery must report errors on stderr, not as an SDK path on stdout.\n' >&2
    exit 1
  fi
  grep -q 'cannot be located' "$test_root/sdk-stderr"
done
printf 'PASS: Native hooks discover the macOS SDK without inherited SDK variables, in either argument order.\n'

case $(xcrun --find codesign) in
  /nix/store/*) ;;
  *) printf 'FAIL: Native hooks must use the pinned signer.\n' >&2; exit 1 ;;
esac
cat > "$test_root/reader.m" <<'OBJC'
#import <Foundation/Foundation.h>

int reader_title_length(void) {
    return [@"Bookfin" length];
}
OBJC
clang -dynamiclib -fobjc-arc -isysroot "$sdk" -framework Foundation \
  -Wl,-no_adhoc_codesign "$test_root/reader.m" -o "$test_root/reader.dylib"
if /usr/bin/codesign --verify --strict "$test_root/reader.dylib"; then
  printf 'FAIL: The signing fixture must start unsigned.\n' >&2
  exit 1
fi
xcrun codesign --force --sign - --timestamp=none "$test_root/reader.dylib"
/usr/bin/codesign --verify --strict "$test_root/reader.dylib"
xcrun codesign --force --sign - --timestamp=none "$test_root/reader.dylib"
/usr/bin/codesign --verify --strict "$test_root/reader.dylib"
if xcrun codesign --force --sign - --timestamp=https://invalid.example "$test_root/reader.dylib"; then
  printf 'FAIL: The ad-hoc signer must reject requested timestamp services.\n' >&2
  exit 1
fi
if xcrun codesign --force --sign - --unsupported-option "$test_root/reader.dylib"; then
  printf 'FAIL: The signer must not ignore unknown options.\n' >&2
  exit 1
fi
printf X | dd of="$test_root/reader.dylib" bs=1 seek=4096 conv=notrunc 2>/dev/null
if /usr/bin/codesign --verify --strict "$test_root/reader.dylib"; then
  printf 'FAIL: Signature verification must detect changed library bytes.\n' >&2
  exit 1
fi
printf 'PASS: Native hooks compile Objective-C and produce a real, verifiable ad-hoc signature without timestamps.\n'
