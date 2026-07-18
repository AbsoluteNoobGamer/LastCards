import 'package:flutter_test/flutter_test.dart';
import 'package:last_cards/features/gameplay/presentation/widgets/match_broadcast_header.dart';

void main() {
  group('resolveMatchModeLabel', () {
    test('solo offline', () {
      expect(
        resolveMatchModeLabel(
          isOnline: false,
          isTournamentMode: false,
          isRanked: false,
          isBust: false,
        ),
        'Solo',
      );
    });

    test('casual online', () {
      expect(
        resolveMatchModeLabel(
          isOnline: true,
          isTournamentMode: false,
          isRanked: false,
          isBust: false,
        ),
        'Casual',
      );
    });

    test('ranked online', () {
      expect(
        resolveMatchModeLabel(
          isOnline: true,
          isTournamentMode: false,
          isRanked: true,
          isBust: false,
        ),
        'Ranked',
      );
    });

    test('tournament beats ranked', () {
      expect(
        resolveMatchModeLabel(
          isOnline: true,
          isTournamentMode: true,
          isRanked: true,
          isBust: false,
        ),
        'Tournament',
      );
    });

    test('bust online (non-tournament)', () {
      expect(
        resolveMatchModeLabel(
          isOnline: true,
          isTournamentMode: false,
          isRanked: false,
          isBust: true,
        ),
        'Bust',
      );
    });
  });
}
