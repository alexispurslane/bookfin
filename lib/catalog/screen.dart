import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../foundation/listenable_selector.dart';
import '../foundation/theme.dart';
import '../downloads/downloads.dart';
import '../downloads/screen.dart';
import '../playback/playback.dart';
import '../playback/screen.dart';
import '../crossings/crossings.dart';
import '../reader/session.dart';
import '../settings/screen.dart';
import '../sync/alert.dart' show ChoicesBadge;
import '../sync/coordinator.dart';
import 'controller.dart';
import 'covers.dart';
import 'jellyfin.dart';
import 'layout.dart';
import 'library_services.dart';
import 'library_view.dart';
import 'book_page.dart' show openBook;

class CatalogHome extends StatefulWidget {
  const CatalogHome({
    super.key,
    required this.catalog,
    required this.onAppearance,
    required this.onReaderNightChanged,
    this.layout,
    this.covers,
    this.downloads,
    this.playback,
    this.reader,
    this.crossings,
    this.sync,
  });
  final CatalogController catalog;
  final VoidCallback onAppearance;
  final ValueChanged<bool> onReaderNightChanged;

  /// The saved library layout. Without one, the layout lasts for this run.
  final LibraryLayout? layout;
  final Covers? covers;
  final Downloads? downloads;
  final Playback? playback;
  final ReaderSession? reader;
  final Crossings? crossings;
  final RecordSync? sync;
  @override
  State<CatalogHome> createState() => _CatalogHomeState();
}

class _MemoryLayoutStore implements LayoutStore {
  String? _value;
  @override
  Future<String?> read() async => _value;
  @override
  Future<void> write(String value) async => _value = value;
}

/// The tabs of the bottom navigation, in order.
enum _Tab { library, downloads, listening, settings }

class _CatalogHomeState extends State<CatalogHome> {
  _Tab _tab = _Tab.library;
  CatalogController get _catalog => widget.catalog;
  late final LibraryLayout _ownLayout = LibraryLayout(_MemoryLayoutStore());
  LibraryLayout get _layout => widget.layout ?? _ownLayout;
  String? _accountKey;
  bool _lastAccessBlocked = false;

  LibraryServices get _services => LibraryServices(
    catalog: _catalog,
    layout: _layout,
    onReaderNightChanged: widget.onReaderNightChanged,
    covers: widget.covers,
    downloads: widget.downloads,
    playback: widget.playback,
    reader: widget.reader,
    crossings: widget.crossings,
  );

  @override
  void initState() {
    super.initState();
    _accountKey = _catalog.session?.scope.key;
    _lastAccessBlocked = _catalog.accessBlocked;
    _catalog.addListener(_accessChanged);
  }

  @override
  void didUpdateWidget(CatalogHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.catalog != _catalog) {
      oldWidget.catalog.removeListener(_accessChanged);
      _catalog.addListener(_accessChanged);
      _accessChanged();
    }
  }

  @override
  void dispose() {
    _catalog.removeListener(_accessChanged);
    _ownLayout.dispose();
    super.dispose();
  }

  /// A new account or blocked access returns to the Library tab. Either one
  /// also closes the pages above the shell, which showed the old account's
  /// books. [AccountBinding] hands the new account to the sources.
  void _accessChanged() {
    final key = _catalog.session?.scope.key;
    if (key == _accountKey && _lastAccessBlocked == _catalog.accessBlocked) {
      return;
    }
    final dismiss = key != _accountKey || _catalog.accessBlocked;
    _accountKey = key;
    _lastAccessBlocked = _catalog.accessBlocked;
    if (mounted) setState(() => _tab = _Tab.library);
    if (mounted && dismiss) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  /// The shell builds only the frame of the app: the navigation, and the tab
  /// or sign-in screen in it. It rebuilds when the tab changes, the user
  /// signs in or out, or a restore learns whether an account is saved. Every
  /// part inside listens to the state that it shows.
  ///
  /// While a restore reads the saved credentials, the shell shows only the
  /// page surface: the person may be signed in, so the sign-in form would be
  /// wrong, and its Cancel would sign the person out.
  @override
  Widget build(BuildContext context) => ListenableSelector(
    listenable: _catalog.accountNotifier,
    select: () {
      final account = _catalog.accountNotifier.value;
      return (
        signedIn: account.session != null,
        unknown: account.session == null && account.restoring,
      );
    },
    builder: (context, shell, _) {
      if (shell.unknown) return const BookfinSurface(child: SizedBox.expand());
      final signedIn = shell.signedIn;
      final tab = signedIn ? _tab : _Tab.library;
      final services = _services;
      final playback = widget.playback;
      return services.pageScope(
        Scaffold(
          // Pages scroll beneath the floating mini player.
          extendBody: true,
          bottomNavigationBar: !signedIn
              ? null
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (playback != null && tab != _Tab.listening)
                      // The navigation bar below keeps the system inset.
                      MediaQuery.removePadding(
                        context: context,
                        removeBottom: true,
                        child: PlaybackMiniPlayer(
                          playback: playback,
                          onOpenBook: (book) =>
                              openBook(context, services, book),
                        ),
                      ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                      ),
                      child: NavigationBar(
                        selectedIndex: tab.index,
                        onDestinationSelected: (value) =>
                            setState(() => _tab = _Tab.values[value]),
                        destinations: [
                          const NavigationDestination(
                            icon: Icon(Icons.auto_stories_outlined),
                            selectedIcon: Icon(Icons.auto_stories),
                            label: 'Library',
                          ),
                          const NavigationDestination(
                            icon: Icon(Icons.download_outlined),
                            selectedIcon: Icon(Icons.download_rounded),
                            label: 'Downloads',
                          ),
                          NavigationDestination(
                            enabled: playback != null,
                            icon: const Icon(Icons.headphones_outlined),
                            selectedIcon: const Icon(Icons.headphones_rounded),
                            label: 'Listening',
                          ),
                          NavigationDestination(
                            icon: _choices(const Icon(Icons.settings_outlined)),
                            selectedIcon: _choices(
                              const Icon(Icons.settings_rounded),
                            ),
                            label: 'Settings',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
          body: switch (tab) {
            _ when !signedIn => TabFrame(
              bar: AppBar(
                title: const Text('Bookfin'),
                actions: [
                  IconButton(
                    tooltip: 'Appearance',
                    onPressed: widget.onAppearance,
                    icon: const Icon(Icons.contrast_rounded),
                  ),
                ],
              ),
              child: TabPage(
                catalog: _catalog,
                playback: playback,
                child: _SignInForm(catalog: _catalog),
              ),
            ),
            _Tab.downloads => TabFrame(
              bar: AppBar(title: const Text('Downloads')),
              child: TabPage(
                catalog: _catalog,
                playback: playback,
                child: DownloadsTab(services: services),
              ),
            ),
            _Tab.listening when playback != null => ListenableSelector(
              listenable: playback,
              select: () => playback.book != null,
              // An open book's player draws its own stage up to the status
              // bar.
              builder: (context, open, page) => TabFrame(
                bar: open ? null : AppBar(title: const Text('Listening')),
                child: page!,
              ),
              child: TabPage(
                catalog: _catalog,
                child: PlayerView(
                  playback: playback,
                  onOpenBook: (book) => openBook(context, services, book),
                ),
              ),
            ),
            _Tab.settings => TabFrame(
              bar: AppBar(title: const Text('Settings')),
              child: TabPage(
                catalog: _catalog,
                playback: playback,
                child: SettingsTab(
                  catalog: _catalog,
                  layout: _layout,
                  onAppearance: widget.onAppearance,
                  sync: widget.sync,
                ),
              ),
            ),
            _ => LibraryTab(services: services),
          },
        ),
      );
    },
  );

  /// [icon] with the count of the choices that wait in record sync.
  Widget _choices(Widget icon) => switch (widget.sync) {
    final sync? => ChoicesBadge(conflicts: sync.conflictsNotifier, child: icon),
    null => icon,
  };
}

/// A tab below its top [bar]. Without a bar, the tab reaches up to the
/// status bar, as an open book's player does.
class TabFrame extends StatelessWidget {
  const TabFrame({super.key, required this.bar, required this.child});
  final PreferredSizeWidget? bar;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (bar case final bar?)
        // The height that a Scaffold gives its app bar.
        SizedBox(
          height: bar.preferredSize.height + MediaQuery.paddingOf(context).top,
          child: bar,
        ),
      Expanded(
        child: MediaQuery.removePadding(
          context: context,
          removeTop: bar != null,
          child: child,
        ),
      ),
    ],
  );
}

/// What a signed-in catalog says while it cannot reach Jellyfin. The shelf
/// then shows only downloaded books.
const _unreachable = 'Cannot reach Jellyfin. Showing downloaded books.';

/// The catalog's progress, its offline notice and its message, above every
/// tab's page. It is the one place where the app shows the state of a
/// catalog refresh, and the controller of that surface: its Retry action
/// refreshes the catalog.
class _CatalogStatus extends StatelessWidget {
  const _CatalogStatus({required this.catalog});
  final CatalogController catalog;

  @override
  Widget build(BuildContext context) => ListenableSelector(
    listenable: Listenable.merge([
      catalog.statusNotifier,
      catalog.accountNotifier,
    ]),
    select: () {
      final status = catalog.statusNotifier.value;
      return (
        refreshing: status.refreshing,
        restoring: catalog.accountNotifier.value.restoring,
        offline:
            status.reach == CatalogReach.unreachable &&
            catalog.accountNotifier.value.session != null,
        message: status.message,
      );
    },
    builder: (context, status, _) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _SlowProgressLine(running: status.refreshing || status.restoring),
        if (status.offline)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 8, 2),
            child: Row(
              children: [
                const Expanded(child: StatusMessage(_unreachable)),
                TextButton(
                  onPressed: status.refreshing
                      ? null
                      : () => unawaited(catalog.refresh(byUser: true)),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        if (status.message case final message?)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: StatusMessage(message),
          ),
      ],
    ),
  );
}

/// A thin progress line for work that is [running], shown only after the
/// work ran for [_delay]. Shorter work shows nothing, so a fast background
/// refresh does not flash.
class _SlowProgressLine extends StatefulWidget {
  const _SlowProgressLine({required this.running});
  final bool running;

  static const _delay = Duration(milliseconds: 1500);

  @override
  State<_SlowProgressLine> createState() => _SlowProgressLineState();
}

class _SlowProgressLineState extends State<_SlowProgressLine> {
  Timer? _timer;
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    _follow();
  }

  @override
  void didUpdateWidget(_SlowProgressLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.running != widget.running) _follow();
  }

  /// Hides the line, and starts the delay again while the work runs.
  void _follow() {
    _timer?.cancel();
    _timer = null;
    _shown = false;
    if (widget.running) {
      _timer = Timer(
        _SlowProgressLine._delay,
        () => setState(() => _shown = true),
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _shown
      ? const LinearProgressIndicator(minHeight: 2)
      : const SizedBox.shrink();
}

/// A tab's page: catalog progress and errors, the player's notices when
/// [playback] is given, then [child].
class TabPage extends StatelessWidget {
  const TabPage({
    super.key,
    required this.catalog,
    this.playback,
    required this.child,
  });
  final CatalogController catalog;
  final Playback? playback;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final playback = this.playback;
    return SafeArea(
      top: false,
      bottom: false,
      child: BookfinSurface(
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            children: [
              _CatalogStatus(catalog: catalog),
              if (playback != null) ...[
                ListenableSelector(
                  listenable: playback,
                  select: () => playback.message,
                  builder: (context, message, _) => message == null
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                          child: StatusMessage(message),
                        ),
                ),
                ReplacementStartNotice(playback: playback),
              ],
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

class _SignInForm extends StatefulWidget {
  const _SignInForm({required this.catalog});
  final CatalogController catalog;
  @override
  State<_SignInForm> createState() => _SignInFormState();
}

class _SignInFormState extends State<_SignInForm> {
  final _form = GlobalKey<FormState>();
  final _server = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  @override
  void dispose() {
    _server.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate() || widget.catalog.busy) return;
    FocusScope.of(context).unfocus();
    await widget.catalog.connect(_server.text, _username.text, _password.text);
    if (!mounted) return;
    // A password manager offers to save only a login that worked.
    TextInput.finishAutofillContext(shouldSave: widget.catalog.session != null);
    _password.clear();
  }

  @override
  // The form shows the catalog's progress and its sign-in errors.
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.catalog,
    builder: (context, _) => ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Your library starts here.',
          style: Theme.of(context).textTheme.displaySmall,
        ),
        const SizedBox(height: 24),
        Form(
          key: _form,
          child: AutofillGroup(
            child: Column(
              children: [
                TextFormField(
                  controller: _server,
                  enabled: !widget.catalog.busy,
                  keyboardType: TextInputType.url,
                  autofillHints: const [AutofillHints.url],
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Server address',
                    hintText: 'https://jellyfin.example',
                  ),
                  validator: (value) {
                    try {
                      parseServer(value ?? '');
                      return null;
                    } on CatalogFailure catch (error) {
                      return error.message;
                    }
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _username,
                  enabled: !widget.catalog.busy,
                  autofillHints: const [AutofillHints.username],
                  autocorrect: false,
                  decoration: const InputDecoration(labelText: 'Username'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter your username.'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _password,
                  enabled: !widget.catalog.busy,
                  obscureText: true,
                  autofillHints: const [AutofillHints.password],
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(labelText: 'Password'),
                  onFieldSubmitted: (_) => unawaited(_submit()),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: widget.catalog.busy ? null : _submit,
                  child: const Text('Sign in'),
                ),
                if (widget.catalog.busy)
                  TextButton(
                    onPressed: () => unawaited(widget.catalog.signOut()),
                    child: const Text('Cancel'),
                  ),
              ],
            ),
          ),
        ),
        if (widget.catalog.message?.contains('Secure sign-out') == true)
          TextButton(
            onPressed: () => unawaited(widget.catalog.signOut()),
            child: const Text('Retry sign-out'),
          ),
      ],
    ),
  );
}

/// The Libraries page of Settings, and the controller of that screen: a
/// tick box for each book library of the account. A ticked library shows,
/// and an unticked one is hidden. Every book library shows until the user
/// hides it, including one that Jellyfin adds later. Save libraries
/// refreshes the catalog with the unticked libraries hidden, and closes the
/// page when the refresh succeeds.
class LibrarySelector extends StatefulWidget {
  const LibrarySelector({super.key, required this.catalog});
  final CatalogController catalog;
  @override
  State<LibrarySelector> createState() => _LibrarySelectorState();
}

class _LibrarySelectorState extends State<LibrarySelector> {
  /// The ids of the libraries that are unticked on this page. Only Save
  /// libraries hides them.
  late final Set<String> _hidden = {
    ...widget.catalog.accountNotifier.value.hidden,
  };

  Future<void> _save() async {
    final catalog = widget.catalog;
    final saved = await catalog.setHiddenLibraries({..._hidden});
    if (mounted && saved) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = widget.catalog;
    return ListenableBuilder(
      listenable: Listenable.merge([
        catalog.accountNotifier,
        catalog.statusNotifier,
      ]),
      builder: (context, _) {
        final libraries = catalog.accountNotifier.value.libraries;
        final status = catalog.statusNotifier.value;
        final busy = catalog.busy;
        return ListView(
          padding: EdgeInsets.fromLTRB(
            24,
            24,
            24,
            24 + floatingBarInset(context),
          ),
          children: [
            Text(
              'Book libraries to show',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Bookfin shows every book library on your server, including '
              'new ones. Untick a library to hide it.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            for (final library in libraries)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(library.name),
                value: !_hidden.contains(library.id),
                onChanged: busy
                    ? null
                    : (shown) => setState(() {
                        if (shown == true) {
                          _hidden.remove(library.id);
                        } else {
                          _hidden.add(library.id);
                        }
                      }),
              ),
            if (libraries.isEmpty && !busy)
              const Text('No book libraries are available to this account.'),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: busy || libraries.isEmpty
                  ? null
                  : () => unawaited(_save()),
              child: const Text('Save libraries'),
            ),
            TextButton(
              onPressed: busy
                  ? catalog.cancel
                  : () => unawaited(catalog.refresh(byUser: true)),
              child: Text(busy ? 'Cancel refresh' : 'Refresh libraries'),
            ),
            if (status.message ??
                    (status.reach == CatalogReach.unreachable
                        ? _unreachable
                        : null)
                case final message?)
              Text(message),
          ],
        );
      },
    );
  }
}
