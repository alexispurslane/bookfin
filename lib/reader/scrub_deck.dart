import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../catalog/glass.dart' show CoverGlass;
import '../catalog/model.dart';
import 'page_previews.dart';

/// The reader's page area, which becomes a deck of page cards while the
/// person scrubs.
///
/// Each card is a glass pane of the open book. A blank card is an empty
/// pane. A drawn card holds its page on paper, inside the glass, with a
/// margin like a printed page, whole and at its own shape.
///
/// When a drag starts, the front card zooms out of the page area as it fades
/// in, and the pages before and after it show as smaller, dimmed cards
/// behind it, to its left and right. A settling deck holds still while the
/// reader moves to its place. When it goes, the front card zooms back in to
/// fill the page area and covers the page until it is gone. A deck that goes
/// without settling fades away. With reduced motion, the deck opens and
/// closes at once.
///
/// The deck shows what [deck] gives it and reports nothing. The shown [page]
/// stays in its place in the tree, painted and unmoved, for the deck's
/// whole life. So a web view in it is never made again, and it does not
/// draw itself again when the deck opens.
class ScrubDeck extends StatefulWidget {
  const ScrubDeck({
    super.key,
    required this.deck,
    required this.paper,
    this.book,
    required this.page,
  });

  /// The deck to show, or null while no drag runs.
  final ValueListenable<DeckView?> deck;

  /// The color of the reading page, which a drawn card's paper takes.
  final Color paper;

  /// The open book, whose cover tints the glass of the cards.
  final Book? book;

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
    _open.value = _view == null ? 0 : 1;
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
    // A settling deck holds still, so the reader draws its new page while
    // nothing else draws. It closes when it goes.
    if (_instant) {
      _open.value = 1;
    } else {
      _open.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    final view = _view;
    final shade = Color.lerp(widget.paper, Colors.black, .22)!;
    return ClipRect(
      // Without a drag, nothing clips the page, which may be a web view.
      clipBehavior: view == null ? Clip.none : Clip.hardEdge,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // The page keeps this place in the tree, under the deck.
          widget.page,
          if (view != null)
            AnimatedBuilder(
              animation: _openness,
              builder: (context, _) {
                final open = _openness.value;
                // A settled deck covers the page until it is gone, so the
                // page shows only once the reader landed.
                final cover = view.settling ? 1.0 : open;
                // The cards share one blur of what lies beneath them.
                return BackdropGroup(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Opacity(
                        key: const ValueKey('deck backdrop'),
                        opacity: cover,
                        child: ColoredBox(color: shade),
                      ),
                      if (view.previous case final card?)
                        _side(
                          const ValueKey('deck previous card'),
                          card,
                          -1,
                          open,
                        ),
                      if (view.next case final card?)
                        _side(const ValueKey('deck next card'), card, 1, open),
                      Opacity(
                        opacity: cover,
                        child: Transform.scale(
                          scale: ui.lerpDouble(1, ScrubDeck.frontScale, open)!,
                          child: KeyedSubtree(
                            key: const ValueKey('deck front card'),
                            child: _card(view.front, animate: true),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
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
        child: KeyedSubtree(
          key: key,
          child: DecoratedBox(
            key: const ValueKey('deck dim'),
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(_radius),
              color: Colors.black.withValues(alpha: .32),
            ),
            child: _card(card, animate: false),
          ),
        ),
      ),
    ),
  );

  static const _radius = 18.0;

  /// A glass card that holds its drawn page, if any. With [animate], a new
  /// page slides in from the way the thumb moved, over the empty glass, and
  /// the old page is gone at once.
  Widget _card(DeckCard card, {required bool animate}) {
    final page = card.page;
    final face = page == null
        ? const SizedBox.expand(key: ValueKey('blank'))
        : Padding(
            key: ObjectKey(page),
            padding: const EdgeInsets.all(8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: widget.paper,
                borderRadius: BorderRadius.circular(_radius - 8),
              ),
              // A margin like a printed page's keeps the text off the edge.
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 26,
                ),
                child: Center(
                  child: AspectRatio(
                    aspectRatio: page.image.width / page.image.height,
                    child: _PageImage(image: page.image),
                  ),
                ),
              ),
            ),
          );
    return CoverGlass(
      book: widget.book,
      radius: _radius,
      child: !animate
          ? face
          : AnimatedSwitcher(
              duration: _instant ? Duration.zero : _shuffle,
              // The old page leaves at once, so the card never shows the
              // text of two pages over each other.
              layoutBuilder: (current, _) => current ?? const SizedBox.shrink(),
              // The new page slides in from the way the thumb moved.
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween(
                    begin: Offset(.08 * _direction, 0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: face,
            ),
    );
  }
}

/// A drawn page. It keeps its own handle to the image, so the owner of the
/// image can free it while the card still fades.
class _PageImage extends StatefulWidget {
  const _PageImage({required this.image});
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
      RawImage(image: _image, fit: BoxFit.fill);
}
