import 'package:bookfin/playback/store.dart';
import 'package:bookfin/playback/playback.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../playback/playback_test.dart'
    show account, title, recording, LocalFiles, TestEngine;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'reading before the first listen does not prevent audio resume persistence',
    () async {
      SharedPreferences.setMockInitialValues({});
      final records = LocalResumeStore();
      final key = account().scope.key;
      final reading = <String, dynamic>{
        'version': 1,
        'fontSize': 22,
        'resumes': [],
        'bookmarks': [],
      };
      await records.reading.write(key, reading);
      final downloads = LocalFiles();
      final playback = Playback(
        downloads: downloads,
        engine: TestEngine(),
        store: records,
      );
      await playback.bind(account(), [title]);
      expect(playback.message, isNull);
      await playback.open(title, recording);
      await playback.jump(forward: true);
      await playback.close();
      final restarted = Playback(
        downloads: downloads,
        engine: TestEngine(),
        store: LocalResumeStore(),
      );
      await restarted.bind(account(), [title]);
      expect(restarted.editionMilliseconds, 30000);
      expect(await records.reading.read(key), {
        ...reading,
        'history': <dynamic>[],
      });
      await restarted.close();
      downloads.dispose();
    },
  );
  test('audio and text records share account persistence without overwriting each other', () async {
    SharedPreferences.setMockInitialValues({});
    final records = LocalResumeStore();
    await Future.wait([
      records.write('account', {
        'version': 3,
        'resumes': {
          'audio': [
            {'source': 'file-a', 'revision': 'v1', 'milliseconds': 123},
          ],
        },
      }),
      records.reading.write('account', {
        'version': 1,
        'resumes': [
          {
            'edition': 'text',
            'source': 'file-t',
            'revision': 'v1',
            'anchor': 'anchor',
          },
        ],
      }),
    ]);
    final restarted = LocalResumeStore();
    expect((await restarted.read('account'))!['resumes'], {
      'audio': [
        {'source': 'file-a', 'revision': 'v1', 'milliseconds': 123},
      ],
    });
    expect((await restarted.reading.read('account'))!['resumes'], [
      {
        'edition': 'text',
        'source': 'file-t',
        'revision': 'v1',
        'anchor': 'anchor',
      },
    ]);
    expect(await restarted.reading.read('other account'), isNull);
  });
}
