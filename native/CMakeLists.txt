# The Android app's native libraries: the MOBI converter, the bridge to
# Tesseract's C API, and the speech runtime. The Nix builds of the host MOBI
# converter and the host speech library build mobi/ and speech/ alone.
cmake_minimum_required(VERSION 3.22)
project(bookfin_native C CXX)
add_subdirectory(mobi)
add_subdirectory(ocr)
add_subdirectory(speech)
