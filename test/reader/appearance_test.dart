import 'dart:async';

import 'package:bookfin/appearance/appearance.dart';
import 'package:bookfin/appearance/preferences.dart';
import 'package:bookfin/foundation/theme.dart';
import 'package:bookfin/reader/document.dart';
import 'package:bookfin/reader/epub/dom.dart' show EpubPlace;
import 'package:bookfin/reader/epub/pager.dart';
import 'package:bookfin/reader/screen.dart';
import 'package:bookfin/reader/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback/playback_test.dart' show account, LocalFiles, MemoryResume;
import '../appearance/preferences_test.dart' show MemoryAppearanceStore;
import 'epub/helpers.dart' show loadReaderFont;
import 'native_reader.dart';
import 'session_test.dart' show source, edition, book;
import 'reader_settings.dart';

Widget readerApp({
  required ReaderSession reader,
  required AppearanceController appearance,
  TransitionBuilder? builder,
}) => ListenableBuilder(
  listenable: appearance,
  builder: (context, _) => MaterialApp(
    theme: bookfinTheme(
      resolveAppearance(
        appearance.settings,
        DateTime.utc(2026, 11, 2),
        Brightness.light,
      ).brightness,
    ),
    builder: builder,
    home: ReaderScreen(
      reader: reader,
      onNightChanged: (night) => unawaited(
        appearance.selectMode(
          night ? AppearanceMode.night : AppearanceMode.day,
        ),
      ),
    ),
  ),
);

void main() {
  setUpAll(loadReaderFont);

  /// Whether [shown] is laid out at [fontSize] pixels, in night or cream.
  bool laidOut(ShownPage shown, double fontSize, bool night) =>
      shown.page.settings.fontSize == fontSize &&
      shown.page.settings.night == night;

  /// Whether [shown] shows [place]: the place is from its first place to
  /// its last.
  bool holds(ShownPage shown, EpubPlace place) =>
      shown.page.startPlace!.compareTo(place) <= 0 &&
      (shown.page.endPlace ?? shown.page.startPlace!).compareTo(place) >= 0;

  /// A reader session of the test account over [twoChapterBook].
  (ReaderSession, LocalFiles) session() {
    final downloads = LocalFiles()
      ..files[source.key] = Uri.file('/verified.epub');
    final publication = twoChapterBook();
    final reader = ReaderSession(
      downloads: downloads,
      store: MemoryResume(),
      load: (_) async => publication,
    );
    return (reader, downloads);
  }

  testWidgets('a text size change while the book opens shows the first page '
      'at the new size, at the book\'s start', (tester) async {
    final (reader, downloads) = session();
    await reader.bind(account(), [book]);
    await reader.open(book, edition);
    final appearance = AppearanceController(MemoryAppearanceStore());
    addTearDown(appearance.dispose);
    await tester.pumpWidget(
      readerApp(
        reader: reader,
        appearance: appearance,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
      ),
    );
    await chooseSetting(tester, 'Larger text', settle: tester.pump);
    final shown = await waitForPage(
      tester,
      reader,
      (shown) => laidOut(shown, 44, false),
    );
    expect(shown.page.section, 0);
    expect(shown.page.start.item, 0, reason: 'The book opens at its start.');
    expect(reader.fontSize, 22);
    await tester.pumpWidget(const SizedBox());
    reader.dispose();
    await finishReader(tester, reader.flush());
    downloads.dispose();
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('a size button lays the page out with the book\'s main text at '
      'the reader\'s text size', (tester) async {
    final (reader, downloads) = session();
    await reader.bind(account(), [book]);
    await reader.open(book, edition);
    final appearance = AppearanceController(MemoryAppearanceStore());
    addTearDown(appearance.dispose);
    await tester.pumpWidget(readerApp(reader: reader, appearance: appearance));
    final own = await waitForPage(
      tester,
      reader,
      (shown) => laidOut(shown, 20, false),
    );
    expect(own.page.settings.sizesMainText, isFalse);
    await chooseSetting(tester, 'Smaller text');
    final chosen = await waitForPage(
      tester,
      reader,
      (shown) => laidOut(shown, 18, false),
    );
    expect(chosen.page.settings.sizesMainText, isTrue);
    await tester.pumpWidget(const SizedBox());
    reader.dispose();
    await finishReader(tester, reader.flush());
    downloads.dispose();
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('text size, theme and the system text scale reach the page and '
      'keep the reading place, also after the book opens again', (
    tester,
  ) async {
    final (reader, downloads) = session();
    await reader.bind(account(), [book]);
    await reader.open(book, edition);
    final scale = ValueNotifier<double>(2);
    final appearance = AppearanceController(MemoryAppearanceStore());
    addTearDown(appearance.dispose);
    await tester.pumpWidget(
      readerApp(
        reader: reader,
        appearance: appearance,
        builder: (context, child) => ValueListenableBuilder<double>(
          valueListenable: scale,
          builder: (context, value, _) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(value)),
            child: child!,
          ),
        ),
      ),
    );
    final first = await waitForPage(
      tester,
      reader,
      (shown) => laidOut(shown, 40, false),
    );
    expect(reader.ready, isTrue);
    await finishReader(tester, reader.move(true));
    final turned = await waitForPage(
      tester,
      reader,
      (shown) => !identical(shown.page, first.page),
    );
    await settleReader(tester, () => reader.position != null);
    final address = reader.visibleAddress;
    final anchor = reader.position!.anchor;
    final place = turned.page.startPlace;

    for (final (change, fontSize, night) in [
      (() => chooseSetting(tester, 'Larger text'), 44.0, false),
      (() => chooseSetting(tester, 'Night reading theme'), 44.0, true),
      (
        () async {
          scale.value = 1.5;
          await tester.pump();
        },
        33.0,
        true,
      ),
    ]) {
      await change();
      final shown = await waitForPage(
        tester,
        reader,
        (shown) => laidOut(shown, fontSize, night),
      );
      expect(
        holds(shown, place!),
        isTrue,
        reason: 'The page at $fontSize px still holds the place.',
      );
      expect(reader.visibleAddress, same(address));
      expect(reader.position!.anchor, anchor);
    }
    expect(reader.fontSize, 22);

    await reader.open(book, edition);
    final reopened = await waitForPage(
      tester,
      reader,
      (shown) => laidOut(shown, 33, true),
    );
    await settleReader(tester, () => reader.visibleAddress != null);
    expect(holds(reopened, place!), isTrue);
    expect(
      (reader.initialAddress! as EpubAddress).location.cfi,
      (address! as EpubAddress).location.cfi,
    );
    expect(reader.position!.anchor, anchor);
    await tester.pumpWidget(const SizedBox());
    reader.dispose();
    await finishReader(tester, reader.flush());
    scale.dispose();
    downloads.dispose();
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
