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

    test('title exclusives cover the planned boards', () {
      final kinds = kAvatarCatalog
          .where((d) => d.isTitleExclusive)
          .map((d) => d.exclusiveKind)
          .toSet();
      expect(kinds, containsAll(AvatarExclusiveKind.values));
    });
  });
}
