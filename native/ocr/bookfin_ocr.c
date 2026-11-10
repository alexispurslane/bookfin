// The bridge from TesseractEngine in OcrChannel.kt to Tesseract's C API.
// tesseract4android 4.9.0's Java TessBaseAPI has no call for the layout
// pass, but its libtesseract.so exports the C API (capi.h of the same
// release). One handle is one TessBaseAPI with Bookfin's English model.
//
// The calls are the ones that the Java TessBaseAPI made before this bridge
// (Init with OEM_LSTM_ONLY, page segmentation mode 3, SetImage of 8-bit
// gray, Recognize, GetHOCRText of page 0, then Clear and
// ClearAdaptiveClassifier), so recognition gives the same hOCR.

#include <jni.h>
#include <stdint.h>
#include <stdlib.h>
#include <tesseract/capi.h>

// A layout record is a list of entries of nine 32-bit numbers each, in
// Tesseract's reading order: kind, left, top, right, bottom, then four
// numbers whose meaning depends on the kind. Boxes are in pixels of the
// image, with the origin at the top left, and right and bottom exclusive.
//
// - Page (kind 0), always the first entry and the only page: the box is
//   the whole image, and the four numbers are 0.
// - Block (kind 1): Tesseract's TessPolyBlockType, then three 0s. A
//   picture, a rule or noise has no paragraphs, lines or words, as in hOCR.
// - Paragraph (kind 2): its TessParagraphJustification, its first-line
//   indent in pixels, whether it is a list item, and whether it is a crown
//   (the first paragraph of a block or a continuation), 1 or 0.
// - Line (kind 3) and word (kind 4): the baseline from (x1, y1) to (x2, y2)
//   at the box's left and right edges.
enum { PAGE, BLOCK, PARAGRAPH, LINE, WORD, ENTRY = 9 };

typedef struct {
  jint *values;
  size_t count;
  size_t capacity;
} Record;

// Adds one entry, or returns 0 when memory runs out.
static int add(Record *record, jint kind, const int box[4], jint a, jint b, jint c, jint d) {
  if (record->count + ENTRY > record->capacity) {
    size_t capacity = record->capacity ? record->capacity * 2 : ENTRY * 256;
    jint *values = realloc(record->values, capacity * sizeof(jint));
    if (values == NULL) return 0;
    record->values = values;
    record->capacity = capacity;
  }
  jint entry[ENTRY] = {kind, box[0], box[1], box[2], box[3], a, b, c, d};
  for (int index = 0; index < ENTRY; index++) record->values[record->count++] = entry[index];
  return 1;
}

// Whether a block of [type] is one box without lines or words: a picture,
// a rule or noise. Tesseract gives such a block a line and a word that
// cover it, and its hOCR skips them, so the record skips them too.
static int whole(TessPolyBlockType type) {
  return type == PT_FLOWING_IMAGE || type == PT_HEADING_IMAGE || type == PT_PULLOUT_IMAGE ||
         type == PT_HORZ_LINE || type == PT_VERT_LINE || type == PT_NOISE;
}

// Adds an entry for each block, paragraph, line and word of the layout that
// [it] walks, after the page entry of a [width] by [height] image. Returns
// 0 when memory runs out.
static int walk(TessPageIterator *it, int width, int height, Record *record) {
  const int page[4] = {0, 0, width, height};
  if (!add(record, PAGE, page, 0, 0, 0, 0)) return 0;
  if (it == NULL) return 1; // An empty page has no blocks.
  int box[4], x1, y1, x2, y2;
  int more = 1;
  while (more) {
    if (TessPageIteratorIsAtBeginningOf(it, RIL_BLOCK)) {
      TessPolyBlockType type = TessPageIteratorBlockType(it);
      TessPageIteratorBoundingBox(it, RIL_BLOCK, &box[0], &box[1], &box[2], &box[3]);
      if (!add(record, BLOCK, box, type, 0, 0, 0)) return 0;
      if (whole(type)) {
        more = TessPageIteratorNext(it, RIL_BLOCK);
        continue;
      }
    }
    if (!TessPageIteratorBoundingBox(it, RIL_WORD, &box[0], &box[1], &box[2], &box[3])) {
      more = TessPageIteratorNext(it, RIL_WORD); // A block without words.
      continue;
    }
    if (TessPageIteratorIsAtBeginningOf(it, RIL_PARA)) {
      TessParagraphJustification justification = JUSTIFICATION_UNKNOWN;
      BOOL list = FALSE, crown = FALSE;
      int indent = 0;
      TessPageIteratorParagraphInfo(it, &justification, &list, &crown, &indent);
      // For a paragraph without a model, ParagraphInfo sets only the
      // justification (unknown), and the C API copies two booleans that
      // nothing set.
      if (justification == JUSTIFICATION_UNKNOWN) list = crown = FALSE;
      int paragraph[4];
      TessPageIteratorBoundingBox(it, RIL_PARA, &paragraph[0], &paragraph[1], &paragraph[2], &paragraph[3]);
      if (!add(record, PARAGRAPH, paragraph, justification, indent, list ? 1 : 0, crown ? 1 : 0)) return 0;
    }
    // A position with a word always has a baseline.
    if (TessPageIteratorIsAtBeginningOf(it, RIL_TEXTLINE)) {
      int line[4];
      TessPageIteratorBoundingBox(it, RIL_TEXTLINE, &line[0], &line[1], &line[2], &line[3]);
      TessPageIteratorBaseline(it, RIL_TEXTLINE, &x1, &y1, &x2, &y2);
      if (!add(record, LINE, line, x1, y1, x2, y2)) return 0;
    }
    TessPageIteratorBaseline(it, RIL_WORD, &x1, &y1, &x2, &y2);
    if (!add(record, WORD, box, x1, y1, x2, y2)) return 0;
    more = TessPageIteratorNext(it, RIL_WORD);
  }
  return 1;
}

static TessBaseAPI *api(jlong handle) { return (TessBaseAPI *)(intptr_t)handle; }

// A new handle with the English model in the folder [tessdata], or 0 when
// the model does not load.
JNIEXPORT jlong JNICALL Java_dev_bookfin_bookfin_TesseractC_create(JNIEnv *env, jobject self, jstring tessdata) {
  const char *path = (*env)->GetStringUTFChars(env, tessdata, NULL);
  if (path == NULL) return 0;
  TessBaseAPI *handle = TessBaseAPICreate();
  int failed = TessBaseAPIInit2(handle, path, "eng", OEM_LSTM_ONLY);
  (*env)->ReleaseStringUTFChars(env, tessdata, path);
  if (failed) {
    TessBaseAPIDelete(handle);
    return 0;
  }
  TessBaseAPISetPageSegMode(handle, PSM_AUTO);
  return (jlong)(intptr_t)handle;
}

// Sets the page to the 8-bit gray image [gray] of [width] by [height]
// pixels. Tesseract copies it.
JNIEXPORT void JNICALL Java_dev_bookfin_bookfin_TesseractC_setImage(JNIEnv *env, jobject self, jlong handle, jbyteArray gray, jint width, jint height) {
  jbyte *pixels = (*env)->GetByteArrayElements(env, gray, NULL);
  if (pixels == NULL) return; // OutOfMemoryError is pending.
  TessBaseAPISetImage(api(handle), (const unsigned char *)pixels, width, height, 1, width);
  (*env)->ReleaseByteArrayElements(env, gray, pixels, JNI_ABORT);
}

// Runs the layout pass on the page, a [width] by [height] image, and gives
// its layout record. The page and its layout stay for recognize.
JNIEXPORT jintArray JNICALL Java_dev_bookfin_bookfin_TesseractC_layout(JNIEnv *env, jobject self, jlong handle, jint width, jint height) {
  TessPageIterator *it = TessBaseAPIAnalyseLayout(api(handle));
  Record record = {NULL, 0, 0};
  int complete = walk(it, width, height, &record);
  if (it != NULL) TessPageIteratorDelete(it);
  jintArray result = NULL;
  if (complete) {
    result = (*env)->NewIntArray(env, (jsize)record.count);
    if (result != NULL) (*env)->SetIntArrayRegion(env, result, 0, (jsize)record.count, record.values);
  } else {
    jclass error = (*env)->FindClass(env, "java/lang/OutOfMemoryError");
    if (error != NULL) (*env)->ThrowNew(env, error, "The layout record does not fit in memory.");
  }
  free(record.values);
  return result;
}

// Recognizes the page and gives its hOCR, or null when recognition fails.
// It reuses the lines of a layout pass on the same page. Recognize must run
// first, because GetHOCRText recognizes only a page without a layout.
JNIEXPORT jstring JNICALL Java_dev_bookfin_bookfin_TesseractC_recognize(JNIEnv *env, jobject self, jlong handle) {
  if (TessBaseAPIRecognize(api(handle), NULL) != 0) return NULL;
  char *hocr = TessBaseAPIGetHOCRText(api(handle), 0);
  if (hocr == NULL) return NULL;
  jstring result = (*env)->NewStringUTF(env, hocr);
  TessDeleteText(hocr);
  return result;
}

// Forgets the page, its layout and its recognition.
JNIEXPORT void JNICALL Java_dev_bookfin_bookfin_TesseractC_clear(JNIEnv *env, jobject self, jlong handle) {
  TessBaseAPIClear(api(handle));
  TessBaseAPIClearAdaptiveClassifier(api(handle));
}

JNIEXPORT void JNICALL Java_dev_bookfin_bookfin_TesseractC_destroy(JNIEnv *env, jobject self, jlong handle) {
  TessBaseAPIEnd(api(handle));
  TessBaseAPIDelete(api(handle));
}
