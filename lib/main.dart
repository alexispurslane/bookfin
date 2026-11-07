import 'dart:async';

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
import 'foundation/listenable_selector.dart';
import 'downloads/downloads.dart';
import 'downloads/platform.dart';
import 'playback/native.dart';
import 'playback/playback.dart';
import 'playback/store.dart';
import 'playback/database.dart';
import 'reader/session.dart';
import 'reader/platform.dart';
import 'reader/licenses.dart';
import 'sync/coordinator.dart';

Future<void> main() => runBookfin();

Future<void> runBookfin({bool gallery = false}) async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(readerLicenses);
  LicenseRegistry.addLicense(() async* {
    for (final font in ['Outfit', 'Source-Serif-4']) {
      yield LicenseEntryWithLineBreaks([
        font,
      ], await rootBundle.loadString('assets/fonts/OFL-$font.txt'));
    }
    yield LicenseEntryWithLineBreaks(
      ['GeoNames city data'],
      '${await rootBundle.loadString('assets/cities/NOTICE.txt')}\n\n${await rootBundle.loadString('assets/cities/CC-BY-4.0.txt')}',
    );
    yield LicenseEntryWithLineBreaks(
      ['Bookfin EPUB navigator'],
      await rootBundle.loadString(
        'packages/flutter_epub_viewer/assets/THIRD-PARTY-LICENSES.txt',
      ),
    );
  });
  final appearance = AppearanceController(LocalAppearanceStore());
  final records = LocalResumeStore(
    openDatabase: !kIsWeb && defaultTargetPlatform == TargetPlatform.android
        ? () => RecordDatabase.open()
        : null,
  );
  final layout = LibraryLayout(LocalLayoutStore());
  final (:downloads, :playback, :covers) = await openSources(
    restoreAppearance: appearance.restore,
    restoreLayout: layout.restore,
    openDownloads: () async =>
        gallery ? null : await createDownloads(MediaPolicy()),
    openPlayback: (downloads) => createPlayback(downloads, store: records),
    openCovers: () async => gallery ? null : await createCovers(),
  );
  final reader = downloads == null
      ? null
      : ReaderSession(
          downloads: downloads,
          store: records.reading,
          load: loadPublication,
          loadDocument: loadReadingDocument,
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
      unawaited(widget.downloads?.refresh());
      _appearance.resume();
    } else {
      // An inactive app stays visible, for example under the notification
      // shade, so record sync keeps its period until the app is hidden.
      if (state != AppLifecycleState.inactive) widget.sync?.suspend();
      unawaited(widget.playback?.flush());
      unawaited(widget.reader?.flush());
      _appearance.suspend();
    }
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
        builder: (context, child) => BookfinThemeTransition(
          theme: theme,
          reduceMotion: reduceMotion,
          child: child!,
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
