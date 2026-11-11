// Tool code for the boo-snng speech prototype, not part of Bookfin.
// The Android harness. At launch it runs the jobs of plan.json in its
// external files directory (pushed with adb): it decodes each window with
// Android's decoder on a Kotlin thread, then transcribes and searches it in
// one long-lived worker isolate, and appends one JSON line per job to
// results.jsonl beside the plan.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'place.dart';
import 'text.dart';
import 'whisper.dart';

const _dir = '/storage/emulated/0/Android/data/dev.bookfin.speech_probe/files';
const _channel = MethodChannel('speech_probe');

void main() => runApp(const MaterialApp(home: ProbePage()));

class ProbePage extends StatefulWidget {
  const ProbePage({super.key});
  @override
  State<ProbePage> createState() => _ProbePageState();
}

class _ProbePageState extends State<ProbePage> {
  final _status = ValueNotifier('starting');

  @override
  void initState() {
    super.initState();
    unawaited(_run().catchError((Object error, StackTrace stack) {
      _status.value = 'failed: $error';
      debugPrint('SPEECHPROBE failed $error $stack');
    }));
  }

  Future<void> _write(Map<String, Object?> row) async {
    final line = jsonEncode(row);
    debugPrint('SPEECHPROBE $line');
    await File('$_dir/results.jsonl').writeAsString('$line\n', mode: FileMode.append);
  }

  Future<void> _run() async {
    final plan = jsonDecode(await File('$_dir/plan.json').readAsString()) as Map<String, dynamic>;
    final jobs = (plan['jobs'] as List).cast<Map<String, dynamic>>();
    final replies = ReceivePort();
    _status.value = 'starting the worker for ${jobs.length} jobs';
    // A worker that fails reports its error as a list, in place of a reply.
    await Isolate.spawn(_worker, replies.sendPort, onError: replies.sendPort);
    final inbox = StreamIterator(replies);
    await inbox.moveNext();
    if (inbox.current is List) throw StateError('worker failed: ${inbox.current}');
    final worker = inbox.current as SendPort;
    Future<Map<String, Object?>> ask(Map<String, Object?> message) async {
      worker.send(message);
      await inbox.moveNext();
      if (inbox.current is List) throw StateError('worker failed: ${inbox.current}');
      return (inbox.current as Map).cast<String, Object?>();
    }

    await _write({'event': 'start', 'jobs': jobs.length, 'at': DateTime.now().toIso8601String()});
    for (final (index, job) in jobs.indexed) {
      _status.value = 'job ${index + 1} of ${jobs.length}';
      try {
        final source = job['source'] as String;
        final decoded = (await _channel.invokeMapMethod<String, Object?>('decode', {
          'source': source.startsWith('http') ? source : '$_dir/$source',
          'startMs': job['startMs'],
          'lengthMs': job['lengthMs'],
        }))!;
        final pcm = decoded.remove('pcm') as Uint8List;
        final result = await ask({
          ...job,
          'dir': _dir,
          'pcm': TransferableTypedData.fromList([pcm]),
        });
        await _write({...job, 'decode': decoded, ...result});
      } catch (error, stack) {
        await _write({...job, 'error': '$error $stack'});
      }
    }
    await _write({'event': 'done', 'at': DateTime.now().toIso8601String()});
    _status.value = 'done';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ValueListenableBuilder(
        valueListenable: _status,
        builder: (context, status, _) => Text('speech_probe: $status'),
      ),
    ),
  );
}

/// The worker isolate: it keeps one whisper model and the books it read,
/// and answers each job with the transcription and the search.
Future<void> _worker(SendPort replies) async {
  final inbox = ReceivePort();
  replies.send(inbox.sendPort);
  final library = openProbe();
  Whisper? whisper;
  String? model;
  final books = <String, BookText>{};
  await for (final message in inbox) {
    final job = (message as Map).cast<String, Object?>();
    final dir = job['dir'] as String;
    final out = <String, Object?>{};
    if (job['model'] != model) {
      whisper?.close();
      final watch = Stopwatch()..start();
      whisper = Whisper.open(library, '$dir/models/ggml-${job['model']}.bin');
      model = job['model'] as String;
      out['modelLoadMs'] = watch.elapsedMilliseconds;
    }
    final key = job['book'] as String;
    if (!books.containsKey(key)) {
      final watch = Stopwatch()..start();
      final book = BookText.fromJson(jsonDecode(await File('$dir/books/$key.json').readAsString()));
      out['bookParseMs'] = watch.elapsedMilliseconds;
      watch.reset();
      book.positions.length;
      out['bookIndexMs'] = watch.elapsedMilliseconds;
      books[key] = book;
    }
    final book = books[key]!;
    final bytes = (job['pcm'] as TransferableTypedData).materialize();
    final pcm = bytes.asFloat32List(0, bytes.lengthInBytes ~/ 4);
    final cpu0 = cpuMs(library);
    final watch = Stopwatch()..start();
    final heard = whisper!.transcribe(pcm, threads: job['threads'] as int, audioCtx: job['ctx'] as int);
    out['transcribeMs'] = watch.elapsedMilliseconds;
    out['transcribeCpuMs'] = cpuMs(library) - cpu0;
    out['heard'] = heard.words.join(' ');
    out['samples'] = pcm.length;
    final radii = [for (final r in job['radii'] as List) (r as num) < 0 ? double.infinity : r.toDouble()];
    final step = searchAround(book, heard, job['startMs'] as int, job['around'] as int, radii);
    out['search'] = step.toJson();
    if (step.confident && heard.words.isNotEmpty) {
      final target = job['atOffsetMs'] as int;
      var j = 0;
      for (var k = 0; k < heard.ms.length; k++) {
        if ((heard.ms[k] - target).abs() < (heard.ms[j] - target).abs()) j = k;
      }
      out['landing'] = step.found!.bookWordOf(j);
    }
    replies.send(out);
  }
}
