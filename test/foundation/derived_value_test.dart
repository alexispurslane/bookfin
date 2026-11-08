import 'package:bookfin/foundation/derived_value.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// A source that holds a count and a name, and notifies on each change.
class _Counter extends ChangeNotifier {
  int count = 0;
  String name = 'first';
  void increment() {
    count++;
    notifyListeners();
  }
}

void main() {
  late _Counter counter;
  setUp(() => counter = _Counter());
  tearDown(() => counter.dispose());

  DerivedValue<int> doubled() =>
      DerivedValue(counter, () => counter.count * 2, source: counter);

  test('reads its value from the source at each read', () {
    final value = doubled();
    counter.count = 4;
    expect(value.value, 8);
  });

  test('tells each listener when the source notifies', () {
    final value = doubled();
    final heard = <int>[];
    value.addListener(() => heard.add(value.value));
    counter.increment();
    counter.increment();
    expect(heard, [2, 4]);
  });

  test('a removed listener hears no more changes', () {
    final value = doubled();
    var notices = 0;
    void heard() => notices++;
    value.addListener(heard);
    counter.increment();
    value.removeListener(heard);
    counter.increment();
    expect(notices, 1);
  });

  test('two values from the same source are equal', () {
    expect(doubled(), doubled());
    expect(doubled().hashCode, doubled().hashCode);
  });

  test('values from different sources differ', () {
    final other = _Counter();
    addTearDown(other.dispose);
    expect(
      doubled(),
      isNot(DerivedValue(other, () => other.count * 2, source: other)),
    );
  });

  test('values of different types from one source differ', () {
    expect(
      DerivedValue<Object>(counter, () => counter.count, source: counter),
      isNot(DerivedValue<String>(counter, () => counter.name, source: counter)),
    );
  });

  test('a value without a source equals only itself', () {
    final value = DerivedValue(counter, () => counter.count);
    expect(value, value);
    expect(value, isNot(DerivedValue(counter, () => counter.count)));
  });

  testWidgets('an owner that rebuilds with a value from the same source keeps '
      'its subscription', (tester) async {
    var subscriptions = 0;
    final source = _CountingSubscriptions(counter, () => subscriptions++);
    Widget shown() => ValueListenableBuilder(
      valueListenable: DerivedValue(
        source,
        () => counter.count,
        source: counter,
      ),
      builder: (context, count, _) =>
          Text('$count', textDirection: TextDirection.ltr),
    );
    await tester.pumpWidget(shown());
    await tester.pumpWidget(shown());
    counter.increment();
    await tester.pump();
    expect(subscriptions, 1);
    expect(find.text('1'), findsOneWidget);
  });
}

/// [source], which calls [onSubscribe] at each added listener.
class _CountingSubscriptions implements Listenable {
  _CountingSubscriptions(this.source, this.onSubscribe);
  final Listenable source;
  final VoidCallback onSubscribe;

  @override
  void addListener(VoidCallback listener) {
    onSubscribe();
    source.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) => source.removeListener(listener);
}
