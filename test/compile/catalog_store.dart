// Compile target for the catalog's native/browser storage boundary. The app's
// PDF FFI import currently prevents using the whole web app for this check.
// Run: flutter build web --no-pub --target test/compile/catalog_store.dart
import 'package:bookfin/catalog/jellyfin.dart';
import 'package:bookfin/catalog/store.dart';
import 'package:flutter/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = LocalCatalogStore();
  final scope = AccountScope(
    server: Uri.parse('https://compile.example'),
    serverId: 'compile',
    userId: 'compile',
  );
  await store.write(scope, 'catalog text');
  await store.migrateLegacy();
  final text = await store.read(scope);
  runApp(Text(text ?? 'No catalog', textDirection: TextDirection.ltr));
}
