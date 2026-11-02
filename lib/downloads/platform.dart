import 'downloads.dart';
import 'platform_stub.dart' if (dart.library.io) 'platform_io.dart' as platform;

Future<Downloads> createDownloads(MediaPolicy policy) =>
    platform.createDownloads(policy);
