import 'dart:convert';
import 'dart:io';

import 'package:bookfin/catalog/jellyfin.dart';
import 'package:bookfin/catalog/store.dart';

final runtime = Directory('.cache/sync/runtime').absolute;

Map<String, dynamic> privateJson(String name) =>
    jsonDecode(File('${runtime.path}/$name').readAsStringSync())
        as Map<String, dynamic>;

Future<void> writePrivate(File file, String value) async {
  await file.create();
  final result = await Process.run('chmod', ['600', file.path]);
  if (result.exitCode != 0) {
    throw StateError('Cannot protect acceptance storage');
  }
  await file.writeAsString(value, flush: true);
}

class DiskCredentials implements CredentialStore {
  DiskCredentials(this.directory);
  final Directory directory;
  File get file => File('${directory.path}/session.json');
  @override
  Future<JellyfinSession?> read() async => await file.exists()
      ? JellyfinSession.fromJson(jsonDecode(await file.readAsString()))
      : null;
  @override
  Future<void> write(JellyfinSession? session) async {
    if (session == null) {
      if (await file.exists()) await file.delete();
    } else {
      await writePrivate(file, jsonEncode(session.toJson()));
    }
  }

  @override
  Future<String> deviceId() async => 'boo-2cgp-app-acceptance';
}

class DiskCatalog implements CatalogStore {
  DiskCatalog(this.directory);
  final Directory directory;
  File file(AccountScope scope) => File(
    '${directory.path}/catalog-${base64Url.encode(utf8.encode(scope.key))}.json',
  );
  @override
  Future<CatalogCache?> read(AccountScope scope) async =>
      await file(scope).exists()
      ? CatalogCache.decode(scope, await file(scope).readAsString())
      : null;
  @override
  Future<void> write(AccountScope scope, CatalogCache cache) async {
    if (scope.key != cache.scope.key) throw StateError('Wrong account cache');
    await writePrivate(file(scope), cache.encode());
  }
}

class HttpObservation {
  HttpObservation(this.method, this.uri);
  final String method;
  final Uri uri;
  String? range;
  String? ifRange;
  int? status;
  String? contentRange;
  String? etag;
  String? lastModified;
  Map<String, dynamic> toJson() => {
    'method': method,
    'path': uri.path,
    'query': uri.query,
    'range': range,
    'ifRange': ifRange,
    'status': status,
    'contentRange': contentRange,
    'etag': etag,
    'lastModified': lastModified,
  };
}

class ObservedClient implements HttpClient {
  ObservedClient(this.inner, this.observations);
  final HttpClient inner;
  final List<HttpObservation> observations;
  @override
  set autoUncompress(bool value) => inner.autoUncompress = value;
  @override
  set connectionTimeout(Duration? value) => inner.connectionTimeout = value;
  @override
  Future<HttpClientRequest> getUrl(Uri url) => openUrl('GET', url);
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    if (url.scheme != 'http' || url.host != '127.0.0.1' || url.port != 7364) {
      throw StateError('Acceptance refuses nonfixture HTTP requests');
    }
    final observation = HttpObservation(method, url);
    observations.add(observation);
    return ObservedRequest(await inner.openUrl(method, url), observation);
  }

  @override
  void close({bool force = false}) => inner.close(force: force);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ObservationOverrides extends HttpOverrides {
  ObservationOverrides(this.observations);
  final List<HttpObservation> observations;
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      ObservedClient(super.createHttpClient(context), observations);
}

class ObservedRequest implements HttpClientRequest {
  ObservedRequest(this.inner, this.observation);
  final HttpClientRequest inner;
  final HttpObservation observation;
  @override
  Uri get uri => inner.uri;
  @override
  HttpHeaders get headers => inner.headers;
  @override
  set followRedirects(bool value) => inner.followRedirects = value;
  @override
  void add(List<int> data) => inner.add(data);
  @override
  void write(Object? object) => inner.write(object);
  @override
  void abort([Object? exception, StackTrace? stackTrace]) =>
      inner.abort(exception, stackTrace);
  @override
  Future<HttpClientResponse> close() async {
    observation.range = headers.value('Range');
    observation.ifRange = headers.value('If-Range');
    final response = await inner.close();
    observation.status = response.statusCode;
    observation.contentRange = response.headers.value('Content-Range');
    observation.etag = response.headers.value('ETag');
    observation.lastModified = response.headers.value('Last-Modified');
    return response;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<Map<String, dynamic>> rawJson(
  Uri origin,
  String method,
  String path, {
  String? token,
  Object? body,
  int expectedStatus = 200,
}) async {
  final client = HttpClient();
  try {
    final request = await client.openUrl(method, origin.resolve(path));
    request.followRedirects = false;
    request.headers.set(
      'Authorization',
      'MediaBrowser Client="Bookfin acceptance setup", Device="Synthetic", DeviceId="boo-2cgp-setup", Version="1"${token == null ? '' : ', Token="$token"'}',
    );
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.add(utf8.encode(jsonEncode(body)));
    }
    final response = await request.close();
    final bytes = await response.fold<List<int>>(
      [],
      (bytes, chunk) => bytes..addAll(chunk),
    );
    if (response.statusCode != expectedStatus) {
      throw StateError(
        '$method ${request.uri.path}: HTTP ${response.statusCode}, expected $expectedStatus',
      );
    }
    if (response.statusCode != 200 || bytes.isEmpty) return {};
    return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  } finally {
    client.close(force: true);
  }
}
