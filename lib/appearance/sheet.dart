import 'dart:async';

import 'package:flutter/material.dart';

import '../catalog/glass.dart';
import '../catalog/model.dart' show Book;
import '../foundation/theme.dart';
import 'appearance.dart';
import 'city_search.dart';
import 'preferences.dart';

/// Shows the appearance sheet over [context], and makes the choices that it
/// reports: a mode, a city from the offline city search, or no location.
/// [child] adds choices owned by the screen that opens the sheet.
/// The shared glass controller closes the sheet from its title-row action.
Future<void> showAppearance(
  BuildContext context,
  AppearanceController appearance, {
  Book? book,
  Widget? child,
  AnimationStyle? sheetAnimationStyle,
}) => showGlassSheet<void>(
  context,
  book: book,
  title: 'Appearance',
  action: GlassSheetAction('Done', onPressed: () {}),
  isScrollControlled: true,
  sheetAnimationStyle: sheetAnimationStyle,
  builder: (sheet) => AppearanceSheet(
    appearance: appearance,
    child: child,
    onMode: (mode) => unawaited(appearance.selectMode(mode)),
    onChooseCity: () => unawaited(
      Navigator.of(sheet).push<void>(
        MaterialPageRoute(builder: (_) => CitySearch(appearance: appearance)),
      ),
    ),
    onRemoveLocation: () => unawaited(appearance.selectLocation(null)),
  ),
);

/// The appearance choices. It shows what [appearance] holds and reports each choice
/// through its callbacks. It changes nothing itself; [showAppearance] acts.
class AppearanceSheet extends StatelessWidget {
  const AppearanceSheet({
    super.key,
    required this.appearance,
    this.child,
    required this.onMode,
    required this.onChooseCity,
    required this.onRemoveLocation,
  });

  final AppearanceController appearance;

  /// Additional choices supplied by the screen that opens the sheet.
  final Widget? child;

  /// The user chose a mode.
  final ValueChanged<AppearanceMode> onMode;

  /// The user asked to search for a city.
  final VoidCallback onChooseCity;

  /// The user asked to remove the selected location.
  final VoidCallback onRemoveLocation;

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
              ?child,
              if (appearance.settings.location != null)
                TextButton(
                  onPressed: onRemoveLocation,
                  child: const Text('Remove selected location'),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
