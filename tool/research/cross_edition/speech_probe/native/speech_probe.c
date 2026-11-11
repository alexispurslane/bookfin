// Tool code for the boo-snng speech prototype, not part of Bookfin.
// A narrow C face of whisper.cpp for Dart FFI: load a model, transcribe a
// window of 16 kHz mono PCM, and give each text token with its start time.
#include <stdio.h>
#include <string.h>
#include <sys/resource.h>

#include "whisper.h"

static void quiet(enum ggml_log_level level, const char *text, void *data) {
  (void)level; (void)text; (void)data;
}

// The model at [path] on the CPU, or NULL. [flash] turns on flash
// attention, which whisper.cpp 1.9 supports on the CPU too.
void *sp_init(const char *path, int flash) {
  whisper_log_set(quiet, NULL);
  struct whisper_context_params cp = whisper_context_default_params();
  cp.use_gpu = false;
  cp.flash_attn = flash != 0;
  return whisper_init_from_file_with_params(path, cp);
}

void sp_free(void *ctx) { whisper_free((struct whisper_context *)ctx); }

// The CPU time of this process so far, user and system, in milliseconds.
long sp_cpu_ms(void) {
  struct rusage u;
  getrusage(RUSAGE_SELF, &u);
  return (long)(u.ru_utime.tv_sec + u.ru_stime.tv_sec) * 1000 +
         (u.ru_utime.tv_usec + u.ru_stime.tv_usec) / 1000;
}

// Transcribes [n] samples of [pcm] with greedy decoding. [audio_ctx] is
// the encoder's context in frames of 20 ms, or 0 for the model's 30 s.
// Writes one line per text token into [out]: "<start ms>\t<text>\n".
// Gives the bytes written, or -1 when whisper fails, or -2 when [out] is
// too small.
int sp_transcribe(void *ctx, const float *pcm, int n, int threads,
                  int audio_ctx, char *out, int cap) {
  struct whisper_context *c = (struct whisper_context *)ctx;
  struct whisper_full_params p =
      whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
  p.n_threads = threads;
  p.audio_ctx = audio_ctx;
  p.language = "en";
  p.no_context = true;
  p.token_timestamps = true;
  p.print_progress = false;
  p.print_realtime = false;
  p.print_timestamps = false;
  p.print_special = false;
  if (whisper_full(c, p, pcm, n) != 0) return -1;
  int used = 0;
  const whisper_token eot = whisper_token_eot(c);
  for (int s = 0; s < whisper_full_n_segments(c); s++) {
    for (int t = 0; t < whisper_full_n_tokens(c, s); t++) {
      whisper_token_data d = whisper_full_get_token_data(c, s, t);
      if (d.id >= eot) continue;
      int wrote = snprintf(out + used, cap - used, "%lld\t%s\n",
                           (long long)d.t0 * 10,
                           whisper_full_get_token_text(c, s, t));
      if (wrote < 0 || wrote >= cap - used) return -2;
      used += wrote;
    }
  }
  return used;
}
