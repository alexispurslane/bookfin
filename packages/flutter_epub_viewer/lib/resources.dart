import 'dart:typed_data';

import 'publication.dart';

class ResourceReply {
  const ResourceReply(this.status, this.mime, this.bytes, this.headers);
  final int status;
  final String mime;
  final Uint8List bytes;
  final Map<String, String> headers;
}

class ReaderResources {
  ReaderResources(this.publication, Map<String, Uint8List> runtime)
    : runtime = Map.unmodifiable({
        for (final entry in runtime.entries)
          entry.key: Uint8List.fromList(entry.value).asUnmodifiableView(),
      });
  final Publication publication;
  final Map<String, Uint8List> runtime;
  static final runtimeUrl = Uri.parse(
    'https://bookfin-runtime.invalid/index.html',
  );
  static const headers = {
    'Access-Control-Allow-Origin': 'https://bookfin-runtime.invalid',
    'Cache-Control': 'no-store',
    'X-Content-Type-Options': 'nosniff',
    'Referrer-Policy': 'no-referrer',
    'Permissions-Policy':
        'camera=(), microphone=(), geolocation=(), payment=(), usb=()',
  };
  ResourceReply reply(Uri url, {String method = 'GET'}) {
    ResourceReply deny() =>
        ResourceReply(403, 'text/plain', Uint8List(0), headers);
    if (method != 'GET' ||
        url.hasQuery ||
        url.hasPort ||
        url.userInfo.isNotEmpty ||
        RegExp(r'%2f|%5c|%2e', caseSensitive: false).hasMatch(url.toString())) {
      return deny();
    }
    if (url.scheme == 'https' && url.host == runtimeUrl.host) {
      if (!url.path.startsWith('/')) return deny();
      final path = url.path.substring(1);
      final mime = {
        'index.html': 'text/html',
        'epub.js': 'text/javascript',
        'reader.js': 'text/javascript',
        'SourceSerif4.ttf': 'font/ttf',
      }[path];
      final bytes = runtime[path];
      if (mime == null || bytes == null) return deny();
      return ResourceReply(200, mime, bytes, {
        ...headers,
        'Content-Security-Policy':
            "default-src 'none'; script-src 'self'; "
            "style-src 'unsafe-inline' https://bookfin-publication.invalid; connect-src 'self' https://bookfin-publication.invalid; "
            "frame-src 'self' about:; img-src data: https://bookfin-publication.invalid; "
            "font-src 'self' https://bookfin-publication.invalid; object-src 'none'; base-uri https://bookfin-publication.invalid; form-action 'none'",
      });
    }
    final path = publication.pathFor(url);
    if (path == null) return deny();
    return ResourceReply(
      200,
      publication.mediaTypes[path]!,
      publication.resources[path]!,
      {...headers, 'Content-Security-Policy': Publication.documentPolicy},
    );
  }

  bool allowsNavigation(Uri url, {required bool mainFrame}) =>
      url == runtimeUrl || (!mainFrame && url.toString() == 'about:blank');
}
