import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'book_cover.dart';
import 'model.dart';

/// A rounded pane of frosted glass tinted by a book's cover. Whatever lies
/// beneath it shows through, blurred, under the cover's colors and a tint of
/// the page color.
///
/// Every layer that floats over a page is one of these panes.
class CoverGlass extends StatelessWidget {
  const CoverGlass({
    super.key,
    this.book,
    required this.child,
    this.radius = 22,
    this.tint = 0.55,
  });

  /// The book the pane belongs to. Without one, the pane shows the book of
  /// the page beneath it, else the book open in the player. With neither, it
  /// is plain frost.
  final Book? book;
  final Widget child;
  final double radius;

  /// How much of the page color covers the blurred cover, from 0 to 1.
  final double tint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final night = theme.brightness == Brightness.dark;
    final shape = BorderRadius.circular(radius);
    final shown =
        book ?? PageBook.of(context) ?? CoverScope.of(context)?.playing;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: night ? 0.4 : 0.16),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: shape,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Stack(
            children: [
              if (shown != null)
                Positioned.fill(
                  child: CoverBlur(book: shown, sigma: 22, opacity: 0.6),
                ),
              Positioned.fill(
                child: ColoredBox(
                  color: theme.colorScheme.surface.withValues(
                    alpha: night ? tint - 0.05 : tint,
                  ),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: shape,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: night ? 0.1 : 0.4),
                    ),
                  ),
                ),
              ),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

/// Marks the book that a page is about. Glass layers opened on the page show
/// this book.
class PageBook extends InheritedTheme {
  const PageBook({super.key, required this.book, required super.child});
  final Book book;

  static Book? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PageBook>()?.book;

  @override
  Widget wrap(BuildContext context, Widget child) =>
      PageBook(book: book, child: child);

  @override
  bool updateShouldNotify(PageBook oldWidget) => oldWidget.book != book;
}

/// Shows a bottom sheet as a glass pane inset from the screen edges.
///
/// [book] is the book the sheet is about, if any. A [title] heads the sheet
/// below its drag handle, in the one heading style of glass sheets, and
/// stays put while the content below it scrolls. An [expand]ed sheet fills
/// the screen and brings its own close control, so it has no drag handle
/// and no title.
///
/// The sheet is a glass pane, except with [glass] false, which draws the
/// plain sheet of the theme with a drag handle, for a screen that keeps its
/// own look, such as the reader. A plain sheet has no [book], [title] or
/// [expand].
Future<T?> showGlassSheet<T>(
  BuildContext context, {
  Book? book,
  String? title,
  bool isScrollControlled = false,
  bool expand = false,
  bool glass = true,
  AnimationStyle? sheetAnimationStyle,
  required WidgetBuilder builder,
}) {
  assert(!expand || title == null, 'An expanded sheet draws its own top.');
  assert(
    glass || (book == null && title == null && !expand),
    'A plain sheet has no glass parts.',
  );
  if (!glass) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      showDragHandle: true,
      sheetAnimationStyle: sheetAnimationStyle,
      builder: builder,
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled || expand,
    useSafeArea: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    elevation: 0,
    barrierColor: Colors.black.withValues(alpha: 0.3),
    constraints: expand ? const BoxConstraints.expand() : null,
    sheetAnimationStyle: sheetAnimationStyle,
    builder: (context) {
      final handle = Theme.of(context).colorScheme.onSurfaceVariant;
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: _StepBack(
            radius: 28,
            child: CoverGlass(
              book: book,
              radius: 28,
              tint: 0.65,
              child: Material(
                type: MaterialType.transparency,
                child: expand
                    ? builder(context)
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 32,
                            height: 4,
                            margin: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: handle.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          if (title != null) _SheetTitle(title),
                          Flexible(child: builder(context)),
                        ],
                      ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _SheetTitle extends StatelessWidget {
  const _SheetTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Semantics(
          header: true,
          child: Text(
            text,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontFamily: 'Source Serif 4',
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

/// Makes a glass pane step back, smaller and darker, while another route
/// covers the route that shows it. Two lively panes then do not compete.
class _StepBack extends StatelessWidget {
  const _StepBack({required this.radius, required this.child});
  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final covered = ModalRoute.of(context)?.secondaryAnimation;
    if (covered == null) return child;
    return AnimatedBuilder(
      animation: covered,
      child: child,
      builder: (context, child) {
        final depth = Curves.easeOut.transform(covered.value);
        return Transform.scale(
          scale: 1 - 0.06 * depth,
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              color: Colors.black.withValues(alpha: 0.35 * depth),
            ),
            child: child,
          ),
        );
      },
    );
  }
}

/// An alert dialog drawn as a glass pane. It takes the same parts as
/// [AlertDialog].
class GlassDialog extends StatelessWidget {
  const GlassDialog({
    super.key,
    this.book,
    this.title,
    this.content,
    this.actions,
  });

  /// The book the dialog is about, if any.
  final Book? book;
  final Widget? title;
  final Widget? content;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      child: CoverGlass(
        book: book,
        radius: 28,
        tint: 0.75,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (title case final title?)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: DefaultTextStyle(
                    style: theme.textTheme.headlineSmall!.copyWith(
                      color: scheme.onSurface,
                    ),
                    child: Semantics(container: true, child: title),
                  ),
                ),
              if (content case final content?)
                Flexible(
                  child: DefaultTextStyle(
                    style: theme.textTheme.bodyMedium!.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    child: SingleChildScrollView(child: content),
                  ),
                ),
              if (actions case final actions? when actions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 18),
                  child: OverflowBar(
                    alignment: MainAxisAlignment.end,
                    spacing: 8,
                    children: actions,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows [choices] as rows on a glass sheet headed [title], and marks the
/// row whose value equals [current]. A tap on a row reports its value through
/// [onSelected] and closes the sheet.
Future<void> showGlassChoices<T>(
  BuildContext context, {
  required String title,
  required List<(T value, String label)> choices,
  required T current,
  required ValueChanged<T> onSelected,
}) => showGlassSheet<void>(
  context,
  title: title,
  builder: (context) => SingleChildScrollView(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (value, label) in choices)
            ListTile(
              title: Text(label),
              selected: value == current,
              onTap: () {
                onSelected(value);
                Navigator.pop(context);
              },
            ),
        ],
      ),
    ),
  ),
);

/// Asks the person to confirm [action] before it happens. The dialog shows
/// [title] and [message], a [cancel] button, and a filled button labeled
/// [action]. It is true only when the person chose [action]; Cancel and a tap
/// outside the dialog are false.
///
/// The dialog is a glass pane, except with [glass] false, which draws a plain
/// dialog for a screen that keeps its own look, such as the reader.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
  String cancel = 'Cancel',
  bool glass = true,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) {
        final actions = [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ];
        return glass
            ? GlassDialog(
                title: Text(title),
                content: Text(message),
                actions: actions,
              )
            : AlertDialog(
                title: Text(title),
                content: Text(message),
                actions: actions,
              );
      },
    ) ??
    false;

/// Shows a short message that floats on glass above the bottom of the page.
void showGlassMessage(BuildContext context, String message) {
  final theme = Theme.of(context);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.transparent,
      elevation: 0,
      padding: EdgeInsets.zero,
      content: CoverGlass(
        radius: 16,
        tint: 0.75,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Text(
            message,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
      ),
    ),
  );
}

/// One choice in a [GlassMenuButton].
class GlassMenuItem {
  const GlassMenuItem(this.label, {this.icon, required this.onSelected});
  final String label;
  final IconData? icon;
  final VoidCallback onSelected;
}

/// An icon button that opens a menu of [items] on a glass pane.
class GlassMenuButton extends StatelessWidget {
  const GlassMenuButton({
    super.key,
    required this.tooltip,
    required this.items,
    this.icon = const Icon(Icons.more_vert),
    this.book,
  });
  final String tooltip;
  final List<GlassMenuItem> items;
  final Widget icon;

  /// The book the menu is about, if any.
  final Book? book;

  @override
  Widget build(BuildContext context) => MenuAnchor(
    style: const MenuStyle(
      backgroundColor: WidgetStatePropertyAll(Colors.transparent),
      surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
      shadowColor: WidgetStatePropertyAll(Colors.transparent),
      elevation: WidgetStatePropertyAll(0),
      padding: WidgetStatePropertyAll(EdgeInsets.zero),
    ),
    menuChildren: [
      // The margin keeps the pane clear of the screen edge, where the menu
      // is pushed when the button sits near it.
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: CoverGlass(
          book: book,
          radius: 16,
          tint: 0.75,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: IntrinsicWidth(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final item in items)
                    MenuItemButton(
                      leadingIcon: item.icon == null ? null : Icon(item.icon),
                      onPressed: item.onSelected,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 24),
                        child: Text(item.label),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ],
    builder: (context, menu, _) => IconButton(
      tooltip: tooltip,
      icon: icon,
      onPressed: () => menu.isOpen ? menu.close() : menu.open(),
    ),
  );
}
