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
