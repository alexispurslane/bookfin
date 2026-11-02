import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

Future<void> main(List<String> arguments) async {
  final server = await HttpServer.bind(
    InternetAddress.loopbackIPv4,
    arguments.isEmpty ? 0 : int.parse(arguments.single),
  );
  final audio = {'journey-one': _wave(90, 440), 'journey-two': _wave(120, 660)};
  final reports = <Map<String, dynamic>>[];
  final downloads = <Map<String, dynamic>>[];
  const token = 'synthetic-playback-token';
  const user = {
    'Id': 'playback-user',
    'Name': 'Synthetic Listener',
    'Policy': {'EnableContentDownloading': true, 'IsAdministrator': false},
  };
  Map<String, dynamic> item(String id) => {
    'Id': id,
    'Name': id == 'journey-one'
        ? 'Synthetic Journey · Part one'
        : 'Synthetic Journey · Part two',
    'Type': 'AudioBook',
    'CanDownload': true,
    'Etag': 'playable-wave-v1',
    'People': [
      {'Name': 'Bookfin Fixture', 'Type': 'Author'},
    ],
    'RunTimeTicks': (id == 'journey-one' ? 90 : 120) * 10000000,
    'Chapters': [
      for (final seconds in [0, 30, 60])
        {
          'Name':
              '${id == 'journey-one' ? 'Departure' : 'Return'} ${seconds ~/ 30 + 1}',
          'StartPositionTicks': seconds * 10000000,
        },
    ],
    'MediaSources': [
      {
        'Id': '$id-source',
        'Type': 'Default',
        'IsRemote': false,
        'ETag': 'wave-v1',
        'Size': audio[id]!.length,
        'Container': 'wav',
        'RunTimeTicks': (id == 'journey-one' ? 90 : 120) * 10000000,
      },
    ],
  };
  stdout.writeln(
    'Disposable playable multi-file fixture; no production requests.',
  );
  stdout.writeln('http://127.0.0.1:${server.port}/jellyfin');
  await for (final request in server) {
    unawaited(() async {
      final response = request.response;
      try {
        final path = request.uri.path;
        final parts = request.uri.pathSegments;
        Object? data;
        if (path == '/fixture/status') {
          data = {'downloads': downloads, 'reports': reports};
        } else if (path.endsWith('/Users/AuthenticateByName')) {
          await request.drain<void>();
          data = {
            'User': user,
            'ServerId': 'playable-disposable-server',
            'AccessToken': token,
          };
        } else if (path.endsWith('/System/Info/Public')) {
          data = {'Id': 'playable-disposable-server'};
        } else if (request.headers.value('X-Emby-Token') != token) {
          response.statusCode = 401;
        } else if (path.endsWith('/Users/Me')) {
          data = user;
        } else if (path.endsWith('/UserViews')) {
          data = {
            'Items': [
              {
                'Id': 'playable-books',
                'Name': 'Playable synthetic books',
                'CollectionType': 'books',
              },
            ],
          };
        } else if (parts.last == 'Items') {
          data = {
            'Items': audio.keys.map(item).toList(),
            'TotalRecordCount': audio.length,
            'StartIndex': 0,
          };
        } else if (parts.length >= 2 &&
            parts[parts.length - 2] == 'Items' &&
            audio.containsKey(parts.last)) {
          data = item(parts.last);
        } else if (path.contains('/Sessions/Playing')) {
          final payload = jsonDecode(
            await utf8.decoder.bind(request).join(),
          ) as Map<String, dynamic>;
          reports.add({'path': path, 'body': payload});
          stdout.writeln(
            'Playback ${parts.last}: ${payload['ItemId']} @ ${payload['PositionTicks']}',
          );
          response.statusCode = 204;
        } else if (parts.last == 'Download' &&
            audio.containsKey(parts[parts.length - 2])) {
          final id = parts[parts.length - 2];
          final bytes = audio[id]!;
          final match = RegExp(r'^bytes=(\d+)-$')
              .firstMatch(request.headers.value('Range') ?? '');
          final offset = match == null ? 0 : int.parse(match[1]!);
          downloads.add({'item': id, 'offset': offset});
          stdout.writeln('Download $id from $offset');
          if (offset >= bytes.length) {
            response.statusCode = 416;
          } else {
            response.statusCode = offset == 0 ? 200 : 206;
            response.headers.contentType = ContentType('audio', 'wav');
            response.headers.set('ETag', '"$id-wave-v1"');
            response.headers.set('Accept-Ranges', 'bytes');
            if (offset > 0) {
              response.headers.set(
                'Content-Range',
                'bytes $offset-${bytes.length - 1}/${bytes.length}',
              );
            }
            response.contentLength = bytes.length - offset;
            response.add(bytes.sublist(offset));
          }
        } else {
          response.statusCode = 404;
        }
        if (data != null) {
          response.headers.contentType = ContentType.json;
          response.write(jsonEncode(data));
        }
      } catch (_) {
        response.statusCode = 500;
      } finally {
        await response.close();
      }
    }());
  }
}

Uint8List _wave(int seconds, int frequency) {
  const rate = 22050;
  final length = seconds * rate * 2;
  final bytes = Uint8List(44 + length);
  final header = ByteData.sublistView(bytes);
  void text(int offset, String value) =>
      bytes.setRange(offset, offset + value.length, ascii.encode(value));
  text(0, 'RIFF');
  header.setUint32(4, length + 36, Endian.little);
  text(8, 'WAVE');
  text(12, 'fmt ');
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little);
  header.setUint16(22, 1, Endian.little);
  header.setUint32(24, rate, Endian.little);
  header.setUint32(28, rate * 2, Endian.little);
  header.setUint16(32, 2, Endian.little);
  header.setUint16(34, 16, Endian.little);
  text(36, 'data');
  header.setUint32(40, length, Endian.little);
  for (var sample = 0; sample < seconds * rate; sample++) {
    final tone = sample % rate < rate ~/ 3
        ? (sin(2 * pi * frequency * sample / rate) * 2400).round()
        : 0;
    header.setInt16(44 + sample * 2, tone, Endian.little);
  }
  return bytes;
}
