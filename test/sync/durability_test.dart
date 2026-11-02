import 'dart:convert';

import 'package:bookfin/playback/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'saving a bookmark durably retains its upload before a restart',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = LocalResumeStore();
      await store.write('alice', {
        'version': 3,
        'resumes': <String, dynamic>{},
        'history': <dynamic>[],
        'bookmarks': [
          {'id': 'mark-a', 'title': 'Offline bookmark'},
        ],
      });
      final preferences = await SharedPreferences.getInstance();
      final saved = jsonDecode(
        preferences.getString('bookfin.playback.v1.alice')!,
      ) as Map<String, dynamic>;
      expect(
        saved['sync'],
        isA<Map<String, dynamic>>(),
        reason: 'A saved personal record must include its durable upload.',
      );
      final sync = saved['sync'] as Map<String, dynamic>;
      final actions = sync['actions'] as List;
      expect(actions, hasLength(1));
      expect((actions.single as Map)['value']['title'], 'Offline bookmark');
      expect(sync['pending'], hasLength(1));
      expect(
        await LocalResumeStore().read('alice'),
        containsPair('bookmarks', [
          {'id': 'mark-a', 'title': 'Offline bookmark'},
        ]),
      );
    },
  );
}
