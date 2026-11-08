import 'dart:async';

import 'package:flutter/material.dart';

import '../catalog/glass.dart' show confirmAction;
import '../catalog/controller.dart';
import '../catalog/layout.dart';
import '../catalog/screen.dart' show LibrarySelector;
import '../foundation/listenable_selector.dart';
import '../foundation/theme.dart';
import '../sync/coordinator.dart';
import '../sync/labels.dart' show waitingChoices;
import '../sync/screen.dart';

/// The Settings tab: account, libraries, layout, appearance, and records.
///
/// It is the controller of the tab. It signs out, opens the pages of the
/// tab, changes the layout density, and confirms and runs the reset of
/// catalog corrections. It follows the catalog's account, and each tile
/// follows only the other signal that it shows.
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
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: catalog.accountNotifier,
    builder: (context, account, _) {
      final session = account.session;
      if (session == null) return const SizedBox.shrink();
      final theme = Theme.of(context);
      final shown = account.libraries
          .where((library) => account.selected.contains(library.id))
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
              ValueListenableBuilder(
                valueListenable: catalog.statusNotifier,
                builder: (context, status, _) => ListTile(
                  title: const Text('Libraries'),
                  subtitle: Text(
                    shown.isEmpty
                        ? 'No libraries shown'
                        : '${shown.join(', ')} · ${shown.length} of ${account.libraries.length} shown',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  enabled: !status.refreshing,
                  onTap: () => _openLibraries(context),
                ),
              ),
            ],
          ),
          SettingsGroup(
            children: [
              ListenableSelector(
                listenable: layout,
                select: () => layout.density,
                builder: (context, density, _) => ListTile(
                  title: const Text('Layout density'),
                  trailing: DensitySwitch(
                    density: density,
                    onChanged: (density) => layout.density = density,
                  ),
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
              if (sync case final sync?)
                ListTile(
                  title: const Text('Personal-record sync'),
                  subtitle: ListenableSelector(
                    listenable: Listenable.merge([
                      sync.conflictsNotifier,
                      catalog.libraryNotifier,
                    ]),
                    select: () => waitingChoices(
                      sync.conflicts,
                      catalog.libraryNotifier.value.books,
                    ),
                    builder: (context, waiting, _) => waiting == null
                        ? const Text('Bookmarks, history, and progress')
                        : _WaitingLine(waiting),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _openRecords(context, sync),
                ),
              // The cache appears together with a new library and goes
              // together with the session, so this tile follows both.
              ValueListenableBuilder(
                valueListenable: catalog.libraryNotifier,
                builder: (context, _, _) => ListTile(
                  title: const Text('Reset catalog corrections'),
                  subtitle: const Text(
                    'Book links, file groups, order, and details',
                  ),
                  enabled: catalog.cache != null && !account.accessBlocked,
                  onTap: () => _resetCorrections(context, session.scope.key),
                ),
              ),
              ListTile(
                title: const Text('Software licenses'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'Bookfin',
                ),
              ),
            ],
          ),
        ],
      );
    },
  );

  /// Opens the Personal records page with the covers of the tab.
  void _openRecords(BuildContext context, RecordSync sync) {
    final scope = InheritedTheme.capture(
      from: context,
      to: Navigator.of(context).context,
    );
    unawaited(
      Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => scope.wrap(
            RecordSyncPage(sync: sync, library: catalog.libraryNotifier),
          ),
        ),
      ),
    );
  }

  void _openLibraries(BuildContext context) => Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Libraries')),
        body: BookfinSurface(
          child: Material(
            type: MaterialType.transparency,
            child: LibrarySelector(catalog: catalog, closeOnSave: true),
          ),
        ),
      ),
    ),
  );

  /// Resets the corrections of [account] after the user confirms, unless
  /// another account signed in meanwhile.
  Future<void> _resetCorrections(BuildContext context, String account) async {
    if (await confirmAction(
      context,
      title: 'Reset catalog corrections?',
      message: 'Remove your book links, file groups, file order, and book details for this account. Jellyfin will not change.',
      action: 'Reset corrections',
    )) {
      if (catalog.session?.scope.key != account) return;
      await catalog.resetCorrections();
    }
  }
}

/// Compact or spacious, as a light track with a white pill on the choice.
/// It shows [density] and reports the user's choice through [onChanged].
class DensitySwitch extends StatelessWidget {
  const DensitySwitch({
    super.key,
    required this.density,
    required this.onChanged,
  });
  final LibraryDensity density;
  final ValueChanged<LibraryDensity> onChanged;

  @override
  Widget build(BuildContext context) => PillChoice<LibraryDensity>(
    segments: const [
      ButtonSegment(value: LibraryDensity.compact, label: Text('Compact')),
      ButtonSegment(value: LibraryDensity.spacious, label: Text('Spacious')),
    ],
    selected: density,
    onChanged: onChanged,
  );
}

/// The copper line of the Personal-record sync row while a choice waits,
/// for example "A choice waits · First Frost".
class _WaitingLine extends StatelessWidget {
  const _WaitingLine(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final copper = Theme.of(context).colorScheme.tertiary;
    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          margin: const EdgeInsets.only(right: 6),
          decoration: BoxDecoration(shape: BoxShape.circle, color: copper),
        ),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: copper, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}
