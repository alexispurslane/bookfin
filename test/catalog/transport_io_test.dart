import 'dart:convert';
import 'dart:io';

import 'package:bookfin/catalog/jellyfin.dart';
import 'package:bookfin/catalog/transport_io.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer server;
  late String body;
  late int status;
  setUp(() async {
    status = 200;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.statusCode = status;
      request.response.add(utf8.encode(body));
      await request.response.close();
    });
  });
  tearDown(() => server.close(force: true));

  Future<Map<String, dynamic>> send() {
    final transport = createTransport();
    addTearDown(transport.close);
    return transport.send(
      Uri.parse('http://127.0.0.1:${server.port}/Items'),
      method: 'GET',
      headers: const {},
    );
  }

  test('a small response reads as its JSON object', () async {
    body = jsonEncode({'Id': 'server', 'Name': 'Bücher'});
    expect(await send(), {'Id': 'server', 'Name': 'Bücher'});
  });

  test('a large library page reads as its JSON object', () async {
    final items = [
      for (var index = 0; index < 400; index++)
        {'Id': 'item$index', 'Name': 'Ünïcode title $index ${'x' * 200}'},
    ];
    body = jsonEncode({'Items': items, 'TotalRecordCount': 400});
    expect(utf8.encode(body).length, greaterThan(64 * 1024));
    final response = await send();
    expect(response['TotalRecordCount'], 400);
    expect(response['Items'], items);
  });

  test('a large response that is not JSON is an unreadable catalog', () async {
    body = '{"Items": [${'"x", ' * 20000}';
    await expectLater(
      send(),
      throwsA(
        isA<CatalogFailure>().having(
          (failure) => failure.kind,
          'kind',
          CatalogFailureKind.invalidResponse,
        ),
      ),
    );
  });

  test('a response that is a JSON list is an unreadable catalog', () async {
    body = '[1, 2, 3]';
    await expectLater(
      send(),
      throwsA(
        isA<CatalogFailure>().having(
          (failure) => failure.kind,
          'kind',
          CatalogFailureKind.invalidResponse,
        ),
      ),
    );
  });

  test('a server error means Jellyfin cannot be reached', () async {
    status = 503;
    body = '';
    await expectLater(
      send(),
      throwsA(
        isA<CatalogFailure>().having(
          (failure) => failure.kind,
          'kind',
          CatalogFailureKind.unavailable,
        ),
      ),
    );
  });
}
