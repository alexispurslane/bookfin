import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'appearance/appearance.dart';
import 'appearance/preferences.dart';
import 'development/gallery.dart';
import 'foundation/theme.dart';

Future<void> main() => runBookfin();

Future<void> runBookfin({bool gallery = false}) async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    for (final font in ['Outfit', 'Source-Serif-4']) {
      yield LicenseEntryWithLineBreaks([
        font,
      ], await rootBundle.loadString('assets/fonts/OFL-$font.txt'));
    }
  });
  final appearance = AppearanceController(LocalAppearanceStore());
  await appearance.restore();
  runApp(BookfinApp(appearance: appearance, gallery: gallery));
}

class BookfinApp extends StatefulWidget {
  const BookfinApp({
    super.key,
    required this.appearance,
    this.gallery = false,
    this.clock,
  });

  final AppearanceController appearance;
  final bool gallery;
  final DateTime Function()? clock;

  @override
  State<BookfinApp> createState() => _BookfinAppState();
}

class _BookfinAppState extends State<BookfinApp> with WidgetsBindingObserver {
  AppearanceController get _appearance => widget.appearance;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
      _startClock();
      _refresh();
    } else {
      _clock?.cancel();
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    _appearance.removeListener(_refresh);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
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
      home: _BookfinHome(
        appearance: _appearance,
        decision: decision,
        gallery: widget.gallery,
        currentDecision: _decision,
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
              if (gallery) ...[
                Text(
                  'Development location fixtures',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Sample cities for testing only. No device location is requested. Production location input awaits a product decision.',
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
              ] else
                const Text(
                  'Location selection is not available in this foundation build. No device location is requested.',
                ),
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
