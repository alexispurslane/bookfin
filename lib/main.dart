import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'appearance/appearance.dart';
import 'appearance/city_search.dart';
import 'appearance/preferences.dart';
import 'development/gallery.dart';
import 'foundation/theme.dart';
import 'catalog/controller.dart';
import 'catalog/screen.dart';
import 'catalog/store.dart';
import 'downloads/downloads.dart';
import 'downloads/platform.dart';
import 'playback/native.dart';
import 'playback/playback.dart';
import 'playback/store.dart';
import 'playback/database.dart';
import 'reader/session.dart';
import 'reader/platform.dart';
import 'sync/coordinator.dart';

Future<void> main() => runBookfin();

Future<void> runBookfin({bool gallery = false}) async {
  WidgetsFlutterBinding.ensureInitialized();
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
  await appearance.restore();
  final downloads = gallery ? null : await createDownloads(MediaPolicy());
  final records = LocalResumeStore(
    openDatabase: !kIsWeb && defaultTargetPlatform == TargetPlatform.android
        ? () => RecordDatabase.open()
        : null,
  );
  final playback = downloads == null
      ? null
      : await createPlayback(downloads, store: records);
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
      downloads: downloads,
      playback: playback,
      reader: reader,
      sync: gallery
          ? null
          : RecordSync(records: records, playback: playback, reader: reader),
    ),
  );
}

class BookfinApp extends StatefulWidget {
  const BookfinApp({
    super.key,
    required this.appearance,
    this.gallery = false,
    this.clock,
    this.catalog,
    this.downloads,
    this.playback,
    this.reader,
    this.sync,
  });

  final AppearanceController appearance;
  final bool gallery;
  final DateTime Function()? clock;
  final CatalogController? catalog;
  final Downloads? downloads;
  final Playback? playback;
  final ReaderSession? reader;
  final RecordSync? sync;

  @override
  State<BookfinApp> createState() => _BookfinAppState();
}

class _BookfinAppState extends State<BookfinApp> with WidgetsBindingObserver {
  AppearanceController get _appearance => widget.appearance;
  Timer? _clock;
  late final CatalogController _catalog;

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
      unawaited(_catalog.restore().then((_) => _catalog.refresh()));
    }
    WidgetsBinding.instance.addObserver(this);
    _catalog.addListener(_syncAccount);
    _syncAccount();
    _appearance.addListener(_refresh);
    _startClock();
  }

  @override
  void didUpdateWidget(BookfinApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.appearance != widget.appearance) {
      oldWidget.appearance.removeListener(_refresh);
      _appearance.addListener(_refresh);
    }
  }

  void _startClock() {
    _clock?.cancel();
    _clock = Timer.periodic(const Duration(seconds: 30), (_) => _refresh());
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void didChangePlatformBrightness() => _refresh();

  @override
  void didChangeAccessibilityFeatures() => _refresh();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.sync?.synchronize());
      unawaited(widget.downloads?.refresh());
      _startClock();
      _refresh();
    } else {
      unawaited(widget.playback?.flush());
      unawaited(widget.reader?.flush());
      _clock?.cancel();
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    _catalog.removeListener(_syncAccount);
    widget.sync?.dispose();
    if (widget.catalog == null) _catalog.dispose();
    _appearance.removeListener(_refresh);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _syncAccount() {
    widget.sync?.bind(_catalog.accessBlocked ? null : _catalog.session);
    if (_catalog.verified) unawaited(widget.sync?.synchronize());
  }

  AppearanceDecision _decision() => resolveAppearance(
    _appearance.settings,
    (widget.clock ?? DateTime.now)(),
    WidgetsBinding.instance.platformDispatcher.platformBrightness,
  );

  @override
  Widget build(BuildContext context) {
    final reduceMotion = WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;
    final decision = _decision();
    final theme = bookfinTheme(decision.brightness, reduceMotion: reduceMotion);
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
      home: widget.gallery
          ? _BookfinHome(
              appearance: _appearance,
              decision: decision,
              gallery: widget.gallery,
              currentDecision: _decision,
            )
          : Builder(
              builder: (context) => CatalogHome(
                catalog: _catalog,
                downloads: widget.downloads,
                playback: widget.playback,
                reader: widget.reader,
                sync: widget.sync,
                onReaderNightChanged: (night) => unawaited(
                  _appearance.selectMode(
                    night ? AppearanceMode.night : AppearanceMode.day,
                  ),
                ),
                onAppearance: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  builder: (_) => _AppearanceSheet(
                    appearance: _appearance,
                    currentDecision: _decision,
                    gallery: false,
                  ),
                ),
              ),
            ),
    );
  }
}

class _BookfinHome extends StatelessWidget {
  const _BookfinHome({
    required this.appearance,
    required this.decision,
    required this.gallery,
    required this.currentDecision,
  });

  final AppearanceController appearance;
  final AppearanceDecision decision;
  final bool gallery;
  final AppearanceDecision Function() currentDecision;

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
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
                  ? AnimationStyle.noAnimation
                  : const AnimationStyle(duration: Duration(milliseconds: 360)),
              builder: (context) => _AppearanceSheet(
                appearance: appearance,
                currentDecision: currentDecision,
                gallery: gallery,
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
                    Text(
                      decision.description,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (appearance.warning != null) Text(appearance.warning!),
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

class _AppearanceSheet extends StatelessWidget {
  const _AppearanceSheet({
    required this.appearance,
    required this.currentDecision,
    required this.gallery,
  });

  final AppearanceController appearance;
  final AppearanceDecision Function() currentDecision;
  final bool gallery;

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
              Text(
                'Appearance',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 16),
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
                      onSelected: (_) => unawaited(appearance.selectMode(mode)),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(currentDecision().description),
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
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => CitySearch(appearance: appearance),
                  ),
                ),
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
                        onPressed: () =>
                            unawaited(appearance.selectLocation(location)),
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
                  onPressed: () => unawaited(appearance.selectLocation(null)),
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
