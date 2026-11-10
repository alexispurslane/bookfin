import 'dart:typed_data';

import '../downloads/downloads.dart';

Future<String?> readOcrCache(
  VerifiedFile original,
  String digest,
  String key,
) async => null;
Future<void> writeOcrCache(
  VerifiedFile original,
  String digest,
  String key,
  String hocr,
  bool Function() live,
) async {}
Future<Int32List?> readLayoutCache(
  VerifiedFile original,
  String digest,
  String key,
) async => null;
Future<void> writeLayoutCache(
  VerifiedFile original,
  String digest,
  String key,
  Int32List record,
  bool Function() live,
) async {}
