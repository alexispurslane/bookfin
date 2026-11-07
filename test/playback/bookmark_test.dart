import 'package:bookfin/playback/playback.dart';
import 'package:flutter_test/flutter_test.dart';

import 'playback_test.dart'
    show LocalFiles, TestEngine, MemoryResume, account, title, recording;

void main() {
  late LocalFiles downloads;
  late Playback playback;
  setUp(() async {
    downloads = LocalFiles();
    playback = Playback(
      downloads: downloads,
      engine: TestEngine(),
      store: MemoryResume(),
    );
    await playback.bind(account(), [title]);
    await playback.open(title, recording, autoplay: false);
  });
  tearDown(() async {
    await playback.close();
    downloads.dispose();
  });

  test(
    'a bookmark in the second file sits after the whole first file',
    () async {
      await playback.seekEdition(75000);
      await playback.addBookmark();
      expect(playback.editionTime(playback.bookmarks.single.position), 75000);
    },
  );

  test('the place counts as bookmarked shortly after a bookmark', () async {
    await playback.seekEdition(20000);
    await playback.addBookmark();
    await playback.seekEdition(30000);
    expect(playback.bookmarkHere?.id, playback.bookmarks.single.id);
  });

  test('the place is not bookmarked well after or before a bookmark', () async {
    await playback.seekEdition(20000);
    await playback.addBookmark();
    await playback.seekEdition(40000);
    expect(playback.bookmarkHere, isNull);
    await playback.seekEdition(10000);
    expect(playback.bookmarkHere, isNull);
  });
}
