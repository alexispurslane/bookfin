import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../catalog/glass.dart'
    show CoverGlass, PageBook, confirmAction, showGlassSheet;
import '../catalog/model.dart' show Book;
import '../foundation/listenable_selector.dart';
import '../foundation/scrub_bar.dart';
import '../foundation/theme.dart' show PillChoice;
import '../foundation/time.dart';
import '../playback/playback.dart';
import '../playback/records_screen.dart' show showBookmarkEditor;
import '../playback/screen.dart';
import 'book_map.dart';
import 'session.dart';
import 'document.dart';
import 'epub/page_source.dart' show PageNumber;
import 'epub/viewport.dart';
import 'pdf.dart';
import 'pdf_viewport.dart';
import 'scrub_deck.dart';

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
/// progress bar, and a text size or reflow change redraws the viewport.
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

  /// Shows the contents and, on its second tab, the reading bookmarks. The
  /// bookmarks follow their changes while the sheet is open.
  void _openContents() => unawaited(
    _sheet(
      (sheet) => ListenableBuilder(
        listenable: reader.bookmarkChanges,
        builder: (_, _) => ReaderContentsPanel(
          contents: reader.contents,
          onContents: (href) {
            Navigator.pop(sheet);
            unawaited(reader.goToContents(href));
          },
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

  /// Shows the reading settings. Each control follows its own value while
  /// the sheet is open, and the theme follows the app's theme.
  void _openSettings() => unawaited(
    _sheet(
      (sheet) => ListenableSelector(
        listenable: Listenable.merge([
          reader.documentChanges,
          reader.fontSizeChanges,
          reader.reflowChanges,
        ]),
        select: () => (
          fontSize: reader.fontSize,
          open: reader.document != null,
          reflow: reader.document is PdfBook ? reader.reflow : null,
        ),
        builder: (context, on, _) => ReaderSettingsPanel(
          fontSize: on.fontSize,
          onSmaller: on.open && on.fontSize > 14
              ? () => unawaited(reader.setFontSize(reader.fontSize - 2))
              : null,
          onLarger: on.open && on.fontSize < 40
              ? () => unawaited(reader.setFontSize(reader.fontSize + 2))
              : null,
          night: Theme.of(context).brightness == Brightness.dark,
          onNightChanged: widget.onNightChanged,
          reflow: on.reflow,
          onReflowChanged: reader.setReflow,
        ),
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

  /// Asks for a new title and note for [bookmark] in the shared bookmark
  /// editor, and saves them unless the person cancels.
  Future<void> _editBookmark(TextBookmark bookmark) async {
    final edited = await showBookmarkEditor(
      context,
      heading: 'Edit reading bookmark',
      title: bookmark.title,
      note: bookmark.note,
      place: 'Saved ${dayAndTime(context, bookmark.createdAt)}',
      glass: false,
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

  /// The chapter arrow before the bar, or after it with [forward]. In a book
  /// without chapters it turns a page, and says so. It rebuilds only when it
  /// turns on or off or changes what it does.
  Widget _arrow({required bool forward}) => ListenableSelector(
    listenable: Listenable.merge([
      reader.documentChanges,
      reader.bookMapChanges,
    ]),
    select: () => (ready: reader.ready, chapters: reader.hasChapters),
    builder: (_, on, _) {
      final step = on.chapters ? 'chapter' : 'page';
      return IconButton(
        tooltip: forward ? 'Next $step' : 'Previous $step',
        onPressed: on.ready
            ? () => unawaited(reader.moveChapter(forward))
            : null,
        icon: Icon(
          forward ? Icons.chevron_right_rounded : Icons.chevron_left_rounded,
        ),
      );
    },
  );

  /// The dock's tool row, with [audio] at its end. It rebuilds only when a
  /// tool turns on or off.
  Widget _tools(Widget? audio) => ListenableSelector(
    listenable: Listenable.merge([
      reader.documentChanges,
      reader.bookmarkChanges,
      reader.placeChanges,
    ]),
    select: () => (
      ready: reader.ready,
      open: reader.document != null,
      bookmark: reader.canBookmark,
    ),
    builder: (_, on, _) => ReaderTools(
      onContents: on.ready ? _openContents : null,
      onSearch: on.ready ? () => unawaited(_openSearch()) : null,
      onSettings: on.open ? _openSettings : null,
      onBookmark: on.bookmark ? () => unawaited(reader.addBookmark()) : null,
      audio: audio,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final night = Theme.of(context).brightness == Brightness.dark;
    final documentOrSize = Listenable.merge([
      reader.documentChanges,
      reader.fontSizeChanges,
    ]);
    final paper = night ? const Color(0xff251e19) : const Color(0xfff6efe2);
    return Scaffold(
      backgroundColor: paper,
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
            // The warnings stay in the column while the controls hide, so
            // that the page after them keeps its place and does not open the
            // book again.
            ListenableBuilder(
              listenable: reader.documentChanges,
              builder: (_, _) =>
                  _controls && reader.publication?.warnings.isNotEmpty == true
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
                    // The deck's glass shows the open book.
                    child: ListenableBuilder(
                      listenable: reader.documentChanges,
                      builder: (_, page) => ScrubDeck(
                        deck: reader.previews.deck,
                        paper: paper,
                        book: reader.book,
                        page: page!,
                      ),
                      child: ListenableBuilder(
                        listenable: Listenable.merge([
                          documentOrSize,
                          reader.saveStatusChanges,
                          reader.reflowChanges,
                        ]),
                        builder: (context, _) => _viewport(context, night),
                      ),
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
                ],
              ),
            ),
            if (_controls)
              Flexible(
                flex: 0,
                child: SingleChildScrollView(
                  child: ListenableSelector(
                    listenable: reader.documentChanges,
                    select: () => reader.book,
                    builder: (context, book, _) => ReaderDock(
                      book: book,
                      bar: ReaderScrubBar(
                        reader: reader,
                        previous: _arrow(forward: false),
                        next: _arrow(forward: true),
                        // The deck's front card is the page area at its own
                        // scale, at the screen's pixel density.
                        onScrubStart: (target) => reader.previews.start(
                          target,
                          width:
                              MediaQuery.sizeOf(context).width *
                              MediaQuery.devicePixelRatioOf(context) *
                              ScrubDeck.frontScale,
                        ),
                        onScrubTarget: reader.previews.aim,
                        onScrubEnd: (target) =>
                            reader.previews.settle(target, reader.goTo(target)),
                      ),
                      // The round cover button joins the row only while an
                      // audiobook is open, so the row spaces four tools
                      // evenly without it.
                      tools: switch (widget.playback) {
                        null => _tools(null),
                        final playback => ListenableSelector(
                          listenable: playback.selectionNotifier,
                          select: () => playback.book != null,
                          builder: (_, open, _) => _tools(
                            open
                                ? PlaybackCoverButton(playback: playback)
                                : null,
                          ),
                        ),
                      },
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
  /// book opens or cannot open: the PDF viewport, or the native viewport of
  /// an EPUB or MOBI book's pager on every platform. It follows the
  /// document, the text size, the reader message and the reflow choice.
  Widget _viewport(BuildContext context, bool night) {
    _viewToken = reader.token;
    final token = reader.token;
    final document = reader.document;
    final pager = reader.pager;
    final fontSize = MediaQuery.textScalerOf(context).scale(reader.fontSize);
    if (document is PdfBook) {
      final viewport = PdfViewport(
        key: ValueKey(token),
        book: document,
        initial: reader.initialAddress as PdfAddress?,
        fontSize: fontSize,
        onReady: (navigator, entries) =>
            reader.attachDocument(token, navigator, entries),
        onAddress: (address) => reader.acceptAddress(token, address),
        reflow: reader.reflow,
        onCancelRecognition: () => document.textSupply?.cancel(),
        onRetryRecognition: (page) => document.textSupply?.retry(page),
      );
      // The glass layers over the page show the open book.
      final book = reader.book;
      return book == null ? viewport : PageBook(book: book, child: viewport);
    }
    if (reader.loading ||
        (reader.edition == null && pager == null && reader.message == null)) {
      return Center(
        child: Semantics(
          label: 'Checking the downloaded EPUB',
          child: const CircularProgressIndicator(),
        ),
      );
    }
    if (pager == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('This EPUB is not open. Use the message above to retry.'),
        ),
      );
    }
    // The pager opens the book at the session's saved place, so the page
    // is ready as soon as the viewport presents its size.
    return EpubViewport(
      key: ValueKey(token),
      pager: pager,
      fontSize: fontSize,
      night: night,
      onTap: () {
        if (mounted) setState(() => _controls = !_controls);
      },
      onTurn: (forward) => unawaited(reader.move(forward)),
      onLink: (href) => unawaited(reader.goToContents(href)),
      onCopy: (text) => unawaited(Clipboard.setData(ClipboardData(text: text))),
    );
  }
}

/// The reader's glass dock at the foot of the page: the place in the book
/// with its [bar] over the [tools]. The glass shows [book], the open book.
class ReaderDock extends StatelessWidget {
  const ReaderDock({
    super.key,
    required this.bar,
    required this.tools,
    this.book,
  });
  final Book? book;

  /// The place label over the scrub bar and its chapter arrows.
  final Widget bar;

  /// The row of reading tools.
  final Widget tools;

  @override
  Widget build(BuildContext context) => Padding(
    // The gap above keeps the dock apart from notes at the foot of the page.
    padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
    child: CoverGlass(
      book: book,
      child: Material(
        type: MaterialType.transparency,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(2, 6, 2, 2),
          child: Column(mainAxisSize: MainAxisSize.min, children: [bar, tools]),
        ),
      ),
    ),
  );
}

/// The reader's row of tools: Contents, Search book, Reading settings and
/// Bookmark this place, then [audio], if any. A tool whose callback is null
/// shows but is off. Each tap goes to its own callback, so the owner decides
/// what it does.
class ReaderTools extends StatelessWidget {
  const ReaderTools({
    super.key,
    required this.onContents,
    required this.onSearch,
    required this.onSettings,
    required this.onBookmark,
    this.audio,
  });

  /// Reports Contents, which asks for the contents and the bookmarks.
  final VoidCallback? onContents;

  /// Reports Search book, which asks for the search panel.
  final VoidCallback? onSearch;

  /// Reports Reading settings, which asks for the text size, the theme and,
  /// in a PDF, the reflow choice.
  final VoidCallback? onSettings;

  /// Reports Bookmark this place, which asks to bookmark the shown place.
  final VoidCallback? onBookmark;

  /// The last tool, such as the open audiobook's button.
  final Widget? audio;

  @override
  Widget build(BuildContext context) {
    Widget button(String tooltip, Widget icon, VoidCallback? onPressed) =>
        IconButton(tooltip: tooltip, onPressed: onPressed, icon: icon);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        button('Contents', const Icon(Icons.list_rounded), onContents),
        button('Search book', const Icon(Icons.search_rounded), onSearch),
        button(
          'Reading settings',
          // "Aa" in the book's type, in the color that the button gives its
          // icon, so that it dims with the button.
          Builder(
            // The tooltip names the button for assistive technology.
            builder: (context) => ExcludeSemantics(
              child: Text(
                'Aa',
                style: TextStyle(
                  fontFamily: 'Source Serif 4',
                  fontSize: 19,
                  height: 1,
                  fontWeight: FontWeight.w600,
                  color: IconTheme.of(context).color,
                ),
              ),
            ),
          ),
          onSettings,
        ),
        button(
          'Bookmark this place',
          const Icon(Icons.bookmark_add_outlined),
          onBookmark,
        ),
        ?audio,
      ],
    );
  }
}

/// The reading settings: the text size, the reading theme and, for a PDF,
/// whether its pages show as reflowed text. A size button whose callback is
/// null shows but is off.
class ReaderSettingsPanel extends StatelessWidget {
  const ReaderSettingsPanel({
    super.key,
    required this.fontSize,
    required this.onSmaller,
    required this.onLarger,
    required this.night,
    required this.onNightChanged,
    this.reflow,
    this.onReflowChanged,
  });

  /// The text size, in points.
  final double fontSize;

  /// Reports Smaller text.
  final VoidCallback? onSmaller;

  /// Reports Larger text.
  final VoidCallback? onLarger;

  /// Whether the night reading theme shows.
  final bool night;

  /// Reports the theme that the person chose: true for night.
  final ValueChanged<bool> onNightChanged;

  /// Whether the open PDF shows as reflowed text. Null when the book is not
  /// a PDF, and then the panel has no reflow choice.
  final bool? reflow;

  /// Reports the view that the person chose: true for reflowed text.
  final ValueChanged<bool>? onReflowChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Each label sits over its control, so that the controls keep the
    // sheet's whole width on a narrow phone and at a large text scale.
    Widget row(String label, Widget control) => Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          control,
        ],
      ),
    );
    final reflow = this.reflow;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Reading settings', style: theme.textTheme.headlineSmall),
            row(
              'Text size',
              Row(
                children: [
                  IconButton.outlined(
                    tooltip: 'Smaller text',
                    onPressed: onSmaller,
                    icon: const Icon(Icons.text_decrease_rounded),
                  ),
                  Expanded(
                    child: Text(
                      '${fontSize.round()}',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  IconButton.outlined(
                    tooltip: 'Larger text',
                    onPressed: onLarger,
                    icon: const Icon(Icons.text_increase_rounded),
                  ),
                ],
              ),
            ),
            row(
              'Theme',
              PillChoice<bool>(
                segments: const [
                  ButtonSegment(
                    value: false,
                    label: Text('Cream'),
                    icon: Icon(Icons.light_mode_outlined),
                    tooltip: 'Cream reading theme',
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text('Night'),
                    icon: Icon(Icons.dark_mode_outlined),
                    tooltip: 'Night reading theme',
                  ),
                ],
                selected: night,
                onChanged: onNightChanged,
              ),
            ),
            if (reflow != null)
              row(
                'Pages',
                PillChoice<bool>(
                  segments: const [
                    ButtonSegment(
                      value: false,
                      label: Text('Original'),
                      icon: Icon(Icons.picture_as_pdf_outlined),
                      tooltip: 'Original page',
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text('Reflow'),
                      icon: Icon(Icons.article_outlined),
                      tooltip: 'Reflow text',
                    ),
                  ],
                  selected: reflow,
                  onChanged: onReflowChanged,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The book's table of contents and, on a second tab, its reading
/// [bookmarks]. A tap on an entry reports its place through [onContents]. A
/// tap on a bookmark reports [onRestore], and the bookmark's menu reports
/// [onEdit] or [onDelete].
class ReaderContentsPanel extends StatelessWidget {
  const ReaderContentsPanel({
    super.key,
    required this.contents,
    required this.onContents,
    required this.bookmarks,
    required this.onRestore,
    required this.onEdit,
    required this.onDelete,
  });
  final List<ContentsEntry> contents;

  /// Reports the href of the entry that the person chose.
  final ValueChanged<String> onContents;

  /// The reading bookmarks of the open edition.
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
      child: DefaultTabController(
        length: 2,
        child: Column(
          children: [
            const TabBar(
              tabs: [
                Tab(text: 'Contents'),
                Tab(text: 'Bookmarks'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      for (final entry in contents)
                        ListTile(
                          contentPadding: EdgeInsets.only(
                            left: entry.depth * 16.0,
                          ),
                          title: Text(entry.title),
                          onTap: () => onContents(entry.href),
                        ),
                    ],
                  ),
                  ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
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
                            onSelected: (action) => (action == 'delete'
                                ? onDelete
                                : onEdit)(bookmark),
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                value: 'edit',
                                child: Text('Edit title and note'),
                              ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Text('Delete'),
                              ),
                            ],
                          ),
                        ),
                    ],
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

/// The reader's scrub bar over the whole open book, between the [previous]
/// and [next] chapter arrows, under a one-line label of the place. The bar
/// marks each chapter start and each reading bookmark. While the person
/// drags, the label names the dragged place instead of the visible place,
/// and the book stays where it is until the drag ends.
///
/// The bar shows once the reader has a map of the book and a visible place.
/// Until then only the label and the arrows show.
class ReaderScrubBar extends StatelessWidget {
  const ReaderScrubBar({
    super.key,
    required this.reader,
    required this.previous,
    required this.next,
    required this.onScrubEnd,
    this.onScrubStart,
    this.onScrubTarget,
  });

  /// The reading session whose place, bookmarks and book map the bar shows.
  final ReaderSession reader;

  /// The arrow before the bar, which goes back a chapter.
  final Widget previous;

  /// The arrow after the bar, which goes to the next chapter.
  final Widget next;

  /// Reports that a drag started, at the place in the book where it started.
  final ValueChanged<BookTarget>? onScrubStart;

  /// Reports each place in the book that a drag passes, before it ends.
  final ValueChanged<BookTarget>? onScrubTarget;

  /// Reports the place in the book where a drag ended. The bar shows that
  /// place until the returned future completes.
  final Future<void> Function(BookTarget target) onScrubEnd;

  /// The visible page, such as "Page 2 of 8", or "Page 2" while the count
  /// of pages is not known.
  static String _pageLabel(int? page, int? pages) {
    return page == null
        ? 'Page progress unavailable'
        : pages == null
        ? 'Page $page'
        : 'Page $page of $pages';
  }

  /// The place at [fraction] of [map], such as "37%" in an EPUB or "Page 12
  /// of 40" in a PDF.
  static String _placeAt(BookMap map, double fraction) {
    final pages = map.pages;
    return pages != null
        ? 'Page ${map.targetAt(fraction).part + 1} of $pages'
        : '${(fraction * 100).round()}%';
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      reader.documentChanges,
      reader.placeChanges,
      reader.bookmarkChanges,
      reader.bookMapChanges,
    ]),
    builder: (context, _) {
      final place = reader.visibleAddress;
      final map = reader.bookMap;
      final at = place == null ? null : map?.fractionOf(place);
      final style = Theme.of(context).textTheme.bodySmall;
      // The label keeps one line, so that a drag never changes the dock's
      // height and the page above it does not lay out again. A long chapter
      // title is cut short, and the place always shows in full.
      Widget label(String? chapter, String place) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        // Assistive technology reads the whole label, uncut.
        child: Semantics(
          label: chapter == null ? place : '$chapter · $place',
          excludeSemantics: true,
          // The place takes the width that it needs, up to the whole row,
          // and the chapter title takes what is left.
          child: LayoutBuilder(
            builder: (context, constraints) => Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (chapter != null)
                  Flexible(
                    child: Text(
                      chapter,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: style,
                    ),
                  ),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                  child: Text(
                    chapter == null ? place : ' · $place',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: style,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      Widget arranged(Widget label, Widget bar) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          label,
          Row(
            children: [
              previous,
              Expanded(child: bar),
              next,
            ],
          ),
        ],
      );
      // A PDF names its page. A native EPUB page names its number in its
      // section, which the pager learns as it lays the section out, and
      // only that label follows it. Until the number is known, the visible
      // place is its share of the book, as the label of a dragged place is.
      // A saved place has no chapter title, so the book map names the
      // chapter of a place that the pager opened at, as it does for a
      // dragged place.
      final chapter =
          place?.chapter ??
          (at == null ? null : map?.targetAt(at).chapter) ??
          'Current chapter unavailable';
      final share = map != null && at != null && map.pages == null
          ? _placeAt(map, at)
          : null;
      Widget visible() => switch (reader.pager?.pageNumber) {
        null => label(chapter, share ?? _pageLabel(place?.page, place?.pages)),
        final numbers => ValueListenableBuilder<PageNumber?>(
          valueListenable: numbers,
          builder: (_, number, _) => label(
            chapter,
            number == null
                ? share ?? _pageLabel(null, null)
                : _pageLabel(number.number, number.count),
          ),
        ),
      };
      if (map == null || at == null) {
        return arranged(
          visible(),
          const SizedBox(height: kMinInteractiveDimension),
        );
      }
      final onStart = onScrubStart;
      final onTarget = onScrubTarget;
      // Android takes a drag that starts in the gesture zone at a screen edge
      // as Back. The thumb at the start or the end of the book sits at the
      // bar's edge, so the bar keeps clear of the zone. The arrow between the
      // bar and the screen edge already keeps it a touch target's width
      // away, and the bar adds the rest of a wider zone.
      final gestures = MediaQuery.systemGestureInsetsOf(context);
      return ScrubBar(
        value: at,
        chapters: [for (final chapter in map.chapters) chapter.start],
        bookmarks: [
          for (final bookmark in reader.bookmarks)
            if (reader.addressOf(bookmark) case final address?)
              ?map.fractionOf(address),
        ],
        describe: (fraction) {
          final target = map.targetAt(fraction);
          final place = _placeAt(map, fraction);
          return target.chapter == null ? place : '${target.chapter} · $place';
        },
        onStart: onStart == null
            ? null
            : (fraction) => onStart(map.targetAt(fraction)),
        onTarget: onTarget == null
            ? null
            : (fraction) => onTarget(map.targetAt(fraction)),
        onEnd: (fraction) => onScrubEnd(map.targetAt(fraction)),
        layout: (context, bar, fraction) => arranged(
          fraction == null
              ? visible()
              : label(map.targetAt(fraction).chapter, _placeAt(map, fraction)),
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: math.max(
                0,
                math.max(gestures.left, gestures.right) -
                    kMinInteractiveDimension,
              ),
            ),
            child: bar,
          ),
        ),
      );
    },
  );
}
