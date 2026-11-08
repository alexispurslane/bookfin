import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'jellyfin.dart';
import 'transport_protocol.dart';

/// The smallest response, in bytes, that decodes in another isolate.
/// Measured in AOT: a hop costs about 35 µs, and 15 KB of Jellyfin JSON
/// decodes in about 70 µs, so a hop pays from about 8 KB. A library page of
/// 200 items is about 370 KB and decodes in about 1.8 ms.
const _hopBytes = 8 * 1024;

Object? _decode(Uint8List bytes) => jsonDecode(utf8.decode(bytes));

JsonTransport createTransport() => _IoTransport();

class _IoTransport implements JsonTransport {
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15);
  bool _closed = false;
  @override
  Future<Map<String, dynamic>> send(
    Uri uri, {
    required String method,
    required Map<String, String> headers,
    Map<String, dynamic>? body,
  }) async {
    final (:status, :bytes) = await _receive(uri, method, headers, body);
    if (status == 204 && bytes.isEmpty) return {};
    try {
      // A typed byte list crosses to the other isolate as one block copy,
      // and the decoded value comes back without a copy.
      final value = bytes.length < _hopBytes
          ? _decode(bytes)
          : await compute(_decode, bytes);
      if (_closed) throw const CatalogFailure(CatalogFailureKind.cancelled);
      if (value is! Map<String, dynamic>) {
        throw const CatalogFailure(CatalogFailureKind.invalidResponse);
      }
      return value;
    } on CatalogFailure {
      rethrow;
    } catch (_) {
      throw CatalogFailure(
        _closed
            ? CatalogFailureKind.cancelled
            : CatalogFailureKind.invalidResponse,
      );
    }
  }

  @override
  Future<Uint8List> fetchBody(
    Uri uri, {
    required String method,
    required Map<String, String> headers,
    Map<String, dynamic>? body,
  }) async => (await _receive(uri, method, headers, body)).bytes;

  /// Sends a request and returns its status and its body.
  Future<({int status, Uint8List bytes})> _receive(
    Uri uri,
    String method,
    Map<String, String> headers,
    Map<String, dynamic>? body,
  ) async {
    if (_closed) throw const CatalogFailure(CatalogFailureKind.cancelled);
    try {
      final request = await _client
          .openUrl(method, uri)
          .timeout(const Duration(seconds: 20));
      request.followRedirects = false;
      headers.forEach(request.headers.set);
      if (body != null) request.add(utf8.encode(jsonEncode(body)));
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      if (response.statusCode == 401) {
        throw const CatalogFailure(CatalogFailureKind.unauthorized);
      }
      if (response.statusCode == 403) {
        throw const CatalogFailure(CatalogFailureKind.forbidden);
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw CatalogFailure(
          CatalogFailureKind.unavailable,
          status: response.statusCode,
        );
      }
      final received = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(const Duration(seconds: 20))) {
        if (received.length + chunk.length > 16 * 1024 * 1024) {
          throw const CatalogFailure(CatalogFailureKind.invalidResponse);
        }
        received.add(chunk);
      }
      if (_closed) throw const CatalogFailure(CatalogFailureKind.cancelled);
      return (status: response.statusCode, bytes: received.takeBytes());
    } on CatalogFailure {
      rethrow;
    } catch (_) {
      throw CatalogFailure(
        _closed ? CatalogFailureKind.cancelled : CatalogFailureKind.unavailable,
      );
    }
  }

  @override
  void close() {
    _closed = true;
    _client.close(force: true);
  }
}
