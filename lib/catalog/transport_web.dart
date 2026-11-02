import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

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
        throw const CatalogFailure(CatalogFailureKind.unavailable);
      }
      final text = (await response.text().toDart).toDart;
      if (_closed) throw const CatalogFailure(CatalogFailureKind.cancelled);
      if (response.status == 204 && text.isEmpty) return {};
      if (text.length > 16 * 1024 * 1024) {
        throw const CatalogFailure(CatalogFailureKind.invalidResponse);
      }
      final value = jsonDecode(text);
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
