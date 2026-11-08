import 'dart:async';

import 'package:bookfin/appearance/appearance.dart';
import 'package:bookfin/appearance/preferences.dart';
import 'package:bookfin/foundation/theme.dart';
import 'package:bookfin/reader/screen.dart';
import 'package:bookfin/reader/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_epub_viewer/publication.dart';
import 'package:flutter_epub_viewer/resources.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback/playback_test.dart' show account, LocalFiles, MemoryResume;
import '../appearance/preferences_test.dart' show MemoryAppearanceStore;
import 'publication_test.dart' show epub;
import 'session_test.dart' show source, edition, book, visible;
import 'reader_settings.dart';

class BridgePlatform extends InAppWebViewPlatform {
  Completer<void>? openGate;
  final controllers = <RecordingBridge>[];
  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams params,
  ) {
    return BridgeView(params, this);
  }
}

class BridgeView extends PlatformInAppWebViewWidget {
  BridgeView(super.params, this.owner) : super.implementation();
  final BridgePlatform owner;
  @override
  T controllerFromPlatform<T>(PlatformInAppWebViewController controller) =>
      params.controllerFromPlatform!(controller) as T;
  @override
  Widget build(BuildContext context) =>
      BridgeSurface(params: params, owner: owner);
  @override
  void dispose() {}
}

class BridgeSurface extends StatefulWidget {
  const BridgeSurface({super.key, required this.params, required this.owner});
  final PlatformInAppWebViewWidgetCreationParams params;
  final BridgePlatform owner;
  @override
  State<BridgeSurface> createState() => _BridgeSurfaceState();
}

class _BridgeSurfaceState extends State<BridgeSurface> {
  @override
  void initState() {
    super.initState();
    final bridge = RecordingBridge()..openGate = widget.owner.openGate;
    widget.owner.controllers.add(bridge);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = widget.params.controllerFromPlatform!(bridge);
      widget.params.onWebViewCreated!(controller);
      widget.params.onLoadStop!(
        controller,
        WebUri.uri(ReaderResources.runtimeUrl),
      );
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

class RecordingBridge extends PlatformInAppWebViewController {
  Completer<void>? openGate;
  RecordingBridge()
    : super.implementation(
        const PlatformInAppWebViewControllerCreationParams(id: 'reader-test'),
      );
  final calls = <({String body, Map<String, dynamic> arguments})>[];
  final handlers = <String, Function>{};
  @override
  void addJavaScriptHandler({
    required String handlerName,
    required Function callback,
  }) {
    handlers[handlerName] = callback;
  }

  @override
  Future<CallAsyncJavaScriptResult?> callAsyncJavaScript({
    required String functionBody,
    Map<String, dynamic> arguments = const {},
    ContentWorld? contentWorld,
  }) async {
    calls.add((body: functionBody, arguments: arguments));
    if (functionBody.contains('openBook')) await openGate?.future;
    return CallAsyncJavaScriptResult(
      value: functionBody.contains('openBook') ? <dynamic>[] : null,
    );
  }
}

Future<void> finishLoading(WidgetTester tester) async {
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });
  await tester.pumpAndSettle();
  await tester.pumpAndSettle();
}

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
  testWidgets(
    'appearance changes during attachment wait for the renderer to open',
    (tester) async {
      final platform = BridgePlatform()..openGate = Completer<void>();
      InAppWebViewPlatform.instance = platform;
      final downloads = LocalFiles()
        ..files[source.key] = Uri.file('/verified.epub');
      final publication = Publication.admit(epub());
      final reader = ReaderSession(
        downloads: downloads,
        store: MemoryResume(),
        load: (_) async => publication,
      );
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
      await finishLoading(tester);
      expect(reader.ready, isFalse);
      final bridge = platform.controllers.single;
      await chooseSetting(tester, 'Larger text');
      expect(bridge.calls, hasLength(1));
      platform.openGate!.complete();
      await tester.pumpAndSettle();
      expect(reader.ready, isTrue);
      expect(bridge.calls.last.arguments, {
        'argument0': 44.0,
        'argument1': false,
      });
      expect(bridge.calls, hasLength(2));
      await tester.pumpWidget(const SizedBox());
      reader.dispose();
      await reader.flush();
      downloads.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    '200 percent text scaling sends one final size and preserves the reading place',
    (tester) async {
      final platform = BridgePlatform();
      final previous = InAppWebViewPlatform.instance;
      InAppWebViewPlatform.instance = platform;
      addTearDown(() {
        if (previous != null) InAppWebViewPlatform.instance = previous;
      });
      final downloads = LocalFiles()
        ..files[source.key] = Uri.file('/verified.epub');
      final publication = Publication.admit(epub());
      final reader = ReaderSession(
        downloads: downloads,
        store: MemoryResume(),
        load: (_) async => publication,
      );
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
      await finishLoading(tester);
      expect(reader.ready, isTrue);
      final bridge = platform.controllers.single;
      expect(
        (bridge.calls.single.arguments['argument0'] as Map)['fontSize'],
        40,
      );
      bridge.handlers['readerLocation']!([visible.toJson()]);
      await tester.pumpAndSettle();
      final anchor = reader.position!.anchor;
      bridge.calls.clear();
      await chooseSetting(tester, 'Larger text');
      expect(reader.fontSize, 22);
      expect(bridge.calls.map((call) => call.arguments).toList(), [
        {'argument0': 44.0, 'argument1': false},
      ]);
      expect(reader.position!.anchor, anchor);
      bridge.calls.clear();
      await chooseSetting(tester, 'Night reading theme');
      expect(bridge.calls.map((call) => call.arguments).toList(), [
        {'argument0': 44.0, 'argument1': true},
      ]);
      expect(reader.position!.anchor, anchor);
      bridge.calls.clear();
      scale.value = 1.5;
      await tester.pumpAndSettle();
      expect(bridge.calls.map((call) => call.arguments).toList(), [
        {'argument0': 33.0, 'argument1': true},
      ]);
      expect(reader.position!.anchor, anchor);
      expect(reader.fontSize, 22);
      await reader.open(book, edition);
      await tester.pumpAndSettle();
      await finishLoading(tester);
      final reopened =
          platform.controllers.last.calls.single.arguments['argument0'] as Map;
      expect(reopened['fontSize'], 33);
      expect(reopened['night'], true);
      expect((reopened['initial'] as Map)['cfi'], visible.cfi);
      await tester.pumpWidget(const SizedBox());
      reader.dispose();
      await reader.flush();
      scale.dispose();
      downloads.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
