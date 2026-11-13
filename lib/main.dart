import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'appearance/appearance.dart';
import 'appearance/app.dart';
import 'appearance/sheet.dart';
import 'appearance/preferences.dart';
import 'app/account_binding.dart';
import 'catalog/covers.dart';
import 'catalog/layout.dart';
import 'catalog/controller.dart';
import 'catalog/screen.dart';
import 'catalog/store.dart';
import 'crossings/crossings.dart';
import 'foundation/derived_store.dart';
import 'downloads/downloads.dart';
import 'downloads/platform.dart';
import 'playback/native.dart';
import 'playback/playback.dart';
import 'playback/store.dart';
import 'playback/database.dart';
import 'reader/kept_pages.dart';
import 'reader/last_page_settings.dart';
import 'reader/reading_speed.dart';
import 'reader/session.dart';
import 'reader/survey_files.dart';
import 'reader/platform.dart';
import 'reader/licenses.dart';
import 'speech/book_search.dart' show ReadBook;
import 'speech/heard_windows.dart';
import 'speech/hearing_policy.dart';
import 'speech/platform.dart';
import 'sync/alert.dart' show RecordSyncScope;
import 'sync/coordinator.dart';
import 'sync/device.dart';

Future<void> main() => runBookfin();

/// Starts the app with local sources. Factories let host tests hold native
/// source opening without replacing the production startup coordination.
/// The app owns the result of [createCatalog], restores it once, and disposes
/// it on failed startup or when the root is removed. [catalogStore] supplies
/// both restoration and legacy migration. [recordStore] replaces native
/// record persistence for hosts without the platform database plugin.
Future<void> runBookfin({
  Future<BookfinSources> Function()? openOtherSources,
  CatalogController Function(LocalCatalogStore store)? createCatalog,
  LocalCatalogStore? catalogStore,
  LocalResumeStore? recordStore,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(readerLicenses);
  registerAppearanceLicenses();
  final appearance = AppearanceController(LocalAppearanceStore());
  // Every native platform keeps personal records in the record database.
  // sqflite supplies it on Android, iOS and macOS. A Linux or Windows port
  // must first set sqflite's databaseFactory to the FFI one.
  final records =
      recordStore ??
      LocalResumeStore(
        openDatabase: kIsWeb ? null : () => RecordDatabase.open(),
        deviceName: deviceName,
      );
  final layout = LibraryLayout(LocalLayoutStore());
  // Local catalog restoration overlaps every independent source opening.
  // Until runApp hands it to the root, this function owns the controller.
  final localStore = catalogStore ?? LocalCatalogStore();
  final catalog =
      createCatalog?.call(localStore) ??
      CatalogController(
        credentials: SecureCredentialStore(),
        store: localStore,
      );
  final restoring = catalog.restore();
  try {
    late final opening = createCovers();
    final (
      :downloads,
      :playback,
      :covers,
    ) = await (openOtherSources?.call() ??
        openSources(
          restoreAppearance: appearance.restore,
          restoreLayout: layout.restore,
          // Downloads prepares each saved ebook for reading in the background, so
          // that its first open reads the admitted book (boo-sy2d).
          openDownloads: () =>
              createDownloads(MediaPolicy(), prepare: prepareDownloadedBook),
          // The system media player draws the blurred cover that the covers make.
          // Playback starts without waiting for the covers to open.
          openPlayback: (downloads) => createPlayback(
            downloads,
            store: records,
            art: (session, cover) async =>
                (await opening)?.blurred(session, cover),
          ),
          openCovers: () => opening,
        ));
    // The reading speed is derived data, so the first frame does not wait
    // for it. Pages that count before it is read join the saved ones.
    final speed = ReadingSpeed(LocalReadingSpeedStore());
    unawaited(speed.restore());
    // The last page settings only give the first open of a book a head
    // start, so the first frame does not wait for them either.
    final pageSettings = LastPageSettings(LocalPageSettingsStore());
    unawaited(pageSettings.restore());
    final reader = downloads == null
        ? null
        : ReaderSession(
            downloads: downloads,
            store: records.reading,
            load: loadPublication,
            loadDocument: loadReadingDocument,
            speed: speed,
            pageSettings: pageSettings,
            surveyStore: SurveyFiles.new,
            // A debug build has no text-engine fingerprint, so it keeps no
            // pages: hot reload changes how pages draw.
            keptPages: KeptPages(engine: textEngineFingerprint),
          );
    // Speech search hears windows of downloaded audiobooks (docs/plans/
    // cross-edition-places.md, "Build design of S2"). The policy starts after
    // the first frame, and the speech runtime loads its model at the first
    // window, never before.
    final hear = createHear();
    final heard = downloads == null || hear == null
        ? null
        : HeardWindows(
            hear: hear,
            store: createDerivedStore('bookfin-heard'),
            localPath: (file) async =>
                (await downloads.localFile(file))?.toFilePath(),
          );
    final hearing = heard == null || playback == null
        ? null
        : HearingPolicy(
            playback: playback,
            heard: heard,
            mayFill: watchFillAllowed(),
          );
    // Crossings measures an ebook's outline only when the History first asks
    // for a landing in it, so no launch step waits for it.
    final crossings = downloads == null
        ? null
        : Crossings(
            store: createDerivedStore('bookfin-outlines'),
            measure: (text) async => switch (text.files) {
              [final file] => await downloads.readLocalFile(
                file,
                (original) => measureDownloadedOutline(original, file),
              ),
              _ => null,
            },
            downloads: downloads.phases,
            speech: heard == null
                ? null
                : (
                    heard: heard,
                    words: (text) async => switch (text.files) {
                      [final file] => await downloads.readLocalFile<ReadBook?>(
                        file,
                        (original) => bookWordsReader(original, file),
                      ),
                      _ => null,
                    },
                  ),
          );
    runApp(
      BookfinApp._restoring(
        restoration: restoring,
        catalogStore: localStore,
        catalog: catalog,
        appearance: appearance,
        layout: layout,
        covers: covers,
        downloads: downloads,
        playback: playback,
        reader: reader,
        crossings: crossings,
        hearing: hearing,
        sync: RecordSync(records: records),
      ),
    );
  } catch (_) {
    catalog.dispose();
    rethrow;
  }
}

/// The independently opened media sources used by the app.
typedef BookfinSources = ({
  Downloads? downloads,
  Playback? playback,
  Covers? covers,
});

/// Restores the saved state that the first frame shows, from this phone
/// only. No step waits for the network.
///
/// The steps are independent, so they all start at once. Playback starts
/// when Downloads is open, because it plays Downloads' files. Without
/// Downloads there is no Playback.
Future<BookfinSources> openSources({
  required Future<void> Function() restoreAppearance,
  required Future<void> Function() restoreLayout,
  required Future<Downloads?> Function() openDownloads,
  required Future<Playback?> Function(Downloads downloads) openPlayback,
  required Future<Covers?> Function() openCovers,
}) async {
  Future<(Downloads?, Playback?)> media() async {
    final downloads = await openDownloads();
    return (
      downloads,
      downloads == null ? null : await openPlayback(downloads),
    );
  }

  final (_, _, (downloads, playback), covers) = await (
    restoreAppearance(),
    restoreLayout(),
    media(),
    openCovers(),
  ).wait;
  return (downloads: downloads, playback: playback, covers: covers);
}

class BookfinApp extends StatefulWidget {
  const BookfinApp({
    super.key,
    required this.appearance,
    this.catalog,
    this.layout,
    this.covers,
    this.downloads,
    this.playback,
    this.reader,
    this.crossings,
    this.hearing,
    this.sync,
  }) : _restoration = null,
       _catalogStore = null;

  // Takes ownership of the controller already started by runBookfin. The
  // public constructor's supplied controllers remain owned by their caller.
  const BookfinApp._restoring({
    required this._restoration,
    required this._catalogStore,
    required this.catalog,
    required this.appearance,
    this.layout,
    this.covers,
    this.downloads,
    this.playback,
    this.reader,
    this.crossings,
    this.hearing,
    this.sync,
  });

  final Future<void>? _restoration;
  final LocalCatalogStore? _catalogStore;
  final AppearanceController appearance;
  final LibraryLayout? layout;
  final Covers? covers;
  final CatalogController? catalog;
  final Downloads? downloads;
  final Playback? playback;
  final ReaderSession? reader;
  final Crossings? crossings;
  final HearingPolicy? hearing;
  final RecordSync? sync;

  @override
  State<BookfinApp> createState() => _BookfinAppState();
}

/// The production root owns account binding and media lifecycle.
/// [AppearanceApp] owns the shared theme and appearance lifecycle.
class _BookfinAppState extends State<BookfinApp> with WidgetsBindingObserver {
  AppearanceController get _appearance => widget.appearance;
  late final CatalogController _catalog;
  late final bool _ownsCatalog;
  late AccountBinding _binding;

  /// Whether the app was hidden since it last returned to the screen. An
  /// inactive app stays visible, for example under the notification shade.
  bool _hidden = false;
  @override
  void initState() {
    super.initState();
    final localStore =
        widget._catalogStore ??
        (widget.catalog == null ? LocalCatalogStore() : null);
    _ownsCatalog = widget.catalog == null || widget._catalogStore != null;
    _catalog =
        widget.catalog ??
        CatalogController(
          credentials: SecureCredentialStore(),
          store: localStore!,
        );
    if (localStore != null) {
      unawaited(
        _restoreCatalog(localStore, widget._restoration ?? _catalog.restore()),
      );
    }
    _binding = _bind();
    // Kept copies of damaged records are read again in the background,
    // never on the path to the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(widget.sync?.recoverKept());
      widget.hearing?.start();
    });
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> _restoreCatalog(
    LocalCatalogStore store,
    Future<void> restoring,
  ) async {
    await restoring;
    if (!mounted) return;
    // The saved library shows first. Refresh and legacy migration proceed
    // independently; inactive accounts never delay the restored library.
    unawaited(_catalog.refresh());
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    try {
      try {
        await store.migrateLegacy();
      } on Exception {
        // Successful accounts may discover retained damage even when another
        // account fails migration. The catalog owns ordering and reporting it.
        if (mounted) await _catalog.reconcileChoices();
        rethrow;
      }
      if (mounted) await _catalog.reconcileChoices();
    } on Exception catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'catalog storage',
          context: ErrorDescription('while transferring legacy catalog files'),
        ),
      );
    }
  }

  AccountBinding _bind() => AccountBinding(
    catalog: _catalog,
    downloads: widget.downloads,
    playback: widget.playback,
    reader: widget.reader,
    sync: widget.sync,
  );

  @override
  void didUpdateWidget(BookfinApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.downloads != widget.downloads ||
        oldWidget.playback != widget.playback ||
        oldWidget.reader != widget.reader ||
        oldWidget.sync != widget.sync) {
      _binding.dispose();
      _binding = _bind();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.sync?.resume();
      widget.reader?.resume();
      unawaited(widget.downloads?.refresh());
      // The catalog owns freshness and recovery after an unreachable result.
      if (_hidden) unawaited(_catalog.resume());
      _hidden = false;
    } else {
      // Record sync keeps its period until the app is hidden.
      if (state != AppLifecycleState.inactive) {
        _hidden = true;
        widget.sync?.suspend();
        widget.reader?.suspend();
      }
      unawaited(widget.playback?.flush());
      unawaited(widget.reader?.flush());
    }
  }

  /// A desktop app can quit from its menu while it is in the foreground,
  /// with no lifecycle change before. The places in the open books are saved
  /// before it exits. A save that fails does not keep the app open: the
  /// binding reports the error and exits.
  @override
  Future<AppExitResponse> didRequestAppExit() async {
    await Future.wait([
      if (widget.playback case final playback?) playback.flush(),
      if (widget.reader case final reader?) reader.flush(),
    ]);
    return AppExitResponse.exit;
  }

  @override
  void dispose() {
    _binding.dispose();
    widget.sync?.dispose();
    widget.hearing?.dispose();
    if (_ownsCatalog) _catalog.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RecordSyncScope(
    sync: widget.sync,
    child: AppearanceApp(
      appearance: _appearance,
      home: Builder(
        builder: (context) => CatalogHome(
          catalog: _catalog,
          layout: widget.layout,
          covers: widget.covers,
          downloads: widget.downloads,
          playback: widget.playback,
          reader: widget.reader,
          crossings: widget.crossings,
          sync: widget.sync,
          onReaderNightChanged: (night) => unawaited(
            _appearance.selectMode(
              night ? AppearanceMode.night : AppearanceMode.day,
            ),
          ),
          onAppearance: () => unawaited(
            showAppearance(context, _appearance, book: widget.playback?.book),
          ),
        ),
      ),
    ),
  );
}
