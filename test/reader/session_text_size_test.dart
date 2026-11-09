// The reader session owns the text size and whether the reader has used
// the size buttons. Once they are used, the text size is the size of each
// book's main text, and that choice is kept with the text size.
import 'package:bookfin/playback/store.dart';
import 'package:bookfin/reader/epub/publication.dart';
import 'package:bookfin/reader/session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../playback/playback_test.dart' show account, LocalFiles, MemoryResume;
import 'publication_test.dart' show epub;
import 'session_test.dart' show book, source;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalFiles downloads;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    downloads = LocalFiles()..files[source.key] = Uri.file('/verified.epub');
  });
  tearDown(() => downloads.dispose());

  ReaderSession session(ReadingStore store) => ReaderSession(
    downloads: downloads,
    store: store,
    load: (_) async => Publication.admit(epub()),
  );

  test('before the size buttons are used, each book keeps its own type '
      'sizes', () async {
    final reader = session(MemoryResume());
    addTearDown(reader.dispose);
    await reader.bind(account(), [book]);
    expect(reader.sizesMainText, isFalse);
    expect(reader.fontSize, 20);
  });

  test('a size button makes the text size the size of the book\'s main '
      'text at once, and notifies the text size', () async {
    final reader = session(MemoryResume());
    addTearDown(reader.dispose);
    await reader.bind(account(), [book]);
    var notified = 0;
    reader.fontSizeChanges.addListener(() => notified++);
    await reader.setFontSize(18);
    expect(reader.sizesMainText, isTrue);
    expect(reader.fontSize, 18);
    expect(notified, 1);
  });

  test('the choice survives a restart', () async {
    final first = session(LocalResumeStore().reading);
    await first.bind(account(), [book]);
    await first.setFontSize(22);
    await first.flush();
    first.dispose();

    final restarted = session(LocalResumeStore().reading);
    addTearDown(restarted.dispose);
    await restarted.bind(account(), [book]);
    expect(restarted.sizesMainText, isTrue);
    expect(restarted.fontSize, 22);
  });

  test('a text size saved before the choice was kept counts as a used size '
      'button when it is not the default', () async {
    for (final (size, used) in [(24, true), (20, false)]) {
      final store = MemoryResume()
        ..values[account().scope.key] = {
          'version': 1,
          'fontSize': size,
          'resumes': [],
          'bookmarks': [],
        };
      final reader = session(store);
      await reader.bind(account(), [book]);
      expect(reader.sizesMainText, used, reason: '$size px');
      reader.dispose();
    }
  });

  test('another account starts with each book\'s own type sizes', () async {
    final store = MemoryResume();
    final reader = session(store);
    addTearDown(reader.dispose);
    await reader.bind(account(), [book]);
    await reader.setFontSize(24);
    await reader.flush();
    await reader.bind(null, const []);
    expect(reader.sizesMainText, isFalse);
    expect(reader.fontSize, 20);
  });
}
