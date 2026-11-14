#!/usr/bin/env bash
# Builds the signed arm64 release APK of one version tag, checks its native
# payloads and its signer, and copies it to dist/bookfin.apk and
# dist/bookfin-<version>.apk. The release workflow runs it, and you can too:
#
#   nix develop --command bash tool/release/build-release-apk.sh v1.2.3
#
# The dev shell's BOOKFIN_RELEASE_SIGNING must name the release key's
# properties file (see android/app/build.gradle.kts).
set -euo pipefail

tag=${1:?usage: build-release-apk.sh vMAJOR.MINOR.PATCH}
if [[ ! $tag =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  echo "Not a release version tag: $tag" >&2
  exit 1
fi
major=$((10#${BASH_REMATCH[1]}))
minor=$((10#${BASH_REMATCH[2]}))
patch=$((10#${BASH_REMATCH[3]}))
if ((minor > 999 || patch > 999)); then
  echo "Minor and patch numbers must be below 1000: $tag" >&2
  exit 1
fi
version="$major.$minor.$patch"
# Android installs an update only over a lower versionCode, so the code
# grows with the version: v1.2.3 is 1002003.
version_code=$((major * 1000000 + minor * 1000 + patch))

# The SHA-256 of the Bookfin release certificate. Every published APK must
# carry it, or phones refuse it as an update.
release_certificate=1f8d2a906453be338870eae05c560d4d0c093b7f040e24bff0ac059c96ce464b

if [[ ! -f ${BOOKFIN_RELEASE_SIGNING:-} ]]; then
  echo "No release key: BOOKFIN_RELEASE_SIGNING names no file." >&2
  exit 1
fi

cd "$(dirname "$0")/../.."
apk=build/app/outputs/flutter-apk/app-release.apk
# A failed build must not leave an older APK to publish.
rm -f "$apk"
python3 tool/reader/native_package.py prepare
flutter pub get
flutter build apk --release --target-platform android-arm64 \
  --build-name "$version" --build-number "$version_code"

certificates=$("$ANDROID_HOME/build-tools/36.0.0/apksigner" verify --print-certs "$apk")
if ! grep -q "certificate SHA-256 digest: $release_certificate" <<<"$certificates"; then
  echo "The APK is not signed with the Bookfin release key:" >&2
  echo "$certificates" >&2
  exit 1
fi
python3 tool/reader/native_package.py verify "$apk"
python3 tool/reader/ocr_package.py verify "$apk"
python3 tool/reader/speech_package.py verify "$apk"

mkdir -p dist
cp "$apk" "dist/bookfin-$version.apk"
cp "$apk" dist/bookfin.apk
echo "Built Bookfin $version ($version_code): dist/bookfin.apk"
