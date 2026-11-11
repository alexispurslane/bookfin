# Tool code for the boo-snng speech prototype, not part of Bookfin.
# Builds libspeech_probe with whisper.cpp and its own ggml linked in, from
# the pinned source in BOOKFIN_WHISPER_SOURCE (nix develop .#speech). The
# Mac and Android builds use the same code on the CPU only: no Metal, no
# Accelerate, no OpenMP.
cmake_minimum_required(VERSION 3.22)
project(speech_probe C CXX)

if(NOT WHISPER_SOURCE)
  set(WHISPER_SOURCE $ENV{BOOKFIN_WHISPER_SOURCE})
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
  # The Tensor G3 and the M1 under the emulator both have these.
  set(GGML_NATIVE OFF CACHE BOOL "" FORCE)
  set(GGML_CPU_ARM_ARCH "armv8.2-a+dotprod+fp16" CACHE STRING "" FORCE)
endif()
add_subdirectory(${WHISPER_SOURCE} whisper)

add_library(speech_probe SHARED speech_probe.c)
target_link_libraries(speech_probe PRIVATE whisper)
