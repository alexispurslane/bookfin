import 'dart:io';
import 'dart:convert';

import 'jellyfin.dart';
import 'transport_protocol.dart';

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
        throw const CatalogFailure(CatalogFailureKind.unavailable);
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 20))) {
        if (bytes.length + chunk.length > 16 * 1024 * 1024) {
          throw const CatalogFailure(CatalogFailureKind.invalidResponse);
        }
        bytes.addAll(chunk);
      }
      if (_closed) throw const CatalogFailure(CatalogFailureKind.cancelled);
      if (response.statusCode == 204 && bytes.isEmpty) return {};
      final value = jsonDecode(utf8.decode(bytes));
      if (value is! Map<String, dynamic>) {
        throw const CatalogFailure(CatalogFailureKind.invalidResponse);
      }
      return value;
    } on CatalogFailure {
      rethrow;
    } on FormatException {
      throw const CatalogFailure(CatalogFailureKind.invalidResponse);
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
