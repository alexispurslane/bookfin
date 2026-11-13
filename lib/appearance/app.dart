import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../foundation/theme.dart';
import 'preferences.dart';

/// Registers the bundled fonts and city data used by both app entry points.
void registerAppearanceLicenses() {
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
}

/// Applies Bookfin's theme to [home] and follows platform appearance,
/// accessibility, and foreground changes. The caller owns [appearance].
/// Pages keep their state when only the theme decision changes.
class AppearanceApp extends StatefulWidget {
  const AppearanceApp({
    super.key,
    required this.appearance,
    required this.home,
  });

  final AppearanceController appearance;
  final Widget home;

  @override
  State<AppearanceApp> createState() => _AppearanceAppState();
}

class _AppearanceAppState extends State<AppearanceApp>
    with WidgetsBindingObserver {
  final _reduceMotion = ValueNotifier(_platformReducesMotion());

  static bool _platformReducesMotion() => WidgetsBinding
      .instance
      .platformDispatcher
      .accessibilityFeatures
      .disableAnimations;

  void _showAppearance() => widget.appearance
    ..platformBrightnessChanged(
      WidgetsBinding.instance.platformDispatcher.platformBrightness,
    )
    ..resume();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _showAppearance();
  }

  @override
  void didUpdateWidget(AppearanceApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.appearance != widget.appearance) {
      oldWidget.appearance.suspend();
      _showAppearance();
    }
  }

  @override
  void didChangePlatformBrightness() =>
      widget.appearance.platformBrightnessChanged(
        WidgetsBinding.instance.platformDispatcher.platformBrightness,
      );

  @override
  void didChangeAccessibilityFeatures() =>
      _reduceMotion.value = _platformReducesMotion();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.appearance.resume();
    } else {
      widget.appearance.suspend();
    }
  }

  @override
  void dispose() {
    widget.appearance.suspend();
    _reduceMotion.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.appearance.decision, _reduceMotion]),
    builder: (context, home) {
      final reduceMotion = _reduceMotion.value;
      final theme = bookfinTheme(
        widget.appearance.decision.value.brightness,
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
    child: widget.home,
  );
}
