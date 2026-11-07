import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../catalog/book_cover.dart';
import '../catalog/glass.dart';
import '../catalog/library_services.dart' show duration;
import '../catalog/model.dart';
import '../foundation/theme.dart';
import 'playback.dart';
import 'recent.dart';
import 'records_screen.dart';
import 'timeline.dart';

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
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: playback,
    builder: (context, _) {
      final book = playback.book;
      if (book == null) return const SizedBox.shrink();
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      final total = playback.durationMilliseconds;
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _UndoControl(playback: playback),
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
                                onTap: () => openPlayer(
                                  context,
                                  playback,
                                  onOpenBook: onOpenBook,
                                ),
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
                                                    fontFamily:
                                                        'Source Serif 4',
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
                                                        .withValues(
                                                          alpha: 0.75,
                                                        ),
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
                          _PlayButton(playback: playback),
                          _JumpButton(
                            playback: playback,
                            forward: true,
                            compact: true,
                          ),
                          const SizedBox(width: 6),
                        ],
                      ),
                      if (total != null && total > 0)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              minHeight: 2.5,
                              value:
                                  (playback.editionMilliseconds ?? 0) / total,
                              color: scheme.primary,
                              backgroundColor: scheme.onSurface.withValues(
                                alpha: 0.12,
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
    },
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

class ReplacementStartNotice extends StatelessWidget {
  const ReplacementStartNotice({
    super.key,
    required this.playback,
    this.onStarted,
  });
  final Playback playback;
  final VoidCallback? onStarted;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: playback,
    builder: (context, _) {
      final request = playback.replacementStart;
      if (request == null) return const SizedBox.shrink();
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${request.book.title} · ${request.edition.label}'),
          const Text(
            'This recording changed. Start the replacement from the beginning?',
          ),
          TextButton(
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => GlassDialog(
                  title: const Text('Start replacement audio?'),
                  content: Text(
                    'Start ${request.edition.label} from the beginning. '
                    'Your old position (${audioTime(request.previous.milliseconds)} within its original audio file), '
                    'history and bookmarks will be kept separately. '
                    'Old positions will not be applied to changed audio.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Start from beginning'),
                    ),
                  ],
                ),
              );
              if (confirmed != true) {
                playback.cancelReplacement(request);
                return;
              }
              await playback.confirmReplacement(request);
              if (context.mounted &&
                  playback.edition == request.edition &&
                  playback.replacementStart == null) {
                onStarted?.call();
              }
            },
            child: const Text('Start replacement'),
          ),
        ],
      );
    },
  );
}

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
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: playback,
    builder: (context, _) {
      final book = playback.book;
      if (book == null) {
        return ListView(
          padding: EdgeInsets.fromLTRB(
            20,
            16,
            20,
            32 + floatingBarInset(context),
          ),
          children: [
            RecordSaveStatus(playback: playback),
            ReplacementStartNotice(playback: playback),
            if (playback.recent.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Text(
                  'Choose a downloaded audio edition to start listening.',
                  textAlign: TextAlign.center,
                ),
              )
            else
              RecentListeningList(playback: playback),
            const SizedBox(height: 12),
            Center(
              child: TextButton(
                onPressed: () => openListeningTimeline(context, playback),
                child: const Text('History'),
              ),
            ),
          ],
        );
      }
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

  Widget _stage(BuildContext context, Book book, bool night) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final top = pane ? 0.0 : MediaQuery.paddingOf(context).top;
    final narrator = playback.edition!.narrator;
    final chapters = playback.chapters;
    final chapter = playback.chapterIndex;
    final total = playback.durationMilliseconds;
    final position = playback.editionMilliseconds;
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
                      if (chapter != null && chapters.length > 1)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
                          child: Text(
                            '${chapters[chapter].name} · ${chapter + 1} of ${chapters.length}',
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: night ? theaterGlow : scheme.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      RecordSaveStatus(playback: playback),
                      ReplacementStartNotice(playback: playback),
                      const SizedBox(height: 10),
                      if (total != null && total > 0 && position != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: _PositionSlider(playback: playback),
                        )
                      else
                        Text(
                          'File position · ${audioTime(playback.position!.milliseconds)}',
                          textAlign: TextAlign.center,
                        ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _JumpButton(
                            playback: playback,
                            forward: false,
                            onLongPress: () => _jumps(context),
                          ),
                          const SizedBox(width: 30),
                          _PlayButton(playback: playback, large: true),
                          const SizedBox(width: 30),
                          _JumpButton(
                            playback: playback,
                            forward: true,
                            onLongPress: () => _jumps(context),
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
                        child: _UndoControl(playback: playback),
                      ),
                      const SizedBox(height: 14),
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
              child: RecentListeningList(playback: playback),
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

  /// Chapters, Bookmark, Speed, Sleep, and History, in one rounded row.
  Widget _tools(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = theme.brightness == Brightness.dark
        ? theaterGlow
        : scheme.primary;
    final deadline = playback.sleepDeadline;
    final value = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: scheme.onSurface,
    );
    Widget tool(String label, Widget top, VoidCallback onTap) => Expanded(
      child: Semantics(
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
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
              tool(
                'Chapters',
                Icon(Icons.format_list_bulleted_rounded, color: accent),
                () => unawaited(_chapters(context)),
              ),
              VerticalDivider(width: 1, color: scheme.outlineVariant),
              // One tap saves an untitled bookmark. Right after, the tool
              // reads Bookmarked, and a tap names that bookmark.
              if (playback.bookmarkHere case final here?)
                tool(
                  'Bookmarked',
                  Icon(Icons.bookmark_rounded, color: accent),
                  () => unawaited(
                    editAudioBookmark(context, playback, bookmark: here),
                  ),
                )
              else
                tool(
                  'Bookmark',
                  Icon(Icons.bookmark_border_rounded, color: accent),
                  () => unawaited(playback.addBookmark()),
                ),
              VerticalDivider(width: 1, color: scheme.outlineVariant),
              tool(
                'Speed',
                Text('${_rate(playback.playbackSpeed)}×', style: value),
                () => unawaited(_speed(context)),
              ),
              VerticalDivider(width: 1, color: scheme.outlineVariant),
              tool(
                'Sleep',
                deadline == null
                    ? Icon(Icons.bedtime_outlined, color: accent)
                    : Text(
                        '${(deadline.difference(DateTime.now()).inSeconds / 60).ceil()} m',
                        style: value,
                      ),
                () => unawaited(_sleep(context)),
              ),
              VerticalDivider(width: 1, color: scheme.outlineVariant),
              tool(
                'History',
                Icon(Icons.history_rounded, color: accent),
                () => openListeningTimeline(
                  context,
                  playback,
                  book: playback.book,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _chapters(BuildContext context) => showGlassSheet<void>(
    context,
    isScrollControlled: true,
    builder: (context) {
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      final accent = theme.brightness == Brightness.dark
          ? theaterGlow
          : scheme.primary;
      final chapters = playback.chapters;
      final current = playback.chapterIndex;
      final position = playback.position?.milliseconds ?? 0;
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.65,
        builder: (context, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                'Chapters',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontFamily: 'Source Serif 4',
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            for (final (index, chapter) in chapters.indexed) ...[
              if (index > 0) Divider(height: 1, color: scheme.outlineVariant),
              InkWell(
                onTap: () {
                  unawaited(
                    playback.seekSource(
                      chapter.sourceKey,
                      chapter.milliseconds,
                    ),
                  );
                  Navigator.pop(context);
                },
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
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(3),
                                    child: LinearProgressIndicator(
                                      minHeight: 3,
                                      color: accent,
                                      backgroundColor: scheme.outlineVariant,
                                      value: _chapterShare(
                                        chapters,
                                        index,
                                        position,
                                      ),
                                    ),
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
        ),
      );
    },
  );

  /// How far through chapter [index] the file position [position] is, from 0
  /// to 1, or null when the chapter's end is unknown.
  double? _chapterShare(
    List<PlaybackChapter> chapters,
    int index,
    int position,
  ) {
    final chapter = chapters[index];
    final next = index + 1 < chapters.length ? chapters[index + 1] : null;
    final end = next != null && next.sourceKey == chapter.sourceKey
        ? next.milliseconds
        : null;
    if (end == null || end <= chapter.milliseconds) return null;
    return ((position - chapter.milliseconds) / (end - chapter.milliseconds))
        .clamp(0, 1);
  }

  Future<void> _speed(BuildContext context) => showGlassSheet<void>(
    context,
    builder: (context) => SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Playback speed',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            for (final speed in [
              0.5,
              0.75,
              1.0,
              1.25,
              1.5,
              1.75,
              2.0,
              2.5,
              3.0,
            ])
              ListTile(
                title: Text('${_rate(speed)}×'),
                selected: speed == playback.playbackSpeed,
                onTap: () {
                  unawaited(playback.setSpeed(speed));
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
    ),
  );

  Future<void> _sleep(BuildContext context) => showGlassSheet<void>(
    context,
    builder: (context) => SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Sleep timer',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            for (final minutes in [5, 15, 30, 45, 60])
              ListTile(
                title: Text('$minutes minutes'),
                onTap: () {
                  unawaited(playback.setSleep(Duration(minutes: minutes)));
                  Navigator.pop(context);
                },
              ),
            ListTile(
              title: const Text('Turn off'),
              onTap: () {
                unawaited(playback.setSleep(null));
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _jumps(BuildContext context) async {
    var backward = playback.backwardSeconds;
    var forward = playback.forwardSeconds;
    await showGlassSheet<void>(
      context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Jump lengths',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
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

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.playback, this.large = false});
  final Playback playback;
  final bool large;
  @override
  Widget build(BuildContext context) {
    final label = playback.playing ? 'Pause' : 'Play';
    final icon = playback.playing
        ? Icons.pause_rounded
        : Icons.play_arrow_rounded;
    void toggle() =>
        unawaited(playback.playing ? playback.pause() : playback.play());
    if (!large) {
      return IconButton(tooltip: label, onPressed: toggle, icon: Icon(icon));
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
              onTap: toggle,
              child: SizedBox.square(
                dimension: 72,
                child: Icon(icon, size: 38, color: scheme.onPrimary),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A circular arrow with the jump length inside. A long press changes the
/// jump lengths.
class _JumpButton extends StatelessWidget {
  const _JumpButton({
    required this.playback,
    required this.forward,
    this.onLongPress,
    this.compact = false,
  });
  final Playback playback;
  final bool forward;
  final VoidCallback? onLongPress;

  /// The mini player's smaller size.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final seconds = forward
        ? playback.forwardSeconds
        : playback.backwardSeconds;
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
          onTap: () => unawaited(playback.jump(forward: forward)),
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

/// The position slider with chapter marks, and the elapsed time, the time
/// left in the chapter, and the time left in the book below it.
class _PositionSlider extends StatefulWidget {
  const _PositionSlider({required this.playback});
  final Playback playback;
  @override
  State<_PositionSlider> createState() => _PositionSliderState();
}

class _PositionSliderState extends State<_PositionSlider> {
  double? _target;
  @override
  Widget build(BuildContext context) {
    final playback = widget.playback;
    final scheme = Theme.of(context).colorScheme;
    final total = playback.durationMilliseconds!;
    final value = (_target ?? playback.editionMilliseconds!.toDouble()).clamp(
      0.0,
      total.toDouble(),
    );
    final chapters = playback.chapters;
    // Where each bookmark of the open edition sits, in edition milliseconds.
    final bookmarks = [
      for (final bookmark in playback.bookmarks)
        if (playback.editionTime(bookmark.position) case final at?
            when bookmark.position.editionId == playback.edition?.id &&
                at <= total)
          (id: bookmark.id, at: at),
    ];
    final accent = Theme.of(context).brightness == Brightness.dark
        ? theaterGlow
        : scheme.primary;
    final index = playback.chapterIndex;
    final next = index != null && index + 1 < chapters.length
        ? chapters[index + 1].editionMilliseconds
        : null;
    final chapterLeft = index == null
        ? null
        : (next ?? total) - playback.editionMilliseconds!;
    final small = TextStyle(
      fontSize: 12,
      color: scheme.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            activeTrackColor: scheme.primary,
            inactiveTrackColor: scheme.outlineVariant,
            thumbColor: scheme.primary,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Slider(
                padding: const EdgeInsets.symmetric(vertical: 12),
                semanticFormatterCallback: (value) => audioTime(value.round()),
                value: value,
                max: total.toDouble(),
                onChangeStart: (_) => unawaited(playback.beginSliderSeek()),
                onChanged: (value) => setState(() => _target = value),
                onChangeEnd: (value) async {
                  await playback.finishSliderSeek(value.round());
                  if (mounted) setState(() => _target = null);
                },
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: LayoutBuilder(
                    builder: (context, size) => Stack(
                      children: [
                        for (final chapter in chapters)
                          if ((chapter.editionMilliseconds ?? 0) > 0 &&
                              chapter.editionMilliseconds! < total)
                            Positioned(
                              left:
                                  size.maxWidth *
                                      chapter.editionMilliseconds! /
                                      total -
                                  0.75,
                              top: size.maxHeight / 2 - 5,
                              child: Container(
                                width: 1.5,
                                height: 10,
                                color: scheme.surface,
                              ),
                            ),
                        for (final (:id, :at) in bookmarks)
                          Positioned(
                            key: ValueKey('bookmark mark $id'),
                            left: size.maxWidth * at / total - 3,
                            top: size.maxHeight / 2 - 13,
                            child: Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: accent,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Row(
          children: [
            Expanded(child: Text(audioTime(value.round()), style: small)),
            if (chapterLeft != null)
              Text(
                chapterLeft < 60000
                    ? 'chapter ${(chapterLeft / 1000).ceil()} s left'
                    : 'chapter ${duration(chapterLeft)} left',
                style: small,
              ),
            Expanded(
              child: Text(
                '${audioTime(total - value.round())} left',
                textAlign: TextAlign.right,
                style: small,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

String _rate(double value) =>
    value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

class _UndoControl extends StatelessWidget {
  const _UndoControl({required this.playback});
  final Playback playback;

  @override
  Widget build(BuildContext context) => playback.undoAction == null
      ? const SizedBox.shrink()
      : BookfinPanel(
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            children: [
              Text(
                playback.unsavedChanges
                    ? 'Position changed. The previous place is not saved yet.'
                    : 'Position changed. Your previous place is saved.',
              ),
              TextButton(
                onPressed: () => unawaited(playback.undoSeek()),
                child: const Text('Undo'),
              ),
              IconButton(
                tooltip: 'Dismiss Undo',
                onPressed: playback.dismissUndo,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        );
}
