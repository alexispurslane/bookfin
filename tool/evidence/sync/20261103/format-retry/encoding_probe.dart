import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  final capture = jsonDecode(
    await File(
      'tool/evidence/reader/formats/20261103/android-corrected/downloads-removed.json',
    ).readAsString(),
  ) as Map;
  final rows = (capture['tables']['record_actions'] as List).cast<Map>();
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  var received = 0;
  server.listen((request) async {
    received++;
    await request.drain<void>();
    await request.response.close();
  });
  final client = HttpClient();
  try {
    for (var sequence = 1; sequence <= 10; sequence++) {
      final row = rows.singleWhere(
        (row) => row['payload']['sequence'] == sequence,
      );
      final payload = jsonEncode(row['payload']);
      final request = await client.openUrl(
        'PUT',
        Uri.parse(
          'http://127.0.0.1:${server.port}/BookfinStorage/v1/objects/${row['identity']}',
        ),
      );
      request.headers.set('Content-Type', 'application/json');
      stdout.writeln(
        'sequence=$sequence pending=${row['pending']} encoding=${request.encoding.name} utf8Bytes=${utf8.encode(payload).length}',
      );
      try {
        request.write(jsonEncode({'Payload': payload}));
        final response = await request.close();
        await response.drain<void>();
        stdout.writeln('sequence=$sequence HTTP=${response.statusCode}');
      } on ArgumentError catch (error, stack) {
        stdout.writeln(
          'sequence=$sequence error=${error.runtimeType} name=${error.name} message=${error.message}',
        );
        stdout.writeln(stack);
        request.abort();
        break;
      }
    }
    stdout.writeln('HTTP requests received=$received');
  } finally {
    client.close(force: true);
    await server.close(force: true);
  }
}
