import 'package:flutter/material.dart';

import '../appearance/appearance.dart';

/// Sample location and font controls for the development gallery.
/// Choices are reported to the gallery controller.
class AppearanceFixtures extends StatelessWidget {
  const AppearanceFixtures({super.key, required this.onLocation});

  final ValueChanged<SelectedLocation> onLocation;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
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
  );
}
