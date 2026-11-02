import 'dart:async';

import 'package:bookfin/reader/screen.dart';
import 'package:bookfin/reader/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_epub_viewer/publication.dart';
import 'package:flutter_epub_viewer/resources.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playback/playback_test.dart' show account, LocalFiles, MemoryResume;
import 'publication_test.dart' show epub;
import 'session_test.dart' show source, edition, book, visible;

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
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: ReaderScreen(reader: reader),
        ),
      );
      await finishLoading(tester);
      expect(reader.ready, isFalse);
      final bridge = platform.controllers.single;
      await tester.tap(find.byTooltip('Larger text'));
      await tester.pumpAndSettle();
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
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => ValueListenableBuilder<double>(
            valueListenable: scale,
            builder: (context, value, _) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(value)),
              child: child!,
            ),
          ),
          home: ReaderScreen(reader: reader),
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
      await tester.tap(find.byTooltip('Larger text'));
      await tester.pumpAndSettle();
      expect(reader.fontSize, 22);
      expect(bridge.calls.map((call) => call.arguments).toList(), [
        {'argument0': 44.0, 'argument1': false},
      ]);
      expect(reader.position!.anchor, anchor);
      bridge.calls.clear();
      await tester.tap(find.byTooltip('Night reading theme'));
      await tester.pumpAndSettle();
      expect(bridge.calls.map((call) => call.arguments).toList(), [
        {'argument0': 44.0, 'argument1': true},
      ]);
      bridge.calls.clear();
      scale.value = 1.5;
      await tester.pumpAndSettle();
      expect(bridge.calls.map((call) => call.arguments).toList(), [
        {'argument0': 33.0, 'argument1': true},
      ]);
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
