import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'page_previews.dart';

/// The reader's page area, which becomes a deck of page cards while the
/// person scrubs.
///
/// When a drag starts, the page zooms out into the front card, and the pages
/// before and after it show as smaller, dimmed cards behind it, to its left
/// and right. When the deck settles, the front card zooms back in to fill
/// the page area. With reduced motion, the deck opens and closes at once.
///
/// The deck shows what [deck] gives it and reports nothing. The shown [page]
/// keeps its place in the tree and stays painted for the deck's whole
/// life, so a web view in it is never made again. It fills the front card
/// until a drawn page covers it.
class ScrubDeck extends StatefulWidget {
  const ScrubDeck({
    super.key,
    required this.deck,
    required this.paper,
    required this.page,
  });

  /// The deck to show, or null while no drag runs.
  final ValueListenable<DeckView?> deck;

  /// The color of the reading page.
  final Color paper;

  /// The page that the reader shows.
  final Widget page;

  /// The size of the front card, as a share of the page area.
  static const frontScale = .86;

  /// The size of a card behind the front card, as a share of the page area.
  static const sideScale = .76;

  @override
  State<ScrubDeck> createState() => _ScrubDeckState();
}

class _ScrubDeckState extends State<ScrubDeck>
    with SingleTickerProviderStateMixin {
  static const _zoom = Duration(milliseconds: 260);
  static const _shuffle = Duration(milliseconds: 150);

  /// How far the deck is open, from 0 for the full page to 1 for the deck.
  late final _open = AnimationController(vsync: this, duration: _zoom);
  late final _openness = CurvedAnimation(
    parent: _open,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  /// The deck that shows. It stays while the deck closes after the drag.
  DeckView? _view;

  /// Which way the front card last moved through the book: 1 forward, -1
  /// back.
  int _direction = 1;

  /// Whether the deck opens and closes without motion.
  bool _instant = false;

  @override
  void initState() {
    super.initState();
    widget.deck.addListener(_changed);
    _view = widget.deck.value;
    _open.value = _view == null || _view!.settling ? 0 : 1;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _instant = MediaQuery.disableAnimationsOf(context);
  }

  @override
  void didUpdateWidget(ScrubDeck oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.deck != widget.deck) {
      oldWidget.deck.removeListener(_changed);
      widget.deck.addListener(_changed);
      _changed();
    }
  }

  @override
  void dispose() {
    widget.deck.removeListener(_changed);
    _openness.dispose();
    _open.dispose();
    super.dispose();
  }

  void _changed() {
    final view = widget.deck.value;
    if (view == null) {
      if (_view == null) return;
      if (_instant || _open.isDismissed) {
        setState(() => _view = null);
      } else {
        _open.reverse().whenCompleteOrCancel(() {
          if (mounted && widget.deck.value == null) {
            setState(() => _view = null);
          }
        });
      }
      return;
    }
    final before = _view?.front.page;
    final after = view.front.page;
    if (before != null && after != null && !identical(before, after)) {
      final order = after.part != before.part
          ? after.part.compareTo(before.part)
          : after.start.compareTo(before.start);
      _direction = order < 0 ? -1 : 1;
    }
    setState(() => _view = view);
    final target = view.settling ? 0.0 : 1.0;
    if (_instant) {
      _open.value = target;
    } else if (view.settling) {
      _open.reverse();
    } else {
      _open.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    final view = _view;
    final shade = Color.lerp(widget.paper, Colors.black, .22)!;
    // Without a drag, nothing clips the page, which may be a web view.
    return ClipRect(
      clipBehavior: view == null ? Clip.none : Clip.hardEdge,
      child: AnimatedBuilder(
        animation: _openness,
        child: widget.page,
        builder: (context, page) {
          final open = _openness.value;
          final front = ui.lerpDouble(1, ScrubDeck.frontScale, open)!;
          final radius = BorderRadius.circular(16 * open);
          return Stack(
            fit: StackFit.expand,
            children: [
              if (view != null) ...[
                Opacity(
                  key: const ValueKey('deck backdrop'),
                  opacity: open,
                  child: ColoredBox(color: shade),
                ),
                if (view.previous case final card?)
                  _side(const ValueKey('deck previous card'), card, -1, open),
                if (view.next case final card?)
                  _side(const ValueKey('deck next card'), card, 1, open),
                Transform.scale(
                  key: const ValueKey('deck shadow'),
                  scale: front,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: radius,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: .3 * open),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              // The front card always holds the shown page at this place in
              // the tree, so the page is kept.
              Transform.scale(
                key: const ValueKey('page'),
                scale: front,
                child: ClipRRect(
                  borderRadius: radius,
                  clipBehavior: open > 0 ? Clip.antiAlias : Clip.none,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // A drawn page covers the shown page, which stays
                      // painted. Taking a web view out of the picture and
                      // back would switch Android's composition mode, which
                      // can flash an old frame.
                      page!,
                      if (view != null)
                        KeyedSubtree(
                          key: const ValueKey('deck front card'),
                          child: _face(view.front, dim: 0),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// A card behind the front card, on [side]: -1 left, 1 right.
  Widget _side(Key key, DeckCard card, int side, double open) => Opacity(
    key: ValueKey(side),
    opacity: open,
    child: FractionalTranslation(
      translation: Offset(side * .16 * open, 0),
      child: Transform.scale(
        scale: ui.lerpDouble(1, ScrubDeck.sideScale, open)!,
        child: ClipRRect(
          key: key,
          borderRadius: BorderRadius.circular(14),
          child: _face(card, dim: .32),
        ),
      ),
    ),
  );

  /// What a card shows: its drawn page, if any, on paper, dimmed by [dim]
  /// and more when the page only stands in for the card's own page.
  Widget _face(DeckCard card, {required double dim}) {
    final shade = card.exact ? dim : dim + .22;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (card.page case final page?)
          ColoredBox(
            color: widget.paper,
            child: AnimatedSwitcher(
              duration: _instant ? Duration.zero : _shuffle,
              transitionBuilder: (child, animation) {
                // A new page slides in from the way the thumb moved, and the
                // old page slides out the other way.
                final entering = child.key == ObjectKey(page);
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween(
                      begin: Offset((entering ? .08 : -.08) * _direction, 0),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: _PageImage(key: ObjectKey(page), image: page.image),
            ),
          ),
        if (shade > 0)
          ColoredBox(
            key: const ValueKey('deck dim'),
            color: Colors.black.withValues(alpha: shade),
          ),
      ],
    );
  }
}

/// A drawn page. It keeps its own handle to the image, so the owner of the
/// image can free it while the card still fades.
class _PageImage extends StatefulWidget {
  const _PageImage({super.key, required this.image});
  final ui.Image image;
  @override
  State<_PageImage> createState() => _PageImageState();
}

class _PageImageState extends State<_PageImage> {
  late ui.Image _image = widget.image.clone();

  @override
  void didUpdateWidget(_PageImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.image.isCloneOf(_image)) {
      _image.dispose();
      _image = widget.image.clone();
    }
  }

  @override
  void dispose() {
    _image.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      RawImage(image: _image, fit: BoxFit.contain);
}
