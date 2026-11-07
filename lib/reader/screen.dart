import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_epub_viewer/flutter_epub_viewer.dart';

import '../catalog/glass.dart' show confirmAction, showGlassSheet;
import '../foundation/listenable_selector.dart';
import '../foundation/time.dart';
import '../playback/playback.dart';
import '../playback/records_screen.dart' show showBookmarkEditor;
import '../playback/screen.dart';
import 'session.dart';
import 'document.dart';
import 'pdf.dart';
import 'pdf_viewport.dart';

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({
    super.key,
    required this.reader,
    required this.onNightChanged,
    this.playback,
  });
  final ReaderSession reader;
  final ValueChanged<bool> onNightChanged;
  final Playback? playback;
  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

/// The reader screen is the controller of the reading view. It owns every
/// side effect: it opens the panels, closes them, and tells [ReaderSession]
/// what the person chose. Each part of the view follows only the session
/// signal that it shows, so a page turn redraws the page label and the
/// progress bar, and a text size change redraws the viewport.
class _ReaderScreenState extends State<ReaderScreen> {
  bool _controls = true;
  int? _viewToken;
  ReaderSession get reader => widget.reader;
  @override
  void dispose() {
    unawaited(reader.flush());
    if (_viewToken != null) reader.closeView(_viewToken!);
    super.dispose();
  }

  /// Shows the panel that [builder] builds on the reader's plain sheet, and
  /// completes when the sheet closes.
  Future<void> _sheet(WidgetBuilder builder) => showGlassSheet<void>(
    context,
    glass: false,
    isScrollControlled: true,
    builder: builder,
  );

  void _openContents() => unawaited(
    _sheet(
      (sheet) => ReaderContentsPanel(
        contents: reader.contents,
        onContents: (href) {
          Navigator.pop(sheet);
          unawaited(reader.goToContents(href));
        },
      ),
    ),
  );

  /// Shows the search panel, and ends the search when the sheet is gone,
  /// however it closed.
  Future<void> _openSearch() async {
    ModalRoute<Object?>? route;
    await _sheet((sheet) {
      route ??= ModalRoute.of(sheet);
      return ListenableBuilder(
        listenable: reader.searchChanges,
        builder: (_, _) => ReaderSearchPanel(
          searching: reader.searching,
          hits: reader.hits,
          error: reader.searchError,
          onSearch: (query) => unawaited(reader.search(query)),
          onOpenHit: (hit) {
            unawaited(reader.openHit(hit));
            Navigator.pop(sheet);
          },
          onCancelSearch: () => Navigator.pop(sheet),
        ),
      );
    });
    // The sheet closes at once but slides away for a moment. Waiting until it
    // is gone keeps its results in place while it slides.
    await route?.completed;
    reader.cancelSearch();
  }

  void _openBookmarks() => unawaited(
    _sheet(
      (sheet) => ListenableBuilder(
        listenable: reader.bookmarkChanges,
        builder: (_, _) => ReaderBookmarksPanel(
          bookmarks: reader.bookmarks,
          onRestore: (bookmark) {
            unawaited(reader.restoreBookmark(bookmark.id));
            Navigator.pop(sheet);
          },
          onEdit: (bookmark) => unawaited(_editBookmark(bookmark)),
          onDelete: (bookmark) => unawaited(_deleteBookmark(bookmark)),
        ),
      ),
    ),
  );

  /// Asks for a new title and note for [bookmark] in the shared bookmark
  /// editor, and saves them unless the person cancels.
  Future<void> _editBookmark(TextBookmark bookmark) async {
    final edited = await showBookmarkEditor(
      context,
      heading: 'Edit reading bookmark',
      title: bookmark.title,
      note: bookmark.note,
      place: 'Saved ${dayAndTime(context, bookmark.createdAt)}',
    );
    if (edited == null) return;
    await reader.editBookmark(
      bookmark.id,
      title: edited.title,
      note: edited.note,
    );
  }

  /// Deletes [bookmark] after the person confirms it.
  Future<void> _deleteBookmark(TextBookmark bookmark) async {
    if (await confirmAction(
      context,
      title: 'Delete reading bookmark?',
      message: 'Remove this bookmark on synced devices. Your reading place and other bookmarks stay.',
      action: 'Delete',
      glass: false,
    )) {
      await reader.deleteBookmark(bookmark.id);
    }
  }

  /// The visible page, such as "Page 2 of 8".
  String get _pageLabel {
    final page = reader.visibleAddress?.page;
    final pages = reader.visibleAddress?.pages;
    return page == null
        ? 'Page progress unavailable'
        : pages == null
        ? 'Page $page'
        : 'Page $page of $pages';
  }

  /// An icon button that is on while [enabled] is true. It rebuilds only
  /// when [changes] notifies and [enabled] changed.
  Widget _button({
    required Listenable changes,
    required bool Function() enabled,
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
  }) => ListenableSelector<bool>(
    listenable: changes,
    select: enabled,
    builder: (_, on, _) => IconButton(
      tooltip: tooltip,
      onPressed: on ? onPressed : null,
      icon: Icon(icon),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final night = Theme.of(context).brightness == Brightness.dark;
    final documentOrSize = Listenable.merge([
      reader.documentChanges,
      reader.fontSizeChanges,
    ]);
    return Scaffold(
      backgroundColor: night
          ? const Color(0xff251e19)
          : const Color(0xfff6efe2),
      appBar: _controls
          ? AppBar(
              title: ListenableBuilder(
                listenable: reader.documentChanges,
                builder: (_, _) => Text(
                  reader.book?.title ?? 'Reading',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              actions: [
                IconButton(
                  tooltip: 'Hide reader controls',
                  onPressed: () => setState(() => _controls = false),
                  icon: const Icon(Icons.fullscreen_rounded),
                ),
              ],
            )
          : null,
      body: SafeArea(
        child: Column(
          children: [
            ListenableBuilder(
              listenable: Listenable.merge([
                reader.documentChanges,
                reader.saveStatusChanges,
              ]),
              builder: (context, _) => reader.message == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          Text(
                            reader.message!,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          if (reader.book != null && reader.edition != null)
                            TextButton(
                              onPressed: () => unawaited(
                                reader.open(reader.book!, reader.edition!),
                              ),
                              child: const Text('Retry opening'),
                            ),
                        ],
                      ),
                    ),
            ),
            if (_controls)
              ListenableBuilder(
                listenable: reader.documentChanges,
                builder: (_, _) =>
                    reader.publication?.warnings.isNotEmpty == true
                    ? Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          reader.publication!.warnings.join(' '),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ListenableBuilder(
                      listenable: Listenable.merge([
                        documentOrSize,
                        reader.saveStatusChanges,
                      ]),
                      builder: (context, _) => _viewport(context, night),
                    ),
                  ),
                  if (!_controls)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: IconButton.filledTonal(
                        tooltip: 'Show reader controls',
                        onPressed: () => setState(() => _controls = true),
                        icon: const Icon(Icons.more_horiz_rounded),
                      ),
                    ),
                  Positioned.fill(
                    child: ListenableBuilder(
                      listenable: Listenable.merge([
                        reader.documentChanges,
                        reader.saveStatusChanges,
                      ]),
                      builder: (_, _) =>
                          reader.publication != null &&
                              !reader.ready &&
                              epubViewportSupported &&
                              reader.message == null
                          ? Center(
                              child: Semantics(
                                label: 'Laying out the book',
                                child: const CircularProgressIndicator(),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                ],
              ),
            ),
            if (_controls)
              Flexible(
                flex: 0,
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            _button(
                              changes: reader.documentChanges,
                              enabled: () => reader.ready,
                              tooltip: 'Contents',
                              icon: Icons.list_rounded,
                              onPressed: _openContents,
                            ),
                            _button(
                              changes: reader.documentChanges,
                              enabled: () => reader.ready,
                              tooltip: 'Search book',
                              icon: Icons.search_rounded,
                              onPressed: () => unawaited(_openSearch()),
                            ),
                            _button(
                              changes: documentOrSize,
                              enabled: () =>
                                  reader.document != null &&
                                  reader.fontSize > 14,
                              tooltip: 'Smaller text',
                              icon: Icons.text_decrease_rounded,
                              onPressed: () => unawaited(
                                reader.setFontSize(reader.fontSize - 2),
                              ),
                            ),
                            _button(
                              changes: documentOrSize,
                              enabled: () =>
                                  reader.document != null &&
                                  reader.fontSize < 40,
                              tooltip: 'Larger text',
                              icon: Icons.text_increase_rounded,
                              onPressed: () => unawaited(
                                reader.setFontSize(reader.fontSize + 2),
                              ),
                            ),
                            _button(
                              changes: Listenable.merge([
                                reader.bookmarkChanges,
                                reader.placeChanges,
                              ]),
                              enabled: () => reader.canBookmark,
                              tooltip: 'Bookmark this place',
                              icon: Icons.bookmark_add_outlined,
                              onPressed: () => unawaited(reader.addBookmark()),
                            ),
                            _button(
                              changes: reader.documentChanges,
                              enabled: () => reader.document != null,
                              tooltip: 'Reading bookmarks',
                              icon: Icons.bookmarks_outlined,
                              onPressed: _openBookmarks,
                            ),
                            IconButton(
                              tooltip: night
                                  ? 'Cream reading theme'
                                  : 'Night reading theme',
                              onPressed: () => widget.onNightChanged(!night),
                              icon: Icon(
                                night
                                    ? Icons.light_mode_outlined
                                    : Icons.dark_mode_outlined,
                              ),
                            ),
                          ],
                        ),
                        ListenableBuilder(
                          listenable: reader.placeChanges,
                          builder: (_, _) {
                            final page = reader.visibleAddress?.page;
                            final pages = reader.visibleAddress?.pages;
                            if (page == null || pages == null) {
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: LinearProgressIndicator(
                                value: page / pages,
                                semanticsLabel:
                                    'Current document page progress. $_pageLabel',
                              ),
                            );
                          },
                        ),
                        Row(
                          children: [
                            _button(
                              changes: reader.documentChanges,
                              enabled: () => reader.ready,
                              tooltip: 'Previous page',
                              icon: Icons.chevron_left_rounded,
                              onPressed: () => unawaited(reader.move(false)),
                            ),
                            Expanded(
                              child: ListenableBuilder(
                                listenable: reader.placeChanges,
                                builder: (context, _) => Text(
                                  '${reader.visibleAddress?.chapter ?? 'Current chapter unavailable'} · $_pageLabel',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            ),
                            _button(
                              changes: reader.documentChanges,
                              enabled: () => reader.ready,
                              tooltip: 'Next page',
                              icon: Icons.chevron_right_rounded,
                              onPressed: () => unawaited(reader.move(true)),
                            ),
                          ],
                        ),
                        if (widget.playback != null)
                          PlaybackMiniPlayer(playback: widget.playback!),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// The view of the open document, or what stands in its place while the
  /// book opens or cannot open. It follows the document, the text size and
  /// the reader message.
  Widget _viewport(BuildContext context, bool night) {
    _viewToken = reader.token;
    final token = reader.token;
    final document = reader.document;
    final publication = reader.publication;
    final fontSize = MediaQuery.textScalerOf(context).scale(reader.fontSize);
    if (document is PdfBook) {
      return PdfViewport(
        key: ValueKey(token),
        book: document,
        initial: reader.initialAddress as PdfAddress?,
        fontSize: fontSize,
        onReady: (navigator, entries) =>
            reader.attachDocument(token, navigator, entries),
        onAddress: (address) => reader.acceptAddress(token, address),
      );
    }
    if (!epubViewportSupported) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'EPUB reading is available in the Android app. Your downloads and listening are unchanged.',
          ),
        ),
      );
    }
    if (reader.loading ||
        (reader.edition == null &&
            publication == null &&
            reader.message == null)) {
      return Center(
        child: Semantics(
          label: 'Checking the downloaded EPUB',
          child: const CircularProgressIndicator(),
        ),
      );
    }
    if (publication == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('This EPUB is not open. Use the message above to retry.'),
        ),
      );
    }
    return EpubViewport(
      key: ValueKey(token),
      publication: publication,
      initial: reader.initialLocation,
      fontSize: fontSize,
      night: night,
      onReady: (controller, contents) =>
          reader.attach(token, controller, contents),
      onLocation: (location) => reader.acceptVisible(token, location),
      onFailure: (message) => reader.failed(token, message),
      onWarning: (message) => reader.warn(token, message),
      onTap: () {
        if (mounted) setState(() => _controls = !_controls);
      },
    );
  }
}

/// The book's table of contents. A tap on an entry reports its place
/// through [onContents].
class ReaderContentsPanel extends StatelessWidget {
  const ReaderContentsPanel({
    super.key,
    required this.contents,
    required this.onContents,
  });
  final List<ContentsEntry> contents;

  /// Reports the href of the entry that the person chose.
  final ValueChanged<String> onContents;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .7,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Contents', style: Theme.of(context).textTheme.headlineSmall),
          for (final entry in contents)
            ListTile(
              contentPadding: EdgeInsets.only(left: entry.depth * 16.0),
              title: Text(entry.title),
              onTap: () => onContents(entry.href),
            ),
        ],
      ),
    ),
  );
}

/// A search field over the [hits] of the last search. [searching] shows
/// that a search runs, and [error] says why a search is incomplete.
class ReaderSearchPanel extends StatefulWidget {
  const ReaderSearchPanel({
    super.key,
    required this.searching,
    required this.hits,
    required this.error,
    required this.onSearch,
    required this.onOpenHit,
    required this.onCancelSearch,
  });
  final bool searching;
  final List<ReaderHit> hits;
  final String? error;

  /// Reports the query that the person submitted.
  final ValueChanged<String> onSearch;

  /// Reports the hit that the person chose.
  final ValueChanged<ReaderHit> onOpenHit;

  /// Reports a tap on Cancel search.
  final VoidCallback onCancelSearch;
  @override
  State<ReaderSearchPanel> createState() => _ReaderSearchPanelState();
}

class _ReaderSearchPanelState extends State<ReaderSearchPanel> {
  final _query = TextEditingController();
  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .7,
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Search',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                IconButton(
                  tooltip: 'Cancel search',
                  onPressed: widget.onCancelSearch,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            TextField(
              controller: _query,
              autofocus: true,
              maxLength: 256,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(labelText: 'Find in this book'),
              onSubmitted: widget.onSearch,
            ),
            Expanded(
              child: ListView(
                children: [
                  if (widget.searching)
                    const LinearProgressIndicator(
                      semanticsLabel: 'Searching the book',
                    ),
                  if (widget.error != null)
                    Text(
                      widget.error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  const Text(
                    'Search uses basic lowercase matching. Some language-specific letter forms differ. Spaces, tabs, and line breaks match as one space. Accents must match. Different Unicode spellings are not combined. Text hidden only by a stylesheet can appear in results.',
                  ),
                  if (!widget.searching &&
                      widget.hits.isEmpty &&
                      _query.text.isNotEmpty &&
                      widget.error == null)
                    const Text('No matches.'),
                  for (final hit in widget.hits)
                    ListTile(
                      title: Text(hit.excerpt),
                      onTap: () => widget.onOpenHit(hit),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// The reading [bookmarks] of the open edition. A tap on a row reports
/// [onRestore], and the row's menu reports [onEdit] or [onDelete].
class ReaderBookmarksPanel extends StatelessWidget {
  const ReaderBookmarksPanel({
    super.key,
    required this.bookmarks,
    required this.onRestore,
    required this.onEdit,
    required this.onDelete,
  });
  final List<TextBookmark> bookmarks;

  /// Reports a tap on a bookmark, to return to its place.
  final ValueChanged<TextBookmark> onRestore;

  /// Reports that the person chose Edit title and note for a bookmark.
  final ValueChanged<TextBookmark> onEdit;

  /// Reports that the person chose Delete for a bookmark.
  final ValueChanged<TextBookmark> onDelete;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .7,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Reading bookmarks',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          if (bookmarks.isEmpty)
            const Text(
              'No reading bookmarks in this edition. Use Bookmark this place while reading.',
            ),
          for (final bookmark in bookmarks)
            ListTile(
              title: Text(
                bookmark.title?.isNotEmpty == true
                    ? bookmark.title!
                    : 'Saved reading place',
              ),
              subtitle: Text(
                bookmark.note?.isNotEmpty == true
                    ? bookmark.note!
                    : dayAndTime(context, bookmark.createdAt),
              ),
              onTap: () => onRestore(bookmark),
              trailing: PopupMenuButton<String>(
                tooltip: 'Edit reading bookmark',
                onSelected: (action) =>
                    (action == 'delete' ? onDelete : onEdit)(bookmark),
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Text('Edit title and note'),
                  ),
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}
