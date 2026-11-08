import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bookfin/catalog/jellyfin.dart';
import 'package:bookfin/catalog/transport_io.dart';
import 'package:bookfin/catalog/transport_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer server;
  late String body;
  late int status;

  /// Holds each response until it completes, when a test sets it.
  Completer<void>? hold;
  late Completer<void> received;
  setUp(() async {
    status = 200;
    hold = null;
    received = Completer();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      if (!received.isCompleted) received.complete();
      await hold?.future;
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

  Future<Uint8List> fetchBody([JsonTransport? transport]) {
    final used = transport ?? createTransport();
    if (transport == null) addTearDown(used.close);
    return used.fetchBody(
      Uri.parse('http://127.0.0.1:${server.port}/Items'),
      method: 'GET',
      headers: const {},
    );
  }

  Matcher failsWith(CatalogFailureKind kind) => throwsA(
    isA<CatalogFailure>().having((failure) => failure.kind, 'kind', kind),
  );

  test('a body request returns the bytes that the server sent', () async {
    body = jsonEncode({
      'Items': [
        for (var index = 0; index < 400; index++)
          {'Id': 'item$index', 'Name': 'Ünïcode title $index ${'x' * 200}'},
      ],
      'TotalRecordCount': 400,
    });
    expect(await fetchBody(), utf8.encode(body));
  });

  test('a body request does not judge what the body holds', () async {
    body = '[1, 2, 3';
    expect(await fetchBody(), utf8.encode(body));
  });

  test('a body request follows the status rules of a JSON request', () async {
    body = 'password=never-display';
    for (final (code, kind) in [
      (401, CatalogFailureKind.unauthorized),
      (403, CatalogFailureKind.forbidden),
      (302, CatalogFailureKind.unavailable),
      (503, CatalogFailureKind.unavailable),
    ]) {
      status = code;
      await expectLater(fetchBody(), failsWith(kind), reason: '$code');
    }
  });

  test('a body over 16 MiB is an unreadable catalog', () async {
    body = 'x' * (16 * 1024 * 1024 + 1);
    await expectLater(
      fetchBody(),
      failsWith(CatalogFailureKind.invalidResponse),
    );
  });

  test('closing the transport cancels a body request in flight', () async {
    hold = Completer();
    body = '{}';
    final transport = createTransport();
    final fetching = fetchBody(transport);
    await received.future;
    transport.close();
    await expectLater(fetching, failsWith(CatalogFailureKind.cancelled));
    hold!.complete();
  });

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
