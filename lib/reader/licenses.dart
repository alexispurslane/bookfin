import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

Stream<LicenseEntry> readerLicenses() async* {
  for (final directory in [
    'assets/licenses/reader',
    'assets/licenses/ocr',
    'assets/licenses/speech',
  ]) {
    final manifest = jsonDecode(
      await rootBundle.loadString('$directory/manifest.json'),
    ) as Map<String, dynamic>;
    for (final entry in manifest.entries) {
      final bytes = (await rootBundle.load('$directory/${entry.key}')).buffer
          .asUint8List();
      String text;
      try {
        text = utf8.decode(bytes);
      } on FormatException {
        text = latin1.decode(bytes);
      }
      yield LicenseEntryWithLineBreaks([
        entry.value['package'] as String,
      ], text);
    }
  }
}
