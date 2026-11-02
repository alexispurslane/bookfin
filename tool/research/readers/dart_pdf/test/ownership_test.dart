@Timeout(Duration(seconds: 60))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'independent worker initialization is a native crash, not PDF rejection',
    () async {
      final result = await runProbe('separate-workers');
      expect(result.exitCode, anyOf(-6, 134), reason: result.output);
      expect(
        result.output,
        contains('Cannot invoke native callback from a different isolate.'),
      );
      expect(result.output, contains('FPDF_LoadPage'));
    },
  );

  group('One application isolate owns the PDF worker lifecycle', () {
    late Map<String, dynamic> report;
    setUpAll(() async {
      final result = await runProbe('shared-worker');
      expect(result.exitCode, 0, reason: result.output);
      report = jsonDecode(
        result.standardOutput.trim().split('\n').last,
      ) as Map<String, dynamic>;
    });

    test('multiple document callers use one callback-owning PDF worker', () {
      expect(report['callers'], 3);
      expect(report['documents_open_before_reading'], 3);
      expect(report['same_worker'], isTrue);
      expect(report['texts'], everyElement(contains('old road')));
      expect(report['render_widths'], [120, 120, 120]);
      expect(report['visible_renders'], [true, true, true]);
      expect(
        report['font_callback_faces'],
        containsAll(['Helvetica', 'Helvetica-Bold']),
      );
    });

    test(
      'closing and reopening documents retains the same font callback owner',
      () {
        expect(report['reopened_texts'], [
          contains('old road'),
          contains('old road'),
        ]);
        expect(report['reopen_same_worker'], isTrue);
        expect(report['document_close_callbacks'], 2);
      },
    );

    test(
      'a failed document caller releases its document before later work',
      () {
        expect(report['caller_failure_propagated'], isTrue);
        expect(report['failed_document_close_callbacks'], 1);
        expect(report['after_failure_text'], contains('old road'));
        expect(report['malformed_document_rejected'], isTrue);
      },
    );

    test(
      'released documents permit worker shutdown and a fresh callback owner',
      () {
        expect(report['worker_exit_events'], [
          'PdfrxEngineWorker',
          'PdfrxEngineWorker',
        ]);
        expect(report['restart_has_new_worker'], isTrue);
        expect(report['restart_text'], contains('old road'));
        expect(report['restart_render_visible'], isTrue);
        expect(report['dart_font_mapper_enabled'], isTrue);
        expect(
          report['restart_font_callback_faces'],
          containsAll(['Helvetica', 'Helvetica-Bold']),
        );
      },
    );
  });
}

Future<({int exitCode, String output, String standardOutput})> runProbe(
  String scenario,
) async {
  final process = await Process.start(Platform.resolvedExecutable, [
    'run',
    'test/support/ownership_probe.dart',
    scenario,
  ]);
  final output = process.stdout.transform(utf8.decoder).join();
  final errors = process.stderr.transform(utf8.decoder).join();
  var timedOut = false;
  final exitCode = await process.exitCode.timeout(
    const Duration(seconds: 45),
    onTimeout: () async {
      timedOut = true;
      process.kill(ProcessSignal.sigkill);
      return await process.exitCode;
    },
  );
  final standardOutput = await output;
  final combined = '$standardOutput${await errors}';
  final evidence = Directory('../_out/ownership')..createSync(recursive: true);
  File('${evidence.path}/$scenario.txt')
      .writeAsStringSync('exit_code=$exitCode\ntimed_out=$timedOut\n$combined');
  expect(timedOut, isFalse, reason: combined);
  return (exitCode: exitCode, output: combined, standardOutput: standardOutput);
}
