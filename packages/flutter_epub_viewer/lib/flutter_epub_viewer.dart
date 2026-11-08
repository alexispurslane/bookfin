import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'navigation.dart';
import 'publication.dart';
import 'resources.dart';

export 'navigation.dart';
export 'publication.dart';

bool get epubViewportSupported =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

class EpubViewport extends StatefulWidget {
  const EpubViewport({
    super.key,
    required this.publication,
    required this.fontSize,
    required this.night,
    required this.onReady,
    required this.onLocation,
    required this.onFailure,
    required this.onWarning,
    required this.onTap,
    this.initial,
  });
  final Publication publication;
  final ReadingLocation? initial;
  final double fontSize;
  final bool night;
  final void Function(NavigatorPort controller, List<ContentsEntry> contents)
  onReady;
  final ValueChanged<ReadingLocation> onLocation;
  final ValueChanged<String> onFailure;
  final ValueChanged<String> onWarning;
  final VoidCallback onTap;
  @override
  State<EpubViewport> createState() => _EpubViewportState();
}

class _EpubViewportState extends State<EpubViewport> {
  late final Future<ReaderResources> _resources = _loadResources();
  _NativeNavigator? _navigator;
  bool _opened = false;
  bool _ready = false;
  Timer? _timeout;

  Future<ReaderResources> _loadResources() async {
    final runtime = <String, Uint8List>{};
    for (final file in ['index.html', 'epub.js', 'reader.js']) {
      final data = await rootBundle.load(
        'packages/flutter_epub_viewer/assets/$file',
      );
      runtime[file] = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
    }
    final font = await rootBundle.load('assets/fonts/SourceSerif4.ttf');
    runtime['SourceSerif4.ttf'] = font.buffer.asUint8List(
      font.offsetInBytes,
      font.lengthInBytes,
    );
    return ReaderResources(widget.publication, runtime);
  }

  void _failure(String message) {
    _timeout?.cancel();
    if (mounted) widget.onFailure(message);
  }

  @override
  void initState() {
    super.initState();
    _timeout = Timer(
      const Duration(seconds: 30),
      () => _failure(
        'The reader did not finish loading. Return to the book and retry.',
      ),
    );
  }

  @override
  void dispose() {
    _timeout?.cancel();
    _navigator?.detach();
    super.dispose();
  }

  @override
  void didUpdateWidget(EpubViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_ready &&
        (widget.fontSize != oldWidget.fontSize ||
            widget.night != oldWidget.night)) {
      unawaited(
        _navigator
            ?.configure(fontSize: widget.fontSize, night: widget.night)
            .catchError(
              (Object _) => _failure(
                'The reading appearance could not be updated. Return to the book and retry.',
              ),
            ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!epubViewportSupported) {
      return const Center(
        child: Text(
          'EPUB reading is available in the Android app. Your downloads and listening are unchanged.',
        ),
      );
    }
    return FutureBuilder<ReaderResources>(
      future: _resources,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Text(
              'The bundled reader files could not be opened. Reinstall Bookfin, then retry.',
            ),
          );
        }
        final resources = snapshot.data;
        if (resources == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return InAppWebView(
          key: ValueKey(widget.publication.identity),
          initialUrlRequest: URLRequest(
            url: WebUri.uri(ReaderResources.runtimeUrl),
          ),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            javaScriptCanOpenWindowsAutomatically: false,
            javaScriptBridgeEnabled: true,
            javaScriptBridgeForMainFrameOnly: true,
            javaScriptBridgeOriginAllowList: {
              'https://bookfin-runtime.invalid',
            },
            useShouldInterceptRequest: true,
            useShouldOverrideUrlLoading: true,
            blockNetworkLoads: true,
            allowFileAccess: false,
            allowContentAccess: false,
            allowFileAccessFromFileURLs: false,
            allowUniversalAccessFromFileURLs: false,
            mixedContentMode: MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
            cacheMode: CacheMode.LOAD_NO_CACHE,
            incognito: true,
            domStorageEnabled: false,
            databaseEnabled: false,
            geolocationEnabled: false,
            supportMultipleWindows: false,
            mediaPlaybackRequiresUserGesture: true,
            allowsInlineMediaPlayback: false,
            iframeAllowFullscreen: false,
            thirdPartyCookiesEnabled: false,
            supportZoom: true,
            builtInZoomControls: true,
            displayZoomControls: false,
            transparentBackground: true,
            isInspectable: false,
          ),
          onWebViewCreated: (controller) {
            _navigator = _NativeNavigator(controller);
            controller.addJavaScriptHandler(
              handlerName: 'readerLocation',
              callback: (arguments) {
                if (!mounted ||
                    arguments.length != 1 ||
                    arguments.first is! Map) {
                  return null;
                }
                try {
                  widget.onLocation(
                    ReadingLocation.fromJson(
                      Map<String, dynamic>.from(arguments.first as Map),
                    ),
                  );
                } catch (_) {
                  _failure(
                    'The reader returned an invalid reading place. Return to the book and retry.',
                  );
                }
                return null;
              },
            );
            controller.addJavaScriptHandler(
              handlerName: 'readerTap',
              callback: (_) {
                if (mounted) widget.onTap();
                return null;
              },
            );
            controller.addJavaScriptHandler(
              handlerName: 'readerFailure',
              callback: (_) {
                _failure(
                  'This chapter or destination could not be opened. Your saved reading place was kept. Return to the book and retry.',
                );
                return null;
              },
            );
            controller.addJavaScriptHandler(
              handlerName: 'readerWarning',
              callback: (arguments) {
                if (mounted &&
                    arguments.length == 1 &&
                    arguments.first is String &&
                    (arguments.first as String).length <= 300) {
                  widget.onWarning(arguments.first as String);
                }
                return null;
              },
            );
          },
          shouldInterceptRequest: (controller, request) async {
            final response = resources.reply(
              request.url,
              method: request.method ?? 'GET',
            );
            return WebResourceResponse(
              contentType: response.mime,
              data: response.bytes,
              statusCode: response.status,
              reasonPhrase: response.status == 200 ? 'OK' : 'Forbidden',
              headers: response.headers,
              contentEncoding:
                  response.mime.startsWith('text/') ||
                      response.mime.contains('xml') ||
                      response.mime == 'text/javascript'
                  ? 'utf-8'
                  : null,
            );
          },
          shouldOverrideUrlLoading: (controller, action) async =>
              action.request.url != null &&
                  resources.allowsNavigation(
                    action.request.url!,
                    mainFrame: action.isForMainFrame,
                  )
              ? NavigationActionPolicy.ALLOW
              : NavigationActionPolicy.CANCEL,
          onPermissionRequest: (controller, request) async =>
              PermissionResponse(
                resources: request.resources,
                action: PermissionResponseAction.DENY,
              ),
          onGeolocationPermissionsShowPrompt: (controller, origin) async =>
              GeolocationPermissionShowPromptResponse(
                origin: origin,
                allow: false,
                retain: false,
              ),
          onCreateWindow: (controller, request) async => false,
          onDownloadStarting: (controller, request) async =>
              DownloadStartResponse(
                action: DownloadStartResponseAction.CANCEL,
                handled: true,
              ),
          onLoadStop: (controller, url) async {
            if (!mounted ||
                _opened ||
                url != WebUri.uri(ReaderResources.runtimeUrl)) {
              return;
            }
            _opened = true;
            var appliedSize = widget.fontSize;
            var appliedNight = widget.night;
            try {
              final entries = await _navigator!._call('openBook', [
                {
                  'base': widget.publication.base.toString(),
                  'packagePath': widget.publication.packagePath,
                  'initial': widget.initial?.toJson(),
                  'fontSize': appliedSize,
                  'night': appliedNight,
                },
              ]);
              while (mounted &&
                  (appliedSize != widget.fontSize ||
                      appliedNight != widget.night)) {
                appliedSize = widget.fontSize;
                appliedNight = widget.night;
                await _navigator!.configure(
                  fontSize: appliedSize,
                  night: appliedNight,
                );
              }
              if (!mounted) return;
              _ready = true;
              _timeout?.cancel();
              widget.onReady(_navigator!, [
                for (final entry in entries as List)
                  ContentsEntry(
                    entry['title'] as String,
                    entry['href'] as String,
                    depth: entry['depth'] as int,
                  ),
              ]);
            } catch (_) {
              _failure(
                'The EPUB document could not be displayed. Check the download, then retry.',
              );
            }
          },
          onReceivedError: (controller, request, error) {
            if (request.isForMainFrame == true) {
              _failure(
                'The bundled reader could not start. Return to the book and retry.',
              );
            }
          },
        );
      },
    );
  }
}

class _NativeNavigator implements NavigatorPort {
  _NativeNavigator(this._controller);
  InAppWebViewController? _controller;
  void detach() {
    _controller = null;
  }

  Future<dynamic> _call(String name, List<dynamic> arguments) async {
    final controller = _controller;
    if (controller == null) throw StateError('The reading viewport is closed.');
    final parameters = <String, dynamic>{
      for (var index = 0; index < arguments.length; index++)
        'argument$index': arguments[index],
    };
    final result = await controller.callAsyncJavaScript(
      functionBody:
          'return await bookfinReader.$name(${parameters.keys.join(',')});',
      arguments: parameters,
    );
    if (result == null || result.error != null) {
      throw StateError('The reading operation did not finish.');
    }
    return result.value;
  }

  @override
  Future<void> move(bool forward) async {
    await _call('move', [forward]);
  }

  @override
  Future<void> display(ReadingLocation location) async {
    await _call('display', [location.toJson()]);
  }

  @override
  Future<void> contents(String href) async {
    await _call('go', [href]);
  }

  @override
  Future<void> seek(int section, double progress) async {
    await _call('seek', [section, progress]);
  }

  @override
  Future<PagePicture> preview(
    int section,
    double progress,
    double width,
  ) async {
    final page = await _call('previewPage', [section, progress, width]) as Map;
    final image = page['image'] as String;
    if (!image.startsWith('data:image/jpeg;base64,')) {
      throw StateError('The reader drew no page image.');
    }
    (int, double)? place(Object? value) => value is Map
        ? (value['part'] as int, (value['progress'] as num).toDouble())
        : null;
    return PagePicture(
      // A page image is about 100 KB, which decodes in well under a
      // millisecond, less than a hop to another isolate costs.
      base64Decode(image.substring(image.indexOf(',') + 1)),
      section: page['part'] as int,
      start: (page['start'] as num).toDouble(),
      end: (page['end'] as num).toDouble(),
      previous: place(page['previous']),
      next: place(page['next']),
    );
  }

  @override
  Future<void> configure({
    required double fontSize,
    required bool night,
  }) async {
    await _call('configure', [fontSize, night]);
  }

  @override
  Future<SearchReport> search(String query, int request) async {
    final report = await _call('search', [query, request]) as Map;
    return SearchReport([
      for (final hit in report['hits'] as List)
        SearchHit(
          ReadingLocation.fromJson(
            Map<String, dynamic>.from(hit['location'] as Map),
          ),
          hit['excerpt'] as String,
        ),
    ], error: report['error'] as String?);
  }

  @override
  Future<void> cancelSearch(int request) async {
    await _call('cancelSearch', [request]);
  }
}
