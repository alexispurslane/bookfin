import 'package:flutter/widgets.dart';

import 'session.dart';

/// The reader session, and the way to bring the reader screen to the front,
/// for screens outside the reader. The History sheet in the player and on
/// the book page reads the reading records from [reader], and shows a
/// reading place with [show]. The library gives it to each of its pages,
/// and sheets, dialogs and menus copy it.
class ReaderScope extends InheritedWidget implements InheritedTheme {
  const ReaderScope({
    super.key,
    required this.reader,
    required this.show,
    required super.child,
  });

  /// The app's one reader session.
  final ReaderSession reader;

  /// Brings the reader screen to the front over [context]. A caller then
  /// opens or moves the book in [reader], which the screen shows.
  final void Function(BuildContext context) show;

  /// The scope above [context], or null in a screen without a reader, such
  /// as a test of the player alone. [context] does not rebuild when the
  /// scope changes, because a caller reads it only when the person acts.
  static ReaderScope? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ReaderScope>();

  @override
  Widget wrap(BuildContext context, Widget child) =>
      ReaderScope(reader: reader, show: show, child: child);

  @override
  bool updateShouldNotify(ReaderScope oldWidget) => false;
}
