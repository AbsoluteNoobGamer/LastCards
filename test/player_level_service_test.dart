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

    test('caps level at 20', () {
      expect(PlayerLevelService.levelFromTotalXP(999999), 20);
    });

    test('levels 11-20 map correctly', () {
      expect(PlayerLevelService.levelFromTotalXP(5600), 11);
      expect(PlayerLevelService.levelFromTotalXP(6900), 12);
      expect(PlayerLevelService.levelFromTotalXP(8400), 13);
      expect(PlayerLevelService.levelFromTotalXP(10100), 14);
      expect(PlayerLevelService.levelFromTotalXP(12000), 15);
      expect(PlayerLevelService.levelFromTotalXP(14100), 16);
      expect(PlayerLevelService.levelFromTotalXP(16400), 17);
      expect(PlayerLevelService.levelFromTotalXP(19000), 18);
      expect(PlayerLevelService.levelFromTotalXP(21900), 19);
      expect(PlayerLevelService.levelFromTotalXP(25000), 20);
    });
  });

  group('PlayerLevelService.progressForTotalXp', () {
    test('level 1 band and fraction', () {
      final p = PlayerLevelService.progressForTotalXp(0);
      expect(p.level, 1);
      expect(p.bandStartXp, 0);
      expect(p.nextBandStartXp, 100);
      expect(p.progressFraction, 0.0);

      final mid = PlayerLevelService.progressForTotalXp(50);
      expect(mid.progressFraction, 0.5);
    });

    test('mid-level progress matches band', () {
      final p = PlayerLevelService.progressForTotalXp(350);
      expect(p.level, 3);
      expect(p.bandStartXp, 300);
      expect(p.nextBandStartXp, 600);
      expect(p.progressFraction, closeTo(50 / 300, 1e-9));
    });

    test('max level (20) has full bar and no next band', () {
      final p = PlayerLevelService.progressForTotalXp(25000);
      expect(p.level, 20);
      expect(p.bandStartXp, 25000);
      expect(p.nextBandStartXp, isNull);
      expect(p.progressFraction, 1.0);

      final over = PlayerLevelService.progressForTotalXp(999999);
      expect(over.level, 20);
      expect(over.nextBandStartXp, isNull);
      expect(over.progressFraction, 1.0);
    });

    test('level 10 is now mid-progression not max', () {
      final p = PlayerLevelService.progressForTotalXp(4500);
      expect(p.level, 10);
      expect(p.bandStartXp, 4500);
      expect(p.nextBandStartXp, 5600);
    });
  });
}

