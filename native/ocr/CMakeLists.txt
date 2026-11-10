# bookfin_ocr: the JNI bridge to Tesseract's C API in the libtesseract.so of
# the pinned tesseract4android AAR. It links that library as it is.
if(NOT DEFINED BOOKFIN_OCR_ANDROID_NATIVE)
  set(BOOKFIN_OCR_ANDROID_NATIVE "$ENV{BOOKFIN_OCR_ANDROID_NATIVE}")
endif()
if(NOT EXISTS "${BOOKFIN_OCR_ANDROID_NATIVE}/include/tesseract/capi.h")
  message(FATAL_ERROR "Use the pinned Bookfin Nix shell for the Tesseract C API")
endif()
add_library(tesseract SHARED IMPORTED)
set_target_properties(tesseract PROPERTIES
  IMPORTED_LOCATION "${BOOKFIN_OCR_ANDROID_NATIVE}/jni/${ANDROID_ABI}/libtesseract.so")
add_library(bookfin_ocr SHARED bookfin_ocr.c)
target_include_directories(bookfin_ocr PRIVATE "${BOOKFIN_OCR_ANDROID_NATIVE}/include")
target_link_libraries(bookfin_ocr tesseract)
target_link_options(bookfin_ocr PRIVATE "-Wl,-z,max-page-size=16384")
install(TARGETS bookfin_ocr LIBRARY DESTINATION lib)
