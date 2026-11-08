import 'dart:typed_data';

abstract interface class JsonTransport {
  /// Sends a request and returns its response, a JSON object.
  Future<Map<String, dynamic>> send(
    Uri uri, {
    required String method,
    required Map<String, String> headers,
    Map<String, dynamic>? body,
  });

  /// Sends a request and returns its response body as the server sent it,
  /// not decoded, so that another isolate can decode it. The status, size,
  /// timeout and cancellation rules of [send] apply.
  Future<Uint8List> fetchBody(
    Uri uri, {
    required String method,
    required Map<String, String> headers,
    Map<String, dynamic>? body,
  });

  void close();
}
