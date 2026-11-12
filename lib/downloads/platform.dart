import '../catalog/model.dart';
import 'downloads.dart';
import 'platform_stub.dart' if (dart.library.io) 'platform_io.dart' as platform;

/// The app's downloads. [prepare] prepares each saved file of a text
/// edition for reading, as `LocalDownloads.prepare` describes.
Future<Downloads> createDownloads(
  MediaPolicy policy, {
  Future<void> Function(VerifiedFile original, SourceFile source)? prepare,
}) => platform.createDownloads(policy, prepare: prepare);
