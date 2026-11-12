# bookfin_speech: whisper.cpp on the CPU, and a decoder of audio windows,
# behind one narrow C face (bookfin_speech.c) for Dart FFI. It links
# whisper.cpp and its own ggml statically, from the pinned source that the
# Nix shell names in BOOKFIN_WHISPER_SOURCE. The Android and host builds
# compile the same source: no Metal, no Accelerate, no OpenMP.
cmake_minimum_required(VERSION 3.22)
project(bookfin_speech C CXX)

if(NOT DEFINED WHISPER_SOURCE)
  set(WHISPER_SOURCE "$ENV{BOOKFIN_WHISPER_SOURCE}")
endif()
if(NOT EXISTS "${WHISPER_SOURCE}/include/whisper.h")
  message(FATAL_ERROR "Use the pinned Bookfin Nix shell for the whisper.cpp source")
endif()
if(NOT CMAKE_BUILD_TYPE)
  # A debug build of ggml transcribes several times slower.
  set(CMAKE_BUILD_TYPE Release)
endif()
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(WHISPER_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_SERVER OFF CACHE BOOL "" FORCE)
set(GGML_METAL OFF CACHE BOOL "" FORCE)
set(GGML_BLAS OFF CACHE BOOL "" FORCE)
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
if(ANDROID)
  # ARMv8.2 with dot products and half floats: the Pixel 8's Tensor G3 and
  # the Mac cores under the arm64 emulator both have them.
  set(GGML_NATIVE OFF CACHE BOOL "" FORCE)
  set(GGML_CPU_ARM_ARCH "armv8.2-a+dotprod+fp16" CACHE STRING "" FORCE)
endif()
add_subdirectory(${WHISPER_SOURCE} whisper EXCLUDE_FROM_ALL)

add_library(bookfin_speech SHARED bookfin_speech.c)
target_link_libraries(bookfin_speech PRIVATE whisper)
# Gradle builds a debug APK's native code at -O0, which transcribes several
# times slower and would hide the real cost of a window. The speech code is
# always optimized, without assertions. A later -O3 wins over -O0.
foreach(target whisper ggml ggml-base ggml-cpu bookfin_speech)
  target_compile_options(${target} PRIVATE -O3)
  target_compile_definitions(${target} PRIVATE NDEBUG)
endforeach()
if(ANDROID)
  target_link_libraries(bookfin_speech PRIVATE mediandk log)
  target_link_options(bookfin_speech PRIVATE "-Wl,-z,max-page-size=16384")
elseif(APPLE)
  target_link_libraries(bookfin_speech PRIVATE "-framework AudioToolbox" "-framework CoreFoundation")
endif()
install(TARGETS bookfin_speech LIBRARY DESTINATION lib)
