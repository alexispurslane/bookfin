#!/usr/bin/env bash
set -euo pipefail
directory=$(mktemp -d)
trap 'rm -rf "$directory"' EXIT
javac -d "$directory" android/app/src/main/java/dev/bookfin/bookfin/ocr/OcrWorker.java test/native/OcrWorkerTest.java
java -cp "$directory" OcrWorkerTest
