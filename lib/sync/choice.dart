import 'package:flutter/material.dart';

import 'labels.dart';

/// Reports that the user keeps the saved version [identity] of [record].
/// [bookmarkTitles] holds the bookmark title of every version, so that each
/// place that stays a bookmark says where it came from.
typedef ResolveChoice = void Function(
  String record,
  String identity,
  Map<String, String> bookmarkTitles,
);

/// The letter that names the version at [index] of a choice: A, B, and on.
String choiceLetter(int index) => String.fromCharCode(0x41 + index);

/// The choice between the saved versions of [record], as [labels] name
/// them: the track of the whole book with a pin for each place, when the
/// places lie on one, then one column for each version with its Keep
/// button. The Personal records page and the sheet over a book show this
/// same choice.
///
/// It causes nothing. A Keep reports through [onResolve], while [enabled].
class ConflictChoice extends StatelessWidget {
  const ConflictChoice({
    super.key,
    required this.record,
    required this.labels,
    required this.enabled,
    required this.onResolve,
  });
  final String record;
  final ConflictLabels labels;

  /// False while a sync or a choice that the user started runs.
  final bool enabled;
  final ResolveChoice onResolve;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final choices = labels.choices;
    final titles = {
      for (final choice in choices) choice.identity: choice.bookmarkTitle,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (labels.track case final track?)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: BookTrack(track: track),
          ),
        // Two columns in each row, so that a third version wraps.
        for (var start = 0; start < choices.length; start += 2)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var index = start; index < start + 2; index++) ...[
                    if (index > start) const SizedBox(width: 8),
                    Expanded(
                      child: index < choices.length
                          ? _Version(
                              letter: choiceLetter(index),
                              label: choices[index],
                              onKeep: enabled
                                  ? () => onResolve(
                                      record,
                                      choices[index].identity,
                                      titles,
                                    )
                                  : null,
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
          ),
        if (labels.places)
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 12, 2, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.bookmark_outline_rounded,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    labels.kind.startsWith('Listening')
                        ? 'Both places stay as bookmarks. Your audio does not jump.'
                        : 'Both places stay as bookmarks. Your page does not jump.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// One saved version: its letter and source, its time, what else it holds,
/// and its Keep button. [onKeep] is null while the choice is off.
class _Version extends StatelessWidget {
  const _Version({
    required this.letter,
    required this.label,
    required this.onKeep,
  });
  final String letter;
  final ChoiceLabel label;
  final VoidCallback? onKeep;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: _Pin(letter: letter, size: 18),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label.source,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
          if (label.time case final time?)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                time,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.5,
                  color: scheme.onSurface,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: label.time == null ? 8 : 2),
              child: Text(
                label.detail,
                style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonal(
              onPressed: onKeep,
              style: FilledButton.styleFrom(
                backgroundColor: scheme.surfaceContainer,
                foregroundColor: scheme.primary,
                minimumSize: const Size(48, 44),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                textStyle: const TextStyle(
                  fontFamily: 'Outfit',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: Text('Keep $letter'),
            ),
          ),
        ],
      ),
    );
  }
}

/// A round mark with the letter of a version. A is filled, and the others
/// are outlined, as on the track.
class _Pin extends StatelessWidget {
  const _Pin({required this.letter, required this.size});
  final String letter;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final filled = letter == 'A';
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? scheme.primary : scheme.surfaceContainerLowest,
        border: filled
            ? null
            : Border.all(color: scheme.primary, width: size / 11),
      ),
      child: Text(
        letter,
        style: TextStyle(
          fontFamily: 'Outfit',
          fontSize: size / 2,
          height: 1,
          fontWeight: FontWeight.w700,
          color: filled ? scheme.onPrimary : scheme.primary,
        ),
      ),
    );
  }
}

/// The whole book as one thin track with its chapter marks, a pin for each
/// place of [track] above it, and the start and the length of the book
/// below it.
class BookTrack extends StatelessWidget {
  const BookTrack({super.key, required this.track});
  final ConflictTrack track;

  static const _pin = 22.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      label: [
        'Places in the whole book:',
        for (final (index, place) in track.places.indexed)
          '${choiceLetter(index)} at ${(place * 100).round()} percent',
      ].join(' '),
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, size) {
                final width = size.maxWidth;
                double at(double share) => share * width;
                return SizedBox(
                  height: _pin + 6 + 4,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: 4,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: scheme.outlineVariant,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      for (final chapter in track.chapters)
                        Positioned(
                          left: at(chapter) - 0.75,
                          bottom: -3,
                          width: 1.5,
                          height: 10,
                          child: ColoredBox(
                            color: scheme.surfaceContainerLowest,
                          ),
                        ),
                      // B and later first, so that A lies on top.
                      for (final (index, place)
                          in track.places.indexed.toList().reversed)
                        Positioned(
                          left: at(place) - _pin / 2,
                          bottom: 4,
                          width: _pin,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _Pin(letter: choiceLetter(index), size: _pin),
                              Container(
                                width: 2,
                                height: 6,
                                color: scheme.primary,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Start', style: theme.textTheme.bodySmall),
                Text(track.length, style: theme.textTheme.bodySmall),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
