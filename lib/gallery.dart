import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'appearance/app.dart';
import 'appearance/preferences.dart';
import 'appearance/sheet.dart';
import 'development/appearance.dart';
import 'development/gallery.dart';
import 'foundation/theme.dart';

/// Starts the development gallery with appearance preferences only.
/// Its screens own their sample state and never open real media or accounts.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerAppearanceLicenses();
  final appearance = AppearanceController(LocalAppearanceStore());
  await appearance.restore();
  runApp(GalleryApp(appearance: appearance));
}

/// Composes the sample screens with the app's real appearance behavior.
/// The caller owns [appearance], just as it does for the production root.
class GalleryApp extends StatelessWidget {
  const GalleryApp({super.key, required this.appearance});

  final AppearanceController appearance;

  @override
  Widget build(BuildContext context) => AppearanceApp(
    appearance: appearance,
    home: _GalleryHome(appearance: appearance),
  );
}

class _GalleryHome extends StatelessWidget {
  const _GalleryHome({required this.appearance});

  final AppearanceController appearance;

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
                child: AppearanceFixtures(
                  onLocation: (location) =>
                      unawaited(appearance.selectLocation(location)),
                ),
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
      body: const SafeArea(
        top: false,
        child: BookfinSurface(child: DevelopmentGallery()),
      ),
    ),
  );
}
