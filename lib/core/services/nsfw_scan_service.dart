import 'dart:io';

import 'package:nsfw_detector_flutter/nsfw_detector_flutter.dart';

/// Abstract interface for NSFW image scanning.
///
/// Defining this as an abstract class allows the real implementation to be
/// swapped out for a mock in unit tests.
abstract class NsfwScanService {
  /// Scans [imageFile] for NSFW content.
  ///
  /// Returns `true` if the image is flagged as NSFW, `false` if safe or if
  /// the scanner is unavailable on the current platform.
  Future<bool> isNsfw(File imageFile);
}

/// Default implementation that calls the native [NsfwDetector].
///
/// Gracefully catches all exceptions (e.g. [MissingPluginException] on desktop)
/// and treats missing platform support as safe (returns false).
class DefaultNsfwScanService implements NsfwScanService {
  @override
  Future<bool> isNsfw(File imageFile) async {
    try {
      final detector = await NsfwDetector.load();
      final result = await detector.detectNSFWFromFile(imageFile);
      return result?.isNsfw == true;
    } catch (_) {
      // Platform not supported or model unavailable — treat as safe.
      return false;
    }
  }
}
