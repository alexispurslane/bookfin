# The Android app's native libraries: the MOBI converter and the bridge to
# Tesseract's C API. The Nix build of the host MOBI converter builds mobi/
# alone.
cmake_minimum_required(VERSION 3.22)
project(bookfin_native C)
add_subdirectory(mobi)
add_subdirectory(ocr)
