import 'dart:async';

import 'package:flutter/material.dart';

import '../downloads/downloads.dart';
import '../downloads/screen.dart';
import '../foundation/theme.dart';
import '../playback/screen.dart';
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

/// The details of one book: its cover, facts, actions, and editions. It reads
/// the current catalog, so it follows refreshes and corrections while open.
class BookPage extends StatelessWidget {
  const BookPage({super.key, required this.services, required this.bookId});
  final LibraryServices services;
  final String bookId;

  CatalogController get catalog => services.catalog;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: services.changes,
    builder: (context, _) {
      final book = catalog.books.where((book) => book.id == bookId).firstOrNull;
      if (book == null) {
        return Scaffold(
          appBar: AppBar(),
          body: const Center(
            child: Text('This book is not in the current library.'),
          ),
        );
      }
      final theme = Theme.of(context);
      final playback = services.playback;
      final audio = book.editions
          .where((edition) => edition.kind == EditionKind.audio)
          .toList();
      final text = book.editions
          .where((edition) => edition.kind == EditionKind.text)
          .toList();
      final listening =
          audio
              .where((edition) => playback?.progress(edition) != null)
              .firstOrNull ??
          audio.firstOrNull;
      final progress = services.progress(book);
      final inSeries =
          book.series != null &&
          shelf(
            catalog.books,
            ShelfFilter.all,
            services.editionDownloaded,
          ).whereType<ShelfSeries>().any(
            (series) => series.books.any((member) => member.id == book.id),
          );
      final audioMs = listening == null ? null : _length(listening);
      final formats = {
        for (final edition in text)
          for (final file in edition.files)
            if (file.container.isNotEmpty) file.container.toUpperCase(),
      };
      final narrator = audio
          .map((edition) => edition.narrator)
          .nonNulls
          .firstOrNull;
      return Scaffold(
        extendBodyBehindAppBar: true,
        extendBody: true,
        bottomNavigationBar: playback == null
            ? null
            : PlaybackMiniPlayer(playback: playback),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          actions: [
            GlassMenuButton(
              tooltip: 'More actions',
              icon: const Icon(Icons.more_horiz_rounded),
              book: book,
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
        body: BookfinSurface(
          child: Material(
            type: MaterialType.transparency,
            child: ListView(
              padding: EdgeInsets.only(bottom: floatingBarInset(context)),
              children: [
                _Header(book: book, downloaded: services.downloaded(book)),
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
                            onPressed: inSeries
                                ? () => openSeries(
                                    context,
                                    services,
                                    shelf(
                                      catalog.books,
                                      ShelfFilter.all,
                                      services.editionDownloaded,
                                    ).whereType<ShelfSeries>().firstWhere(
                                      (series) => series.books.any(
                                        (member) => member.id == book.id,
                                      ),
                                    ),
                                  )
                                : null,
                            style: TextButton.styleFrom(
                              minimumSize: const Size(48, 36),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                            ),
                            child: Text(
                              [
                                    book.series!,
                                    if (book.seriesOrder != null)
                                      'Book ${seriesPosition(book.seriesOrder!)}',
                                  ].join(' · ') +
                                  (inSeries ? '  ›' : ''),
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ),
                      const SizedBox(height: 14),
                      _Facts(
                        facts: [
                          if (audioMs != null) (duration(audioMs), 'audio'),
                          if (formats.isNotEmpty)
                            (formats.join(' + '), 'ebook')
                          else if (text.isNotEmpty)
                            ('Ebook', 'edition'),
                          if (book.year != null) ('${book.year}', 'published'),
                        ],
                      ),
                      const SizedBox(height: 18),
                      _Actions(
                        services: services,
                        book: book,
                        listening: listening,
                        reading: text.firstOrNull,
                      ),
                      if (progress != null && progress.totalMs > 0) ...[
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                progress.totalMs - progress.elapsedMs < 60000
                                    ? 'Finished'
                                    : '${(progress.elapsedMs * 100 / progress.totalMs).floor()}% · ${duration(progress.totalMs - progress.elapsedMs)} left',
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                            if (playback != null &&
                                playback.book?.id == book.id)
                              TextButton(
                                onPressed: () =>
                                    openListeningHistory(context, playback),
                                style: TextButton.styleFrom(
                                  minimumSize: const Size(48, 32),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                ),
                                child: const Text(
                                  'Bookmarks and history',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: progress.elapsedMs / progress.totalMs,
                            minHeight: 3,
                            backgroundColor: theme.colorScheme.outlineVariant,
                          ),
                        ),
                      ],
                      if (catalog.message != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            catalog.message!,
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                        ),
                      if (playback?.message != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(playback!.message!),
                        ),
                      if (playback != null &&
                          playback.replacementStart?.book.id == bookId)
                        ReplacementStartNotice(
                          playback: playback,
                          onStarted: () => openPlayer(context, playback),
                        ),
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
                      if (book.genres.isNotEmpty)
                        ('Genre', book.genres.join(', ')),
                      if (book.publisher != null)
                        ('Publisher', book.publisher!),
                      if (_files(book).isNotEmpty) ('Files', _files(book)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('EDITIONS', style: _sectionStyle(theme)),
                      const SizedBox(height: 10),
                      for (final edition in book.editions)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _EditionPanel(
                            services: services,
                            book: book,
                            edition: edition,
                          ),
                        ),
                      if (possibleMatches(book, catalog.books).isNotEmpty)
                        Text(
                          '${possibleMatches(book, catalog.books).length} possible ${possibleMatches(book, catalog.books).length == 1 ? 'match' : 'matches'} · Confirmation required',
                          style: theme.textTheme.bodySmall,
                        ),
                    ],
                  ),
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
    final candidate = await showGlassSheet<Book>(
      context,
      book: book,
      isScrollControlled: true,
      builder: (_) => _BookPicker(book: book, books: catalog.books),
    );
    if (candidate == null || !context.mounted) return;
    if (await confirmAction(
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
    if (await confirmAction(
      context,
      'Combine as one recording?',
      'Use this only for consecutive files of the same recording, not different narrators or abridged versions. You can correct the file order afterward.',
      'Combine files',
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

TextStyle _sectionStyle(ThemeData theme) => TextStyle(
  fontSize: 11,
  letterSpacing: 1.2,
  fontWeight: FontWeight.w500,
  color: theme.colorScheme.onSurfaceVariant,
);

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

/// The main actions: listen or resume, read, and download.
class _Actions extends StatelessWidget {
  const _Actions({
    required this.services,
    required this.book,
    required this.listening,
    required this.reading,
  });
  final LibraryServices services;
  final Book book;
  final Edition? listening;
  final Edition? reading;

  @override
  Widget build(BuildContext context) {
    final playback = services.playback;
    final reader = services.reader;
    final progress = listening == null ? null : playback?.progress(listening!);
    final listen = listening != null && playback != null
        ? () async {
            await playback.open(book, listening!);
            if (context.mounted && playback.edition == listening) {
              openPlayer(context, playback);
            }
          }
        : null;
    final read = reading != null && reader != null
        ? () {
            unawaited(reader.open(book, reading!));
            Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => ReaderScreen(
                  reader: reader,
                  onNightChanged: services.onReaderNightChanged,
                  playback: playback,
                ),
              ),
            );
          }
        : null;
    final saved = listening ?? reading;
    return Row(
      children: [
        if (listening != null)
          Expanded(
            child: FilledButton.icon(
              onPressed: listen,
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(progress == null ? 'Listen' : 'Resume'),
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
        if (saved != null && services.downloads?.supported == true) ...[
          const SizedBox(width: 8),
          _DownloadButton(downloads: services.downloads!, edition: saved),
        ],
      ],
    );
  }
}

class _DownloadButton extends StatelessWidget {
  const _DownloadButton({required this.downloads, required this.edition});
  final Downloads downloads;
  final Edition edition;
  @override
  Widget build(BuildContext context) {
    final state = downloads.status(edition);
    final (icon, tooltip, action) = switch (state.phase) {
      DownloadPhase.downloaded => (
        Icons.check_rounded,
        'Downloaded. Remove download',
        () async {
          if (await confirmAction(
            context,
            'Remove download?',
            'The files leave this phone. You can download them again later.',
            'Remove',
          )) {
            await downloads.remove(edition);
          }
        },
      ),
      DownloadPhase.downloading => (
        Icons.close_rounded,
        'Cancel download',
        () => downloads.cancel(edition),
      ),
      DownloadPhase.waiting => (
        Icons.wifi_off_rounded,
        'Waiting for Wi-Fi. Cancel download',
        () => downloads.cancel(edition),
      ),
      DownloadPhase.failed => (
        Icons.refresh_rounded,
        'Download failed. Try again',
        () => downloads.request(edition),
      ),
      _ => (
        Icons.download_rounded,
        'Download',
        () => downloads.request(edition),
      ),
    };
    final downloading = state.phase == DownloadPhase.downloading;
    return Stack(
      alignment: Alignment.center,
      children: [
        if (downloading)
          SizedBox(
            width: 44,
            height: 44,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              value: state.totalBytes != null && state.totalBytes! > 0
                  ? (state.bytes / state.totalBytes!).clamp(0, 1)
                  : null,
            ),
          ),
        IconButton.filled(
          style: IconButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
            foregroundColor: Theme.of(context).colorScheme.onSurface,
            minimumSize: const Size(52, 52),
          ),
          tooltip: tooltip,
          onPressed: () => unawaited(action()),
          icon: Icon(icon),
        ),
      ],
    );
  }
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

/// One edition with its own download, listen or read action, and files.
class _EditionPanel extends StatelessWidget {
  const _EditionPanel({
    required this.services,
    required this.book,
    required this.edition,
  });
  final LibraryServices services;
  final Book book;
  final Edition edition;

  CatalogController get catalog => services.catalog;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final playback = services.playback;
    final reader = services.reader;
    final audio = edition.kind == EditionKind.audio;
    final length = audio ? _length(edition) : null;
    // The main actions above already open the only edition of a kind.
    final choice =
        book.editions.where((other) => other.kind == edition.kind).length > 1;
    return BookfinPanel(
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(audio ? 'Audiobook' : 'Ebook', style: _sectionStyle(theme)),
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
            DownloadControls(downloads: services.downloads, edition: edition),
            Wrap(
              spacing: 8,
              children: [
                if (choice && audio && playback != null)
                  FilledButton.tonalIcon(
                    onPressed: () async {
                      await playback.open(book, edition);
                      if (context.mounted && playback.edition == edition) {
                        openPlayer(context, playback);
                      }
                    },
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Listen'),
                  ),
                if (choice && !audio && reader != null)
                  FilledButton.tonalIcon(
                    onPressed: () {
                      unawaited(reader.open(book, edition));
                      Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ReaderScreen(
                            reader: reader,
                            onNightChanged: services.onReaderNightChanged,
                            playback: playback,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.menu_book_outlined),
                    label: const Text('Read'),
                  ),
                if (edition.files.length > 1)
                  TextButton(
                    onPressed: () => _orderFiles(context, edition),
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
                      trailing: Text(_time(chapter.startMs)),
                    ),
                  TextButton(
                    onPressed: () async {
                      if (await confirmAction(
                        context,
                        'Separate this source?',
                        'This source becomes a separate book. Its Jellyfin item will not change.',
                        'Separate',
                      )) {
                        await catalog.separateEdition(file.key);
                      }
                    },
                    child: const Text('Separate source'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _orderFiles(BuildContext context, Edition edition) async {
    final keys = await showGlassSheet<List<String>>(
      context,
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

Future<bool> confirmAction(
  BuildContext context,
  String title,
  String message,
  String action,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => GlassDialog(
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

String _time(int milliseconds) {
  final seconds = milliseconds ~/ 1000;
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}
