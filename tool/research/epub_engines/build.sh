#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$root"
test "${BOOKFIN_NIX_SHELL:-}" = 1 || { echo 'Run through nix develop --command bash tool/research/epub_engines/build.sh' >&2; exit 1; }
evidence=tool/research/epub_engines/evidence
test -f .cache/epub-engines/assets/manifest.json || { echo 'Run prepare.py first' >&2; exit 1; }
ndk="$ANDROID_HOME/ndk/28.2.13676358/toolchains/llvm/prebuilt/darwin-x86_64"
native=.cache/epub-engines/jni/arm64-v8a
"$ndk/bin/aarch64-linux-android29-clang++" -std=c++17 -O3 -fPIC -shared -static-libstdc++ \
  tool/research/epub_engines/native/bridge.cpp -L"$native" \
  -l:libkoreader-monolibtic.so -l:libluajit.so -ljnigraphics -llog \
  -Wl,-z,max-page-size=16384 -Wl,-soname,libepub-bench.so -o "$native/libepub-bench.so"
if ! test -f .cache/epub-engines/benchmark.keystore; then
  keytool -genkeypair -keystore .cache/epub-engines/benchmark.keystore -storepass benchmark \
    -keypass benchmark -alias benchmark -dname 'CN=Public EPUB benchmark' -keyalg RSA -validity 10000 >/dev/null 2>&1
fi
printf 'sdk.dir=%s\n' "$ANDROID_HOME" > tool/research/epub_engines/native/local.properties
gradle="$(cat .cache/epub-engines/source-path.txt)/gradle-9.3.1/bin/gradle"
"$gradle" -p tool/research/epub_engines/native :app:assembleWebviewRelease :app:assembleKoreaderRelease :app:assembleWebviewReleaseAndroidTest :app:assembleKoreaderReleaseAndroidTest --no-daemon --console=plain > "$evidence/native-build.txt" 2>&1
mkdir -p tool/research/epub_engines/bookfin/.cache
cp .cache/epub-engines/assets/SourceSerif4.ttf tool/research/epub_engines/bookfin/.cache/SourceSerif4.ttf
cd tool/research/epub_engines/bookfin
flutter pub get > ../evidence/flutter-pub-get.txt 2>&1
flutter build apk --release --target-platform android-arm64 > ../evidence/bookfin-build.txt 2>&1
"$gradle" -p android :app:assembleReleaseAndroidTest -Ptarget-platform=android-arm64 \
  --project-cache-dir="$root/.cache/epub-engines/flutter-test-gradle" \
  -Pkotlin.project.persistent.dir="$root/.cache/epub-engines/flutter-test-kotlin" \
  -x :app:mergeReleaseNativeLibs \
  --no-daemon --console=plain > ../evidence/bookfin-test-build.txt 2>&1
