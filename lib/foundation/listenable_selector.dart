import 'package:flutter/widgets.dart';

/// Builds from one value that [select] reads, and rebuilds only when that
/// value changes after [listenable] notifies. A value is the same when it is
/// `==` to the last one, so a record of the shown fields works well.
///
/// [select] runs on every notification, so it must be cheap. A parent that
/// rebuilds this widget also rebuilds [builder], with a fresh value.
class ListenableSelector<T> extends StatefulWidget {
  const ListenableSelector({
    super.key,
    required this.listenable,
    required this.select,
    required this.builder,
    this.child,
  });
  final Listenable listenable;
  final T Function() select;

  /// Gets [child] unchanged, for a part that does not depend on the value.
  final Widget Function(BuildContext context, T value, Widget? child) builder;
  final Widget? child;

  @override
  State<ListenableSelector<T>> createState() => _ListenableSelectorState<T>();
}

class _ListenableSelectorState<T> extends State<ListenableSelector<T>> {
  late T _value = widget.select();

  @override
  void initState() {
    super.initState();
    widget.listenable.addListener(_changed);
  }

  @override
  void didUpdateWidget(ListenableSelector<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.listenable != widget.listenable) {
      oldWidget.listenable.removeListener(_changed);
      widget.listenable.addListener(_changed);
    }
    _value = widget.select();
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    final value = widget.select();
    if (value != _value) setState(() => _value = value);
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _value, widget.child);
}
