import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bookfin/catalog/book_cover.dart';
import 'package:bookfin/catalog/covers.dart';
import 'package:bookfin/catalog/glass.dart';
import 'package:bookfin/catalog/jellyfin.dart';
import 'package:bookfin/catalog/model.dart';
import 'package:bookfin/foundation/theme.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final session = JellyfinSession(
  scope: AccountScope(
    server: Uri.parse('https://books.example'),
    serverId: 'server',
    userId: 'alice',
  ),
  token: 'token',
  username: 'alice',
  canDownload: true,
);
const ref = CoverRef('graft', 'tag');
const graft = Book(
  id: 'graft',
  title: 'Graft',
  author: 'Ines Okoro',
  editions: [],
  cover: ref,
);

/// Covers that serve [bytes] for every book.
class _FixedCovers implements Covers {
  _FixedCovers([this.bytes]);
  final Uint8List? bytes;
  @override
  Future<Uint8List?> load(JellyfinSession session, CoverRef cover) async =>
      bytes;
  @override
  Future<Uri?> blurred(JellyfinSession session, CoverRef cover) async => null;
  @override
  Future<void> clear(AccountScope account) async {}
}

class _CredentialCovers extends _FixedCovers {
  _CredentialCovers(super.bytes);
  @override
  Future<Uint8List?> load(JellyfinSession session, CoverRef cover) async =>
      session.needsSignIn ? null : bytes;
}

/// Paints a cover of four flat quadrants, [width] by 1.5 [width] pixels.
Future<Uint8List> quadrantCover(int width) async {
  final height = width * 3 ~/ 2;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const colors = [
    Color(0xFFB0392B),
    Color(0xFF2E5E8C),
    Color(0xFFE8C468),
    Color(0xFF1F3A2B),
  ];
  for (var i = 0; i < 4; i++) {
    canvas.drawRect(
      Rect.fromLTWH(
        (i % 2) * width / 2,
        (i ~/ 2) * height / 2,
        width / 2,
        height / 2,
      ),
      Paint()..color = colors[i],
    );
  }
  final image = await recorder.endRecording().toImage(width, height);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return png!.buffer.asUint8List();
}

/// The width that [cover] asks the decoder for, from a source image of
/// [sourceWidth] by 1.5 [sourceWidth] pixels.
Future<int?> decodedWidth(CoverImage cover, int sourceWidth) async {
  int? asked;
  Future<ui.Codec> decode(
    ui.ImmutableBuffer buffer, {
    ui.TargetImageSizeCallback? getTargetSize,
  }) async {
    asked = getTargetSize!(sourceWidth, sourceWidth * 3 ~/ 2).width;
    throw StateError('Only the size is wanted.');
  }

  final stream = cover.loadImage(cover, decode);
  final done = Completer<void>();
  stream.addListener(
    ImageStreamListener(
      (_, _) => done.complete(),
      onError: (_, _) => done.complete(),
    ),
  );
  await done.future;
  return asked;
}

void main() {
  final covers = _FixedCovers(Uint8List(4));

  testWidgets('signing in again retries a missing cover in the current view', (
    tester,
  ) async {
    final png = (await tester.runAsync(() => quadrantCover(32)))!;
    final covers = _CredentialCovers(png);
    Future<void> show(JellyfinSession account) => tester.pumpWidget(
      CoverScope(
        covers: covers,
        session: account,
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 100,
              child: BookCover(title: 'Graft', cover: ref),
            ),
          ),
        ),
      ),
    );
    final rejected = JellyfinSession.fromJson({
      ...session.toJson(),
      'needsSignIn': true,
    });
    await show(rejected);
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<RawImage>(find.byType(RawImage))
          .any((image) => image.image != null),
      isFalse,
    );
    await show(JellyfinSession.fromJson(session.toJson()));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<RawImage>(find.byType(RawImage))
          .any((image) => image.image != null),
      isTrue,
    );
  });

  test('each cover size class has its own place in the image cache', () {
    expect(
      CoverImage(covers, session, ref, CoverSize.small),
      CoverImage(covers, session, ref, CoverSize.small),
    );
    expect(
      CoverImage(covers, session, ref, CoverSize.small),
      isNot(CoverImage(covers, session, ref, CoverSize.large)),
    );
  });

  test('a cover decodes no wider than its size class', () async {
    for (final size in CoverSize.values) {
      final cover = CoverImage(covers, session, ref, size);
      expect(await decodedWidth(cover, 2000), size.width, reason: '$size');
    }
  });

  test('a cover narrower than its size class is not enlarged', () async {
    final cover = CoverImage(covers, session, ref, CoverSize.large);
    expect(await decodedWidth(cover, 300), 300);
  });

  /// The size class of the cover image drawn in a [width] cover.
  Future<CoverSize> sizeShownAt(WidgetTester tester, double width) async {
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      CoverScope(
        covers: covers,
        session: session,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(width: width, child: BookCover.book(graft)),
          ),
        ),
      ),
    );
    final image = tester.widget<Image>(find.byType(Image));
    return (image.image as CoverImage).size;
  }

  testWidgets('a list row cover decodes small and a stage cover large', (
    tester,
  ) async {
    expect(await sizeShownAt(tester, 36), CoverSize.small);
    expect(await sizeShownAt(tester, 56), CoverSize.small);
    expect(await sizeShownAt(tester, 168), CoverSize.large);
    expect(await sizeShownAt(tester, 400), CoverSize.large);
  });

  testWidgets('a compact grid tile decodes between a row and a stage', (
    tester,
  ) async {
    expect(await sizeShownAt(tester, 112), CoverSize.medium);
  });

  testWidgets('a blurred cover loads the tiny size class', (tester) async {
    await tester.pumpWidget(
      CoverScope(
        covers: covers,
        session: session,
        child: const SizedBox(
          width: 300,
          height: 80,
          child: CoverBlur(book: graft),
        ),
      ),
    );
    final status = PaintingBinding.instance.imageCache.statusForKey(
      CoverImage(covers, session, ref, CoverSize.tiny),
    );
    expect(status.tracked, isTrue);
  });

  /// The layers that make Flutter draw offscreen and blend back, besides the
  /// backdrop blur of a glass pane.
  List<Layer> offscreenLayers(WidgetTester tester) => [
    for (final layer in tester.layers)
      if (layer is OpacityLayer ||
          layer is ImageFilterLayer ||
          layer is ShaderMaskLayer ||
          layer is ColorFilterLayer)
        layer,
  ];

  testWidgets('a glass pane draws its cover with no offscreen layer but its '
      'backdrop blur', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: bookfinTheme(Brightness.light),
        home: const Center(
          child: CoverGlass(
            book: graft,
            child: SizedBox(width: 300, height: 80),
          ),
        ),
      ),
    );
    expect(offscreenLayers(tester), isEmpty);
    expect(tester.layers.whereType<BackdropFilterLayer>(), hasLength(1));
  });

  for (final brightness in Brightness.values) {
    testWidgets('a stage backdrop draws with no offscreen layer '
        '(${brightness.name})', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: bookfinTheme(brightness),
          home: const SizedBox(
            width: 400,
            height: 420,
            child: CoverBackdrop(book: graft),
          ),
        ),
      );
      expect(offscreenLayers(tester), isEmpty);
    });
  }

  testWidgets('a pre-blurred cover looks like the full blur it replaces', (
    tester,
  ) async {
    final png = (await tester.runAsync(() => quadrantCover(300)))!;
    final covers = _FixedCovers(png);
    final shot = GlobalKey();

    /// The RGBA pixels of [art] drawn 360 by 80 over white, once its cover
    /// image is decoded.
    Future<Uint8List> pixels(Widget art) async {
      await tester.pumpWidget(
        CoverScope(
          covers: covers,
          session: session,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Align(
              alignment: Alignment.topLeft,
              child: RepaintBoundary(
                key: shot,
                child: ColoredBox(
                  color: const Color(0xFFFFFFFF),
                  child: SizedBox(width: 360, height: 80, child: art),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();
      final boundary =
          shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      return (await tester.runAsync(() async {
        final image = await boundary.toImage();
        final data = await image.toByteData();
        image.dispose();
        return data!.buffer.asUint8List();
      }))!;
    }

    // The glass cover as drawn before: a full-size blur of the whole cover
    // at the pane's size, faded by an opacity layer.
    final before = await pixels(
      Opacity(
        opacity: 0.6,
        child: ClipRect(
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: coverPalette(graft.title),
                ),
              ),
              child: Image(
                image: MemoryImage(png),
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
              ),
            ),
          ),
        ),
      ),
    );
    final after = await pixels(
      const CoverBlur(book: graft, sigma: 22, opacity: 0.6),
    );
    expect(after, hasLength(before.length));
    var largest = 0;
    var total = 0;
    for (var i = 0; i < before.length; i++) {
      final difference = (before[i] - after[i]).abs();
      total += difference;
      if (difference > largest) largest = difference;
    }
    final mean = total / before.length;
    expect(mean, lessThan(1), reason: 'largest difference $largest');
    expect(largest, lessThan(6), reason: 'mean difference $mean');
  });

  testWidgets(
    'a change of the playing book redraws glass panes and no cover face',
    (tester) async {
      const tide = Book(
        id: 'tide',
        title: 'Tidewater',
        author: '',
        editions: [],
      );
      const child = Column(
        children: [
          SizedBox(
            width: 120,
            child: BookCover(title: 'Graft', cover: ref),
          ),
          SizedBox(
            width: 120,
            height: 60,
            child: CoverGlass(child: SizedBox.shrink()),
          ),
          SizedBox(width: 120, height: 60, child: CoverBlur(book: graft)),
        ],
      );
      final covers = _FixedCovers();
      Widget scoped(Book playing) => MaterialApp(
        home: CoverScope(
          covers: covers,
          session: session,
          playing: playing,
          child: child,
        ),
      );
      await tester.pumpWidget(scoped(graft));
      // The names of the rebuilt widgets outside a glass pane, and the
      // glass panes themselves.
      final rebuilt = <String>[];
      debugOnRebuildDirtyWidget = (element, _) {
        if (element.findAncestorWidgetOfExactType<CoverGlass>() == null) {
          rebuilt.add(element.widget.runtimeType.toString());
        }
      };
      try {
        await tester.pumpWidget(scoped(tide));
      } finally {
        debugOnRebuildDirtyWidget = null;
      }
      expect(rebuilt, contains('CoverGlass'));
      expect(rebuilt, isNot(contains('_CoverFace')));
      expect(rebuilt, isNot(contains('CoverBlur')));
    },
  );

  testWidgets(
    'a new cover store with the same playing book redraws no glass pane',
    (tester) async {
      const child = SizedBox(
        width: 120,
        height: 60,
        child: CoverGlass(child: SizedBox.shrink()),
      );
      Widget scoped(Covers covers) => MaterialApp(
        home: CoverScope(
          covers: covers,
          session: session,
          playing: graft,
          child: child,
        ),
      );
      await tester.pumpWidget(scoped(_FixedCovers()));
      final rebuilt = <String>[];
      debugOnRebuildDirtyWidget = (element, _) =>
          rebuilt.add(element.widget.runtimeType.toString());
      try {
        await tester.pumpWidget(scoped(_FixedCovers()));
      } finally {
        debugOnRebuildDirtyWidget = null;
      }
      expect(rebuilt, isNot(contains('CoverGlass')));
    },
  );
}
