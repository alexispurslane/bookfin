import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

Future<void> main(List<String> arguments) async {
  final server = await HttpServer.bind(
    InternetAddress.loopbackIPv4,
    arguments.isEmpty ? 0 : int.parse(arguments.single),
  );
  const user = {
    'Id': 'fixture-user',
    'Name': 'Synthetic Reader',
    'Policy': {'EnableContentDownloading': true, 'IsAdministrator': false},
  };
  const lengths = {
    'fixture-audio': 6291456,
    'fixture-second': 1048576,
    'fixture-text': 6,
  };
  final transfers = <Map<String, Object>>[];
  var deny = false;
  Map<String, Object> item(String id) => {
    'Id': id,
    'Name': switch (id) {
      'fixture-audio' => 'Synthetic Transfer Audio',
      'fixture-second' => 'Synthetic Second Audio',
      _ => 'Synthetic Transfer Text',
    },
    'Type': id == 'fixture-text' ? 'Book' : 'AudioBook',
    'CanDownload': true,
    'Etag': 'synthetic-item-v1',
    'MediaSources': [
      {
        'Id': id,
        'Type': 'Default',
        'IsRemote': false,
        'ETag': 'synthetic-source-v1',
        'Size': lengths[id]!,
        'Container': id == 'fixture-text' ? 'epub' : 'm4b',
      },
    ],
  };
  stdout.writeln(
    'Synthetic transfer bytes, not playable books. No production credentials.',
  );
  stdout.writeln('http://127.0.0.1:${server.port}/jellyfin');
  await for (final request in server) {
    unawaited(() async {
      final response = request.response;
      try {
        final parts = request.uri.pathSegments;
        final path = request.uri.path;
        response.headers.contentType = ContentType.json;
        Object? data;
        if (path == '/fixture/status') {
          data = {'transfers': transfers, 'denied': deny};
        } else if (path == '/fixture/deny' || path == '/fixture/allow') {
          deny = path.endsWith('/deny');
          data = {'denied': deny};
        } else if (path.endsWith('/Users/AuthenticateByName')) {
          await request.drain<void>();
          data = {
            'User': user,
            'ServerId': 'download-fixture-server',
            'AccessToken': 'synthetic-fixture-token',
          };
        } else if (path.endsWith('/System/Info/Public')) {
          data = {'Id': 'download-fixture-server'};
        } else if (request.headers.value('X-Emby-Token') !=
            'synthetic-fixture-token') {
          response.statusCode = 401;
        } else if (path.endsWith('/Users/Me')) {
          data = user;
        } else if (path.endsWith('/UserViews')) {
          data = {
            'Items': [
              {
                'Id': 'fixture-books',
                'Name': 'Synthetic transfer fixtures',
                'CollectionType': 'books',
              },
            ],
          };
        } else if (parts.last == 'Items') {
          data = {
            'Items': lengths.keys.map(item).toList(),
            'TotalRecordCount': 3,
            'StartIndex': 0,
          };
        } else if (parts.last == 'Download' &&
            lengths.containsKey(parts[parts.length - 2])) {
          final id = parts[parts.length - 2];
          if (deny) {
            response.statusCode = 403;
          } else {
            final length = lengths[id]!;
            final match = RegExp(r'^bytes=(\d+)-$')
                .firstMatch(request.headers.value('Range') ?? '');
            final offset = match == null ? 0 : int.parse(match[1]!);
            transfers.add({'item': id, 'offset': offset});
            stdout.writeln('Media $id from byte $offset');
            if (offset >= length) {
              response.statusCode = 416;
            } else {
              response.statusCode = offset == 0 ? 200 : 206;
              response.headers.contentType = ContentType.binary;
              response.headers.set('ETag', '"synthetic-http-v1"');
              response.headers.set('Accept-Ranges', 'bytes');
              if (offset > 0) {
                response.headers.set(
                  'Content-Range',
                  'bytes $offset-${length - 1}/$length',
                );
              }
              response.contentLength = length - offset;
              response.bufferOutput = false;
              var sent = offset;
              while (sent < length) {
                final count = min(65536, length - sent);
                response.add(List<int>.filled(count, 42));
                await response.flush();
                sent += count;
                if (id != 'fixture-text') {
                  await Future<void>.delayed(const Duration(milliseconds: 150));
                }
              }
            }
          }
        } else if (parts.length >= 2 && lengths.containsKey(parts.last)) {
          data = item(parts.last);
        } else {
          response.statusCode = 404;
        }
        if (data != null) response.write(jsonEncode(data));
        await response.close();
      } catch (_) {
        try {
          await response.close();
        } catch (_) {}
      }
    }());
  }
}
