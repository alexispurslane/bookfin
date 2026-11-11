// Tool code for the boo-snng speech prototype, not part of Bookfin.
// Measures speech placement on the Mac with the same Dart search and the
// same whisper.cpp build as the Android harness. It decodes windows with
// ffmpeg, and compares each landing with the reference map that
// speech_truth.py made. Usage (in nix develop .#speech):
//   dart run bin/host_eval.dart <work dir> <experiment> <out.jsonl> [options]
// Experiments: audio-to-text, text-to-audio, windows. See main().
import 'dart:convert';
import 'dart:ffi' show DynamicLibrary;
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:speech_probe/place.dart';
import 'package:speech_probe/text.dart';
import 'package:speech_probe/whisper.dart';

/// Where the reference map puts the spoken words of one section.
class Truth {
  Truth(this.ms, this.words);
  final List<int> ms;
  final List<int> words;

  /// The book word spoken at [t] ms into the section, when reference
  /// words lie within 3 s on both sides.
  int? wordAt(int t) {
    var k = _last(ms, t);
    if (k < 0 || k + 1 >= ms.length) return null;
    if (t - ms[k] > 3000 || ms[k + 1] - t > 3000) return null;
    if (words[k + 1] < words[k] || words[k + 1] - words[k] > 12) return null;
    final share = ms[k + 1] == ms[k] ? 0 : (t - ms[k]) / (ms[k + 1] - ms[k]);
    return (words[k] + share * (words[k + 1] - words[k])).round();
  }

  /// When book word [w] is spoken, in ms into the section, when reference
  /// words lie within 10 words on both sides.
  int? msOf(int w) {
    var k = _last(words, w);
    if (k < 0) return null;
    if (words[k] == w) return ms[k];
    if (k + 1 >= words.length || words[k + 1] - words[k] > 10) return null;
    return (ms[k] + (w - words[k]) / (words[k + 1] - words[k]) * (ms[k + 1] - ms[k])).round();
  }

  static int _last(List<int> list, int value) {
    var lo = 0, hi = list.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (list[mid] <= value) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo - 1;
  }
}

class Section {
  Section(this.n, this.file, this.startMs, this.durationMs, this.truth);
  final int n;
  final String? file;
  final int startMs;
  final int durationMs;
  final Truth? truth;

  /// The text span of this section's chapter in visible characters, when
  /// the section reads exactly one contents span (design A's case).
  (int, int)? chapter;
}

class Recording {
  Recording(this.key, this.book, this.sections);
  final String key;
  final BookText book;
  final List<Section> sections;
  int get totalMs => sections.last.startMs + sections.last.durationMs;

  Section at(int ms) => sections.lastWhere((s) => s.startMs <= ms, orElse: () => sections.first);

  /// The whole-book estimate of the ebook word at edition time [ms].
  int shareWord(int ms) => book.wordAt(ms / totalMs * book.characters);

  /// The whole-book estimate of the edition time of book word [w].
  int shareMs(int w) => (book.offsets[w] / book.characters * totalMs).round();

  /// Design A's estimate of the word at [ms], or null outside a matched
  /// chapter.
  int? chapterWord(int ms) {
    final s = at(ms);
    final c = s.chapter;
    if (c == null) return null;
    return book.wordAt(c.$1 + (ms - s.startMs) / s.durationMs * (c.$2 - c.$1));
  }

  /// Design A's estimate of the time of word [w], or null.
  int? chapterMs(int w) {
    final chars = book.offsets[w];
    for (final s in sections) {
      final c = s.chapter;
      if (c != null && chars >= c.$1 && chars < c.$2) {
        return s.startMs + ((chars - c.$1) / (c.$2 - c.$1) * s.durationMs).round();
      }
    }
    return null;
  }
}

Future<Recording> loadRecording(String work, String key, Map<String, dynamic> durations) async {
  final book = BookText.fromJson(jsonDecode(await File('$work/books/$key.json').readAsString()));
  final entries = [
    for (final e in (jsonDecode(await File('$work/books/$key.json').readAsString())['entries'] as List))
      e['start'] as int,
  ]..sort();
  final manifest = jsonDecode(await File('$work/audio/$key/manifest.json').readAsString());
  final sections = <Section>[];
  var start = 0;
  for (final s in manifest['sections'] as List) {
    final n = s['n'] as int;
    final file = s['file'] as String?;
    final path = file == null ? null : '$work/audio/$key/$file';
    final duration = (path != null && durations[path] != null)
        ? durations[path] as int
        : (s['playtime'] as int) * 1000;
    Truth? truth;
    final truthFile = File('$work/truth/$key/${n.toString().padLeft(3, '0')}.json');
    if (await truthFile.exists()) {
      final t = jsonDecode(await truthFile.readAsString());
      final points = (t['points'] as List).cast<List>();
      truth = Truth([for (final p in points) p[0] as int], [for (final p in points) p[1] as int]);
    }
    final section = Section(n, path, start, duration, truth);
    if (truth != null && truth.words.length > 50) {
      final first = book.offsets[truth.words.first], last = book.offsets[truth.words.last];
      final from = entries.lastWhere((e) => e <= first + 50, orElse: () => 0);
      final to = entries.firstWhere((e) => e > last, orElse: () => book.characters);
      if ((last - first) / (to - from) > 0.85) section.chapter = (from, to);
    }
    sections.add(section);
    start += duration;
  }
  return Recording(key, book, sections);
}

/// The duration of each downloaded file in ms, by ffprobe, kept in
/// durations.json.
Future<Map<String, dynamic>> durations(String work, List<String> keys) async {
  final file = File('$work/out/durations.json');
  final known = await file.exists() ? jsonDecode(await file.readAsString()) as Map<String, dynamic> : <String, dynamic>{};
  final ffprobe = (await Process.run('which', ['ffprobe'])).stdout.toString().trim();
  for (final key in keys) {
    final manifest = jsonDecode(await File('$work/audio/$key/manifest.json').readAsString());
    for (final s in manifest['sections'] as List) {
      if (s['file'] == null) continue;
      final path = '$work/audio/$key/${s['file']}';
      if (known.containsKey(path)) continue;
      final r = await Process.run(ffprobe, ['-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', path]);
      known[path] = (double.parse(r.stdout.toString().trim()) * 1000).round();
    }
  }
  await file.writeAsString(jsonEncode(known));
  return known;
}

/// Decodes and transcribes windows of a recording, and keeps the time of
/// each step.
class Listener {
  Listener(this.recording, this.whisper, {this.threads = 4, this.audioCtx = 0});
  final Recording recording;
  final Whisper whisper;
  final int threads;
  int audioCtx;
  final windows = <Map<String, Object?>>[];

  Future<({Heard heard, int startMs})?> call(int startMs, int lengthMs) async {
    // The file that holds the window's middle. A window does not cross
    // the start or end of a file.
    final s = recording.at(startMs + lengthMs ~/ 2);
    if (s.file == null) return null;
    var offset = math.max(0, startMs - s.startMs);
    if (offset + lengthMs > s.durationMs) offset = math.max(0, s.durationMs - lengthMs);
    final watch = Stopwatch()..start();
    final r = await Process.run('ffmpeg', [
      // Over HTTP, seek by the bit rate. ffmpeg's default exact seek reads
      // an MP3 from its first byte.
      '-v', 'error', if (s.file!.startsWith('http')) ...['-fflags', '+fastseek'], '-ss', (offset / 1000).toStringAsFixed(3), '-t', (lengthMs / 1000).toStringAsFixed(3),
      '-i', s.file!, '-f', 'f32le', '-ac', '1', '-ar', '16000', '-',
    ], stdoutEncoding: null);
    final bytes = Uint8List.fromList(r.stdout as List<int>);
    final pcm = bytes.buffer.asFloat32List(0, bytes.length ~/ 4);
    final decodeMs = watch.elapsedMilliseconds;
    final cpu0 = cpuMs(whisper.library);
    watch.reset();
    final heard = whisper.transcribe(pcm, threads: threads, audioCtx: audioCtx);
    windows.add({
      'decodeMs': decodeMs,
      'transcribeMs': watch.elapsedMilliseconds,
      'transcribeCpuMs': cpuMs(whisper.library) - cpu0,
      'lengthMs': lengthMs,
      'words': heard.words.length,
    });
    return (heard: heard, startMs: s.startMs + offset);
  }
}

/// A seeded random sample of [count] edition times inside sections with a
/// reference map, at least [margin] ms from a section's ends.
List<int> sampleTimes(Recording r, int count, math.Random random, {int margin = 20000}) {
  final usable = r.sections.where((s) => s.truth != null && s.durationMs > 2 * margin).toList();
  final total = usable.fold(0, (a, s) => a + s.durationMs - 2 * margin);
  final out = <int>[];
  while (out.length < count) {
    var x = random.nextInt(total);
    for (final s in usable) {
      final span = s.durationMs - 2 * margin;
      if (x < span) {
        final t = s.startMs + margin + x;
        if (s.truth!.wordAt(t - s.startMs) != null) out.add(t);
        break;
      }
      x -= span;
    }
  }
  return out..sort();
}

int? truthWord(Recording r, int ms) {
  final s = r.at(ms);
  return s.truth?.wordAt(ms - s.startMs);
}

int? truthMs(Recording r, int word) {
  for (final s in r.sections) {
    final t = s.truth;
    if (t == null || t.words.isEmpty) continue;
    if (word >= t.words.first && word <= t.words.last) {
      final ms = t.msOf(word);
      return ms == null ? null : s.startMs + ms;
    }
  }
  return null;
}

Map<String, Object?> landingRow(Recording r, int? landing, int? truth) {
  if (landing == null || truth == null) return {'landing': landing, 'truth': truth};
  final b = r.book;
  return {
    'landing': landing,
    'truth': truth,
    'errorWords': landing - truth,
    'errorPages': (b.offsets[landing] - b.offsets[truth]) / pageCharacters,
    'sameSentence': b.sentences[landing] == b.sentences[truth],
  };
}

Future<void> main(List<String> args) async {
  final work = args[0], experiment = args[1], outPath = args[2];
  final options = {
    for (final a in args.skip(3))
      if (a.contains('=')) a.split('=')[0]: a.split('=')[1],
  };
  final keys = (options['books'] ?? 'alice,time-machine,heart-of-darkness,pride-and-prejudice,moby-dick,jane-eyre').split(',');
  final model = options['model'] ?? 'tiny.en-q5_1';
  final count = int.parse(options['count'] ?? '40');
  final lengthMs = int.parse(options['length'] ?? '15000');
  final audioCtx = int.parse(options['ctx'] ?? '0');
  final threads = int.parse(options['threads'] ?? '4');
  final library = openProbe(options['lib'] ?? '$work/build-host/libspeech_probe.dylib');
  final models = Platform.environment['BOOKFIN_WHISPER_MODELS']!;
  final loadWatch = Stopwatch()..start();
  final whisper = Whisper.open(library, '$models/ggml-$model.bin');
  final loadMs = loadWatch.elapsedMilliseconds;
  final out = File(outPath).openWrite(mode: FileMode.append);
  if (experiment == 'server') {
    await runServer(work, options, library, whisper, model, out);
    await out.close();
    whisper.close();
    return;
  }
  final known = await durations(work, keys);
  final load = (await Process.run('sysctl', ['-n', 'vm.loadavg'])).stdout.toString().trim();
  out.writeln(jsonEncode({'event': 'start', 'experiment': experiment, 'model': model, 'loadMs': loadMs, 'loadavg': load, 'options': options}));
  for (final key in keys) {
    final r = await loadRecording(work, key, known);
    final random = math.Random(_stableSeed('$key/${options['seed'] ?? '1'}'));
    final listen = Listener(r, whisper, threads: threads, audioCtx: audioCtx);
    final msPerWord = r.totalMs / r.book.words.length;
    switch (experiment) {
      case 'audio-to-text':
        // A listening place into the ebook: one 15 s window around each
        // sampled time, searched from both estimates.
        for (final t in sampleTimes(r, count, random)) {
          final truth = truthWord(r, t);
          final row = <String, Object?>{'book': key, 'atMs': t, 'model': model, 'lengthMs': lengthMs, 'ctx': audioCtx};
          final windowCount = listen.windows.length;
          Heard? heard;
          int windowStart = 0;
          Future<({Heard heard, int startMs})?> once(int s, int l) async {
            if (heard == null) {
              final w = await listen(s, l);
              if (w == null) return null;
              heard = w.heard;
              windowStart = w.startMs;
            }
            return (heard: heard!, startMs: windowStart);
          }
          for (final (name, estimate, radii) in [
            ('share', r.shareWord(t), wholeBookRadii),
            ('chapter', r.chapterWord(t), chapterRadii),
            ('whole', 0, const [double.infinity]),
          ]) {
            if (estimate == null) continue;
            final result = await audioToText(book: r.book, listen: once, atMs: t, estimateWord: estimate, radiiPages: radii, lengthMs: lengthMs);
            row[name] = {
              'estimateError': truth == null ? null : (r.book.offsets[estimate] - r.book.offsets[truth]) / pageCharacters,
              ...?result.step?.toJson(),
              ...landingRow(r, result.word, truth),
            };
          }
          row['window'] = listen.windows.length > windowCount ? listen.windows.last : null;
          row['heard'] = heard?.words.join(' ');
          out.writeln(jsonEncode(row));
        }
      case 'intro':
        // A listening place 5 s into each section: inside LibriVox's
        // spoken notice.
        for (final s in r.sections.where((s) => s.file != null && s.truth != null)) {
          final t = s.startMs + 5000;
          final result = await audioToText(book: r.book, listen: listen.call, atMs: t, estimateWord: r.shareWord(t), radiiPages: wholeBookRadii, lengthMs: lengthMs);
          final firstTruth = s.truth?.words.first;
          out.writeln(jsonEncode({
            'book': key, 'section': s.n, 'atMs': t, 'model': model,
            ...?result.step?.toJson(),
            'landing': result.word,
            'firstSpokenWord': firstTruth,
            'firstSpokenMs': s.truth?.ms.first,
            'errorWords': result.word != null && firstTruth != null ? result.word! - firstTruth : null,
            'window': listen.windows.last,
          }));
        }
      case 'text-to-audio':
        // A reading place into the audiobook: the start of a sampled
        // sentence, placed from both estimates.
        for (final t in sampleTimes(r, count, random)) {
          var target = truthWord(r, t)!;
          while (target > 0 && r.book.sentences[target - 1] == r.book.sentences[target]) {
            target--;
          }
          final truth = truthMs(r, target);
          if (truth == null) continue;
          final nextSentence = r.book.sentences.indexOf(r.book.sentences[target] + 1, target);
          final sentenceEnd = nextSentence < 0 ? null : truthMs(r, nextSentence);
          final row = <String, Object?>{'book': key, 'target': target, 'truthMs': truth, 'sentenceEndMs': sentenceEnd, 'model': model, 'lengthMs': lengthMs, 'ctx': audioCtx};
          for (final (name, estimate, radii, rate) in [
            ('share', r.shareMs(target), wholeBookRadii, msPerWord),
            ('chapter', r.chapterMs(target), chapterRadii, msPerWord),
          ]) {
            if (estimate == null) continue;
            final before = listen.windows.length;
            final result = await textToAudio(book: r.book, listen: listen.call, target: target, estimateMs: estimate, msPerWord: rate, radiiPages: radii, lengthMs: lengthMs);
            row[name] = {
              'estimateErrorMs': estimate - truth,
              'landingMs': result.ms,
              'errorMs': result.ms - truth,
              'converged': result.converged,
              'rounds': result.steps.length,
              'steps': [for (final s in result.steps) s.toJson()],
              'windows': listen.windows.sublist(before),
            };
          }
          out.writeln(jsonEncode(row));
        }
      case 'windows':
        // The last L s heard before a time, for each window length, as the
        // anchor map would transcribe while playing. Searched near the
        // reference place (the anchor map's case) and in the whole book.
        final lengths = (options['lengths'] ?? '3000,5000,8000,10000,15000').split(',').map(int.parse).toList();
        final reduced = options['reduced'] == 'true';
        for (final t in sampleTimes(r, count, random)) {
          final truth = truthWord(r, t)!;
          for (final l in lengths) {
            listen.audioCtx = reduced ? math.min(1500, (l / 20 * 1.1).ceil() + 32) : 0;
            final row = <String, Object?>{'book': key, 'atMs': t, 'model': model, 'lengthMs': l, 'ctx': listen.audioCtx};
            final w = await listen(t - l, l);
            if (w == null) continue;
            for (final (name, radii) in [('near', const [3.0]), ('whole', const [double.infinity])]) {
              final step = searchAround(r.book, w.heard, w.startMs, truth, radii);
              int? landing;
              if (step.confident) {
                // The anchor is the last heard word: the place at time t.
                landing = step.found!.bookWordOf(w.heard.words.length - 1);
              }
              row[name] = {...step.toJson(), ...landingRow(r, landing, truth)};
            }
            row['window'] = listen.windows.last;
            row['heard'] = w.heard.words.join(' ');
            out.writeln(jsonEncode(row));
          }
        }
    }
    await out.flush();
    stdout.writeln('$experiment $key done');
  }
  await out.close();
  whisper.close();
}

int _stableSeed(String text) => text.codeUnits.fold(17, (a, c) => (a * 31 + c) & 0x7fffffff);

/// The server experiment: recordings of the user's Jellyfin server, read
/// through speech_server.py's proxy, which passes byte ranges through. No
/// reference map exists, so a stronger reference stands in: base.en on 30 s
/// around the place, searched in the whole book, with a stricter rule.
Future<void> runServer(String work, Map<String, String> options, DynamicLibrary library, Whisper whisper,
    String model, IOSink out) async {
  final port = options['port'] ?? '8766';
  final items = {
    for (final f in (jsonDecode(await File('$work/server/private.json').readAsString()) as List))
      f['letter'] as String: f as Map<String, dynamic>,
  };
  final models = Platform.environment['BOOKFIN_WHISPER_MODELS']!;
  final reference = Whisper.open(library, '$models/ggml-base.en.bin');
  final count = int.parse(options['count'] ?? '30');
  final load = (await Process.run('sysctl', ['-n', 'vm.loadavg'])).stdout.toString().trim();
  out.writeln(jsonEncode({'event': 'start', 'experiment': 'server', 'model': model, 'loadavg': load}));
  for (final letter in (options['letters'] ?? 'B,C,E,G,A').split(',')) {
    final item = items[letter]!;
    final book = BookText.fromJson(jsonDecode(await File('$work/server/books/$letter.json').readAsString()));
    final duration = item['durationMs'] as int;
    final r = Recording(letter, book, [Section(0, 'http://127.0.0.1:$port/$letter', 0, duration, null)]);
    final listen = Listener(r, whisper);
    final strong = Listener(r, reference);
    final random = math.Random(_stableSeed('server/$letter'));
    final times = <(int, String)>[
      for (var k = 0; k < count; k++) (20000 + random.nextInt(duration - 40000), 'sample'),
      for (final c in (item['chapters'] as List))
        if ((c['name'] as String).toLowerCase().contains('credit')) ((c['startMs'] as int) + 10000, 'credits'),
    ];
    final msPerWord = duration / book.words.length;
    for (final (t, kind) in times) {
      final row = <String, Object?>{'book': letter, 'kind': kind, 'atMs': t, 'container': item['container']};
      // The reference place: base.en on 30 s around t, in the whole book.
      final w = await strong(t - 15000, 30000);
      int? truth;
      if (w != null) {
        final step = searchAround(book, w.heard, w.startMs, 0, const [double.infinity]);
        final f = step.found;
        row['reference'] = {...step.toJson(), 'window': strong.windows.last};
        if (f != null && f.matched >= 0.6 * f.heard && f.runnerUp <= 0.35 * f.matched) {
          var j = 0;
          for (var k = 0; k < w.heard.ms.length; k++) {
            if ((w.heard.ms[k] - (t - w.startMs)).abs() < (w.heard.ms[j] - (t - w.startMs)).abs()) j = k;
          }
          truth = f.bookWordOf(j);
        }
      }
      final estimate = r.shareWord(t);
      final result = await audioToText(book: book, listen: listen.call, atMs: t, estimateWord: estimate, radiiPages: wholeBookRadii);
      row['share'] = {
        'estimateError': truth == null ? null : (book.offsets[estimate] - book.offsets[truth]) / pageCharacters,
        ...?result.step?.toJson(),
        ...landingRow(r, result.word, truth),
        'window': listen.windows.last,
      };
      // A reading place into the audiobook: a sentence start that the
      // reference window heard, with the reference's time for it.
      if (truth != null && w != null) {
        final f = searchAround(book, w.heard, w.startMs, truth, const [double.infinity]).found!;
        final starts = [
          for (final (i, p) in f.pairs)
            if (p > 0 && book.sentences[p - 1] != book.sentences[p]) (i, p),
        ];
        if (starts.isNotEmpty) {
          final (i, target) = starts[random.nextInt(starts.length)];
          final truthMs = w.startMs + w.heard.ms[i];
          final before = listen.windows.length;
          final placed = await textToAudio(book: book, listen: listen.call, target: target,
              estimateMs: r.shareMs(target), msPerWord: msPerWord, radiiPages: wholeBookRadii, lengthMs: 15000);
          row['textToAudio'] = {
            'target': target,
            'truthMs': truthMs,
            'estimateErrorMs': r.shareMs(target) - truthMs,
            'landingMs': placed.ms,
            'errorMs': placed.ms - truthMs,
            'converged': placed.converged,
            'rounds': placed.steps.length,
            'steps': [for (final s in placed.steps) s.toJson()],
            'windows': listen.windows.sublist(before),
          };
        }
      }
      out.writeln(jsonEncode(row));
    }
    await out.flush();
    stdout.writeln('server $letter done');
  }
  reference.close();
}
