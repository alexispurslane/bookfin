// Throwaway Android app for ticket t0-etnk. At launch it runs the plans in
// its external files directory (pushed with adb) on a worker isolate and
// writes JSON lines to results.jsonl beside it. Each plan loads its model
// anew, so its first clause is measured with a cold model.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as so;

import 'bench.dart';

const _dir = '/storage/emulated/0/Android/data/dev.bookfin.ttsbench/files';

void main() {
  runApp(const MaterialApp(home: BenchPage()));
}

class BenchPage extends StatefulWidget {
  const BenchPage({super.key});
  @override
  State<BenchPage> createState() => _BenchPageState();
}

class _BenchPageState extends State<BenchPage> {
  String _status = 'running';

  @override
  void initState() {
    super.initState();
    _run();
  }

  static const _channel = MethodChannel('ttsbench');

  // Every 30 s, one "phone" line with Android's thermal status and headroom,
  // the battery level and current, and the charger state.
  Future<void> _sample() async {
    final m = await _channel.invokeMapMethod<String, Object?>('phone');
    final line = jsonEncode({
      'event': 'phone',
      'epochMs': DateTime.now().millisecondsSinceEpoch,
      ...?m,
    });
    await File('$_dir/results.jsonl')
        .writeAsString('$line\n', mode: FileMode.append);
  }

  Future<void> _run() async {
    await _sample();
    final timer = Timer.periodic(const Duration(seconds: 30), (_) => _sample());
    try {
      await Isolate.run(() {
        so.initBindings();
        // plan.json holds a list of plans. One launch runs them in order,
        // so the person taps the app once.
        final json = jsonDecode(File('$_dir/plan.json').readAsStringSync());
        for (final j in (json as List).cast<Map<String, dynamic>>()) {
          final plan = Plan.fromJson(j);
          try {
            runPlan(plan, File('$_dir/results.jsonl'), print);
          } catch (e, s) {
            final line = jsonEncode({
              'label': plan.label,
              'event': 'error',
              'error': '$e $s',
            });
            print('TTSBENCH $line');
            File('$_dir/results.jsonl')
                .writeAsStringSync('$line\n', mode: FileMode.append);
          }
        }
      });
      timer.cancel();
      await _sample();
      setState(() => _status = 'done');
      print('TTSBENCH {"event":"exit"}');
    } catch (e, s) {
      timer.cancel();
      final line = jsonEncode({'event': 'error', 'error': '$e $s'});
      print('TTSBENCH $line');
      File('$_dir/results.jsonl')
          .writeAsStringSync('$line\n', mode: FileMode.append);
      setState(() => _status = 'error: $e');
    }
  }

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text('ttsbench: $_status')));
}
