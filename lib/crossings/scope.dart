import 'package:flutter/widgets.dart';

import 'crossings.dart';

/// The app's one [Crossings], for the History sheet, which places a choice
/// of the other medium in the open edition. The library gives it to each
/// of its pages, and sheets, dialogs and menus copy it.
class CrossingsScope extends InheritedWidget implements InheritedTheme {
  const CrossingsScope({
    super.key,
    required this.crossings,
    required super.child,
  });

  final Crossings crossings;

  /// The crossings above [context], or null in a screen without them, such
  /// as a test of the player alone. [context] does not rebuild when the
  /// scope changes, because a caller reads it only when the History opens.
  static Crossings? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<CrossingsScope>()?.crossings;

  @override
  Widget wrap(BuildContext context, Widget child) =>
      CrossingsScope(crossings: crossings, child: child);

  @override
  bool updateShouldNotify(CrossingsScope oldWidget) => false;
}
