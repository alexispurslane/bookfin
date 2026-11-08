import 'package:bookfin/catalog/layout.dart';
import 'package:bookfin/catalog/library_services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../foundation_test.dart' show disconnectedCatalog;

/// A layout store that keeps the last saved layout in memory.
class _MemoryLayoutStore implements LayoutStore {
  String? saved;
  @override
  Future<String?> read() async => saved;
  @override
  Future<void> write(String value) async => saved = value;
}

void main() {
  late LibraryLayout layout;
  late LibraryServices services;
  setUp(() {
    layout = LibraryLayout(_MemoryLayoutStore());
    services = LibraryServices(
      catalog: disconnectedCatalog(),
      layout: layout,
      onReaderNightChanged: (_) {},
    );
  });
  tearDown(() {
    services.catalog.dispose();
    layout.dispose();
  });

  test('the shelf layout reports each new view and density of the saved '
      'layout', () {
    final shelf = services.shelfLayout;
    final heard = <ShelfLayout>[];
    shelf.addListener(() => heard.add(shelf.value));
    layout.view = LibraryView.list;
    layout.density = LibraryDensity.compact;
    expect(heard, [
      (view: LibraryView.list, density: LibraryDensity.spacious),
      (view: LibraryView.list, density: LibraryDensity.compact),
    ]);
  });

  test('two reads of the shelf layout are equal, so a rebuilt library keeps '
      'its subscription', () {
    expect(services.shelfLayout, services.shelfLayout);
    expect(services.shelfLayout.hashCode, services.shelfLayout.hashCode);
  });
}
