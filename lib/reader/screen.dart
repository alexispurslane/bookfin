import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart' hide TextPosition;
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart';

import '../catalog/glass.dart'
    show
        CoverGlass,
        GlassSheetAction,
        PageBook,
        glassSheetTextBottom,
        glassSheetTextInset,
        glassSheetTextWidth,
        showGlassSheet;
import '../catalog/model.dart' show Book, EditionKind;
import '../foundation/derived_value.dart';
import '../foundation/listenable_selector.dart';
import '../foundation/scrub_bar.dart';
import '../foundation/theme.dart' show PillChoice;
import '../foundation/time.dart';
import '../playback/playback.dart';
import '../playback/records_screen.dart' show editReadingBookmark;
import '../playback/screen.dart';
import '../playback/timeline.dart' show openHistory;
import 'book_map.dart';
import 'session.dart';
import 'document.dart';
import 'epub/page_source.dart' show PageNumber;
import 'epub/pager.dart' show EpubLink, EpubPager, LaidNote;
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
/// side effect: it opens the panels, closes them, enters and leaves full
/// screen, and tells [ReaderSession] what the person chose. Each part of
/// the view follows only the session signal that it shows, so a page turn
/// redraws the page label and the progress bar, and a text size or reflow
/// change redraws the viewport.
///
/// Every reader view reports the same two gestures: a swipe turns the page,
/// and a tap on the page enters or leaves full screen. The page fills a
/// frame that never changes size (see [_SystemBarFrame]). The controls lie
/// over it as glass, and full screen hides them and Android's system bars.
class _ReaderScreenState extends State<ReaderScreen> {
  /// Whether the reader shows only the page: no controls, and Android's
  /// system bars hidden. Only the controls follow it, so the page does not
  /// build again when it changes.
  final _fullScreen = ValueNotifier(false);
  int? _viewToken;
  ReaderSession get reader => widget.reader;
  @override
  void dispose() {
    if (_fullScreen.value) _showSystemBars(true);
    _fullScreen.dispose();
    unawaited(reader.flush());
    if (_viewToken != null) reader.closeView(_viewToken!);
    super.dispose();
  }

  /// Shows Android's system bars over the app with [on], or hides them
  /// until the person swipes from an edge of the screen.
  static void _showSystemBars(bool on) => unawaited(
    SystemChrome.setEnabledSystemUIMode(
      on ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky,
    ),
  );

  /// Enters full screen, or leaves it.
  void _toggleFullScreen() {
    _fullScreen.value = !_fullScreen.value;
    _showSystemBars(!_fullScreen.value);
  }

  /// Shows the panel that [builder] builds on a glass sheet that shows the
  /// open book, under [title] and its [action], if any, and completes when
  /// the sheet closes.
  Future<void> _sheet(
    WidgetBuilder builder, {
    String? title,
    GlassSheetAction? action,
  }) => showGlassSheet<void>(
    context,
    book: reader.book,
    title: title,
    action: action,
    isScrollControlled: true,
    builder: builder,
  );

  /// Shows the contents. The bookmarks are in History.
  void _openContents() => unawaited(
    _sheet(
      (sheet) => ReaderContentsPanel(
        timeLeft: DerivedValue(
          reader.timeLeftChanges,
          () => reader.timeLeft?.book,
          source: reader,
        ),
        contents: reader.contents,
        onContents: (href) {
          Navigator.pop(sheet);
          unawaited(reader.goToContents(href));
        },
      ),
      title: 'Contents',
    ),
  );

  /// Shows the shared History timeline of the open book: its reading and
  /// listening moves and bookmarks. The reader comes from the [ReaderScope]
  /// above this screen, which holds this screen's session.
  void _openHistory() => openHistory(
    context,
    widget.playback,
    book: reader.book,
    showing: EditionKind.text,
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
          reader.trimMarginsChanges,
        ]),
        select: () => (
          fontSize: reader.fontSize,
          open: reader.document != null,
          reflow: reader.document is PdfBook ? reader.reflow : null,
          trimMargins: reader.document is PdfBook ? reader.trimMargins : null,
        ),
        builder: (context, on, _) => ReaderSettingsPanel(
          fontSize: on.fontSize,
          onSmaller: on.open && on.fontSize > 14
              ? () => unawaited(reader.stepFontSize(larger: false))
              : null,
          onLarger: on.open && on.fontSize < 40
              ? () => unawaited(reader.stepFontSize(larger: true))
              : null,
          night: Theme.of(context).brightness == Brightness.dark,
          onNightChanged: widget.onNightChanged,
          reflow: on.reflow,
          onReflowChanged: reader.setReflow,
          trimMargins: on.trimMargins,
          onTrimMarginsChanged: (on) => unawaited(reader.setTrimMargins(on)),
        ),
      ),
      title: 'Reading settings',
    ),
  );

  /// Shows the search panel, and ends the search when the sheet is gone,
  /// however it closed: with Close, a hit, Back or a tap outside it.
  Future<void> _openSearch() async {
    ModalRoute<Object?>? route;
    await _sheet(
      (sheet) {
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
          ),
        );
      },
      title: 'Search',
      // Close only closes the sheet. The search ends below, with the sheet.
      action: GlassSheetAction(
        'Close',
        icon: Icons.close_rounded,
        onPressed: () {},
      ),
    );
    // The sheet closes at once but slides away for a moment. Waiting until it
    // is gone keeps its results in place while it slides.
    await route?.completed;
    reader.cancelSearch();
  }

  /// Follows [link] of [pager]'s shown page. A link to a note shows the
  /// note on a glass sheet, and the page and the saved place stay. Go to
  /// note in the sheet's title row then shows the note in the book. Any
  /// other link goes to its destination. A link that the pager cannot read
  /// goes to its destination too, which reports the failure.
  Future<void> _followLink(EpubPager pager, EpubLink link) async {
    LaidNote? note;
    try {
      note = await pager.note(link, width: glassSheetTextWidth(context));
    } on ArgumentError {
      // The link names no section of the book.
    } on Exception {
      // Its section could not be prepared.
    }
    if (!mounted || !identical(reader.pager, pager)) {
      note?.dispose();
      return;
    }
    if (note == null) return reader.followLink(link.href);
    var go = false;
    ModalRoute<Object?>? route;
    await _sheet(
      (sheet) {
        route ??= ModalRoute.of(sheet);
        return ReaderNotePanel(
          note: note!,
          onCopy: (text) =>
              unawaited(Clipboard.setData(ClipboardData(text: text))),
        );
      },
      title: 'Note',
      action: GlassSheetAction(
        'Go to note',
        icon: Icons.arrow_forward_rounded,
        onPressed: () => go = true,
      ),
    );
    // The sheet slides away for a moment after it closes, and draws the note
    // until it is gone.
    await route?.completed;
    note.dispose();
    if (go && mounted && identical(reader.pager, pager)) {
      await reader.followLink(link.href);
    }
  }

  /// Saves an untitled bookmark at the shown page at once, as the player
  /// does. While the shown page holds a bookmark, asks for that bookmark's
  /// title and note in the shared bookmark editor instead.
  Future<void> _bookmark() => switch (reader.bookmarkHere) {
    null => reader.addBookmark(),
    final here => editReadingBookmark(context, reader, here),
  };

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
  /// tool turns on or off, or the Bookmark tool's state changes.
  Widget _tools(Widget? audio) => ListenableSelector(
    listenable: Listenable.merge([
      reader.documentChanges,
      reader.bookmarkChanges,
      reader.placeChanges,
      reader.bookMapChanges,
    ]),
    select: () => (
      ready: reader.ready,
      open: reader.document != null,
      book: reader.book != null,
      bookmark: reader.canBookmark,
      bookmarked: reader.bookmarkHere != null,
    ),
    builder: (_, on, _) => ReaderTools(
      onContents: on.ready ? _openContents : null,
      onSearch: on.ready ? () => unawaited(_openSearch()) : null,
      onSettings: on.open ? _openSettings : null,
      onBookmark: on.bookmark ? () => unawaited(_bookmark()) : null,
      bookmarked: on.bookmarked,
      onHistory: on.book ? _openHistory : null,
      audio: audio,
    ),
  );

  /// The player's Undo row while the session offers Undo after a move. A
  /// move made in full screen keeps its offer, so the row shows with the
  /// controls.
  Widget _undo() => ListenableBuilder(
    listenable: reader.undoChanges,
    builder: (_, _) => switch (reader.undoOffer) {
      null => const SizedBox.shrink(),
      final offer => Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
        child: UndoNotice(
          unsaved: !offer.saved,
          onUndo: () => unawaited(reader.undoMove()),
          onDismiss: reader.dismissUndo,
        ),
      ),
    },
  );

  @override
  Widget build(BuildContext context) {
    final night = Theme.of(context).brightness == Brightness.dark;
    final documentOrSize = Listenable.merge([
      reader.documentChanges,
      reader.fontSizeChanges,
    ]);
    final paper = night ? const Color(0xff251e19) : const Color(0xfff6efe2);
    // The deck's glass shows the open book.
    final page = ListenableBuilder(
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
          reader.trimMarginsChanges,
        ]),
        builder: (context, _) => _viewport(context, night),
      ),
    );
    // The system bars' icons stay readable on the paper.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: night ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: paper,
        // The keyboard of a sheet's field lies over the page too.
        resizeToAvoidBottomInset: false,
        // The page fills the screen whether or not the controls show.
        body: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: _SystemBarFrame(
                // A screen reader shows and hides the controls through the
                // page, as a tap does.
                child: ValueListenableBuilder<bool>(
                  valueListenable: _fullScreen,
                  builder: (_, fullScreen, page) => Semantics(
                    container: true,
                    explicitChildNodes: true,
                    customSemanticsActions: {
                      CustomSemanticsAction(
                        label: fullScreen
                            ? 'Show reader controls'
                            : 'Hide reader controls',
                      ): _toggleFullScreen,
                    },
                    child: page,
                  ),
                  child: page,
                ),
              ),
            ),
            ValueListenableBuilder<bool>(
              valueListenable: _fullScreen,
              builder: (_, fullScreen, controls) =>
                  fullScreen ? const SizedBox.shrink() : controls!,
              child: _ReaderControls(
                message: _message(),
                dock: ListenableSelector(
                  listenable: reader.documentChanges,
                  select: () => reader.book,
                  builder: (context, book, _) => ReaderDock(
                    book: book,
                    undo: _undo(),
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
                    // audiobook is open, so the row spaces five tools
                    // evenly without it.
                    tools: switch (widget.playback) {
                      null => _tools(null),
                      final playback => ListenableSelector(
                        listenable: playback.selectionNotifier,
                        select: () => playback.book != null,
                        builder: (_, open, _) => _tools(
                          open ? PlaybackCoverButton(playback: playback) : null,
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

  /// The reader's message about the open page on glass, while a page shows.
  /// When no page can show, the page area says it instead.
  Widget _message() => ListenableBuilder(
    listenable: Listenable.merge([
      reader.documentChanges,
      reader.saveStatusChanges,
    ]),
    builder: (context, _) =>
        reader.message == null ||
            (reader.document is! PdfBook && reader.pager == null)
        ? const SizedBox.shrink()
        : CoverGlass(
            book: reader.book,
            radius: 16,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Text(
                reader.message!,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
  );

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
        trimMargins: reader.trimMargins,
        onCancelRecognition: () => document.textSupply?.cancel(),
        onTap: _toggleFullScreen,
        onTurn: (forward) => unawaited(reader.move(forward)),
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
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                reader.message ?? 'This book is not open.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (reader.book != null && reader.edition != null)
                TextButton(
                  onPressed: () =>
                      unawaited(reader.open(reader.book!, reader.edition!)),
                  child: const Text('Retry opening'),
                ),
            ],
          ),
        ),
      );
    }
    // The pager opens the book at the session's saved place, so the page
    // is ready as soon as the viewport presents its size.
    return EpubViewport(
      key: ValueKey(token),
      pager: pager,
      fontSize: fontSize,
      sizesMainText: reader.sizesMainText,
      night: night,
      onTap: _toggleFullScreen,
      onTurn: (forward) => unawaited(reader.move(forward)),
      onLink: (link) => unawaited(_followLink(pager, link)),
      onCopy: (text) => unawaited(Clipboard.setData(ClipboardData(text: text))),
    );
  }
}

/// The room that Android's system bars take while they show. [child] lies
/// inside it, and the room stays when the bars hide in full screen, so the
/// page never moves or changes size. The strips that the bars leave show
/// the paper.
///
/// Flutter reports only the room of the bars that show, so the frame keeps
/// the largest room that each edge had at the current screen size. A new
/// screen size, such as a turn of the phone, starts again from the room
/// reported then.
class _SystemBarFrame extends StatefulWidget {
  const _SystemBarFrame({required this.child});
  final Widget child;
  @override
  State<_SystemBarFrame> createState() => _SystemBarFrameState();
}

class _SystemBarFrameState extends State<_SystemBarFrame> {
  Size? _size;
  EdgeInsets _room = EdgeInsets.zero;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final bars = MediaQuery.viewPaddingOf(context);
    // The room is a view state of the frame, derived from what Flutter
    // reported at this size, so it changes in build without a rebuild.
    if (size != _size) {
      _size = size;
      _room = bars;
    } else {
      _room = EdgeInsets.fromLTRB(
        math.max(_room.left, bars.left),
        math.max(_room.top, bars.top),
        math.max(_room.right, bars.right),
        math.max(_room.bottom, bars.bottom),
      );
    }
    return Padding(
      padding: _room,
      // The page has no system bars inside its frame.
      child: MediaQuery.removePadding(
        context: context,
        removeLeft: true,
        removeTop: true,
        removeRight: true,
        removeBottom: true,
        child: widget.child,
      ),
    );
  }
}

/// The reader's controls over the page: the [message], if any, at the top
/// and the [dock] at the foot, each out of the way of Android's system bars.
/// The page between them still takes taps and swipes.
class _ReaderControls extends StatelessWidget {
  const _ReaderControls({required this.message, required this.dock});
  final Widget message;
  final Widget dock;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
            child: message,
          ),
        ),
      ),
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: SafeArea(top: false, child: dock),
      ),
    ],
  );
}

/// The reader's glass dock at the foot of the page: the [undo] row over the
/// place in the book with its [bar], over the [tools]. The glass shows
/// [book], the open book. The dock lies over the page, so a change of its
/// height never moves the page or lays it out again.
class ReaderDock extends StatelessWidget {
  const ReaderDock({
    super.key,
    required this.bar,
    required this.tools,
    this.undo,
    this.book,
  });
  final Book? book;

  /// The Undo row, which takes no room while it offers nothing.
  final Widget? undo;

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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [?undo, bar, tools],
          ),
        ),
      ),
    ),
  );
}

/// The reader's row of tools: Contents, Search book, Reading settings,
/// Bookmark this place and History, then [audio], if any. A tool whose
/// callback is null shows but is off. Each tap goes to its own callback, so
/// the owner decides what it does.
class ReaderTools extends StatelessWidget {
  const ReaderTools({
    super.key,
    required this.onContents,
    required this.onSearch,
    required this.onSettings,
    required this.onBookmark,
    required this.bookmarked,
    required this.onHistory,
    this.audio,
  });

  /// Reports Contents, which asks for the contents.
  final VoidCallback? onContents;

  /// Reports Search book, which asks for the search panel.
  final VoidCallback? onSearch;

  /// Reports Reading settings, which asks for the text size, the theme and,
  /// in a PDF, the reflow choice.
  final VoidCallback? onSettings;

  /// Reports a tap on the Bookmark tool, which asks to bookmark the shown
  /// place, or, while it is [bookmarked], to name that bookmark.
  final VoidCallback? onBookmark;

  /// Whether the shown page holds a bookmark. The Bookmark tool then fills
  /// its icon and reads Bookmarked.
  final bool bookmarked;

  /// Reports History, which asks for the book's History timeline.
  final VoidCallback? onHistory;

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
        bookmarked
            ? button(
                'Bookmarked',
                const Icon(Icons.bookmark_rounded),
                onBookmark,
              )
            : button(
                'Bookmark this place',
                const Icon(Icons.bookmark_add_outlined),
                onBookmark,
              ),
        button('History', const Icon(Icons.history_rounded), onHistory),
        ?audio,
      ],
    );
  }
}

/// The reading settings: the text size, the reading theme and, for a PDF,
/// whether its pages show as reflowed text, for a sheet headed Reading
/// settings. A size button whose callback is null shows but is off.
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
    this.trimMargins,
    this.onTrimMarginsChanged,
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

  /// Whether original PDF pages show their content crop. Null for books
  /// that are not PDFs, which have no Trim margins control.
  final bool? trimMargins;

  /// Reports whether original PDF pages should show their content crop.
  final ValueChanged<bool>? onTrimMarginsChanged;

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
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
              if (trimMargins case final on?)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Trim margins'),
                    value: on,
                    onChanged: onTrimMarginsChanged,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The book's table of contents. A tap on an entry reports its place
/// through [onContents].
class ReaderContentsPanel extends StatelessWidget {
  const ReaderContentsPanel({
    super.key,
    this.timeLeft,
    required this.contents,
    required this.onContents,
  });

  /// The estimated reading time left in the book, which shows above the
  /// contents while it is known.
  final ValueListenable<Duration?>? timeLeft;

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
          if (timeLeft case final timeLeft?)
            ValueListenableBuilder<Duration?>(
              valueListenable: timeLeft,
              builder: (context, left, _) => left == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '${estimatedTime(left)} left in book',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
            ),
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

/// A note of the book, [note], for a sheet headed Note. A long note
/// scrolls. Copy of selected text reports [onCopy].
class ReaderNotePanel extends StatefulWidget {
  const ReaderNotePanel({super.key, required this.note, required this.onCopy});
  final LaidNote note;

  /// Reports the text that the person chose to copy.
  final ValueChanged<String> onCopy;

  @override
  State<ReaderNotePanel> createState() => _ReaderNotePanelState();
}

class _ReaderNotePanelState extends State<ReaderNotePanel> {
  final _scroll = ScrollController();

  /// How far a scrolled note fades out under the title row: the room that
  /// the title row leaves below its text.
  static const _topFade = 16.0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .7,
      ),
      // A long note fades out under the title row once it scrolls, and in
      // the space above the sheet's bottom edge while more of it follows.
      // At its end that space is empty.
      child: ListenableBuilder(
        listenable: _scroll,
        builder: (context, child) {
          final top = _scroll.hasClients
              ? _scroll.offset.clamp(0.0, _topFade)
              : 0.0;
          return ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (bounds) => LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: const [
                Colors.transparent,
                Colors.black,
                Colors.black,
                Colors.transparent,
              ],
              stops: [
                0,
                math.min(1, top / bounds.height),
                math.max(0, 1 - glassSheetTextBottom / bounds.height),
                1,
              ],
            ).createShader(bounds),
            child: child,
          );
        },
        // The note lines up with the sheet's title, right under its row.
        child: SingleChildScrollView(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(
            glassSheetTextInset,
            0,
            glassSheetTextInset,
            glassSheetTextBottom,
          ),
          child: Center(
            child: EpubNoteView(note: widget.note, onCopy: widget.onCopy),
          ),
        ),
      ),
    ),
  );
}

/// A search field over the [hits] of the last search, for a sheet headed
/// Search. [searching] shows that a search runs, and [error] says why a
/// search is incomplete.
class ReaderSearchPanel extends StatefulWidget {
  const ReaderSearchPanel({
    super.key,
    required this.searching,
    required this.hits,
    required this.error,
    required this.onSearch,
    required this.onOpenHit,
  });
  final bool searching;
  final List<ReaderHit> hits;
  final String? error;

  /// Reports the query that the person submitted.
  final ValueChanged<String> onSearch;

  /// Reports the hit that the person chose.
  final ValueChanged<ReaderHit> onOpenHit;
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
///
/// A drag keeps the map that the bar showed when it started until the move
/// that it reported ends. So the marks and the label under the finger do not
/// change while the pager lays out sections, and the release goes to the
/// place that the label named.
class ReaderScrubBar extends StatefulWidget {
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

  @override
  State<ReaderScrubBar> createState() => _ReaderScrubBarState();
}

class _ReaderScrubBarState extends State<ReaderScrubBar> {
  /// The map of the running drag, until the move that it reported ends.
  BookMap? _held;

  /// The visible page, such as "Page 2 of 8", or "Page 2" while the count
  /// of pages is not known.
  static String _pageLabel(int? page, int? pages) {
    return page == null
        ? 'Page progress unavailable'
        : pages == null
        ? 'Page $page'
        : 'Page $page of $pages';
  }

  /// The place at [fraction] of [map]: its page among the book's pages,
  /// such as "Page 12 of 40", once the map knows every page, else its share
  /// of the book, such as "37%".
  static String _placeAt(BookMap map, double fraction) =>
      switch (map.targetAt(fraction).page) {
        final page? => 'Page $page of ${map.pages}',
        null => '${(fraction * 100).round()}%',
      };

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      widget.reader.documentChanges,
      widget.reader.placeChanges,
      widget.reader.bookmarkChanges,
      widget.reader.bookMapChanges,
    ]),
    builder: (context, _) {
      final reader = widget.reader;
      final place = reader.visibleAddress;
      final map = _held ?? reader.bookMap;
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
              widget.previous,
              Expanded(child: bar),
              widget.next,
            ],
          ),
        ],
      );
      // A PDF names its page. A native EPUB page names its number, which the
      // pager learns as it lays the book out, and only that label follows
      // it: in its section until every section is laid out, then in the
      // whole book. Until the number is known, the visible place is its
      // share of the book, as the label of a dragged place is.
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
      // The visible place adds the time left in its chapter once the
      // reader knows the person's speed. Only the label follows it.
      Widget visible() => ListenableBuilder(
        listenable: reader.timeLeftChanges,
        builder: (_, _) {
          final left = reader.timeLeft;
          String timed(String place) => left == null
              ? place
              : '$place · ${estimatedTime(left.chapter)} left in chapter';
          return switch (reader.pager?.pageNumber) {
            null => label(
              chapter,
              timed(share ?? _pageLabel(place?.page, place?.pages)),
            ),
            final numbers => ValueListenableBuilder<PageNumber?>(
              valueListenable: numbers,
              builder: (_, number, _) => label(
                chapter,
                timed(
                  number == null
                      ? share ?? _pageLabel(null, null)
                      : _pageLabel(number.number, number.count),
                ),
              ),
            ),
          };
        },
      );
      if (map == null || at == null) {
        return arranged(
          visible(),
          const SizedBox(height: kMinInteractiveDimension),
        );
      }
      final onStart = widget.onScrubStart;
      final onTarget = widget.onScrubTarget;
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
        onStart: (fraction) {
          // The map shows already, so the bar need not build again.
          _held = map;
          onStart?.call(map.targetAt(fraction));
        },
        onTarget: onTarget == null
            ? null
            : (fraction) => onTarget(map.targetAt(fraction)),
        onEnd: (fraction) async {
          try {
            await widget.onScrubEnd(map.targetAt(fraction));
          } finally {
            if (mounted) setState(() => _held = null);
          }
        },
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
