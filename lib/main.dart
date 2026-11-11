import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'appearance/appearance.dart';
import 'appearance/city_search.dart';
import 'appearance/preferences.dart';
import 'app/account_binding.dart';
import 'development/gallery.dart';
import 'foundation/theme.dart';
import 'catalog/covers.dart';
import 'catalog/glass.dart';
import 'catalog/layout.dart';
import 'catalog/controller.dart';
import 'catalog/screen.dart';
import 'catalog/model.dart' show Book;
import 'catalog/store.dart';
import 'crossings/crossings.dart';
import 'crossings/outlines.dart';
import 'foundation/listenable_selector.dart';
import 'downloads/downloads.dart';
import 'downloads/platform.dart';
import 'playback/native.dart';
import 'playback/playback.dart';
import 'playback/store.dart';
import 'playback/database.dart';
import 'reader/reading_speed.dart';
import 'reader/session.dart';
import 'reader/survey_files.dart';
import 'reader/platform.dart';
import 'reader/licenses.dart';
import 'sync/alert.dart' show RecordSyncScope;
import 'sync/coordinator.dart';
import 'sync/device.dart';

Future<void> main() => runBookfin();

Future<void> runBookfin({bool gallery = false}) async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(readerLicenses);
  LicenseRegistry.addLicense(() async* {
    for (final font in ['Outfit', 'Source-Serif-4', 'Noto-Sans-Math']) {
      yield LicenseEntryWithLineBreaks([
        font,
      ], await rootBundle.loadString('assets/fonts/OFL-$font.txt'));
    }
    yield LicenseEntryWithLineBreaks(
      ['GeoNames city data'],
      '${await rootBundle.loadString('assets/cities/NOTICE.txt')}\n\n${await rootBundle.loadString('assets/cities/CC-BY-4.0.txt')}',
    );
  });
  final appearance = AppearanceController(LocalAppearanceStore());
  // Every native platform keeps personal records in the record database.
  // sqflite supplies it on Android, iOS and macOS. A Linux or Windows port
  // must first set sqflite's databaseFactory to the FFI one.
  final records = LocalResumeStore(
    openDatabase: kIsWeb ? null : () => RecordDatabase.open(),
    deviceName: deviceName,
  );
  final layout = LibraryLayout(LocalLayoutStore());
  final opening = gallery ? Future<Covers?>.value() : createCovers();
  final (:downloads, :playback, :covers) = await openSources(
    restoreAppearance: appearance.restore,
    restoreLayout: layout.restore,
    openDownloads: () async =>
        gallery ? null : await createDownloads(MediaPolicy()),
    // The system media player draws the blurred cover that the covers make.
    // Playback starts without waiting for the covers to open.
    openPlayback: (downloads) => createPlayback(
      downloads,
      store: records,
      art: (session, cover) async => (await opening)?.blurred(session, cover),
    ),
    openCovers: () => opening,
  );
  // The reading speed is derived data, so the first frame does not wait
  // for it. Pages that count before it is read join the saved ones.
  final speed = ReadingSpeed(LocalReadingSpeedStore());
  unawaited(speed.restore());
  final reader = downloads == null
      ? null
      : ReaderSession(
          downloads: downloads,
          store: records.reading,
          load: loadPublication,
          loadDocument: loadReadingDocument,
          speed: speed,
          surveyStore: SurveyFiles.new,
        );
  // Crossings measures an ebook's outline only when the History first asks
  // for a landing in it, so no launch step waits for it.
  final crossings = downloads == null
      ? null
      : Crossings(
          store: createOutlineStore(),
          measure: (text) async => switch (text.files) {
            [final file] => await downloads.readLocalFile(
              file,
              (original) => measureDownloadedOutline(original, file),
            ),
            _ => null,
          },
          downloads: downloads.phases,
        );
  runApp(
    BookfinApp(
      appearance: appearance,
      gallery: gallery,
      layout: layout,
      covers: covers,
      downloads: downloads,
      playback: playback,
      reader: reader,
      crossings: crossings,
      sync: gallery
          ? null
          : RecordSync(records: records, playback: playback, reader: reader),
    ),
  );
}

/// Restores the saved state that the first frame shows, from this phone
/// only. No step waits for the network.
///
/// The steps are independent, so they all start at once. Playback starts
/// when Downloads is open, because it plays Downloads' files. Without
/// Downloads, as in the development gallery, there is no Playback.
Future<({Downloads? downloads, Playback? playback, Covers? covers})>
openSources({
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
    this.gallery = false,
    this.catalog,
    this.layout,
    this.covers,
    this.downloads,
    this.playback,
    this.reader,
    this.crossings,
    this.sync,
  });

  final AppearanceController appearance;
  final LibraryLayout? layout;
  final Covers? covers;
  final bool gallery;
  final CatalogController? catalog;
  final Downloads? downloads;
  final Playback? playback;
  final ReaderSession? reader;
  final Crossings? crossings;
  final RecordSync? sync;

  @override
  State<BookfinApp> createState() => _BookfinAppState();
}

/// The app's root. It reports the phone's brightness, accessibility and
/// lifecycle to the sources, and rebuilds [MaterialApp] only when the theme
/// decision or the reduced-motion choice changes.
class _BookfinAppState extends State<BookfinApp> with WidgetsBindingObserver {
  AppearanceController get _appearance => widget.appearance;
  late final CatalogController _catalog;
  late AccountBinding _binding;

  /// Whether the app was hidden since it last returned to the screen. An
  /// inactive app stays visible, for example under the notification shade.
  bool _hidden = false;
  final _reduceMotion = ValueNotifier(_platformReducesMotion());

  static bool _platformReducesMotion() => WidgetsBinding
      .instance
      .platformDispatcher
      .accessibilityFeatures
      .disableAnimations;

  @override
  void initState() {
    super.initState();
    _catalog =
        widget.catalog ??
        CatalogController(
          credentials: SecureCredentialStore(),
          store: LocalCatalogStore(),
        );
    if (widget.catalog == null && !widget.gallery) {
      // The saved library shows first. The refresh runs in the background.
      unawaited(_catalog.restore().then((_) => _catalog.refresh()));
    }
    _binding = _bind();
    // Kept copies of damaged records are read again in the background,
    // never on the path to the first frame.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(widget.sync?.recoverKept()),
    );
    WidgetsBinding.instance.addObserver(this);
    _showAppearance(_appearance);
  }

  AccountBinding _bind() => AccountBinding(
    catalog: _catalog,
    downloads: widget.downloads,
    playback: widget.playback,
    reader: widget.reader,
    sync: widget.sync,
  );

  void _showAppearance(AppearanceController appearance) => appearance
    ..platformBrightnessChanged(
      WidgetsBinding.instance.platformDispatcher.platformBrightness,
    )
    ..resume();

  @override
  void didUpdateWidget(BookfinApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.appearance != widget.appearance) {
      oldWidget.appearance.suspend();
      _showAppearance(_appearance);
    }
    if (oldWidget.downloads != widget.downloads ||
        oldWidget.playback != widget.playback ||
        oldWidget.reader != widget.reader ||
        oldWidget.sync != widget.sync) {
      _binding.dispose();
      _binding = _bind();
    }
  }

  @override
  void didChangePlatformBrightness() => _appearance.platformBrightnessChanged(
    WidgetsBinding.instance.platformDispatcher.platformBrightness,
  );

  @override
  void didChangeAccessibilityFeatures() =>
      _reduceMotion.value = _platformReducesMotion();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.sync?.resume();
      widget.reader?.resume();
      unawaited(widget.downloads?.refresh());
      _appearance.resume();
      // A return after the app was hidden refreshes the catalog in the
      // background, so a library that could not reach Jellyfin comes back.
      // It never replaces a sign-in, a refresh or a restore that runs: the
      // launch refresh follows a restore.
      if (_hidden && !_catalog.busy) unawaited(_catalog.refresh());
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
      _appearance.suspend();
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
    _appearance.suspend();
    _binding.dispose();
    widget.sync?.dispose();
    if (widget.catalog == null) _catalog.dispose();
    _reduceMotion.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_appearance.decision, _reduceMotion]),
    builder: (context, home) {
      final reduceMotion = _reduceMotion.value;
      final theme = bookfinTheme(
        _appearance.decision.value.brightness,
        reduceMotion: reduceMotion,
      );
      return MaterialApp(
        title: 'Bookfin',
        debugShowCheckedModeBanner: false,
        theme: theme,
        themeAnimationDuration: Duration.zero,
        builder: (context, child) => RecordSyncScope(
          sync: widget.sync,
          child: BookfinThemeTransition(
            theme: theme,
            reduceMotion: reduceMotion,
            child: child!,
          ),
        ),
        home: home,
      );
    },
    // The same home on every theme, so a new theme rebuilds no page.
    child: widget.gallery
        ? _BookfinHome(appearance: _appearance, gallery: widget.gallery)
        : Builder(
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
                showAppearance(
                  context,
                  _appearance,
                  book: widget.playback?.book,
                ),
              ),
            ),
          ),
  );
}

/// Shows the appearance sheet over [context], and makes the choices that it
/// reports: a mode, a city from the offline city search, a development
/// location in the [gallery], or no location.
Future<void> showAppearance(
  BuildContext context,
  AppearanceController appearance, {
  Book? book,
  bool gallery = false,
  AnimationStyle? sheetAnimationStyle,
}) => showGlassSheet<void>(
  context,
  book: book,
  title: 'Appearance',
  isScrollControlled: true,
  sheetAnimationStyle: sheetAnimationStyle,
  builder: (sheet) => AppearanceSheet(
    appearance: appearance,
    gallery: gallery,
    onMode: (mode) => unawaited(appearance.selectMode(mode)),
    onChooseCity: () => unawaited(
      Navigator.of(sheet).push<void>(
        MaterialPageRoute(builder: (_) => CitySearch(appearance: appearance)),
      ),
    ),
    onLocation: (location) => unawaited(appearance.selectLocation(location)),
  ),
);

class _BookfinHome extends StatelessWidget {
  const _BookfinHome({required this.appearance, required this.gallery});

  final AppearanceController appearance;
  final bool gallery;

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: Theme.of(context).brightness == Brightness.dark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark,
    child: Scaffold(
      appBar: AppBar(
        title: Text('BOOKFIN', style: Theme.of(context).textTheme.labelSmall),
        actions: [
          IconButton(
            tooltip: 'Appearance',
            icon: const Icon(Icons.contrast_rounded),
            onPressed: () => unawaited(
              showAppearance(
                context,
                appearance,
                gallery: gallery,
                sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
                    ? AnimationStyle.noAnimation
                    : const AnimationStyle(
                        duration: Duration(milliseconds: 360),
                      ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: BookfinSurface(
          child: gallery
              ? const DevelopmentGallery()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
                  children: [
                    Text(
                      'Book libraries',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'A little further\ninto the story.',
                      style: Theme.of(context).textTheme.displaySmall,
                    ),
                    const SizedBox(height: 28),
                    const BookfinPanel(
                      child: Text('Your library starts here.'),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Library connection is not available in this setup build.',
                    ),
                    const SizedBox(height: 24),
                    ValueListenableBuilder(
                      valueListenable: appearance.decision,
                      builder: (context, decision, _) => Text(
                        decision.description,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    ListenableSelector(
                      listenable: appearance,
                      select: () => appearance.warning,
                      builder: (context, warning, _) => warning == null
                          ? const SizedBox.shrink()
                          : Text(warning),
                    ),
                    const SizedBox(height: 28),
                    const Wrap(
                      spacing: 12,
                      children: [
                        TextButton(onPressed: null, child: Text('Library')),
                        TextButton(onPressed: null, child: Text('Downloads')),
                        TextButton(onPressed: null, child: Text('Listening')),
                      ],
                    ),
                  ],
                ),
        ),
      ),
    ),
  );
}

/// The appearance choices: a mode, a city and, in the development gallery,
/// sample locations. It shows what [appearance] holds and reports each choice
/// through its callbacks. It changes nothing itself; [showAppearance] acts.
class AppearanceSheet extends StatelessWidget {
  const AppearanceSheet({
    super.key,
    required this.appearance,
    required this.gallery,
    required this.onMode,
    required this.onChooseCity,
    required this.onLocation,
  });

  final AppearanceController appearance;
  final bool gallery;

  /// The user chose a mode.
  final ValueChanged<AppearanceMode> onMode;

  /// The user asked to search for a city.
  final VoidCallback onChooseCity;

  /// The user chose a sample location, or null to remove the location.
  final ValueChanged<SelectedLocation?> onLocation;

  @override
  Widget build(BuildContext context) => BookfinSurface(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    child: ListenableBuilder(
      listenable: appearance,
      builder: (context, _) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            24,
            0,
            24,
            24 + MediaQuery.paddingOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final mode in AppearanceMode.values)
                    ChoiceChip(
                      checkmarkColor: Theme.of(context).colorScheme.onPrimary,
                      label: Text(switch (mode) {
                        AppearanceMode.automatic => 'Automatic',
                        AppearanceMode.day => 'Day',
                        AppearanceMode.night => 'Night',
                      }),
                      selected: appearance.settings.mode == mode,
                      labelStyle: TextStyle(
                        color: appearance.settings.mode == mode
                            ? Theme.of(context).colorScheme.onPrimary
                            : Theme.of(context).colorScheme.onSurface,
                      ),
                      onSelected: (_) => onMode(mode),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              ValueListenableBuilder(
                valueListenable: appearance.decision,
                builder: (context, decision, _) => Text(decision.description),
              ),
              const SizedBox(height: 8),
              const Text(
                'Automatic uses sunrise and sunset at your selected location. Without a location, it follows Android system appearance.',
              ),
              if (appearance.saveState == PreferenceSaveState.saving)
                const Text('Saving on this device…'),
              if (appearance.warning != null)
                Text(
                  appearance.warning!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: 24),
              Text(
                'Selected city',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(appearance.settings.location?.name ?? 'No city selected'),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: onChooseCity,
                child: const Text('Choose city'),
              ),
              const SizedBox(height: 8),
              const Text(
                'Search the bundled offline city list. No device location or network lookup is used.',
              ),
              if (gallery) ...[
                const SizedBox(height: 24),
                Text(
                  'Development location fixtures',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Sample cities for testing only. The offline city search above is also available in production.',
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final location in [
                      SelectedLocation('New York', 40.7128, -74.0060),
                      SelectedLocation('Tokyo', 35.6762, 139.6503),
                      SelectedLocation('Tromsø', 69.6492, 18.9553),
                    ])
                      OutlinedButton(
                        onPressed: () => onLocation(location),
                        child: Text(location.name),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  'Font fallback sample',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'À côté · Ελληνικά · Кириллица · 日本語 · العربية',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
              if (appearance.settings.location != null)
                TextButton(
                  onPressed: () => onLocation(null),
                  child: const Text('Remove selected location'),
                ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
