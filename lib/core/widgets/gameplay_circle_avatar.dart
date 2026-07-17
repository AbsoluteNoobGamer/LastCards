import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../shared/avatars/avatar_catalog.dart';
import '../../shared/avatars/avatar_face.dart';
import '../utils/display_name_utils.dart';

/// Avatar face for the table: cosmetic id, HTTPS image, local file, or initials.
class GameplayCircleAvatar extends StatelessWidget {
  const GameplayCircleAvatar({
    super.key,
    required this.radius,
    required this.displayName,
    this.avatarUrl,
    this.avatarCosmeticId,
    this.localFilePath,
    this.initialsOverride,
    this.foregroundTextStyle,
  });

  final double radius;
  final String displayName;
  final String? avatarUrl;

  /// Locker cosmetic id; takes precedence over photo/initials when valid.
  final String? avatarCosmeticId;
  final String? localFilePath;

  /// When non-null (e.g. AI seat), used instead of [initialsFromDisplayName].
  final String? initialsOverride;
  final TextStyle? foregroundTextStyle;

  @override
  Widget build(BuildContext context) {
    final design = avatarDesignById(avatarCosmeticId);
    if (design != null) {
      return AvatarFace(design: design, size: radius * 2);
    }

    final trimmedUrl = avatarUrl?.trim();
    final hasHttps =
        trimmedUrl != null &&
        trimmedUrl.isNotEmpty &&
        trimmedUrl.toLowerCase().startsWith('https://');

    final useLocal = !kIsWeb &&
        !hasHttps &&
        localFilePath != null &&
        localFilePath!.isNotEmpty;

    final initials =
        initialsOverride ?? initialsFromDisplayName(displayName);

    if (hasHttps) {
      return ClipOval(
        child: Image.network(
          trimmedUrl,
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _initialsFallback(initials),
        ),
      );
    }
    if (useLocal) {
      final file = File(localFilePath!);
      if (file.existsSync()) {
        return ClipOval(
          child: Image.file(
            file,
            width: radius * 2,
            height: radius * 2,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _initialsFallback(initials),
          ),
        );
      }
    }

    return _initialsFallback(initials);
  }

  Widget _initialsFallback(String initials) {
    return Center(
      child: Text(
        initials,
        style: foregroundTextStyle,
        textAlign: TextAlign.center,
      ),
    );
  }
}
