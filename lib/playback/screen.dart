import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../foundation/theme.dart';
import 'playback.dart';

class PlaybackMiniPlayer extends StatelessWidget {
  const PlaybackMiniPlayer({super.key, required this.playback});
  final Playback playback;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: playback,
    builder: (context, _) => playback.book == null
        ? const SizedBox.shrink()
        : Material(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (playback.durationMilliseconds != null &&
                    playback.durationMilliseconds! > 0)
                  LinearProgressIndicator(
                    minHeight: 2,
                    value:
                        (playback.editionMilliseconds ?? 0) /
                        playback.durationMilliseconds!,
                  ),
                Row(
                  children: [
                    Expanded(
                      child: Tooltip(
                        message: 'Open player',
                        child: InkWell(
                          onTap: () => openPlayer(context, playback),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 14,
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.headphones_rounded),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        playback.book!.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontFamily: 'Source Serif 4',
                                            ),
                                      ),
                                      Text(
                                        playback.book!.author,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
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
                    IconButton(
                      tooltip: 'Forward ${playback.forwardSeconds} seconds',
                      onPressed: () => unawaited(playback.jump(forward: true)),
                      icon: const Icon(Icons.forward_rounded),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              ],
            ),
          ),
  );
}

void openPlayer(BuildContext context, Playback playback) => unawaited(
  Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Listening')),
        body: BookfinSurface(child: PlayerView(playback: playback)),
      ),
    ),
  ),
);

class PlayerView extends StatelessWidget {
  const PlayerView({super.key, required this.playback});
  final Playback playback;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: playback,
    builder: (context, _) {
      final book = playback.book;
      if (book == null) {
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Choose a downloaded audio edition to start listening.',
            ),
          ),
        );
      }
      final duration = playback.durationMilliseconds;
      final position = playback.editionMilliseconds;
      return ListView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        children: [
          Text(
            'NOW LISTENING',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(height: 20),
          Center(
            child: Container(
              width: 170,
              height: 195,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(20),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.auto_stories_rounded,
                size: 72,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            book.title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium
                ?.copyWith(fontFamily: 'Source Serif 4'),
          ),
          Text(book.author, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            playback.edition!.label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (playback.message != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                playback.message!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 20),
          if (duration != null && duration > 0 && position != null) ...[
            Slider(
              semanticFormatterCallback: (value) => _time(value.round()),
              value: position.toDouble().clamp(0, duration.toDouble()),
              max: duration.toDouble(),
              onChanged: (value) =>
                  unawaited(playback.seekEdition(value.round())),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_time(position)),
                Text('${_time(duration - position)} left'),
              ],
            ),
          ] else
            Text(
              'File position · ${_time(playback.position!.milliseconds)}',
              textAlign: TextAlign.center,
            ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: 'Back ${playback.backwardSeconds} seconds',
                iconSize: 32,
                onPressed: () => unawaited(playback.jump(forward: false)),
                icon: const Icon(Icons.replay_rounded),
              ),
              Text('${playback.backwardSeconds}s'),
              const SizedBox(width: 16),
              _PlayButton(playback: playback, large: true),
              const SizedBox(width: 16),
              Text('${playback.forwardSeconds}s'),
              IconButton(
                tooltip: 'Forward ${playback.forwardSeconds} seconds',
                iconSize: 32,
                onPressed: () => unawaited(playback.jump(forward: true)),
                icon: const Icon(Icons.forward_rounded),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton(
                onPressed: () => _chapters(context),
                child: const Text('Chapters'),
              ),
              OutlinedButton(
                onPressed: () => _speed(context),
                child: Text('${_rate(playback.playbackSpeed)}× speed'),
              ),
              OutlinedButton(
                onPressed: () => _sleep(context),
                child: Text(
                  playback.sleepDeadline == null
                      ? 'Sleep timer'
                      : 'Sleep timer on',
                ),
              ),
              TextButton(
                onPressed: () => _jumps(context),
                child: const Text('Short jumps'),
              ),
            ],
          ),
        ],
      );
    },
  );

  Future<void> _chapters(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.all(20),
        children: [
          Text('Chapters', style: Theme.of(context).textTheme.headlineSmall),
          for (final chapter in playback.chapters)
            ListTile(
              title: Text(chapter.name),
              subtitle: Text(_time(chapter.milliseconds)),
              selected:
                  playback.position?.sourceKey == chapter.sourceKey &&
                  playback.position!.milliseconds >= chapter.milliseconds &&
                  !playback.chapters.any(
                    (next) =>
                        next.sourceKey == chapter.sourceKey &&
                        next.milliseconds > chapter.milliseconds &&
                        next.milliseconds <= playback.position!.milliseconds,
                  ),
              onTap: () {
                unawaited(
                  playback.seekSource(chapter.sourceKey, chapter.milliseconds),
                );
                Navigator.pop(context);
              },
            ),
        ],
      ),
    ),
  );

  Future<void> _speed(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
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

  Future<void> _sleep(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
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
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Short jumps',
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
                  child: const Text('Save short jumps'),
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
    final icon = Icon(
      playback.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
    );
    final label = playback.playing ? 'Pause' : 'Play';
    void toggle() =>
        unawaited(playback.playing ? playback.pause() : playback.play());
    return large
        ? IconButton.filled(
            tooltip: label,
            iconSize: 42,
            padding: const EdgeInsets.all(16),
            onPressed: toggle,
            icon: icon,
          )
        : IconButton(tooltip: label, onPressed: toggle, icon: icon);
  }
}

String _time(int milliseconds) {
  final seconds = max(0, milliseconds) ~/ 1000;
  final minutes = seconds ~/ 60;
  return '${minutes ~/ 60 > 0 ? '${minutes ~/ 60}:' : ''}${(minutes % 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
}

String _rate(double value) =>
    value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
