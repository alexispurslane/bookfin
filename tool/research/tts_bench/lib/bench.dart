// One benchmark run of one voice: load the model, time a short first clause
// cold and warm, then synthesize book sentences one at a time for a fixed
// wall time. Every event is one JSON line in the results file and in the log.
import 'dart:convert';
import 'dart:io';

import 'package:sherpa_onnx/sherpa_onnx.dart' as so;

/// A run plan, read from a JSON file.
///
/// `model` is `kokoro`, `kitten` or `supertonic`. `dir` holds the model
/// files. `modelFile` names the Kokoro or Kitten ONNX file inside `dir`.
class Plan {
  Plan.fromJson(Map<String, dynamic> j)
    : label = j['label'] as String,
      model = j['model'] as String,
      dir = j['dir'] as String,
      modelFile = j['modelFile'] as String? ?? '',
      lexicon = j['lexicon'] as String? ?? '',
      threads = j['threads'] as int,
      sid = j['sid'] as int? ?? 0,
      numSteps = j['numSteps'] as int? ?? 5,
      textFile = j['textFile'] as String,
      startLine = j['startLine'] as int? ?? 0,
      seconds = j['seconds'] as int,
      firstClause = j['firstClause'] as String? ?? 'He read the letter twice,',
      passageFile = j['passageFile'] as String? ?? '',
      passageWav = j['passageWav'] as String? ?? '',
      ipaFile = j['ipaFile'] as String? ?? '',
      extraIpaFile = j['extraIpaFile'] as String? ?? '';

  final String label, model, dir, modelFile, lexicon, textFile;
  final String firstClause, passageFile, passageWav;

  /// IPA phonemes, one line per line of [textFile], made on the Mac by
  /// scripts/phonemize.py. If set, Kokoro and Kitten read these instead of
  /// the text. [extraIpaFile] holds the first clause, then the passage.
  final String ipaFile, extraIpaFile;
  final int threads, sid, numSteps, startLine, seconds;
}

so.OfflineTtsConfig _config(Plan p) {
  final d = p.dir;
  final so.OfflineTtsModelConfig m = switch (p.model) {
    'kokoro' => so.OfflineTtsModelConfig(
      kokoro: so.OfflineTtsKokoroModelConfig(
        model: '$d/${p.modelFile}',
        voices: '$d/voices.bin',
        tokens: '$d/tokens.txt',
        lexicon: p.lexicon.isEmpty ? '$d/lexicon-us-en.txt' : p.lexicon,
      ),
      numThreads: p.threads,
    ),
    'kitten' => so.OfflineTtsModelConfig(
      kitten: so.OfflineTtsKittenModelConfig(
        model: '$d/${p.modelFile}',
        voices: '$d/voices.bin',
        tokens: '$d/tokens.txt',
        lexicon: p.lexicon,
      ),
      numThreads: p.threads,
    ),
    'supertonic' => so.OfflineTtsModelConfig(
      supertonic: so.OfflineTtsSupertonicModelConfig(
        durationPredictor: '$d/duration_predictor.int8.onnx',
        textEncoder: '$d/text_encoder.int8.onnx',
        vectorEstimator: '$d/vector_estimator.int8.onnx',
        vocoder: '$d/vocoder.int8.onnx',
        ttsJson: '$d/tts.json',
        unicodeIndexer: '$d/unicode_indexer.bin',
        voiceStyle: '$d/voice.bin',
      ),
      numThreads: p.threads,
    ),
    _ => throw ArgumentError('unknown model ${p.model}'),
  };
  return so.OfflineTtsConfig(model: m);
}

/// Peak and current resident memory of this process in KB, from Linux's
/// /proc. Zero where /proc does not exist (macOS).
(int, int) _memoryKb() {
  final f = File('/proc/self/status');
  if (!f.existsSync()) return (0, 0);
  int field(String s, String name) =>
      int.tryParse(RegExp('$name:\\s+(\\d+)').firstMatch(s)?.group(1) ?? '') ??
      0;
  final s = f.readAsStringSync();
  return (field(s, 'VmHWM'), field(s, 'VmRSS'));
}

/// Runs [p] and appends JSON lines to [out]. [log] receives each line too.
void runPlan(Plan p, File out, void Function(String) log) {
  // Reset this process's peak memory (VmHWM) so that each plan reports its
  // own peak. Linux accepts "5" in clear_refs for that.
  try {
    File('/proc/self/clear_refs').writeAsStringSync('5');
  } on FileSystemException {
    // macOS has no /proc.
  }
  final sink = out.openSync(mode: FileMode.append);
  final clock = Stopwatch()..start();
  void emit(Map<String, Object?> e) {
    final (hwm, rss) = _memoryKb();
    final line = jsonEncode({
      'label': p.label,
      't': clock.elapsedMilliseconds,
      'epochMs': DateTime.now().millisecondsSinceEpoch,
      ...e,
      'hwmKb': hwm,
      'rssKb': rss,
    });
    sink.writeStringSync('$line\n');
    sink.flushSync();
    log('TTSBENCH $line');
  }

  final usesIpa = p.ipaFile.isNotEmpty && p.model != 'supertonic';
  // Text in, or IPA in when [usesIpa]. Returns the samples and the time.
  (so.GeneratedAudio, int) synth(String text) {
    final gen = so.OfflineTtsGenerationConfig(
      sid: p.sid,
      numSteps: p.numSteps,
      phonemeCodepoints: usesIpa ? [text.runes.toList()] : null,
    );
    final w = Stopwatch()..start();
    final a = _tts!.generateWithConfig(text: usesIpa ? '' : text, config: gen);
    return (a, w.elapsedMilliseconds);
  }

  ({int ms, int audioMs}) speak(String text) {
    final (a, ms) = synth(text);
    final audioMs = a.sampleRate == 0
        ? 0
        : a.samples.length * 1000 ~/ a.sampleRate;
    return (ms: ms, audioMs: audioMs);
  }

  final extra = usesIpa
      ? File(p.extraIpaFile).readAsLinesSync()
      : [
          p.firstClause,
          if (p.passageFile.isNotEmpty)
            File(p.passageFile).readAsStringSync().replaceAll('\n', ' ').trim(),
        ];

  emit({'event': 'start', 'threads': p.threads, 'model': p.model});
  final load = Stopwatch()..start();
  _tts = so.OfflineTts(_config(p));
  load.stop();
  emit({'event': 'load', 'ms': load.elapsedMilliseconds});

  final cold = speak(extra[0]);
  emit({'event': 'firstClauseCold', 'ms': cold.ms, 'audioMs': cold.audioMs});
  final warm = speak(extra[0]);
  emit({'event': 'firstClauseWarm', 'ms': warm.ms, 'audioMs': warm.audioMs});

  if (p.passageFile.isNotEmpty) {
    final (a, ms) = synth(extra[1]);
    if (p.passageWav.isNotEmpty) {
      so.writeWave(
        filename: p.passageWav,
        samples: a.samples,
        sampleRate: a.sampleRate,
      );
    }
    emit({
      'event': 'passage',
      'ms': ms,
      'audioMs': a.samples.length * 1000 ~/ a.sampleRate,
    });
  }

  final lines = File(usesIpa ? p.ipaFile : p.textFile)
      .readAsLinesSync()
      .skip(p.startLine)
      .where((l) => l.trim().isNotEmpty)
      // Kitten's BERT encoder fails above about 500 tokens. The few longer
      // book lines are left out for every model, so all read the same lines.
      .where((l) => l.runes.length <= 400)
      .toList();
  final runStart = clock.elapsedMilliseconds;
  var i = 0;
  while (clock.elapsedMilliseconds - runStart < p.seconds * 1000 &&
      i < lines.length) {
    final r = speak(lines[i]);
    emit({
      'event': 'sentence',
      'i': i + p.startLine,
      'chars': lines[i].length,
      'ms': r.ms,
      'audioMs': r.audioMs,
    });
    i++;
  }
  emit({'event': 'done', 'sentences': i});
  _tts!.free();
  _tts = null;
  sink.closeSync();
}

so.OfflineTts? _tts;
