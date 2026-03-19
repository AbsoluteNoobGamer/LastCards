import 'package:flutter_test/flutter_test.dart';
import 'package:last_cards/core/services/player_level_service.dart';

void main() {
  group('PlayerLevelService.levelFromTotalXP', () {
    test('clamps negative XP to level 1', () {
      expect(PlayerLevelService.levelFromTotalXP(-10), 1);
    });

    test('maps XP thresholds to expected levels', () {
      expect(PlayerLevelService.levelFromTotalXP(0), 1);
      expect(PlayerLevelService.levelFromTotalXP(99), 1);

      expect(PlayerLevelService.levelFromTotalXP(100), 2);
      expect(PlayerLevelService.levelFromTotalXP(299), 2);

      expect(PlayerLevelService.levelFromTotalXP(300), 3);
      expect(PlayerLevelService.levelFromTotalXP(599), 3);

      expect(PlayerLevelService.levelFromTotalXP(600), 4);
      expect(PlayerLevelService.levelFromTotalXP(999), 4);

      expect(PlayerLevelService.levelFromTotalXP(1000), 5);
      expect(PlayerLevelService.levelFromTotalXP(1499), 5);

      expect(PlayerLevelService.levelFromTotalXP(1500), 6);
      expect(PlayerLevelService.levelFromTotalXP(2099), 6);

      expect(PlayerLevelService.levelFromTotalXP(2100), 7);
      expect(PlayerLevelService.levelFromTotalXP(2799), 7);

      expect(PlayerLevelService.levelFromTotalXP(2800), 8);
      expect(PlayerLevelService.levelFromTotalXP(3599), 8);

      expect(PlayerLevelService.levelFromTotalXP(3600), 9);
      expect(PlayerLevelService.levelFromTotalXP(4499), 9);

      expect(PlayerLevelService.levelFromTotalXP(4500), 10);
    });

    test('caps level at 10', () {
      expect(PlayerLevelService.levelFromTotalXP(999999), 10);
    });
  });
}

