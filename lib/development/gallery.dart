import 'package:flutter/material.dart';

import '../foundation/theme.dart';

class DevelopmentGallery extends StatefulWidget {
  const DevelopmentGallery({super.key});

  @override
  State<DevelopmentGallery> createState() => _DevelopmentGalleryState();
}

class _DevelopmentGalleryState extends State<DevelopmentGallery> {
  int _screen = 0;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          children: [
            Text(
              'Development gallery · sample books and positions\nNo server connection, downloads, or audio',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 4,
              children: [
                for (final (index, label) in [
                  'Library',
                  'Player & history',
                  'Reader',
                ].indexed)
                  TextButton(
                    onPressed: () => setState(() => _screen = index),
                    style: TextButton.styleFrom(
                      backgroundColor: _screen == index
                          ? Theme.of(context).colorScheme.surfaceContainer
                          : null,
                    ),
                    child: Text(label),
                  ),
              ],
            ),
          ],
        ),
      ),
      Expanded(
        child: BookfinScreenStack(
          index: _screen,
          children: [
            _LibraryFixture(onPlayer: () => setState(() => _screen = 1)),
            const _PlayerFixture(),
            _ReaderFixture(onPlayer: () => setState(() => _screen = 1)),
          ],
        ),
      ),
    ],
  );
}

class _LibraryFixture extends StatefulWidget {
  const _LibraryFixture({required this.onPlayer});

  final VoidCallback onPlayer;

  @override
  State<_LibraryFixture> createState() => _LibraryFixtureState();
}

class _LibraryFixtureState extends State<_LibraryFixture> {
  bool _downloaded = false;

  @override
  Widget build(BuildContext context) => ListView(
    key: const PageStorageKey('gallery-library'),
    padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
    children: [
      Text('Book libraries', style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 24),
      Text(
        'A little further\ninto the story.',
        style: Theme.of(context).textTheme.displaySmall,
      ),
      const SizedBox(height: 28),
      BookfinPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '● Downloaded audio only',
              style: TextStyle(color: Theme.of(context).colorScheme.primary),
            ),
            Text(
              'Sample state: cellular · media transfers paused',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      Wrap(
        spacing: 8,
        children: [
          for (final (local, label) in [
            (false, 'All books'),
            (true, 'Downloaded'),
          ])
            ChoiceChip(
              checkmarkColor: Theme.of(context).colorScheme.onPrimary,
              label: Text(label),
              selected: _downloaded == local,
              labelStyle: TextStyle(
                color: _downloaded == local
                    ? Theme.of(context).colorScheme.onPrimary
                    : Theme.of(context).colorScheme.onSurface,
              ),
              onSelected: (_) => setState(() => _downloaded = local),
            ),
        ],
      ),
      const _BookRow(
        title: 'The Time Machine',
        author: 'H. G. Wells · 3h 28m',
        availability: '✓ Audio downloaded · EPUB downloaded',
        note: 'Chapter 5 · 1h 27m listened',
        progress: 0.42,
      ),
      AnimatedSize(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 360),
        alignment: Alignment.topCenter,
        curve: Curves.easeOutCubic,
        child: Column(
          children: [
            if (!_downloaded) ...[
              const _BookRow(
                title: 'The Lost World',
                author: 'Arthur Conan Doyle',
                availability: 'Audio not downloaded',
                note: 'Professor Challenger · Book 1\nEPUB downloaded',
                cover: Color(0xFF5E644A),
              ),
              const _BookRow(
                title: 'The Poison Belt',
                author: 'Arthur Conan Doyle',
                availability: 'Audio partial · 2 of 6 files',
                note: 'Professor Challenger · Book 2\nWaiting for Wi-Fi',
                cover: Color(0xFF6D5160),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 18),
      BookfinPanel(
        child: Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('The Time Machine'),
                  Text('Sample resume · chapter 5'),
                ],
              ),
            ),
            IconButton.filled(
              onPressed: widget.onPlayer,
              tooltip: 'Open sample player',
              icon: const Icon(Icons.play_arrow_rounded),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        spacing: 8,
        children: [
          TextButton(
            onPressed: () => setState(() => _downloaded = false),
            child: const Text('Library'),
          ),
          TextButton(
            onPressed: () => setState(() => _downloaded = true),
            child: const Text('Downloads'),
          ),
          TextButton(
            onPressed: widget.onPlayer,
            child: const Text('Listening'),
          ),
        ],
      ),
    ],
  );
}

class _BookRow extends StatelessWidget {
  const _BookRow({
    required this.title,
    required this.author,
    required this.availability,
    required this.note,
    this.progress,
    this.cover = const Color(0xFF775035),
  });

  final String title;
  final String author;
  final String availability;
  final String note;
  final double? progress;
  final Color cover;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 23),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Cover(title: title, color: cover),
            const SizedBox(width: 17),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 5),
                  Text(author, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 8),
                  Text(
                    availability,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  if (progress != null) ...[
                    const SizedBox(height: 10),
                    LinearProgressIndicator(value: progress, minHeight: 4),
                  ],
                  const SizedBox(height: 6),
                  Text(note, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
      const Divider(),
    ],
  );
}

class _Cover extends StatelessWidget {
  const _Cover({
    required this.title,
    this.color = const Color(0xFF775035),
    this.large = false,
  });

  final String title;
  final Color color;
  final bool large;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Sample cover: $title',
    image: true,
    child: Container(
      width: large ? 176 : 72,
      constraints: BoxConstraints(minHeight: large ? 232 : 104),
      padding: EdgeInsets.all(large ? 24 : 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: const BorderRadius.horizontal(
          left: Radius.circular(4),
          right: Radius.circular(12),
        ),
        border: const Border(
          left: BorderSide(color: Color(0xFF39291F), width: 4),
        ),
      ),
      alignment: Alignment.center,
      child: ExcludeSemantics(
        child: Text(
          title.replaceAll(' ', '\n'),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Source Serif 4',
            fontSize: large ? 27 : 13,
            height: 1.25,
            color: const Color(0xFFFFF9EF),
          ),
        ),
      ),
    ),
  );
}

class _PlayerFixture extends StatefulWidget {
  const _PlayerFixture();

  @override
  State<_PlayerFixture> createState() => _PlayerFixtureState();
}

class _PlayerFixtureState extends State<_PlayerFixture> {
  bool _chapters = false;

  @override
  Widget build(BuildContext context) => ListView(
    key: const PageStorageKey('gallery-player'),
    padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
    children: [
      Text(
        'NOW LISTENING · SAMPLE',
        style: Theme.of(context).textTheme.labelSmall,
      ),
      const SizedBox(height: 28),
      const Center(child: _Cover(title: 'The Time Machine', large: true)),
      const SizedBox(height: 24),
      Text(
        'The Time Machine',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleLarge,
      ),
      Text(
        'H. G. Wells · Chapter 5 of 12',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 24),
      const LinearProgressIndicator(value: 0.42, minHeight: 5),
      const SizedBox(height: 10),
      const Wrap(
        alignment: WrapAlignment.spaceBetween,
        spacing: 32,
        children: [Text('1:27:14'), Text('3:28:00 total')],
      ),
      const SizedBox(height: 18),
      const Wrap(
        alignment: WrapAlignment.center,
        spacing: 12,
        children: [
          OutlinedButton(onPressed: null, child: Text('↶ 15s')),
          IconButton.filled(
            onPressed: null,
            tooltip: 'Sample only · playback unavailable',
            icon: Icon(Icons.play_arrow_rounded),
            iconSize: 36,
          ),
          OutlinedButton(onPressed: null, child: Text('30s ↷')),
        ],
      ),
      const SizedBox(height: 18),
      const Text(
        'Visual fixture only · playback is unavailable',
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 12),
      Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        children: [
          TextButton(
            onPressed: () => setState(() => _chapters = true),
            child: const Text('Chapters'),
          ),
          const TextButton(onPressed: null, child: Text('Bookmark')),
          TextButton(
            onPressed: () => setState(() => _chapters = false),
            child: const Text('History'),
          ),
        ],
      ),
      Text(
        'Sample: 1.25× speed · sleep timer off',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 24),
      AnimatedSize(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 360),
        alignment: Alignment.topCenter,
        child: BookfinPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _chapters
                ? [
                    Text(
                      'Sample chapters',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    const Text('5 · In the Golden Age'),
                    const OutlinedButton(onPressed: null, child: Text('Jump')),
                    const Text('6 · The Sunset of Mankind'),
                    const OutlinedButton(onPressed: null, child: Text('Jump')),
                  ]
                : [
                    Text(
                      'Your listening history',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Sample pause · 9:42\nChapter 5 · 1:27:14 into book',
                    ),
                    const OutlinedButton(
                      onPressed: null,
                      child: Text('Restore'),
                    ),
                    const Divider(height: 28),
                    const Text(
                      'Sample chapter jump · 9:18\nFrom 1:02:09 to 1:12:00',
                    ),
                    const OutlinedButton(
                      onPressed: null,
                      child: Text('Restore'),
                    ),
                  ],
          ),
        ),
      ),
    ],
  );
}

class _ReaderFixture extends StatefulWidget {
  const _ReaderFixture({required this.onPlayer});

  final VoidCallback onPlayer;

  @override
  State<_ReaderFixture> createState() => _ReaderFixtureState();
}

class _ReaderFixtureState extends State<_ReaderFixture> {
  double _fontSize = 19;

  @override
  Widget build(BuildContext context) => ListView(
    key: const PageStorageKey('gallery-reader'),
    padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
    children: [
      Text(
        'THE TIME MACHINE · SAMPLE EPUB',
        style: Theme.of(context).textTheme.labelSmall,
      ),
      const SizedBox(height: 32),
      Text('CHAPTER I', style: Theme.of(context).textTheme.labelSmall),
      const SizedBox(height: 17),
      Text(
        'The Time Traveller',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: 28),
      Text(
        'The Time Traveller (for so it will be convenient to speak of him) was expounding a recondite matter to us. His grey eyes shone and twinkled, and his usually pale face was flushed and animated.',
        style: TextStyle(
          fontFamily: 'Source Serif 4',
          fontFamilyFallback: const ['Noto Serif'],
          fontSize: _fontSize,
          height: 1.85,
        ),
      ),
      const SizedBox(height: 20),
      Text(
        'The fire burned brightly, and the soft radiance of the incandescent lights in the lilies of silver caught the bubbles that flashed and passed in our glasses.',
        style: TextStyle(
          fontFamily: 'Source Serif 4',
          fontFamilyFallback: const ['Noto Serif'],
          fontSize: _fontSize,
          height: 1.85,
        ),
      ),
      const SizedBox(height: 28),
      Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        children: [
          OutlinedButton(
            onPressed: _fontSize > 15
                ? () => setState(() => _fontSize -= 2)
                : null,
            child: const Text('A−'),
          ),
          OutlinedButton(
            onPressed: _fontSize < 29
                ? () => setState(() => _fontSize += 2)
                : null,
            child: const Text('A+'),
          ),
          const OutlinedButton(onPressed: null, child: Text('Bookmark')),
        ],
      ),
      const SizedBox(height: 24),
      BookfinPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Audio stays close',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Return to the sample player. Audio playback is unavailable in this gallery.',
            ),
            OutlinedButton(
              onPressed: widget.onPlayer,
              child: const Text('Player'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      const LinearProgressIndicator(value: 0.08, minHeight: 4),
      const SizedBox(height: 12),
      Text(
        'Sample chapter 1 · no ebook file is open\nText size and scroll stay in this gallery session.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );
}
