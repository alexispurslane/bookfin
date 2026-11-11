import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../catalog/book_cover.dart';
import '../catalog/glass.dart';
import '../catalog/model.dart';
import '../foundation/derived_value.dart';
import '../foundation/listenable_selector.dart';
import '../foundation/scrub_bar.dart';
import '../foundation/theme.dart';
import '../foundation/time.dart';
import '../sync/alert.dart'
    show BookConflictAlert, RecordSyncScope, chooseConflict;
import 'playback.dart';
import 'recent.dart';
import 'records_screen.dart';
import 'timeline.dart';

// The player surfaces in this file are controllers: PlayerView for the
// Listening page and the player pane, and PlaybackMiniPlayer and
// ReplacementStartNotice for the surfaces that several screens show. Each
// one wires pure controls, such as PlayPauseButton and PositionSlider, to
// Playback. A control draws the values it gets and reports what the
// listener did. Each value is followed by the lowest widget that shows it,
// so a playing tick rebuilds only the position widgets.

/// The open book floating over the page, with play and a forward jump. A tap
/// on the book opens the player.
class PlaybackMiniPlayer extends StatelessWidget {
  const PlaybackMiniPlayer({
    super.key,
    required this.playback,
    this.onOpenBook,
  });
  final Playback playback;

  /// Lets the opened player offer the book details page.
  final ValueChanged<Book>? onOpenBook;
  @override
  Widget build(BuildContext context) => _withOpenBook(
    playback,
    (context, book) => MiniPlayerCard(
      book: book,
      onOpen: () => openPlayer(context, playback, onOpenBook: onOpenBook),
      notice: _undoNotice(playback),
      controls: [
        _playPause(playback),
        _jump(playback, forward: true, compact: true),
      ],
      progress: _progress(playback),
    ),
  );
}

/// The open audiobook as a round button: its cover inside a ring of how far
/// through it the open place is. A tap plays or pauses, and a long press
/// opens the player. With no audiobook open, it takes no room.
class PlaybackCoverButton extends StatelessWidget {
  const PlaybackCoverButton({super.key, required this.playback});
  final Playback playback;

  @override
  Widget build(BuildContext context) => _withOpenBook(
    playback,
    (context, book) => _followPlayState(
      playback,
      (context, state, onPlayPause) => CoverPlayButton(
        book: book,
        playing: state.playing,
        starting: state.starting,
        progress: _progress(playback),
        onPlayPause: onPlayPause,
        onOpen: () => openPlayer(context, playback),
      ),
    ),
  );
}

/// Opens the player as a glass pane that rises over the current page.
void openPlayer(
  BuildContext context,
  Playback playback, {
  ValueChanged<Book>? onOpenBook,
}) => unawaited(
  showGlassSheet<void>(
    context,
    book: playback.book,
    expand: true,
    builder: (_) =>
        PlayerView(playback: playback, onOpenBook: onOpenBook, pane: true),
  ),
);

/// Offers to start the replacement of a changed recording from its
/// beginning, after the listener confirms.
class ReplacementStartNotice extends StatelessWidget {
  const ReplacementStartNotice({
    super.key,
    required this.playback,
    this.onStarted,
  });
  final Playback playback;

  /// Runs after the replacement starts.
  final VoidCallback? onStarted;

  @override
  Widget build(BuildContext context) => ListenableSelector<AudioReplacement?>(
    // The replacement offer has no narrow signal, so this follows every
    // change of Playback and rebuilds only when the offer changes.
    listenable: playback,
    select: () => playback.replacementStart,
    builder: (context, request, _) => request == null
        ? const SizedBox.shrink()
        : ReplacementOffer(
            request: request,
            onStartReplacement: (request) =>
                unawaited(_start(context, request)),
          ),
  );

  Future<void> _start(BuildContext context, AudioReplacement request) async {
    final confirmed = await confirmAction(
      context,
      title: 'Start replacement audio?',
      message:
          'Start ${request.edition.label} from the beginning. '
          'Your old position (${audioTime(request.previous.milliseconds)} within its original audio file), '
          'history and bookmarks will be kept separately. '
          'Old positions will not be applied to changed audio.',
      action: 'Start from beginning',
    );
    if (!confirmed) {
      playback.cancelReplacement(request);
      return;
    }
    await playback.confirmReplacement(request);
    if (context.mounted &&
        playback.edition == request.edition &&
        playback.replacementStart == null) {
      onStarted?.call();
    }
  }
}

/// The Listening page, or the player pane over another page: the open book
/// on its stage with the player controls, and the books listened to
/// recently.
class PlayerView extends StatelessWidget {
  const PlayerView({
    super.key,
    required this.playback,
    this.onOpenBook,
    this.pane = false,
  });
  final Playback playback;

  /// Shows the player in a glass pane over the page, with a close button,
  /// instead of on its own stage.
  final bool pane;

  /// Opens the book details page. The More menu offers it only when set.
  final ValueChanged<Book>? onOpenBook;

  @override
  Widget build(BuildContext context) => ListenableSelector<(Book?, Edition?)>(
    listenable: playback.selectionNotifier,
    select: () => (playback.book, playback.edition),
    builder: (context, open, _) {
      final (book, _) = open;
      if (book == null) return _nothingOpen(context);
      final base = Theme.of(context);
      final night = base.brightness == Brightness.dark;
      return Theme(
        data: night ? theaterTheme(base) : base,
        // Sheets, dialogs and menus opened on the stage are about this book.
        child: PageBook(
          book: book,
          child: Builder(builder: (context) => _stage(context, book, night)),
        ),
      );
    },
  );

  void _resume(RecentListening entry) =>
      unawaited(playback.open(entry.book, entry.edition));

  Widget _nothingOpen(BuildContext context) => ListView(
    padding: EdgeInsets.fromLTRB(20, 16, 20, 32 + floatingBarInset(context)),
    children: [
      RecordSaveStatus(playback: playback),
      ReplacementStartNotice(playback: playback),
      RecentListeningList(
        recent: recentProgress(playback),
        open: null,
        onResume: _resume,
        empty: const Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: Text(
            'Choose a downloaded audio edition to start listening.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
      const SizedBox(height: 12),
      Center(
        child: TextButton(
          onPressed: () =>
              openHistory(context, playback, showing: EditionKind.audio),
          child: const Text('History'),
        ),
      ),
    ],
  );

  Widget _stage(BuildContext context, Book book, bool night) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final top = pane ? 0.0 : MediaQuery.paddingOf(context).top;
    final narrator = playback.edition!.narrator;
    final chapters = playback.chapters;
    final total = playback.durationMilliseconds;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: night ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: ColoredBox(
        // In a pane the glass is the background.
        color: pane ? Colors.transparent : scheme.surface,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Stack(
              children: [
                if (!pane)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    height: top + 380,
                    child: CoverBackdrop(book: book),
                  ),
                Padding(
                  padding: EdgeInsets.only(top: top),
                  child: Column(
                    children: [
                      _topBar(context, book),
                      StageCover(book: book, width: 168),
                      const SizedBox(height: 20),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          book.title,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontFamily: 'Source Serif 4',
                            fontWeight: FontWeight.w600,
                            height: 1.1,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: book.author,
                                style: TextStyle(color: scheme.onSurface),
                              ),
                              if (narrator != null)
                                TextSpan(text: ' · read by $narrator'),
                            ],
                          ),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      if (chapters.length > 1)
                        ListenableSelector<int?>(
                          listenable: playback.positionNotifier,
                          select: () => playback.chapterIndex,
                          builder: (context, chapter, _) => chapter == null
                              ? const SizedBox.shrink()
                              : Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    24,
                                    10,
                                    24,
                                    0,
                                  ),
                                  child: Text(
                                    '${chapters[chapter].name} · ${chapter + 1} of ${chapters.length}',
                                    textAlign: TextAlign.center,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      color: glowAccent(theme),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                        ),
                      if (RecordSyncScope.of(context) case final sync?)
                        BookConflictAlert(
                          conflicts: sync.conflictsNotifier,
                          book: book,
                          compact: true,
                          padding: const EdgeInsets.only(top: 12),
                          onChoose: (record) => unawaited(
                            chooseConflict(
                              context,
                              sync,
                              book: book,
                              record: record,
                            ),
                          ),
                        ),
                      RecordSaveStatus(playback: playback),
                      ReplacementStartNotice(playback: playback),
                      const SizedBox(height: 10),
                      // The position ticks while audio plays. Its own layer
                      // keeps the cover and blur behind it from repainting.
                      ListenableBuilder(
                        // The bookmark marks on the slider follow the records.
                        listenable: Listenable.merge([
                          playback.positionNotifier,
                          playback.recordsNotifier,
                        ]),
                        builder: (context, _) {
                          final position = playback.editionMilliseconds;
                          if (total == null || total <= 0 || position == null) {
                            return RepaintBoundary(
                              child: Text(
                                'File position · ${audioTime(playback.position?.milliseconds ?? 0)}',
                                textAlign: TextAlign.center,
                              ),
                            );
                          }
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: RepaintBoundary(
                              child: PositionSlider(
                                position: position,
                                total: total,
                                chapters: chapters,
                                chapterIndex: playback.chapterIndex,
                                bookmarks: playback.editionBookmarks,
                                onSeekStart: () =>
                                    unawaited(playback.beginSliderSeek()),
                                onSeekEnd: playback.finishSliderSeek,
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _jump(
                            playback,
                            forward: false,
                            onLongPress: () => _jumps(context),
                          ),
                          const SizedBox(width: 30),
                          RepaintBoundary(
                            child: _playPause(playback, large: true),
                          ),
                          const SizedBox(width: 30),
                          _jump(
                            playback,
                            forward: true,
                            onLongPress: () => _jumps(context),
                          ),
                        ],
                      ),
                      // The Undo pill comes and goes in a slot that keeps
                      // its height, so the tool row below never moves.
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 8,
                        ),
                        child: SizedBox(
                          height: UndoNotice.height,
                          child: _undoNotice(playback),
                        ),
                      ),
                      _tools(context),
                    ],
                  ),
                ),
              ],
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                30,
                20,
                32 + floatingBarInset(context),
              ),
              child: RecentListeningList(
                recent: recentProgress(playback),
                open: book,
                onResume: _resume,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topBar(BuildContext context, Book book) => SizedBox(
    height: kToolbarHeight,
    child: Row(
      children: [
        const SizedBox(width: 4),
        if (pane)
          IconButton(
            tooltip: 'Close player',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.keyboard_arrow_down_rounded),
          )
        else if (Navigator.of(context).canPop())
          const BackButton(),
        const Spacer(),
        GlassMenuButton(
          tooltip: 'More player actions',
          icon: const Icon(Icons.more_horiz_rounded),
          items: [
            GlassMenuItem(
              'Jump lengths',
              icon: Icons.replay_rounded,
              onSelected: () => unawaited(_jumps(context)),
            ),
            if (onOpenBook != null)
              GlassMenuItem(
                'Book details',
                icon: Icons.article_outlined,
                onSelected: () => onOpenBook!(book),
              ),
          ],
        ),
        const SizedBox(width: 8),
      ],
    ),
  );

  /// Chapters, Bookmark, Speed, Sleep, and History, in one rounded row. The
  /// row itself follows nothing. Each tool that shows a value follows it.
  Widget _tools(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = glowAccent(theme);
    final value = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: scheme.onSurface,
    );
    final divider = VerticalDivider(width: 1, color: scheme.outlineVariant);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(20),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: IntrinsicHeight(
          child: Row(
            children: [
              Expanded(
                child: _Tool(
                  label: 'Chapters',
                  top: Icon(Icons.format_list_bulleted_rounded, color: accent),
                  onTap: () => unawaited(_chapters(context)),
                ),
              ),
              divider,
              // One tap saves an untitled bookmark. Right after, the tool
              // reads Bookmarked, and a tap names that bookmark. The place
              // moves away from the bookmark as audio plays.
              Expanded(
                child: ListenableSelector<Bookmark<AudioPosition>?>(
                  listenable: Listenable.merge([
                    playback.positionNotifier,
                    playback.recordsNotifier,
                  ]),
                  select: () => playback.bookmarkHere,
                  builder: (context, here, _) => here == null
                      ? _Tool(
                          label: 'Bookmark',
                          top: Icon(
                            Icons.bookmark_border_rounded,
                            color: accent,
                          ),
                          onTap: () => unawaited(playback.addBookmark()),
                        )
                      : _Tool(
                          label: 'Bookmarked',
                          top: Icon(Icons.bookmark_rounded, color: accent),
                          onTap: () => unawaited(
                            editAudioBookmark(
                              context,
                              playback,
                              bookmark: here,
                            ),
                          ),
                        ),
                ),
              ),
              divider,
              Expanded(
                child: _Tool(
                  label: 'Speed',
                  top: ListenableSelector<double>(
                    listenable: playback.settingsNotifier,
                    select: () => playback.playbackSpeed,
                    builder: (context, speed, _) =>
                        Text('${_rate(speed)}×', style: value),
                  ),
                  onTap: () => unawaited(_speed(context)),
                ),
              ),
              divider,
              Expanded(
                child: _Tool(
                  label: 'Sleep',
                  top: ValueListenableBuilder(
                    valueListenable: playback.sleepNotifier,
                    builder: (context, left, _) => left == null
                        ? Icon(Icons.bedtime_outlined, color: accent)
                        : Text(
                            '${(left.inSeconds / 60).ceil()} m',
                            style: value,
                          ),
                  ),
                  onTap: () => unawaited(_sleep(context)),
                ),
              ),
              divider,
              Expanded(
                child: _Tool(
                  label: 'History',
                  top: Icon(Icons.history_rounded, color: accent),
                  onTap: () => openHistory(
                    context,
                    playback,
                    book: playback.book,
                    showing: EditionKind.audio,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _chapters(BuildContext context) => showChapters(
    context,
    chapters: playback.chapters,
    current: playback.chapterIndex,
    position: playback.position?.milliseconds ?? 0,
    onChapter: (chapter) =>
        unawaited(playback.seekSource(chapter.sourceKey, chapter.milliseconds)),
  );

  Future<void> _speed(BuildContext context) => showGlassChoices<double>(
    context,
    title: 'Playback speed',
    choices: [
      for (final speed in [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0])
        (speed, '${_rate(speed)}×'),
    ],
    current: playback.playbackSpeed,
    onSelected: (speed) => unawaited(playback.setSpeed(speed)),
  );

  Future<void> _sleep(BuildContext context) => showGlassChoices<Duration?>(
    context,
    title: 'Sleep timer',
    choices: [
      for (final minutes in [5, 15, 30, 45, 60])
        (Duration(minutes: minutes), '$minutes minutes'),
      (null, 'Turn off'),
    ],
    current: playback.sleepTimer,
    onSelected: (timer) => unawaited(playback.setSleep(timer)),
  );

  Future<void> _jumps(BuildContext context) async {
    var backward = playback.backwardSeconds;
    var forward = playback.forwardSeconds;
    await showGlassSheet<void>(
      context,
      title: 'Jump lengths',
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  initialValue: backward,
                  decoration: const InputDecoration(
                    labelText: 'Back, in seconds',
                  ),
                  items: {5, 10, 15, 20, 30, 45, 60, backward}
                      .toList()
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text('$value'),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => backward = value!),
                ),
                DropdownButtonFormField<int>(
                  initialValue: forward,
                  decoration: const InputDecoration(
                    labelText: 'Forward, in seconds',
                  ),
                  items: {5, 10, 15, 20, 30, 45, 60, forward}
                      .toList()
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text('$value'),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => forward = value!),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    unawaited(playback.setJumps(backward, forward));
                    Navigator.pop(context);
                  },
                  child: const Text('Save jump lengths'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// The wiring that the controllers above share. Each function builds a
// control that follows its own signal and commands Playback.

/// Builds [builder] with the book open in [playback], and nothing while no
/// book is open. It rebuilds only when the open book or edition changes.
Widget _withOpenBook(
  Playback playback,
  Widget Function(BuildContext context, Book book) builder,
) => ListenableSelector<(Book?, Edition?)>(
  listenable: playback.selectionNotifier,
  select: () => (playback.book, playback.edition),
  builder: (context, open, _) {
    final (book, _) = open;
    return book == null ? const SizedBox.shrink() : builder(context, book);
  },
);

/// How far through its edition the open place of [playback] is, from 0 to 1,
/// or null when the edition's length is unknown.
ValueListenable<double>? _progress(Playback playback) {
  final total = playback.durationMilliseconds;
  return total != null && total > 0
      ? DerivedValue(
          playback.positionNotifier,
          () => (playback.editionMilliseconds ?? 0) / total,
        )
      : null;
}

/// Builds [builder] with whether [playback] plays or starts the open
/// edition, and with the tap that means Pause while it plays or starts, else
/// Play.
Widget _followPlayState(
  Playback playback,
  Widget Function(
    BuildContext context,
    ({bool playing, bool starting}) state,
    VoidCallback onPlayPause,
  )
  builder,
) {
  bool starting() {
    final edition = playback.starting;
    return edition != null && edition.id == playback.edition?.id;
  }

  return ListenableSelector<({bool playing, bool starting})>(
    listenable: Listenable.merge([
      playback.selectionNotifier,
      playback.startingNotifier,
    ]),
    select: () => (playing: playback.playing, starting: starting()),
    builder: (context, state, _) => builder(
      context,
      state,
      () => unawaited(
        playback.playing || starting() ? playback.pause() : playback.play(),
      ),
    ),
  );
}

/// The play button, following whether [playback] plays or starts the open
/// edition. A tap while it starts or plays means Pause.
Widget _playPause(Playback playback, {bool large = false}) => _followPlayState(
  playback,
  (context, state, onPlayPause) => PlayPauseButton(
    playing: state.playing,
    starting: state.starting,
    large: large,
    onPlayPause: onPlayPause,
  ),
);

/// A jump button, following the jump length of its direction.
Widget _jump(
  Playback playback, {
  required bool forward,
  bool compact = false,
  VoidCallback? onLongPress,
}) => ListenableSelector<int>(
  listenable: playback.settingsNotifier,
  select: () => forward ? playback.forwardSeconds : playback.backwardSeconds,
  builder: (context, seconds, _) => JumpButton(
    forward: forward,
    seconds: seconds,
    compact: compact,
    onLongPress: onLongPress,
    onJump: (forward) => unawaited(playback.jump(forward: forward)),
  ),
);

/// The Undo offer after a position change, while there is one.
Widget _undoNotice(Playback playback) => ValueListenableBuilder(
  valueListenable: playback.undoNotifier,
  builder: (context, offer, _) => offer == null
      ? const SizedBox.shrink()
      : UndoNotice(
          unsaved: !offer.saved,
          onUndo: () => unawaited(playback.undoSeek()),
          onDismiss: playback.dismissUndo,
        ),
);

/// One tool of the player's tool row: [top] over a small [label].
class _Tool extends StatelessWidget {
  const _Tool({required this.label, required this.top, required this.onTap});
  final String label;
  final Widget top;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 10, 4, 9),
        child: Column(
          children: [
            SizedBox(height: 22, child: Center(child: top)),
            const SizedBox(height: 3),
            // Five tools share the row, so a long label shrinks a little
            // instead of wrapping onto a second line.
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Shows [chapters] on a glass sheet titled Chapters. A tap on a chapter
/// goes to [onChapter], then closes the sheet. [current] and [position] are
/// as in [ChapterList].
Future<void> showChapters(
  BuildContext context, {
  required List<PlaybackChapter> chapters,
  required int? current,
  required int position,
  required ValueChanged<PlaybackChapter> onChapter,
}) => showGlassSheet<void>(
  context,
  title: 'Chapters',
  isScrollControlled: true,
  builder: (sheet) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.65,
    builder: (context, scroll) => ChapterList(
      controller: scroll,
      chapters: chapters,
      current: current,
      position: position,
      onChapter: (chapter) {
        onChapter(chapter);
        Navigator.pop(sheet);
      },
    ),
  ),
);

/// The chapters of an edition, each with where it starts in the edition. The
/// current chapter stands out and shows how far through it the place is. A
/// tap on a chapter reports it through [onChapter].
class ChapterList extends StatelessWidget {
  const ChapterList({
    super.key,
    required this.chapters,
    required this.current,
    required this.position,
    required this.onChapter,
    this.controller,
  });

  /// The chapters in order.
  final List<PlaybackChapter> chapters;

  /// The index in [chapters] of the chapter that holds the place, or null
  /// when none does.
  final int? current;

  /// The place in the file of the current chapter, in milliseconds from the
  /// start of that file.
  final int position;

  /// Reports a tapped chapter, which asks to go to its start.
  final ValueChanged<PlaybackChapter> onChapter;

  /// Scrolls the list, for example the controller of a draggable sheet.
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = glowAccent(theme);
    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      children: [
        for (final (index, chapter) in chapters.indexed) ...[
          if (index > 0) Divider(height: 1, color: scheme.outlineVariant),
          InkWell(
            onTap: () => onChapter(chapter),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: DefaultTextStyle.merge(
                style: index == current
                    ? TextStyle(color: accent, fontWeight: FontWeight.w600)
                    : null,
                child: Row(
                  children: [
                    SizedBox(
                      width: 26,
                      child: Text(
                        '${index + 1}',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 12,
                          color: index == current
                              ? accent
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(chapter.name),
                          if (index == current)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: ProgressLine(
                                color: accent,
                                value: _share(index),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      audioTime(
                        chapter.editionMilliseconds ?? chapter.milliseconds,
                      ),
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// How far through chapter [index] the place is, from 0 to 1, or null when
  /// the chapter's end is unknown.
  double? _share(int index) {
    final chapter = chapters[index];
    final next = index + 1 < chapters.length ? chapters[index + 1] : null;
    final end = next != null && next.sourceKey == chapter.sourceKey
        ? next.milliseconds
        : null;
    if (end == null || end <= chapter.milliseconds) return null;
    return ((position - chapter.milliseconds) / (end - chapter.milliseconds))
        .clamp(0, 1);
  }
}

/// The icon of every Play control: a progress ring while its audio is
/// [starting], a pause sign while it is [playing], else a play arrow. It
/// takes its size and color from the surrounding icon theme, unless [size]
/// or [color] is given.
class PlayStateIcon extends StatelessWidget {
  const PlayStateIcon({
    super.key,
    this.playing = false,
    this.starting = false,
    this.size,
    this.color,
  });
  final bool playing;
  final bool starting;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    if (!starting) {
      return Icon(
        playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
        size: size,
        color: color,
      );
    }
    final theme = IconTheme.of(context);
    final side = size ?? theme.size ?? 24;
    // The ring fills the middle of the icon box, like the arrow's glyph.
    return SizedBox.square(
      dimension: side,
      child: Padding(
        padding: EdgeInsets.all(side / 8),
        child: CircularProgressIndicator(
          strokeWidth: side / 12,
          color: color ?? theme.color,
        ),
      ),
    );
  }
}

/// Play while paused, Pause while audio plays or starts. [large] is the
/// stage's round button, and the default is the mini player's icon button.
class PlayPauseButton extends StatelessWidget {
  const PlayPauseButton({
    super.key,
    required this.playing,
    required this.onPlayPause,
    this.large = false,
    this.starting = false,
  });
  final bool playing;

  /// Whether a Play command waits for the audio to sound. The button then
  /// shows a progress ring and offers Pause.
  final bool starting;

  /// Reports a tap. The listener means Pause while [playing] or [starting],
  /// else Play.
  final VoidCallback onPlayPause;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final label = playing || starting ? 'Pause' : 'Play';
    if (!large) {
      return IconButton(
        tooltip: label,
        onPressed: onPlayPause,
        icon: PlayStateIcon(playing: playing, starting: starting),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0x73000000)
                    : scheme.primary.withValues(alpha: 0.35),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Material(
            color: scheme.primary,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onPlayPause,
              child: SizedBox.square(
                dimension: 72,
                child: Center(
                  child: PlayStateIcon(
                    playing: playing,
                    starting: starting,
                    size: 38,
                    color: scheme.onPrimary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A circular arrow with the jump length inside.
class JumpButton extends StatelessWidget {
  const JumpButton({
    super.key,
    required this.forward,
    required this.seconds,
    required this.onJump,
    this.onLongPress,
    this.compact = false,
  });

  /// Whether the button jumps forward rather than back.
  final bool forward;

  /// The jump length shown, in seconds.
  final int seconds;

  /// Reports a tap with [forward].
  final ValueChanged<bool> onJump;

  /// Reports a long press, which asks to change the jump lengths.
  final VoidCallback? onLongPress;

  /// The mini player's smaller size.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface;
    final label = '${forward ? 'Forward' : 'Back'} $seconds seconds';
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: InkResponse(
          radius: compact ? 22 : 30,
          onTap: () => onJump(forward),
          onLongPress: onLongPress,
          child: SizedBox.square(
            dimension: compact ? 44 : 56,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Transform.flip(
                  flipX: forward,
                  child: Icon(
                    Icons.replay_rounded,
                    size: compact ? 30 : 42,
                    color: color,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    '$seconds',
                    style: TextStyle(
                      fontSize: compact ? 8.5 : 11,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The position slider with chapter and bookmark marks, and the elapsed
/// time, the time left in the chapter, and the time left in the book below
/// it. While the listener drags, it shows the dragged place instead of
/// [position], until the seek that the drag reports lands.
class PositionSlider extends StatelessWidget {
  const PositionSlider({
    super.key,
    required this.position,
    required this.total,
    required this.chapters,
    required this.chapterIndex,
    required this.bookmarks,
    required this.onSeekStart,
    required this.onSeekEnd,
  });

  /// The open place, in milliseconds from the edition's start.
  final int position;

  /// The length of the edition, in milliseconds.
  final int total;
  final List<PlaybackChapter> chapters;

  /// The index in [chapters] of the chapter that holds [position].
  final int? chapterIndex;
  final List<EditionBookmark> bookmarks;

  /// Reports that a drag started, at the open place.
  final VoidCallback onSeekStart;

  /// Reports where a drag ended, in milliseconds from the edition's start.
  /// The slider shows that place until the returned future completes.
  final Future<void> Function(int milliseconds) onSeekEnd;

  @override
  Widget build(BuildContext context) {
    // An edition of no length has every place at its start.
    double fraction(int milliseconds) => total > 0 ? milliseconds / total : 0;
    int milliseconds(double fraction) => (fraction * total).round();
    final index = chapterIndex;
    final next = index != null && index + 1 < chapters.length
        ? chapters[index + 1].editionMilliseconds
        : null;
    final chapterLeft = index == null ? null : (next ?? total) - position;
    final small = TextStyle(
      fontSize: 12,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return ScrubBar(
      value: fraction(position),
      chapters: [
        for (final PlaybackChapter(:editionMilliseconds) in chapters)
          if (editionMilliseconds != null) fraction(editionMilliseconds),
      ],
      bookmarks: [for (final (bookmark: _, :at) in bookmarks) fraction(at)],
      describe: (value) => audioTime(milliseconds(value)),
      onStart: (_) => onSeekStart(),
      onEnd: (value) => onSeekEnd(milliseconds(value)),
      layout: (context, bar, target) {
        final shown = (target == null ? position : milliseconds(target)).clamp(
          0,
          total,
        );
        final times = Row(
          children: [
            Expanded(child: Text(audioTime(shown), style: small)),
            if (chapterLeft != null)
              Text(
                chapterLeft < 60000
                    ? 'chapter ${(chapterLeft / 1000).ceil()} s left'
                    : 'chapter ${duration(chapterLeft)} left',
                style: small,
              ),
            Expanded(
              child: Text(
                '${audioTime(total - shown)} left',
                textAlign: TextAlign.right,
                style: small,
              ),
            ),
          ],
        );
        return Column(mainAxisSize: MainAxisSize.min, children: [bar, times]);
      },
    );
  }
}

String _rate(double value) =>
    value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

/// A one-line pill that says that the position changed, and offers to go
/// back to the previous place.
class UndoNotice extends StatelessWidget {
  const UndoNotice({
    super.key,
    required this.unsaved,
    required this.onUndo,
    required this.onDismiss,
  });

  /// Whether the previous place is not saved yet.
  final bool unsaved;
  final VoidCallback onUndo;
  final VoidCallback onDismiss;

  /// The height of the pill. The player keeps a slot of this height under
  /// its transport controls, whether the pill shows or not.
  static const height = 44.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      height: height,
      padding: const EdgeInsetsDirectional.only(start: 16, end: 2),
      decoration: ShapeDecoration(
        color: scheme.surfaceContainer,
        shape: StadiumBorder(side: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Row(
          children: [
            Expanded(
              child: Text(
                unsaved
                    ? 'Saving your previous place'
                    : 'Your previous place is saved',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurface,
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: onUndo,
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              child: const Text('Undo'),
            ),
            IconButton(
              tooltip: 'Dismiss Undo',
              onPressed: onDismiss,
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    );
  }
}

/// The open book on glass at the foot of a page: its cover, title and
/// author, the [controls] beside them, and the [progress] line below.
class MiniPlayerCard extends StatelessWidget {
  const MiniPlayerCard({
    super.key,
    required this.book,
    required this.onOpen,
    required this.controls,
    this.progress,
    this.notice,
  });
  final Book book;

  /// Reports a tap on the book, which asks to open the player.
  final VoidCallback onOpen;

  /// The buttons right of the book.
  final List<Widget> controls;

  /// How far through the book the place is, from 0 to 1. Only the line
  /// that shows it follows it. Null when the length is unknown.
  final ValueListenable<double>? progress;

  /// Shown above the glass, such as the Undo offer.
  final Widget? notice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final progress = this.progress;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ?notice,
            CoverGlass(
              book: book,
              child: Material(
                type: MaterialType.transparency,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Tooltip(
                            message: 'Open player',
                            child: InkWell(
                              onTap: onOpen,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  10,
                                  10,
                                  8,
                                  8,
                                ),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 36,
                                      child: BookCover.book(
                                        book,
                                        showText: false,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            book.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.titleMedium
                                                ?.copyWith(
                                                  fontFamily: 'Source Serif 4',
                                                  fontWeight: FontWeight.w600,
                                                ),
                                          ),
                                          Text(
                                            book.author,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                                  color: scheme.onSurface
                                                      .withValues(alpha: 0.75),
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        ...controls,
                        const SizedBox(width: 6),
                      ],
                    ),
                    // The progress ticks while audio plays. Its own layer
                    // keeps the glass behind it from repainting.
                    if (progress != null)
                      RepaintBoundary(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                          child: ValueListenableBuilder(
                            valueListenable: progress,
                            // On glass a faint ink track reads better than
                            // the paper outline.
                            builder: (context, value, _) => ProgressLine(
                              height: 2.5,
                              value: value,
                              color: scheme.primary,
                              trackColor: scheme.onSurface.withValues(
                                alpha: 0.12,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The cover of [book] in a circle, ringed by the [progress] through it, with
/// the play state over the cover: a progress ring while its audio is
/// [starting], a pause sign while it is [playing], else a play arrow.
class CoverPlayButton extends StatelessWidget {
  const CoverPlayButton({
    super.key,
    required this.book,
    required this.playing,
    required this.onPlayPause,
    required this.onOpen,
    this.starting = false,
    this.progress,
  });
  final Book book;
  final bool playing;

  /// Whether a Play command waits for the audio to sound.
  final bool starting;

  /// How far through the book the place is, from 0 to 1. Only the pie
  /// follows it. Null when the length is unknown, and then the whole cover
  /// stays faded.
  final ValueListenable<double>? progress;

  /// Reports a tap. The listener means Pause while [playing] or [starting],
  /// else Play.
  final VoidCallback onPlayPause;

  /// Reports a long press, which asks to open the player.
  final VoidCallback onOpen;

  /// The width of the whole button, in logical pixels. It matches an icon
  /// button's touch target.
  static const size = 48.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final progress = this.progress;
    final cover = FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: 38,
        height: 57,
        child: BookCover.book(book, showText: false),
      ),
    );
    Widget pie(double value) =>
        ClipPath(clipper: ProgressPie(value), child: cover);
    return Semantics(
      button: true,
      label: playing || starting ? 'Pause audiobook' : 'Play audiobook',
      onLongPressHint: 'Open player',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onPlayPause,
        onLongPress: onOpen,
        child: SizedBox.square(
          dimension: size,
          child: ClipOval(
            child: Stack(
              fit: StackFit.expand,
              children: [
                // The cover that is still ahead shows faded.
                cover,
                ColoredBox(color: scheme.surface.withValues(alpha: .62)),
                // The pie moves while audio plays. Its own layer keeps the
                // glass behind it from repainting.
                if (progress != null)
                  RepaintBoundary(
                    child: ValueListenableBuilder(
                      valueListenable: progress,
                      builder: (context, value, _) => pie(value),
                    ),
                  ),
                // A small dark disc keeps the icon readable on any cover,
                // and leaves the pie around it visible.
                Center(
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      color: Color(0x73000000),
                      shape: BoxShape.circle,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: PlayStateIcon(
                        playing: playing,
                        starting: starting,
                        size: 20,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Says that the recording of [request] changed, and offers to start the
/// replacement from its beginning.
class ReplacementOffer extends StatelessWidget {
  const ReplacementOffer({
    super.key,
    required this.request,
    required this.onStartReplacement,
  });
  final AudioReplacement request;

  /// Reports a tap on Start replacement, with [request].
  final ValueChanged<AudioReplacement> onStartReplacement;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text('${request.book.title} · ${request.edition.label}'),
      const Text(
        'This recording changed. Start the replacement from the beginning?',
      ),
      TextButton(
        onPressed: () => onStartReplacement(request),
        child: const Text('Start replacement'),
      ),
    ],
  );
}

/// The part of a round cover that a listener has heard: a pie slice that
/// starts at twelve o'clock and grows clockwise to [value] of the circle.
class ProgressPie extends CustomClipper<Path> {
  const ProgressPie(this.value);

  /// How far through the audiobook the place is, from 0 to 1.
  final double value;

  @override
  Path getClip(Size size) {
    final circle = Offset.zero & size;
    final value = this.value.clamp(0.0, 1.0);
    if (value >= 1) return Path()..addOval(circle);
    if (value <= 0) return Path();
    return Path()
      ..moveTo(circle.center.dx, circle.center.dy)
      ..arcTo(circle, -math.pi / 2, 2 * math.pi * value, false)
      ..close();
  }

  @override
  bool shouldReclip(ProgressPie oldClipper) => oldClipper.value != value;
}
