// The C face of Bookfin's speech runtime for Dart FFI (lib/speech/).
//
// It loads whisper.cpp's model from a byte range of a file: the APK holds
// the model uncompressed (tool/reader/speech_package.py), so the runtime
// reads it in place, and a test reads a plain file from its start. It
// decodes a window of an audio file and transcribes it on a thread of its
// own at a low priority, so that playback and the UI never wait for it.

#include <math.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <sys/types.h>
#include <unistd.h>

#include "whisper.h"

static void quiet(enum ggml_log_level level, const char *text, void *data) {
  (void)level;
  (void)text;
  (void)data;
}

// The bytes of the model that the loader still has to read.
typedef struct {
  FILE *file;
  long long left;
} Range;

static size_t range_read(void *context, void *output, size_t size) {
  Range *range = context;
  if ((long long)size > range->left) size = (size_t)range->left;
  size_t read = fread(output, 1, size, range->file);
  range->left -= (long long)read;
  return read;
}

static bool range_eof(void *context) {
  Range *range = context;
  return range->left <= 0 || feof(range->file);
}

static void range_close(void *context) {
  (void)context;
}

// The model in the [length] bytes at [offset] of the file at [path], on
// the CPU, or NULL when the file or the model cannot be read.
void *bs_open(const char *path, long long offset, long long length) {
  whisper_log_set(quiet, NULL);
  FILE *file = fopen(path, "rb");
  if (file == NULL) return NULL;
  if (fseeko(file, (off_t)offset, SEEK_SET) != 0) {
    fclose(file);
    return NULL;
  }
  Range range = {file, length};
  struct whisper_model_loader loader = {
      .context = &range,
      .read = range_read,
      .eof = range_eof,
      .close = range_close,
  };
  struct whisper_context_params params = whisper_context_default_params();
  params.use_gpu = false;
  params.flash_attn = true;
  struct whisper_context *context = whisper_init_with_params(&loader, params);
  fclose(file);
  return context;
}

void bs_close(void *context) { whisper_free((struct whisper_context *)context); }

// The samples of a decoded window at the file's own rate, mixed to mono.
typedef struct {
  float *samples;
  int count;
  int capacity;
} Mono;

static int mono_add(Mono *mono, float sample) {
  if (mono->count == mono->capacity) {
    int capacity = mono->capacity ? mono->capacity * 2 : 1 << 16;
    float *samples = realloc(mono->samples, (size_t)capacity * sizeof(float));
    if (samples == NULL) return 0;
    mono->samples = samples;
    mono->capacity = capacity;
  }
  mono->samples[mono->count++] = sample;
  return 1;
}

// [mono] at [rate] samples a second, resampled to 16 kHz in [out] by linear
// interpolation, as the speech prototype did. Gives the samples written.
static int resample(const Mono *mono, int rate, float *out, int capacity) {
  if (mono->count == 0 || rate <= 0) return 0;
  long long count = (long long)mono->count * 16000 / rate;
  if (count > capacity) count = capacity;
  for (long long index = 0; index < count; index++) {
    double at = (double)index * rate / 16000;
    long long left = (long long)at;
    float a = mono->samples[left < mono->count ? left : mono->count - 1];
    float b = mono->samples[left + 1 < mono->count ? left + 1 : mono->count - 1];
    out[index] = a + (b - a) * (float)(at - (double)left);
  }
  return (int)count;
}

#if defined(__APPLE__)
#include <AudioToolbox/AudioToolbox.h>

// Core Audio's ExtAudioFile decodes and converts to 16 kHz mono itself.
static int decode(const char *path, int start_ms, int length_ms, float *out, int capacity) {
  CFURLRef url = CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8 *)path,
                                                         (CFIndex)strlen(path), false);
  if (url == NULL) return -1;
  ExtAudioFileRef file = NULL;
  OSStatus status = ExtAudioFileOpenURL(url, &file);
  CFRelease(url);
  if (status != noErr) return -1;
  int result = -1;
  AudioStreamBasicDescription source;
  UInt32 size = sizeof(source);
  if (ExtAudioFileGetProperty(file, kExtAudioFileProperty_FileDataFormat, &size, &source) != noErr)
    goto done;
  AudioStreamBasicDescription client = {
      .mSampleRate = 16000,
      .mFormatID = kAudioFormatLinearPCM,
      .mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
      .mBytesPerPacket = 4,
      .mFramesPerPacket = 1,
      .mBytesPerFrame = 4,
      .mChannelsPerFrame = 1,
      .mBitsPerChannel = 32,
  };
  if (ExtAudioFileSetProperty(file, kExtAudioFileProperty_ClientDataFormat, sizeof(client),
                              &client) != noErr)
    goto done;
  // The seek counts frames of the file's own rate.
  if (ExtAudioFileSeek(file, (SInt64)start_ms * (SInt64)source.mSampleRate / 1000) != noErr)
    goto done;
  long long want = (long long)length_ms * 16;
  if (want > capacity) want = capacity;
  int count = 0;
  while (count < want) {
    UInt32 frames = (UInt32)(want - count < 4096 ? want - count : 4096);
    AudioBufferList buffers = {
        .mNumberBuffers = 1,
        .mBuffers = {{.mNumberChannels = 1, .mDataByteSize = frames * 4, .mData = out + count}},
    };
    if (ExtAudioFileRead(file, &frames, &buffers) != noErr) goto done;
    if (frames == 0) break;
    count += (int)frames;
  }
  result = count;
done:
  ExtAudioFileDispose(file);
  return result;
}

#elif defined(__ANDROID__)
#include <fcntl.h>
#include <media/NdkMediaCodec.h>
#include <media/NdkMediaExtractor.h>
#include <sys/stat.h>
#include <unistd.h>

// Android's own decoders, through the NDK: the extractor reads the file's
// packets from the sync point before the window, and the codec gives PCM,
// which this mixes to mono and resamples.
static int decode(const char *path, int start_ms, int length_ms, float *out, int capacity) {
  int fd = open(path, O_RDONLY | O_CLOEXEC);
  if (fd < 0) return -1;
  struct stat status;
  AMediaExtractor *extractor = AMediaExtractor_new();
  AMediaCodec *codec = NULL;
  AMediaFormat *format = NULL;
  Mono mono = {0};
  int result = -1;
  if (fstat(fd, &status) != 0 ||
      AMediaExtractor_setDataSourceFd(extractor, fd, 0, status.st_size) != AMEDIA_OK)
    goto done;
  const char *mime = NULL;
  size_t tracks = AMediaExtractor_getTrackCount(extractor);
  for (size_t track = 0; track < tracks && mime == NULL; track++) {
    AMediaFormat *candidate = AMediaExtractor_getTrackFormat(extractor, track);
    const char *kind = NULL;
    if (AMediaFormat_getString(candidate, AMEDIAFORMAT_KEY_MIME, &kind) &&
        strncmp(kind, "audio/", 6) == 0) {
      AMediaExtractor_selectTrack(extractor, track);
      format = candidate;
      AMediaFormat_getString(format, AMEDIAFORMAT_KEY_MIME, &mime);
    } else {
      AMediaFormat_delete(candidate);
    }
  }
  if (mime == NULL) goto done;
  int32_t rate = 0, channels = 0, encoding = 2;
  AMediaFormat_getInt32(format, AMEDIAFORMAT_KEY_SAMPLE_RATE, &rate);
  AMediaFormat_getInt32(format, AMEDIAFORMAT_KEY_CHANNEL_COUNT, &channels);
  codec = AMediaCodec_createDecoderByType(mime);
  if (codec == NULL || AMediaCodec_configure(codec, format, NULL, NULL, 0) != AMEDIA_OK ||
      AMediaCodec_start(codec) != AMEDIA_OK)
    goto done;
  const int64_t start_us = (int64_t)start_ms * 1000, end_us = (int64_t)(start_ms + length_ms) * 1000;
  AMediaExtractor_seekTo(extractor, start_us, AMEDIAEXTRACTOR_SEEK_PREVIOUS_SYNC);
  int input_done = 0, output_done = 0, idle = 0;
  while (!output_done && idle < 400) {
    if (!input_done) {
      // Short waits: the decoder answers within microseconds, and a long
      // wait for each of a window's frames adds up.
      ssize_t index = AMediaCodec_dequeueInputBuffer(codec, 500);
      if (index >= 0) {
        size_t size = 0;
        uint8_t *buffer = AMediaCodec_getInputBuffer(codec, (size_t)index, &size);
        ssize_t read = AMediaExtractor_readSampleData(extractor, buffer, size);
        int64_t time = AMediaExtractor_getSampleTime(extractor);
        if (read < 0 || time > end_us) {
          AMediaCodec_queueInputBuffer(codec, (size_t)index, 0, 0, 0,
                                       AMEDIACODEC_BUFFER_FLAG_END_OF_STREAM);
          input_done = 1;
        } else {
          AMediaCodec_queueInputBuffer(codec, (size_t)index, 0, (size_t)read, (uint64_t)time, 0);
          AMediaExtractor_advance(extractor);
        }
      }
    }
    AMediaCodecBufferInfo info;
    ssize_t index = AMediaCodec_dequeueOutputBuffer(codec, &info, input_done ? 5000 : 500);
    if (index == AMEDIACODEC_INFO_OUTPUT_FORMAT_CHANGED) {
      AMediaFormat *changed = AMediaCodec_getOutputFormat(codec);
      AMediaFormat_getInt32(changed, AMEDIAFORMAT_KEY_SAMPLE_RATE, &rate);
      AMediaFormat_getInt32(changed, AMEDIAFORMAT_KEY_CHANNEL_COUNT, &channels);
      AMediaFormat_getInt32(changed, "pcm-encoding", &encoding);
      AMediaFormat_delete(changed);
    } else if (index >= 0) {
      idle = 0;
      size_t size = 0;
      uint8_t *buffer = AMediaCodec_getOutputBuffer(codec, (size_t)index, &size);
      if (buffer != NULL && channels > 0 && rate > 0) {
        const int bytes = encoding == 4 ? 4 : 2;
        const int frames = info.size / (bytes * channels);
        const uint8_t *data = buffer + info.offset;
        for (int frame = 0; frame < frames; frame++) {
          int64_t us = info.presentationTimeUs + (int64_t)frame * 1000000 / rate;
          if (us < start_us) continue;
          if (us >= end_us) break;
          float sum = 0;
          for (int channel = 0; channel < channels; channel++) {
            int at = frame * channels + channel;
            sum += bytes == 4 ? ((const float *)data)[at] : ((const int16_t *)data)[at] / 32768.0f;
          }
          if (!mono_add(&mono, sum / (float)channels)) goto done;
        }
      }
      AMediaCodec_releaseOutputBuffer(codec, (size_t)index, false);
      if (info.flags & AMEDIACODEC_BUFFER_FLAG_END_OF_STREAM) output_done = 1;
    } else if (input_done) {
      idle++;
    }
  }
  result = resample(&mono, rate, out, capacity);
done:
  if (codec != NULL) {
    AMediaCodec_stop(codec);
    AMediaCodec_delete(codec);
  }
  if (format != NULL) AMediaFormat_delete(format);
  AMediaExtractor_delete(extractor);
  close(fd);
  free(mono.samples);
  return result;
}

#else
// NOTE: The Linux dev shell has no decoder yet. Speech search there falls
// back to matched chapters, and the decoder tests fail.
static int decode(const char *path, int start_ms, int length_ms, float *out, int capacity) {
  (void)path;
  (void)start_ms;
  (void)length_ms;
  (void)out;
  (void)capacity;
  return -1;
}
#endif

// Decodes [length_ms] of the audio file at [path] from [start_ms] to mono
// 16 kHz float samples in [out], which holds [capacity] samples. Gives the
// number of samples, fewer when the file ends sooner, or -1 when the file
// cannot be read or decoded.
int bs_decode(const char *path, int start_ms, int length_ms, float *out, int capacity) {
  if (start_ms < 0 || length_ms <= 0 || capacity <= 0) return -1;
  return decode(path, start_ms, length_ms, out, capacity);
}

// One window to hear, and its result.
typedef struct {
  struct whisper_context *context;
  const char *path;
  int start_ms;
  int length_ms;
  int threads;
  char *out;
  int capacity;
  int result;
} Hearing;

// Lowers the calling thread below the app's own threads. whisper.cpp starts
// its worker threads from this thread, and on Linux and Android a new
// thread takes the nice value of the thread that starts it.
static void lower_priority(void) {
#if defined(__APPLE__)
  pthread_set_qos_class_self_np(QOS_CLASS_UTILITY, 0);
#elif defined(__linux__)
  setpriority(PRIO_PROCESS, (id_t)gettid(), 10);
#endif
}

// Whisper's encoder reads 50 frames a second and pads a window to 30 s
// unless the context is cut. A cut context costs a quarter to a half of a
// full one ("The shortest window").
static int audio_context(int samples) {
  int frames = (int)ceil((double)samples / 16000.0 * 50.0 * 1.1) + 32;
  return frames < 1500 ? frames : 1500;
}

static int transcribe(Hearing *hearing, const float *samples, int count) {
  struct whisper_full_params params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
  params.n_threads = hearing->threads;
  params.audio_ctx = audio_context(count);
  params.language = "en";
  params.no_context = true;
  params.single_segment = true;
  params.token_timestamps = true;
  // A cut context can make whisper repeat one phrase. Narration holds about
  // three words a second, so a window never needs more tokens than this.
  params.max_tokens = count / 16000 * 6 + 8;
  params.print_progress = false;
  params.print_realtime = false;
  params.print_timestamps = false;
  params.print_special = false;
  struct whisper_context *context = hearing->context;
  if (whisper_full(context, params, samples, count) != 0) return -2;
  int used = 0;
  const whisper_token end = whisper_token_eot(context);
  for (int segment = 0; segment < whisper_full_n_segments(context); segment++) {
    for (int token = 0; token < whisper_full_n_tokens(context, segment); token++) {
      whisper_token_data data = whisper_full_get_token_data(context, segment, token);
      if (data.id >= end) continue;
      int wrote = snprintf(hearing->out + used, (size_t)(hearing->capacity - used), "%lld\t%s\n",
                           (long long)data.t0 * 10,
                           whisper_full_get_token_text(context, segment, token));
      if (wrote < 0 || wrote >= hearing->capacity - used) return -3;
      used += wrote;
    }
  }
  return used;
}

static void *hear_window(void *argument) {
  Hearing *hearing = argument;
  lower_priority();
  int capacity = hearing->length_ms * 16 + 16000;
  float *samples = malloc((size_t)capacity * sizeof(float));
  if (samples == NULL) {
    hearing->result = -1;
    return NULL;
  }
  int count = decode(hearing->path, hearing->start_ms, hearing->length_ms, samples, capacity);
  if (count < 0) {
    hearing->result = -1;
  } else if (count < 8000) {
    // Less than half a second holds no word to search.
    hearing->result = 0;
  } else {
    hearing->result = transcribe(hearing, samples, count);
  }
  free(samples);
  return NULL;
}

// Decodes [length_ms] of the audio file at [path] from [start_ms] and
// transcribes it with the model [context] and [threads] threads, on a new
// thread at a low priority. Writes one line for each text token into
// [out]: "<start ms>\t<text>\n", the start counted from the window's start.
// Gives the bytes written, 0 when the window holds less than half a second
// of audio, -1 when the file cannot be decoded, -2 when whisper fails, and
// -3 when [out] is too small.
int bs_hear(void *context, const char *path, int start_ms, int length_ms, int threads, char *out,
            int capacity) {
  if (context == NULL || start_ms < 0 || length_ms <= 0 || threads <= 0) return -1;
  Hearing hearing = {context, path, start_ms, length_ms, threads, out, capacity, -1};
  pthread_attr_t attributes;
  pthread_attr_init(&attributes);
  pthread_attr_setstacksize(&attributes, 4 << 20);
  pthread_t thread;
  int started = pthread_create(&thread, &attributes, hear_window, &hearing);
  pthread_attr_destroy(&attributes);
  if (started != 0) return -1;
  pthread_join(thread, NULL);
  return hearing.result;
}
