#!/usr/bin/env bash
set -euo pipefail
: "${ANDROID_HOME:?Run this test through nix develop.}"

test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT
cat > "$test_root/ReaderContext.java" <<'JAVA'
import android.content.Context;
import android.os.ParcelFileDescriptor;

final class ReaderContext {
    static ParcelFileDescriptor open(Context context) throws java.io.IOException {
        return context.getContentResolver().openFileDescriptor(
            android.net.Uri.parse("content://bookfin/reader"), "r");
    }
}
JAVA

for api in 35 36; do
  javac -source 8 -target 8 -Xlint:-options \
    -bootclasspath "$ANDROID_HOME/platforms/android-$api/android.jar" \
    -d "$test_root/api-$api" "$test_root/ReaderContext.java"
  test -s "$test_root/api-$api/ReaderContext.class"
done
printf 'PASS: Android reader file access compiles against shared SDK platforms 35 and 36.\n'
