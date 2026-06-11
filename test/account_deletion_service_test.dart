import 'package:flutter_test/flutter_test.dart';
import 'package:last_cards/core/services/account_deletion_service.dart';
import 'package:last_cards/core/services/profile_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AccountDeletionService.clearLocalUserData', () {
    test('resets profile and clears account-linked prefs', () async {
      SharedPreferences.setMockInitialValues({
        'profile_name': 'Alice',
        'profile_avatar_path': '/tmp/avatar.jpg',
        'reaction_wheel_slots_v1': '[1,2,3]',
        'player_total_xp': 420,
      });

      await AccountDeletionService.clearLocalUserData();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('profile_name'), ProfileDefaults.name);
      expect(prefs.containsKey('profile_avatar_path'), isFalse);
      expect(prefs.containsKey('reaction_wheel_slots_v1'), isFalse);
      expect(prefs.containsKey('player_total_xp'), isFalse);
    });
  });
}
