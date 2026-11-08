import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../downloads/downloads.dart' show DownloadAction, Downloads;
import '../foundation/listenable_selector.dart';
import '../downloads/screen.dart';
import '../foundation/theme.dart';
import '../foundation/time.dart';
import '../playback/screen.dart';
import '../playback/timeline.dart';
import '../reader/screen.dart';
import 'book_cover.dart';
import 'controller.dart';
import 'library_services.dart';
import 'library_view.dart';
import 'model.dart';
import 'shelf.dart';
import 'glass.dart';

void openBook(BuildContext context, LibraryServices services, Book book) =>
    unawaited(
      Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => services.coverScope(
            BookPage(services: services, bookId: book.id),
          ),
        ),
      ),
    );

/// The details of one book: its cover, facts, actions, and editions.
///
/// The page is the controller of everything on it. It follows the catalog's
/// library, so it shows refreshes and corrections while open, and finds its
/// book, series and possible matches through the library's indexes. Each
/// part below follows only its own state: the cover its download state, the
/// actions and progress the book's activity, each edition panel its own
/// download, and the status lines their messages. The parts report taps,
/// and the page opens the player and the reader, asks before a change, and
/// tells the catalog, Playback or Downloads what to do.
class BookPage extends StatelessWidget {
  const BookPage({super.key, required this.services, required this.bookId});
  final LibraryServices services;
  final String bookId;

  CatalogController get catalog => services.catalog;

  @override
  Widget build(BuildContext context) => ListenableSelector(
    listenable: catalog.libraryNotifier,
    select: () {
      final library = catalog.libraryNotifier.value;
      final book = library.book(bookId);
      return (
        book: book,
        series: book == null ? null : library.seriesOf(book),
        matches: book == null ? 0 : library.matches(book).length,
      );
    },
    builder: (context, found, _) => switch (found.book) {
      null => Scaffold(
        appBar: AppBar(),
        body: const Center(
          child: Text('This book is not in the current library.'),
        ),
      ),
      final book => PageBook(
        // Sheets, dialogs, menus and messages opened here are about this
        // book, so the actions below use the context inside it.
        book: book,
        child: Builder(
          builder: (context) =>
              _page(context, book, found.series, found.matches),
        ),
      ),
    },
  );

  Widget _page(
    BuildContext context,
    Book book,
    ShelfSeries? series,
    int matches,
  ) {
    final theme = Theme.of(context);
    final playback = services.playback;
    final reader = services.reader;
    final downloads = services.downloads;
    final audio = book.editions
        .where((edition) => edition.kind == EditionKind.audio)
        .toList();
    final text = book.editions
        .where((edition) => edition.kind == EditionKind.text)
        .toList();
    final formats = {
      for (final edition in text)
        for (final file in edition.files)
          if (file.container.isNotEmpty) file.container.toUpperCase(),
    };
    final narrator = audio
        .map((edition) => edition.narrator)
        .nonNulls
        .firstOrNull;
    final activity = services.bookActivity(book);
    return services.page(
      context,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        actions: [
          GlassMenuButton(
            tooltip: 'More actions',
            icon: const Icon(Icons.more_horiz_rounded),
            items: [
              GlassMenuItem(
                'Correct book details',
                onSelected: () => unawaited(_correct(context, book)),
              ),
              GlassMenuItem(
                'Link another book or ebook',
                onSelected: () => unawaited(_link(context, book)),
              ),
              if (audio.length > 1)
                GlassMenuItem(
                  'Combine files of one recording',
                  onSelected: () => unawaited(_combine(context, book)),
                ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.only(bottom: floatingBarInset(context)),
        children: [
          ListenableSelector(
            listenable: Listenable.merge([
              if (downloads != null)
                for (final edition in book.editions) downloads.watch(edition),
            ]),
            select: () => services.downloaded(book),
            builder: (context, downloaded, _) =>
                _Header(book: book, downloaded: downloaded),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const SizedBox(height: 18),
                Text(
                  book.title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Source Serif 4',
                    fontSize: 28,
                    height: 1.12,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.3,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  [
                    if (book.author.isNotEmpty) book.author,
                    if (narrator != null) 'read by $narrator',
                  ].join(' · '),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (book.series != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: TextButton(
                      onPressed: series == null
                          ? null
                          : () => openSeries(context, services, series),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      child: Text(
                        [
                              book.series!,
                              if (book.seriesOrder != null)
                                'Book ${seriesPosition(book.seriesOrder!)}',
                            ].join(' · ') +
                            (series != null ? '  ›' : ''),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
                const SizedBox(height: 14),
                // The edition to listen to changes when listening starts on
                // another one, not on each position tick.
                ListenableSelector(
                  listenable: activity,
                  select: () => _listening(audio),
                  builder: (context, listening, _) {
                    final audioMs = listening.edition == null
                        ? null
                        : _length(listening.edition!);
                    final reading = text.firstOrNull;
                    return Column(
                      children: [
                        _Facts(
                          facts: [
                            if (audioMs != null) (duration(audioMs), 'audio'),
                            if (formats.isNotEmpty)
                              (formats.join(' + '), 'ebook')
                            else if (text.isNotEmpty)
                              ('Ebook', 'edition'),
                            if (book.year != null)
                              ('${book.year}', 'published'),
                          ],
                        ),
                        const SizedBox(height: 18),
                        BookActions(
                          listening: listening.edition,
                          reading: reading,
                          resume: listening.resume,
                          downloads: downloads,
                          starting: playback?.startingNotifier,
                          onListen: playback == null
                              ? null
                              : (edition) =>
                                    unawaited(_listen(context, book, edition)),
                          onRead: reader == null
                              ? null
                              : (edition) => _read(context, book, edition),
                          onDownload: (edition, action) =>
                              _download(context, edition, action),
                        ),
                      ],
                    );
                  },
                ),
                ListenableSelector(
                  listenable: activity,
                  select: () => services.progress(book),
                  builder: (context, progress, _) =>
                      progress == null || progress.totalMs <= 0
                      ? const SizedBox.shrink()
                      : _Progress(
                          progress: progress,
                          onHistory: playback == null
                              ? null
                              : () => openListeningTimeline(
                                  context,
                                  playback,
                                  book: book,
                                ),
                        ),
                ),
                _StatusLine(
                  catalog.statusNotifier,
                  () => catalog.statusNotifier.value.message,
                ),
                if (playback != null) ...[
                  _StatusLine(
                    playback.statusNotifier,
                    () => playback.statusNotifier.value.message,
                  ),
                  // The replacement offer has no narrow signal, so this
                  // follows every change of Playback and rebuilds only when
                  // the offer comes or goes for this book.
                  ListenableSelector(
                    listenable: playback,
                    select: () => playback.replacementStart?.book.id == bookId,
                    builder: (_, offered, _) => offered
                        ? ReplacementStartNotice(
                            playback: playback,
                            onStarted: () => openPlayer(context, playback),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
          if (book.description != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
              child: _Description(text: book.description!),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
            child: _Metadata(
              rows: [
                if (book.genres.isNotEmpty) ('Genre', book.genres.join(', ')),
                if (book.publisher != null) ('Publisher', book.publisher!),
                if (_files(book).isNotEmpty) ('Files', _files(book)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionLabel('EDITIONS'),
                const SizedBox(height: 10),
                for (final edition in book.editions)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _editionPanel(
                      context,
                      book,
                      edition,
                      // The main actions above already open the only
                      // edition of a kind.
                      choice: switch (edition.kind) {
                        EditionKind.audio => audio.length > 1,
                        EditionKind.text => text.length > 1,
                      },
                    ),
                  ),
                if (matches > 0)
                  Text(
                    '$matches possible ${matches == 1 ? 'match' : 'matches'} · Confirmation required',
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _editionPanel(
    BuildContext context,
    Book book,
    Edition edition, {
    required bool choice,
  }) {
    final playback = services.playback;
    final reader = services.reader;
    final audio = edition.kind == EditionKind.audio;
    return EditionPanel(
      edition: edition,
      downloads: services.downloads,
      starting: playback?.startingNotifier,
      onListen: choice && audio && playback != null
          ? () => unawaited(_listen(context, book, edition))
          : null,
      onRead: choice && !audio && reader != null
          ? () => _read(context, book, edition)
          : null,
      onOrderFiles: () => unawaited(_orderFiles(context, edition)),
      onSeparate: (file) => unawaited(_separate(context, file)),
      onDownload: (action) => _download(context, edition, action),
    );
  }

  /// The audio edition that Listen opens: the first one with listening
  /// progress, or else the first one. [resume] says whether it has progress.
  ({Edition? edition, bool resume}) _listening(List<Edition> audio) {
    final playback = services.playback;
    for (final edition in audio) {
      if (playback?.progress(edition) != null) {
        return (edition: edition, resume: true);
      }
    }
    return (edition: audio.firstOrNull, resume: false);
  }

  /// Opens [edition] in the player, then shows the player when it opened.
  /// A second tap while [edition] starts does nothing.
  Future<void> _listen(BuildContext context, Book book, Edition edition) async {
    final playback = services.playback!;
    if (playback.starting?.id == edition.id) return;
    await playback.open(book, edition);
    if (context.mounted && playback.edition == edition) {
      openPlayer(context, playback);
    }
  }

  /// Opens [edition] in the reader and shows the reader screen.
  void _read(BuildContext context, Book book, Edition edition) {
    final reader = services.reader!;
    unawaited(reader.open(book, edition));
    unawaited(
      Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => ReaderScreen(
            reader: reader,
            onNightChanged: services.onReaderNightChanged,
            playback: services.playback,
          ),
        ),
      ),
    );
  }

  void _download(BuildContext context, Edition edition, DownloadAction action) {
    final downloads = services.downloads;
    if (downloads != null) changeDownload(context, downloads, edition, action);
  }

  /// The book of this page in the current library, or null when it left.
  Book? get _current => catalog.libraryNotifier.value.book(bookId);

  /// Asks before [file] becomes a separate book, and separates it after a
  /// yes, while it is still a source of this book.
  Future<void> _separate(BuildContext context, SourceFile file) async {
    if (!await confirmAction(
      context,
      title: 'Separate this source?',
      message: 'This source becomes a separate book. Its Jellyfin item will not change.',
      action: 'Separate',
    )) {
      return;
    }
    if (_current?.editions.any(
          (edition) => edition.memberIds.contains(file.key),
        ) ==
        true) {
      await catalog.separateEdition(file.key);
    }
  }

  Future<void> _orderFiles(BuildContext context, Edition edition) async {
    final keys = await showGlassSheet<List<String>>(
      context,
      title: 'Correct file order',
      isScrollControlled: true,
      builder: (_) => _FileOrder(edition: edition),
    );
    if (keys != null &&
        _current?.editions.any((candidate) => candidate.id == edition.id) ==
            true) {
      await catalog.orderFiles(edition.id, keys);
    }
  }

  Future<void> _correct(BuildContext context, Book book) async {
    final result = await showDialog<BookDetails>(
      context: context,
      builder: (_) => _BookCorrection(book: book),
    );
    if (result != null && _current != null) {
      await catalog.correctBook(book.id, result);
    }
  }

  Future<void> _link(BuildContext context, Book book) async {
    final candidate = await showGlassSheet<Book>(
      context,
      title: 'Link editions',
      isScrollControlled: true,
      builder: (_) =>
          _BookPicker(book: book, library: catalog.libraryNotifier.value),
    );
    if (candidate == null || !context.mounted) return;
    if (await confirmAction(
      context,
      title: 'Link editions?',
      message:
          'Keep “${candidate.title}” by ${candidate.author.isEmpty ? 'an unknown author' : candidate.author} as the book details. Recordings and ebook editions stay separate. Jellyfin will not change.',
      action: 'Link editions',
    )) {
      final library = catalog.libraryNotifier.value;
      if (library.book(book.id) == null || library.book(candidate.id) == null) {
        return;
      }
      await catalog.linkBooks(book.id, candidate.id);
      if (context.mounted && catalog.statusNotifier.value.message == null) {
        Navigator.pop(context);
      }
    }
  }

  Future<void> _combine(BuildContext context, Book book) async {
    final selected = await showDialog<List<String>>(
      context: context,
      builder: (_) => _RecordingPicker(book: book),
    );
    if (selected == null || !context.mounted) return;
    if (await confirmAction(
      context,
      title: 'Combine as one recording?',
      message: 'Use this only for consecutive files of the same recording, not different narrators or abridged versions. You can correct the file order afterward.',
      action: 'Combine files',
    )) {
      try {
        await catalog.combineAudio(book.id, selected);
      } on ArgumentError {
        if (context.mounted) {
          showGlassMessage(
            context,
            'Choose different source items, not alternate versions of the same file.',
          );
        }
      }
    }
  }
}

/// Total length of an edition, or null when a file length is unknown.
int? _length(Edition edition) =>
    edition.files.any((file) => file.durationMs == null)
    ? null
    : edition.files.fold<int>(0, (total, file) => total + file.durationMs!);

/// For example "M4B 412 MB · EPUB 2 MB".
String _files(Book book) => [
  for (final edition in book.editions)
    if (edition.files.isNotEmpty &&
        edition.files.every((file) => file.sizeBytes != null))
      [
        edition.files.first.container.toUpperCase(),
        formatBytes(
          edition.files.fold<int>(0, (total, file) => total + file.sizeBytes!),
        ),
      ].where((part) => part.isNotEmpty).join(' '),
].join(' · ');

class _Header extends StatelessWidget {
  const _Header({required this.book, required this.downloaded});
  final Book book;
  final bool downloaded;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;
    return SizedBox(
      height: top + 250,
      child: Stack(
        children: [
          Positioned.fill(child: CoverBackdrop(book: book)),
          Positioned(
            top: top,
            left: 0,
            right: 0,
            child: Center(
              child: StageCover(book: book, width: 156, downloaded: downloaded),
            ),
          ),
        ],
      ),
    );
  }
}

class _Facts extends StatelessWidget {
  const _Facts({required this.facts});
  final List<(String, String)> facts;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IntrinsicHeight(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final (index, (value, label)) in facts.indexed) ...[
            if (index > 0)
              VerticalDivider(
                width: 1,
                color: theme.colorScheme.outlineVariant,
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The main actions: listen or resume, read, and download. It reports each
/// tap with its edition and causes nothing itself.
class BookActions extends StatelessWidget {
  const BookActions({
    super.key,
    required this.listening,
    required this.reading,
    required this.resume,
    required this.downloads,
    required this.onListen,
    required this.onRead,
    required this.onDownload,
    this.starting,
  });

  /// The edition that Playback starts, which Listen follows to show a
  /// progress ring while [listening] starts. Null without playback.
  final ValueListenable<Edition?>? starting;

  /// The audio edition that Listen opens, or null without one.
  final Edition? listening;

  /// The ebook edition that Read opens, or null without one.
  final Edition? reading;

  /// Whether [listening] has listening progress, so Listen says Resume.
  final bool resume;

  /// What the round download button follows for its edition, or null
  /// without downloads.
  final Downloads? downloads;

  /// Reports a tap on Listen or Resume. Null disables the button.
  final ValueChanged<Edition>? onListen;

  /// Reports a tap on Read. Null disables the button.
  final ValueChanged<Edition>? onRead;

  /// Reports a tap on the download button: the edition and its action.
  final void Function(Edition edition, DownloadAction action) onDownload;

  @override
  Widget build(BuildContext context) {
    final listening = this.listening;
    final reading = this.reading;
    final listen = listening == null || onListen == null
        ? null
        : () => onListen!(listening);
    final read = reading == null || onRead == null
        ? null
        : () => onRead!(reading);
    final saved = listening ?? reading;
    final downloads = this.downloads;
    return Row(
      children: [
        if (listening != null)
          Expanded(
            child: FilledButton.icon(
              onPressed: listen,
              icon: _ListenIcon(starting: starting, edition: listening),
              label: Text(resume ? 'Resume' : 'Listen'),
            ),
          ),
        if (reading != null) ...[
          if (listening != null) const SizedBox(width: 8),
          listening == null
              ? Expanded(
                  child: FilledButton.icon(
                    onPressed: read,
                    icon: const Icon(Icons.menu_book_outlined),
                    label: const Text('Read'),
                  ),
                )
              : FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .surfaceContainer,
                    foregroundColor: Theme.of(context).colorScheme.onSurface,
                  ),
                  onPressed: read,
                  icon: const Icon(Icons.menu_book_outlined),
                  label: const Text('Read'),
                ),
        ],
        if (saved != null && downloads != null && downloads.supported) ...[
          const SizedBox(width: 8),
          DownloadButton(
            downloads: downloads,
            edition: saved,
            onAction: (action) => onDownload(saved, action),
          ),
        ],
      ],
    );
  }
}

/// How far the listening of the book is, with the way to its history.
class _Progress extends StatelessWidget {
  const _Progress({required this.progress, required this.onHistory});
  final ({int elapsedMs, int totalMs}) progress;

  /// Reports a tap on History. Null hides the button.
  final VoidCallback? onHistory;

  @override
  Widget build(BuildContext context) {
    final (:elapsedMs, :totalMs) = progress;
    return Column(
      children: [
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Text(
                totalMs - elapsedMs < 60000
                    ? 'Finished'
                    : '${(elapsedMs * 100 / totalMs).floor()}% · ${duration(totalMs - elapsedMs)} left',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            if (onHistory != null)
              TextButton(
                onPressed: onHistory,
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: const Text('History', style: TextStyle(fontSize: 12)),
              ),
          ],
        ),
        const SizedBox(height: 4),
        ProgressLine(value: elapsedMs / totalMs),
      ],
    );
  }
}

/// The message that [message] reads after [listenable] notifies, or nothing
/// without one. It rebuilds only when the message changes.
class _StatusLine extends StatelessWidget {
  const _StatusLine(this.listenable, this.message);
  final Listenable listenable;
  final String? Function() message;

  @override
  Widget build(BuildContext context) => ListenableSelector(
    listenable: listenable,
    select: message,
    builder: (context, message, _) => message == null
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: 12),
            child: StatusMessage(message),
          ),
  );
}

class _Description extends StatefulWidget {
  const _Description({required this.text});
  final String text;
  @override
  State<_Description> createState() => _DescriptionState();
}

class _DescriptionState extends State<_Description> {
  bool _open = false;
  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: 'Source Serif 4',
      fontSize: 16,
      height: 1.6,
      color: Theme.of(context).colorScheme.onSurface,
    );
    return LayoutBuilder(
      builder: (context, size) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: 5,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: size.maxWidth);
        final long = painter.didExceedMaxLines;
        painter.dispose();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.text,
              style: style,
              maxLines: _open ? null : 5,
              overflow: _open ? null : TextOverflow.fade,
            ),
            if (long)
              TextButton(
                onPressed: () => setState(() => _open = !_open),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(48, 40),
                  alignment: Alignment.centerLeft,
                  textStyle: const TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: Text(_open ? 'Less' : 'More'),
              ),
          ],
        );
      },
    );
  }
}

class _Metadata extends StatelessWidget {
  const _Metadata({required this.rows});
  final List<(String, String)> rows;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        const Divider(),
        for (final (label, value) in rows) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 96,
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    value,
                    textAlign: TextAlign.end,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
        ],
      ],
    );
  }
}

/// The icon of a Listen button: a progress ring while [edition] starts.
class _ListenIcon extends StatelessWidget {
  const _ListenIcon({required this.starting, required this.edition});
  final ValueListenable<Edition?>? starting;
  final Edition edition;

  @override
  Widget build(BuildContext context) {
    final starting = this.starting;
    if (starting == null) return const PlayStateIcon();
    return ValueListenableBuilder(
      valueListenable: starting,
      builder: (context, value, _) =>
          PlayStateIcon(starting: value?.id == edition.id),
    );
  }
}

/// One edition with its download controls, its files, and the actions that
/// open or correct it. It reports each tap and causes nothing itself.
class EditionPanel extends StatelessWidget {
  const EditionPanel({
    super.key,
    required this.edition,
    required this.downloads,
    this.onListen,
    this.onRead,
    required this.onOrderFiles,
    required this.onSeparate,
    required this.onDownload,
    this.starting,
  });
  final Edition edition;

  /// The edition that Playback starts, which Listen follows to show a
  /// progress ring while [edition] starts. Null without playback.
  final ValueListenable<Edition?>? starting;

  /// What the download controls follow for [edition], or null without
  /// downloads.
  final Downloads? downloads;

  /// Reports a tap on Listen. Null shows no Listen button.
  final VoidCallback? onListen;

  /// Reports a tap on Read. Null shows no Read button.
  final VoidCallback? onRead;

  /// Reports a tap on Correct file order, shown for two or more files.
  final VoidCallback onOrderFiles;

  /// Reports a tap on Separate source under one of the files.
  final ValueChanged<SourceFile> onSeparate;

  /// Reports a tap on one of the edition's download actions.
  final ValueChanged<DownloadAction> onDownload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final audio = edition.kind == EditionKind.audio;
    final length = audio ? _length(edition) : null;
    return BookfinPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(audio ? 'Audiobook' : 'Ebook'),
          const SizedBox(height: 4),
          Text(
            audio && edition.narrator != null
                ? 'Read by ${edition.narrator}'
                : edition.label,
            style: theme.textTheme.titleMedium,
          ),
          Text(
            [
              '${edition.files.length} ${edition.files.length == 1 ? 'file' : 'files'}',
              if (length != null) duration(length),
            ].join(' · '),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          DownloadControls(
            downloads: downloads,
            edition: edition,
            onAction: onDownload,
          ),
          Wrap(
            spacing: 8,
            children: [
              if (onListen != null)
                FilledButton.tonalIcon(
                  onPressed: onListen,
                  icon: _ListenIcon(starting: starting, edition: edition),
                  label: const Text('Listen'),
                ),
              if (onRead != null)
                FilledButton.tonalIcon(
                  onPressed: onRead,
                  icon: const Icon(Icons.menu_book_outlined),
                  label: const Text('Read'),
                ),
              if (edition.files.length > 1)
                TextButton(
                  onPressed: onOrderFiles,
                  child: const Text('Correct file order'),
                ),
            ],
          ),
          for (final file in edition.files)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              shape: const Border(),
              collapsedShape: const Border(),
              title: Text(file.displayName),
              subtitle: Text(
                [
                  if (file.container.isNotEmpty) file.container.toUpperCase(),
                  if (file.durationMs != null) duration(file.durationMs!),
                  if (file.sizeBytes != null) formatBytes(file.sizeBytes!),
                ].join(' · '),
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
                    trailing: Text(audioTime(chapter.startMs)),
                  ),
                TextButton(
                  onPressed: () => onSeparate(file),
                  child: const Text('Separate source'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

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
        : seriesPosition(widget.book.seriesOrder!),
  );
  @override
  void dispose() {
    for (final controller in [_title, _author, _series, _position]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GlassDialog(
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
  const _BookPicker({required this.book, required this.library});
  final Book book;
  final CatalogLibrary library;
  @override
  State<_BookPicker> createState() => _BookPickerState();
}

class _BookPickerState extends State<_BookPicker> {
  String _query = '';

  /// The ids of the possible matches of the book, from the library's index.
  late final _suggested = {
    for (final book in widget.library.matches(widget.book)) book.id,
  };

  @override
  Widget build(BuildContext context) {
    // The library's own search and order: one pass over the books, with no
    // sort, so a keystroke costs as much as a library search.
    final found = _query.trim().isEmpty
        ? widget.library.books
        : widget.library.search(_query);
    final books = [
      for (final suggested in [true, false])
        for (final book in found)
          if (book.id != widget.book.id &&
              _suggested.contains(book.id) == suggested)
            book,
    ];
    return FractionallySizedBox(
      heightFactor: 0.85,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                    '${books[index].author}${_suggested.contains(books[index].id) ? ' · Possible match' : ''}',
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
  Widget build(BuildContext context) => GlassDialog(
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
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        children: [
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
