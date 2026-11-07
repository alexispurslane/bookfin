import 'dart:async';

import 'package:flutter/material.dart';

import '../catalog/glass.dart' show confirmAction;
import '../catalog/controller.dart';
import '../catalog/layout.dart';
import '../catalog/screen.dart' show LibrarySelector;
import '../foundation/theme.dart';
import '../sync/coordinator.dart';
import '../sync/screen.dart';

/// The Settings tab's page. It follows the catalog and the layout.
class SettingsTab extends StatelessWidget {
  const SettingsTab({
    super.key,
    required this.catalog,
    required this.layout,
    required this.onAppearance,
    this.sync,
  });
  final CatalogController catalog;
  final LibraryLayout layout;
  final VoidCallback onAppearance;
  final RecordSync? sync;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([catalog, layout]),
    builder: (context, _) => SettingsPage(
      catalog: catalog,
      layout: layout,
      onAppearance: onAppearance,
      sync: sync,
    ),
  );
}

/// The Settings tab: account, libraries, layout, appearance, and records.
class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.catalog,
    required this.layout,
    required this.onAppearance,
    this.sync,
  });
  final CatalogController catalog;
  final LibraryLayout layout;
  final VoidCallback onAppearance;
  final RecordSync? sync;

  @override
  Widget build(BuildContext context) {
    final session = catalog.session;
    if (session == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final shown = catalog.libraries
        .where(
          (library) => catalog.cache?.selected.contains(library.id) == true,
        )
        .map((library) => library.name)
        .toList();
    return ListView(
      padding: EdgeInsets.fromLTRB(18, 4, 18, 32 + floatingBarInset(context)),
      children: [
        SettingsGroup(
          children: [
            ListTile(
              leading: CircleAvatar(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
                child: Text(
                  session.username.isEmpty
                      ? '?'
                      : session.username.characters.first.toUpperCase(),
                ),
              ),
              title: Text(session.username),
              subtitle: Text(session.scope.server.host),
            ),
            ListTile(
              title: const Text('Sign in to another account'),
              subtitle: const Text('Signs out of this account first'),
              onTap: () => unawaited(catalog.signOut()),
            ),
            ListTile(
              title: const Text('Sign out'),
              onTap: () => unawaited(catalog.signOut()),
            ),
          ],
        ),
        SettingsGroup(
          children: [
            ListTile(
              title: const Text('Libraries'),
              subtitle: Text(
                shown.isEmpty
                    ? 'No libraries shown'
                    : '${shown.join(', ')} · ${shown.length} of ${catalog.libraries.length} shown',
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              enabled: !catalog.busy,
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: const Text('Libraries')),
                    body: BookfinSurface(
                      child: Material(
                        type: MaterialType.transparency,
                        child: LibrarySelector(
                          catalog: catalog,
                          closeOnSave: true,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        SettingsGroup(
          children: [
            ListenableBuilder(
              listenable: layout,
              builder: (context, _) => ListTile(
                title: const Text('Layout density'),
                trailing: DensitySwitch(layout: layout),
              ),
            ),
            ListTile(
              title: const Text('Appearance'),
              subtitle: const Text('Daylight, after sunset, or automatic'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: onAppearance,
            ),
          ],
        ),
        SettingsGroup(
          children: [
            if (sync != null)
              ListTile(
                title: const Text('Personal-record sync'),
                subtitle: const Text('Bookmarks, history, and progress'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => Scaffold(
                      appBar: AppBar(title: const Text('Personal records')),
                      body: BookfinSurface(
                        child: Material(
                          type: MaterialType.transparency,
                          child: ListView(
                            padding: const EdgeInsets.all(20),
                            children: [
                              RecordSyncView(sync: sync!, books: catalog.books),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ListTile(
              title: const Text('Reset catalog corrections'),
              subtitle: const Text(
                'Book links, file groups, order, and details',
              ),
              enabled: catalog.cache != null && !catalog.accessBlocked,
              onTap: () async {
                final account = catalog.session!.scope.key;
                if (await confirmAction(
                  context,
                  title: 'Reset catalog corrections?',
                  message: 'Remove your book links, file groups, file order, and book details for this account. Jellyfin will not change.',
                  action: 'Reset corrections',
                )) {
                  if (catalog.session?.scope.key != account) return;
                  await catalog.resetCorrections();
                }
              },
            ),
            ListTile(
              title: const Text('Software licenses'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () =>
                  showLicensePage(context: context, applicationName: 'Bookfin'),
            ),
          ],
        ),
      ],
    );
  }
}

/// Compact or spacious, as a light track with a white pill on the choice.
class DensitySwitch extends StatelessWidget {
  const DensitySwitch({super.key, required this.layout});
  final LibraryLayout layout;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(99),
    ),
    child: SegmentedButton<LibraryDensity>(
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(value: LibraryDensity.compact, label: Text('Compact')),
        ButtonSegment(value: LibraryDensity.spacious, label: Text('Spacious')),
      ],
      selected: {layout.density},
      onSelectionChanged: (value) => layout.density = value.single,
    ),
  );
}
