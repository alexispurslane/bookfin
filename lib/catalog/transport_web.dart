import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'jellyfin.dart';
import 'transport_protocol.dart';

JsonTransport createTransport() => _WebTransport();

class _WebTransport implements JsonTransport {
  final _active = <web.AbortController>{};
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
      // A web build has no other isolate: compute runs its work here, so the
      // response decodes here too.
      final value = jsonDecode(utf8.decode(bytes));
      if (value is! Map<String, dynamic>) {
        throw const CatalogFailure(CatalogFailureKind.invalidResponse);
      }
      return value;
    } on CatalogFailure {
      rethrow;
    } catch (_) {
      throw const CatalogFailure(CatalogFailureKind.invalidResponse);
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
    final controller = web.AbortController();
    _active.add(controller);
    final timeout = Timer(
      const Duration(seconds: 25),
      () => controller.abort(),
    );
    try {
      final requestHeaders = web.Headers();
      headers.forEach((name, value) => requestHeaders.set(name, value));
      final response = await web.window
          .fetch(
            uri.toString().toJS,
            web.RequestInit(
              method: method,
              headers: requestHeaders,
              body: body == null ? null : jsonEncode(body).toJS,
              redirect: 'error',
              credentials: 'omit',
              referrerPolicy: 'no-referrer',
              cache: 'no-store',
              signal: controller.signal,
            ),
          )
          .toDart;
      if (response.status == 401) {
        throw const CatalogFailure(CatalogFailureKind.unauthorized);
      }
      if (response.status == 403) {
        throw const CatalogFailure(CatalogFailureKind.forbidden);
      }
      if (!response.ok) {
        throw CatalogFailure(
          CatalogFailureKind.unavailable,
          status: response.status,
        );
      }
      final bytes = (await response.arrayBuffer().toDart).toDart.asUint8List();
      if (_closed) throw const CatalogFailure(CatalogFailureKind.cancelled);
      if (bytes.length > 16 * 1024 * 1024) {
        throw const CatalogFailure(CatalogFailureKind.invalidResponse);
      }
      return (status: response.status, bytes: bytes);
    } on CatalogFailure {
      rethrow;
    } catch (_) {
      throw CatalogFailure(
        _closed ? CatalogFailureKind.cancelled : CatalogFailureKind.unavailable,
      );
    } finally {
      timeout.cancel();
      _active.remove(controller);
    }
  }

  @override
  void close() {
    _closed = true;
    for (final controller in _active) {
      controller.abort();
    }
    _active.clear();
  }
}
