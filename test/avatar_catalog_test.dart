import 'package:flutter_test/flutter_test.dart';
import 'package:last_cards/shared/avatars/avatar_catalog.dart';

void main() {
  group('avatar catalog', () {
    test('known ids include use_photo and every catalog entry', () {
      expect(isKnownAvatarId(kAvatarUsePhotoId), isTrue);
      expect(isKnownAvatarId(kAvatarDefaultId), isTrue);
      expect(isKnownAvatarId('not_a_real_avatar'), isFalse);
      for (final d in kAvatarCatalog) {
        expect(isKnownAvatarId(d.id), isTrue);
        expect(avatarDesignById(d.id)?.id, d.id);
      }
    });

    test('use_photo and null do not resolve to a design', () {
      expect(avatarDesignById(null), isNull);
      expect(avatarDesignById(kAvatarUsePhotoId), isNull);
      expect(avatarDesignById(''), isNull);
    });

    test('title exclusives cover the planned boards with labels', () {
      final titles =
          kAvatarCatalog.where((d) => d.isTitleExclusive).toList();
      final kinds = titles.map((d) => d.exclusiveKind).toSet();
      expect(kinds, containsAll(AvatarExclusiveKind.values));
      for (final d in titles) {
        expect(d.leaderboardLabel, isNotNull);
        expect(d.leaderboardLabel, isNotEmpty);
        // Titles must not unlock via the normal level path.
        expect(d.unlockLevel, 1);
        expect(d.isTitleExclusive, isTrue);
        // Leaderboard titles always loop an aura in AvatarFace.
        expect(d.animated, isTrue);
      }
    });

    test('leaderboardLabelForKind matches catalog copy', () {
      expect(
        leaderboardLabelForKind(AvatarExclusiveKind.comboKing),
        'Combo leaderboard',
      );
      expect(
        leaderboardLabelForKind(AvatarExclusiveKind.casualAce),
        'Casual Online wins',
      );
      expect(
        leaderboardLabelForKind(AvatarExclusiveKind.rankedCrown),
        'Ranked MMR',
      );
    });

    test('level unlocks are not title exclusives', () {
      final levelOnly =
          kAvatarCatalog.where((d) => !d.isTitleExclusive).toList();
      expect(levelOnly, isNotEmpty);
      for (final d in levelOnly) {
        expect(d.exclusiveKind, isNull);
        expect(d.leaderboardLabel, isNull);
      }
    });
  });
}
