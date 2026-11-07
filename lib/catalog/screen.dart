import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../foundation/theme.dart';
import '../downloads/downloads.dart';
import '../downloads/screen.dart';
import '../playback/playback.dart';
import '../playback/screen.dart';
import '../reader/session.dart';
import '../settings/screen.dart';
import '../sync/coordinator.dart';
import 'book_cover.dart';
import 'controller.dart';
import 'covers.dart';
import 'jellyfin.dart';
import 'layout.dart';
import 'library_services.dart';
import 'library_view.dart';
import 'model.dart';
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
  int _bindingGeneration = 0;

  /// The account and books last handed to Downloads, Playback and the reader.
  JellyfinSession? _boundSession;
  List<Book>? _boundBooks;

  LibraryServices get _services => LibraryServices(
    catalog: _catalog,
    layout: _layout,
    onReaderNightChanged: widget.onReaderNightChanged,
    covers: widget.covers,
    downloads: widget.downloads,
    playback: widget.playback,
    reader: widget.reader,
  );

  @override
  void initState() {
    super.initState();
    _accountKey = _catalog.session?.scope.key;
    _lastAccessBlocked = _catalog.accessBlocked;
    _catalog.addListener(_accessChanged);
    _bindDownloads();
  }

  @override
  void didUpdateWidget(CatalogHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.catalog != _catalog) {
      oldWidget.catalog.removeListener(_accessChanged);
      _catalog.addListener(_accessChanged);
      _accessChanged();
    }
    if (oldWidget.downloads != widget.downloads ||
        oldWidget.playback != widget.playback ||
        oldWidget.reader != widget.reader) {
      _bindDownloads();
    }
  }

  @override
  void dispose() {
    _catalog.removeListener(_accessChanged);
    _ownLayout.dispose();
    super.dispose();
  }

  void _accessChanged() {
    // The catalog replaces its session and book list when either changes, so
    // identity shows whether this notice changed what the services hold.
    if (!identical(_boundSession, _visibleSession) ||
        !identical(_boundBooks, _catalog.books)) {
      if (_accountKey != _catalog.session?.scope.key ||
          _catalog.accessBlocked) {
        unawaited(widget.playback?.bind(null, []));
        unawaited(widget.reader?.bind(null, []));
      }
      _bindDownloads();
    }
    final key = _catalog.session?.scope.key;
    if (key == _accountKey && _lastAccessBlocked == _catalog.accessBlocked) {
      return;
    }
    final dismiss = key != _accountKey || _catalog.accessBlocked;
    _accountKey = key;
    _lastAccessBlocked = _catalog.accessBlocked;
    _tab = _Tab.library;
    if (mounted && dismiss) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  JellyfinSession? get _visibleSession =>
      _catalog.accessBlocked ? null : _catalog.session;

  void _bindDownloads() {
    final session = _boundSession = _visibleSession;
    final books = _boundBooks = _catalog.books;
    final downloads = widget.downloads;
    if (downloads != null) {
      final generation = ++_bindingGeneration;
      final readingBinding = widget.reader?.bind(session, books);
      unawaited(() async {
        await downloads.bind(session, books);
        if (!mounted || generation != _bindingGeneration) return;
        await widget.playback?.bind(session, books);
        if (!mounted || generation != _bindingGeneration) return;
        await readingBinding;
      }());
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      _catalog,
      _layout,
      if (widget.downloads != null) widget.downloads!,
      if (widget.playback != null) widget.playback!,
    ]),
    builder: (context, _) {
      final signedIn = _catalog.session != null;
      final tab = signedIn ? _tab : _Tab.library;
      final choosing =
          signedIn &&
          (_catalog.cache == null || _catalog.cache!.selected.isEmpty);
      final services = _services;
      return CoverScope(
        covers: widget.covers,
        session: _catalog.accessBlocked ? null : _catalog.session,
        playing: widget.playback?.book,
        child: Scaffold(
          // Pages scroll beneath the floating mini player.
          extendBody: true,
          // An open book's player draws its own stage up to the status bar.
          appBar: tab == _Tab.listening && widget.playback?.book != null
              ? null
              : AppBar(
                  title: Text(switch (tab) {
                    _ when !signedIn => 'Bookfin',
                    _Tab.library => 'Library',
                    _Tab.downloads => 'Downloads',
                    _Tab.listening => 'Listening',
                    _Tab.settings => 'Settings',
                  }),
                  actions: [
                    if (tab == _Tab.library && signedIn && !choosing) ...[
                      IconButton(
                        tooltip: 'Search',
                        onPressed: () => openSearch(context, services),
                        icon: const Icon(Icons.search_rounded),
                      ),
                      LayoutToggle(layout: _layout),
                      const SizedBox(width: 8),
                    ],
                    if (!signedIn)
                      IconButton(
                        tooltip: 'Appearance',
                        onPressed: widget.onAppearance,
                        icon: const Icon(Icons.contrast_rounded),
                      ),
                  ],
                ),
          bottomNavigationBar: !signedIn
              ? null
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.playback != null && tab != _Tab.listening)
                      // The navigation bar below keeps the system inset.
                      MediaQuery.removePadding(
                        context: context,
                        removeBottom: true,
                        child: PlaybackMiniPlayer(
                          playback: widget.playback!,
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
                            enabled: widget.playback != null,
                            icon: const Icon(Icons.headphones_outlined),
                            selectedIcon: const Icon(Icons.headphones_rounded),
                            label: 'Listening',
                          ),
                          const NavigationDestination(
                            icon: Icon(Icons.settings_outlined),
                            selectedIcon: Icon(Icons.settings_rounded),
                            label: 'Settings',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
          body: SafeArea(
            top: false,
            bottom: false,
            child: BookfinSurface(
              child: Material(
                type: MaterialType.transparency,
                child: Column(
                  children: [
                    if (_catalog.busy)
                      const LinearProgressIndicator(minHeight: 2),
                    if (_catalog.message != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                        child: Text(
                          _catalog.message!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    if (widget.playback?.message != null &&
                        tab != _Tab.listening)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                        child: Text(widget.playback!.message!),
                      ),
                    if (widget.playback != null && tab != _Tab.listening)
                      ReplacementStartNotice(playback: widget.playback!),
                    Expanded(
                      child: !signedIn
                          ? _SignInForm(catalog: _catalog)
                          : switch (tab) {
                              _Tab.downloads => DownloadsPage(
                                downloads: widget.downloads,
                                books: _catalog.books,
                                compact:
                                    _layout.density == LibraryDensity.compact,
                                onOpen: (context, book) =>
                                    openBook(context, services, book),
                              ),
                              _Tab.listening when widget.playback != null =>
                                PlayerView(
                                  playback: widget.playback!,
                                  onOpenBook: (book) =>
                                      openBook(context, services, book),
                                ),
                              _Tab.settings => SettingsPage(
                                catalog: _catalog,
                                layout: _layout,
                                onAppearance: widget.onAppearance,
                                sync: widget.sync,
                              ),
                              _ when choosing => LibrarySelector(
                                key: ValueKey(_catalog.session!.scope.key),
                                catalog: _catalog,
                              ),
                              _ => LibraryShelf(
                                key: ValueKey(_catalog.session!.scope.key),
                                services: services,
                              ),
                            },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
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
  Widget build(BuildContext context) => ListView(
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
  );
}

class LibrarySelector extends StatefulWidget {
  const LibrarySelector({
    super.key,
    required this.catalog,
    this.closeOnSave = false,
  });
  final CatalogController catalog;
  final bool closeOnSave;
  @override
  State<LibrarySelector> createState() => _LibrarySelectorState();
}

class _LibrarySelectorState extends State<LibrarySelector> {
  late final Set<String> _selected = {...?widget.catalog.cache?.selected}
    ..retainAll(widget.catalog.libraries.map((library) => library.id));
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.catalog,
    builder: (context, _) => ListView(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + floatingBarInset(context)),
      children: [
        Text(
          'Choose book libraries',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 16),
        for (final library in widget.catalog.libraries)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(library.name),
            value: _selected.contains(library.id),
            onChanged: widget.catalog.busy
                ? null
                : (value) => setState(() {
                    if (value == true) {
                      _selected.add(library.id);
                    } else {
                      _selected.remove(library.id);
                    }
                  }),
          ),
        if (widget.catalog.libraries.isEmpty && !widget.catalog.busy)
          const Text('No book libraries are available to this account.'),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: widget.catalog.busy || widget.catalog.libraries.isEmpty
              ? null
              : () async {
                  await widget.catalog.refresh(selected: _selected);
                  if (context.mounted &&
                      widget.closeOnSave &&
                      widget.catalog.message == null) {
                    Navigator.pop(context);
                  }
                },
          child: const Text('Save libraries'),
        ),
        TextButton(
          onPressed: widget.catalog.busy
              ? widget.catalog.cancel
              : () => unawaited(widget.catalog.refresh()),
          child: Text(
            widget.catalog.busy ? 'Cancel refresh' : 'Refresh libraries',
          ),
        ),
        if (widget.closeOnSave && widget.catalog.message != null)
          Text(widget.catalog.message!),
      ],
    ),
  );
}
