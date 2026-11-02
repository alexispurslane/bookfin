import 'dart:async';

import 'package:flutter/material.dart';

import '../foundation/theme.dart';
import '../downloads/downloads.dart';
import '../downloads/screen.dart';
import '../playback/playback.dart';
import '../playback/screen.dart';
import 'controller.dart';
import 'jellyfin.dart';
import 'model.dart';

class CatalogHome extends StatefulWidget {
  const CatalogHome({
    super.key,
    required this.catalog,
    required this.onAppearance,
    this.downloads,
    this.playback,
  });
  final CatalogController catalog;
  final VoidCallback onAppearance;
  final Downloads? downloads;
  final Playback? playback;
  @override
  State<CatalogHome> createState() => _CatalogHomeState();
}

class _CatalogHomeState extends State<CatalogHome> {
  String _query = '';
  String _filter = 'All';
  int _destination = 0;
  CatalogController get _catalog => widget.catalog;
  String? _accountKey;
  bool _lastAccessBlocked = false;
  int _bindingGeneration = 0;

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
        oldWidget.playback != widget.playback) {
      _bindDownloads();
    }
  }

  @override
  void dispose() {
    _catalog.removeListener(_accessChanged);
    super.dispose();
  }

  void _accessChanged() {
    if (_accountKey != _catalog.session?.scope.key || _catalog.accessBlocked) {
      unawaited(widget.playback?.bind(null, []));
    }
    _bindDownloads();
    final key = _catalog.session?.scope.key;
    if (key == _accountKey && _lastAccessBlocked == _catalog.accessBlocked) {
      return;
    }
    final dismiss = key != _accountKey || _catalog.accessBlocked;
    _accountKey = key;
    _lastAccessBlocked = _catalog.accessBlocked;
    _query = '';
    _filter = 'All';
    _destination = 0;
    if (mounted && dismiss) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  void _bindDownloads() {
    final downloads = widget.downloads;
    if (downloads != null) {
      final generation = ++_bindingGeneration;
      final session = _catalog.accessBlocked ? null : _catalog.session;
      final books = _catalog.books;
      unawaited(() async {
        await downloads.bind(session, books);
        if (!mounted || generation != _bindingGeneration) return;
        await widget.playback?.bind(session, books);
      }());
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      _catalog,
      if (widget.downloads != null) widget.downloads!,
      if (widget.playback != null) widget.playback!,
    ]),
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: Text('BOOKFIN', style: Theme.of(context).textTheme.labelSmall),
        actions: [
          if (_catalog.session != null)
            IconButton(
              tooltip: 'Book libraries',
              onPressed: _catalog.busy ? null : () => _libraries(context),
              icon: const Icon(Icons.library_books_outlined),
            ),
          IconButton(
            tooltip: 'Appearance',
            onPressed: widget.onAppearance,
            icon: const Icon(Icons.contrast_rounded),
          ),
          if (_catalog.session != null)
            IconButton(
              tooltip: 'Account',
              onPressed: () => _account(context),
              icon: const Icon(Icons.person_outline_rounded),
            ),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.playback != null && _destination != 2)
            PlaybackMiniPlayer(playback: widget.playback!),
          NavigationBar(
            selectedIndex: _destination,
            onDestinationSelected: (value) =>
                setState(() => _destination = value),
            destinations: [
              NavigationDestination(
                icon: Icon(Icons.local_library_outlined),
                selectedIcon: Icon(Icons.local_library_rounded),
                label: 'Library',
              ),
              NavigationDestination(
                enabled: _catalog.session != null,
                icon: Icon(Icons.download_outlined),
                label: 'Downloads',
              ),
              NavigationDestination(
                enabled: widget.playback != null && _catalog.session != null,
                icon: Icon(Icons.headphones_outlined),
                label: 'Listening',
              ),
            ],
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
                if (_catalog.busy) const LinearProgressIndicator(minHeight: 2),
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
                if (widget.playback?.message != null && _destination != 2)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                    child: Text(widget.playback!.message!),
                  ),
                Expanded(
                  child: _catalog.session == null
                      ? _SignInForm(catalog: _catalog)
                      : _destination == 1
                      ? DownloadsPage(
                          downloads: widget.downloads,
                          books: _catalog.books,
                        )
                      : _catalog.cache == null ||
                            _catalog.cache!.selected.isEmpty
                      ? _LibrarySelector(
                          key: ValueKey(_catalog.session!.scope.key),
                          catalog: _catalog,
                        )
                      : _destination == 2 && widget.playback != null
                      ? PlayerView(playback: widget.playback!)
                      : _library(context),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _library(BuildContext context) {
    final filtered = _catalog.books.where((book) {
      final matches = '${book.title} ${book.author} ${book.series ?? ''}'
          .toLowerCase()
          .contains(_query.toLowerCase());
      final kind = _filter == 'Audio' ? EditionKind.audio : EditionKind.text;
      return matches &&
          (_filter == 'All' ||
              _filter == 'Downloaded' &&
                  book.editions.any(
                    (edition) =>
                        edition.kind == EditionKind.audio &&
                        widget.downloads?.status(edition).phase ==
                            DownloadPhase.downloaded,
                  ) ||
              _filter == 'Series' && book.series != null ||
              (_filter == 'Audio' || _filter == 'Ebooks') &&
                  book.editions.any((edition) => edition.kind == kind));
    }).toList();
    if (_filter == 'Series') {
      filtered.sort((left, right) {
        final series = left.series!.compareTo(right.series!);
        return series != 0
            ? series
            : (left.seriesOrder ?? double.infinity).compareTo(
                right.seriesOrder ?? double.infinity,
              );
      });
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      'A little further\ninto the story.',
                      style: Theme.of(context).textTheme.displaySmall,
                    ),
                  ),
                  IconButton(
                    tooltip: _catalog.busy ? 'Cancel refresh' : 'Refresh books',
                    onPressed: _catalog.busy
                        ? _catalog.cancel
                        : () => unawaited(_catalog.refresh()),
                    icon: Icon(
                      _catalog.busy ? Icons.close : Icons.refresh_rounded,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                key: ValueKey('search:${_catalog.session!.scope.key}'),
                decoration: const InputDecoration(
                  labelText: 'Search books and authors',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final filter in [
                      'All',
                      'Audio',
                      'Ebooks',
                      'Downloaded',
                      'Series',
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(filter),
                          selected: _filter == filter,
                          onSelected: (_) => setState(() => _filter = filter),
                        ),
                      ),
                  ],
                ),
              ),
              if (!_catalog.verified && _catalog.cache?.completedAt != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Saved library · ${_catalog.cache!.completedAt!.toLocal().toString().split('.').first}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    _catalog.accessBlocked
                        ? 'Choose available book libraries to continue.'
                        : _filter == 'Series'
                        ? 'No series yet.'
                        : 'No books found.',
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final book = filtered[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: BookfinPanel(
                        child: InkWell(
                          onTap: () => Navigator.push<void>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => _BookPage(
                                catalog: _catalog,
                                bookId: book.id,
                                downloads: widget.downloads,
                                playback: widget.playback,
                              ),
                            ),
                          ),
                          borderRadius: BorderRadius.circular(16),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 56,
                                  height: 78,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHigh,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    book.editions.any(
                                          (edition) =>
                                              edition.kind == EditionKind.audio,
                                        )
                                        ? Icons.headphones_rounded
                                        : Icons.menu_book_rounded,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (book.series != null)
                                        Text(
                                          '${book.series}${book.seriesOrder == null ? '' : ' · ${_order(book.seriesOrder!)}'}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall,
                                        ),
                                      Text(
                                        book.title,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge,
                                      ),
                                      if (book.author.isNotEmpty)
                                        Text(book.author),
                                      const SizedBox(height: 6),
                                      Text(
                                        _editionSummary(book),
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                      for (final kind in EditionKind.values)
                                        if (book.editions.any(
                                          (edition) => edition.kind == kind,
                                        ))
                                          Text(
                                            bookAvailability(
                                              book,
                                              kind,
                                              widget.downloads,
                                            ),
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall,
                                          ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.chevron_right_rounded),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _libraries(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => FractionallySizedBox(
      heightFactor: 0.85,
      child: _LibrarySelector(catalog: _catalog, closeOnSave: true),
    ),
  );

  Future<void> _account(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    builder: (context) => Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Account', style: Theme.of(context).textTheme.headlineSmall),
          Text(_catalog.session!.username),
          Text(_catalog.session!.scope.server.toString()),
          const SizedBox(height: 20),
          TextButton(
            onPressed: _catalog.cache == null || _catalog.accessBlocked
                ? null
                : () async {
                    final account = _catalog.session!.scope.key;
                    if (await _confirm(
                      context,
                      'Reset catalog corrections?',
                      'Remove your book links, file groups, file order, and book details for this account. Jellyfin will not change.',
                      'Reset corrections',
                    )) {
                      if (_catalog.session?.scope.key != account) return;
                      await _catalog.resetCorrections();
                      if (context.mounted && _catalog.message == null) {
                        Navigator.pop(context);
                      }
                    }
                  },
            child: const Text('Reset catalog corrections'),
          ),
          OutlinedButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _query = '';
                _filter = 'All';
              });
              unawaited(_catalog.signOut());
            },
            child: const Text('Sign out'),
          ),
        ],
      ),
    ),
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
    final password = _password.text;
    _password.clear();
    FocusScope.of(context).unfocus();
    await widget.catalog.connect(_server.text, _username.text, password);
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
        child: Column(
          children: [
            TextFormField(
              controller: _server,
              enabled: !widget.catalog.busy,
              keyboardType: TextInputType.url,
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
      if (widget.catalog.message?.contains('Secure sign-out') == true)
        TextButton(
          onPressed: () => unawaited(widget.catalog.signOut()),
          child: const Text('Retry sign-out'),
        ),
    ],
  );
}

class _LibrarySelector extends StatefulWidget {
  const _LibrarySelector({
    super.key,
    required this.catalog,
    this.closeOnSave = false,
  });
  final CatalogController catalog;
  final bool closeOnSave;
  @override
  State<_LibrarySelector> createState() => _LibrarySelectorState();
}

class _LibrarySelectorState extends State<_LibrarySelector> {
  late final Set<String> _selected = {...?widget.catalog.cache?.selected}
    ..retainAll(widget.catalog.libraries.map((library) => library.id));
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.catalog,
    builder: (context, _) => ListView(
      padding: const EdgeInsets.all(24),
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

class _BookPage extends StatelessWidget {
  const _BookPage({
    required this.catalog,
    required this.bookId,
    this.downloads,
    this.playback,
  });
  final CatalogController catalog;
  final String bookId;
  final Downloads? downloads;
  final Playback? playback;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([catalog, ?downloads, ?playback]),
    builder: (context, _) {
      final matches = catalog.books.where((book) => book.id == bookId);
      if (matches.isEmpty) {
        return Scaffold(
          appBar: AppBar(),
          body: const Center(
            child: Text('This book is not in the current library.'),
          ),
        );
      }
      final book = matches.single;
      return Scaffold(
        bottomNavigationBar: playback == null
            ? null
            : PlaybackMiniPlayer(playback: playback!),
        appBar: AppBar(
          title: const Text('Book details'),
          actions: [
            IconButton(
              tooltip: 'Correct book details',
              onPressed: () => _correct(context, book),
              icon: const Icon(Icons.edit_outlined),
            ),
          ],
        ),
        body: BookfinSurface(
          child: Material(
            type: MaterialType.transparency,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  book.title,
                  style: Theme.of(context).textTheme.headlineLarge
                      ?.copyWith(fontFamily: 'Source Serif 4'),
                ),
                if (book.author.isNotEmpty) Text(book.author),
                if (book.series != null)
                  Text(
                    '${book.series}${book.seriesOrder == null ? '' : ' · ${_order(book.seriesOrder!)}'}',
                  ),
                if (catalog.message != null) Text(catalog.message!),
                const SizedBox(height: 24),
                for (final kind in EditionKind.values)
                  if (book.editions.any((edition) => edition.kind == kind)) ...[
                    Text(
                      kind == EditionKind.audio
                          ? 'Audio editions'
                          : 'Ebook editions',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    for (final edition in book.editions.where(
                      (edition) => edition.kind == kind,
                    ))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: BookfinPanel(
                          child: Material(
                            type: MaterialType.transparency,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  edition.label,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                Text(
                                  '${edition.files.length} ${edition.files.length == 1 ? 'file' : 'files'}',
                                ),
                                DownloadControls(
                                  downloads: downloads,
                                  edition: edition,
                                ),
                                if (kind == EditionKind.audio &&
                                    playback != null)
                                  FilledButton.icon(
                                    onPressed: () async {
                                      await playback!.open(book, edition);
                                      if (context.mounted &&
                                          playback!.edition == edition) {
                                        openPlayer(context, playback!);
                                      }
                                    },
                                    icon: const Icon(Icons.play_arrow_rounded),
                                    label: const Text('Listen'),
                                  ),
                                if (playback?.message != null)
                                  Text(playback!.message!),
                                if (edition.files.length > 1)
                                  TextButton(
                                    onPressed: () =>
                                        _orderFiles(context, edition),
                                    child: const Text('Correct file order'),
                                  ),
                                for (final file in edition.files)
                                  ExpansionTile(
                                    tilePadding: EdgeInsets.zero,
                                    title: Text(file.displayName),
                                    subtitle: Text(
                                      file.durationMs == null
                                          ? file.container.toUpperCase()
                                          : '${(file.durationMs! / 60000).toStringAsFixed(1)} minutes',
                                    ),
                                    children: [
                                      ListTile(
                                        title: const Text('Jellyfin item'),
                                        subtitle: SelectableText(file.itemId),
                                      ),
                                      ListTile(
                                        title: const Text('Media source'),
                                        subtitle: SelectableText(
                                          file.mediaSourceId.isEmpty
                                              ? 'Not provided by Jellyfin'
                                              : file.mediaSourceId,
                                        ),
                                      ),
                                      for (final chapter in file.chapters)
                                        ListTile(
                                          title: Text(chapter.name),
                                          trailing: Text(
                                            _time(chapter.startMs),
                                          ),
                                        ),
                                      TextButton(
                                        onPressed: () async {
                                          if (await _confirm(
                                            context,
                                            'Separate this source?',
                                            'This source becomes a separate book. Its Jellyfin item will not change.',
                                            'Separate',
                                          )) {
                                            await catalog.separateEdition(
                                              file.key,
                                            );
                                          }
                                        },
                                        child: const Text('Separate source'),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => _link(context, book),
                  child: const Text('Link another book or ebook'),
                ),
                if (book.editions
                        .where((edition) => edition.kind == EditionKind.audio)
                        .length >
                    1)
                  OutlinedButton(
                    onPressed: () => _combine(context, book),
                    child: const Text('Combine files of one recording'),
                  ),
                if (possibleMatches(book, catalog.books).isNotEmpty)
                  Text(
                    '${possibleMatches(book, catalog.books).length} possible ${possibleMatches(book, catalog.books).length == 1 ? 'match' : 'matches'} · Confirmation required',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );

  Future<void> _correct(BuildContext context, Book book) async {
    final result = await showDialog<BookDetails>(
      context: context,
      builder: (_) => _BookCorrection(book: book),
    );
    if (result != null &&
        catalog.books.any((candidate) => candidate.id == book.id)) {
      await catalog.correctBook(book.id, result);
    }
  }

  Future<void> _link(BuildContext context, Book book) async {
    final candidate = await showModalBottomSheet<Book>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _BookPicker(book: book, books: catalog.books),
    );
    if (candidate == null || !context.mounted) return;
    if (await _confirm(
      context,
      'Link editions?',
      'Keep “${candidate.title}” by ${candidate.author.isEmpty ? 'an unknown author' : candidate.author} as the book details. Recordings and ebook editions stay separate. Jellyfin will not change.',
      'Link editions',
    )) {
      if (!catalog.books.any((candidate) => candidate.id == book.id) ||
          !catalog.books.any((book) => book.id == candidate.id)) {
        return;
      }
      await catalog.linkBooks(book.id, candidate.id);
      if (context.mounted && catalog.message == null) Navigator.pop(context);
    }
  }

  Future<void> _combine(BuildContext context, Book book) async {
    final selected = await showDialog<List<String>>(
      context: context,
      builder: (_) => _RecordingPicker(book: book),
    );
    if (selected == null || !context.mounted) return;
    if (await _confirm(
      context,
      'Combine as one recording?',
      'Use this only for consecutive files of the same recording, not different narrators or abridged versions. You can correct the file order afterward.',
      'Combine files',
    )) {
      try {
        await catalog.combineAudio(book.id, selected);
      } on ArgumentError {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Choose different source items, not alternate versions of the same file.',
              ),
            ),
          );
        }
      }
    }
  }

  Future<void> _orderFiles(BuildContext context, Edition edition) async {
    final keys = await showModalBottomSheet<List<String>>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => _FileOrder(edition: edition),
    );
    if (keys != null &&
        catalog.books
            .expand((book) => book.editions)
            .any((candidate) => candidate.id == edition.id)) {
      await catalog.orderFiles(edition.id, keys);
    }
  }
}

Future<bool> _confirm(
  BuildContext context,
  String title,
  String message,
  String action,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

class _BookCorrection extends StatefulWidget {
  const _BookCorrection({required this.book});
  final Book book;
  @override
  State<_BookCorrection> createState() => _BookCorrectionState();
}

class _BookCorrectionState extends State<_BookCorrection> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.book.title);
  late final _author = TextEditingController(text: widget.book.author);
  late final _series = TextEditingController(text: widget.book.series);
  late final _position = TextEditingController(
    text: widget.book.seriesOrder == null
        ? ''
        : _order(widget.book.seriesOrder!),
  );
  @override
  void dispose() {
    for (final controller in [_title, _author, _series, _position]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Correct book details'),
    content: SingleChildScrollView(
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Title'),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Enter a title.'
                  : null,
            ),
            TextFormField(
              controller: _author,
              decoration: const InputDecoration(labelText: 'Author'),
            ),
            TextFormField(
              controller: _series,
              decoration: const InputDecoration(labelText: 'Series'),
            ),
            TextFormField(
              controller: _position,
              decoration: const InputDecoration(
                labelText: 'Series position',
                hintText: '1.5',
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? null
                  : double.tryParse(value)?.isFinite != true ||
                        _series.text.trim().isEmpty
                  ? 'Enter a number and a series name.'
                  : null,
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.pop(
              context,
              BookDetails(
                title: _title.text.trim(),
                author: _author.text.trim(),
                series: _series.text.trim().isEmpty
                    ? null
                    : _series.text.trim(),
                seriesOrder: double.tryParse(_position.text),
              ),
            );
          }
        },
        child: const Text('Save correction'),
      ),
    ],
  );
}

class _BookPicker extends StatefulWidget {
  const _BookPicker({required this.book, required this.books});
  final Book book;
  final List<Book> books;
  @override
  State<_BookPicker> createState() => _BookPickerState();
}

class _BookPickerState extends State<_BookPicker> {
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final suggested = possibleMatches(
      widget.book,
      widget.books,
    ).map((book) => book.id).toSet();
    final books =
        widget.books
            .where(
              (book) =>
                  book.id != widget.book.id &&
                  '${book.title} ${book.author}'.toLowerCase().contains(
                    _query.toLowerCase(),
                  ),
            )
            .toList()
          ..sort(
            (left, right) =>
                suggested.contains(left.id) == suggested.contains(right.id)
                ? left.title.compareTo(right.title)
                : suggested.contains(left.id)
                ? -1
                : 1,
          );
    return FractionallySizedBox(
      heightFactor: 0.85,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Link editions',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            TextField(
              decoration: const InputDecoration(labelText: 'Search for a book'),
              onChanged: (value) => setState(() => _query = value),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: books.length,
                itemBuilder: (context, index) => ListTile(
                  title: Text(books[index].title),
                  subtitle: Text(
                    '${books[index].author}${suggested.contains(books[index].id) ? ' · Possible match' : ''}',
                  ),
                  onTap: () => Navigator.pop(context, books[index]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordingPicker extends StatefulWidget {
  const _RecordingPicker({required this.book});
  final Book book;
  @override
  State<_RecordingPicker> createState() => _RecordingPickerState();
}

class _RecordingPickerState extends State<_RecordingPicker> {
  final _selected = <String>{};
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Files of one recording'),
    content: SizedBox(
      width: 400,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final edition in widget.book.editions.where(
              (edition) => edition.kind == EditionKind.audio,
            ))
              CheckboxListTile(
                title: Text(edition.label),
                subtitle: Text(
                  edition.files.map((file) => file.displayName).join(', '),
                ),
                value: _selected.contains(edition.id),
                onChanged: (value) => setState(() {
                  if (value == true) {
                    _selected.add(edition.id);
                  } else {
                    _selected.remove(edition.id);
                  }
                }),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _selected.length < 2
            ? null
            : () => Navigator.pop(context, _selected.toList()),
        child: const Text('Continue'),
      ),
    ],
  );
}

class _FileOrder extends StatefulWidget {
  const _FileOrder({required this.edition});
  final Edition edition;
  @override
  State<_FileOrder> createState() => _FileOrderState();
}

class _FileOrderState extends State<_FileOrder> {
  late final _files = widget.edition.files.toList();
  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    heightFactor: 0.85,
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Text(
            'Correct file order',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _files.length,
              itemBuilder: (context, index) => ListTile(
                title: Text('${index + 1}. ${_files[index].displayName}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Move file up',
                      onPressed: index == 0
                          ? null
                          : () => setState(() {
                              final file = _files.removeAt(index);
                              _files.insert(index - 1, file);
                            }),
                      icon: const Icon(Icons.arrow_upward_rounded),
                    ),
                    IconButton(
                      tooltip: 'Move file down',
                      onPressed: index == _files.length - 1
                          ? null
                          : () => setState(() {
                              final file = _files.removeAt(index);
                              _files.insert(index + 1, file);
                            }),
                      icon: const Icon(Icons.arrow_downward_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, _files.map((file) => file.key).toList()),
            child: const Text('Save file order'),
          ),
        ],
      ),
    ),
  );
}

String _order(double order) => order == order.truncateToDouble()
    ? order.toInt().toString()
    : order.toString();
String _time(int milliseconds) {
  final seconds = milliseconds ~/ 1000;
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

String _editionSummary(Book book) {
  final audio = book.editions
      .where((edition) => edition.kind == EditionKind.audio)
      .length;
  final text = book.editions.length - audio;
  return [
    if (audio > 0) '$audio audio ${audio == 1 ? 'edition' : 'editions'}',
    if (text > 0) '$text ${text == 1 ? 'ebook' : 'ebooks'}',
  ].join(' · ');
}
