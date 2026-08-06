import 'package:shared_preferences/shared_preferences.dart';

/// Local persistence for the in-game coin wallet. Mirrors [ThemeService]'s
/// shape: this class is pure SharedPreferences I/O — reactive state and
/// Firestore sync live in [CurrencyNotifier].
class CurrencyService {
  static const _balanceKey = 'currencyCoinBalance';
  static const _walletVersionKey = 'currencyWalletVersion';
  static const _lastRewardedLevelKey = 'currencyLastRewardedLevel';
  static const _lastDailyRewardEpochDayKey = 'currencyLastDailyRewardEpochDay';
  static const _dailyStreakKey = 'currencyDailyStreak';

  const CurrencyService();

  Future<int> loadBalance() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_balanceKey) ?? 0;
  }

  Future<void> saveBalance(int balance) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_balanceKey, balance);
  }

  /// Monotonic counter bumped only by server-authoritative wallet writes
  /// (see `WalletService` on the game server) — never by this client. Lets
  /// [CurrencyNotifier.loadFromPrefs] tell a real server-side decrease (e.g.
  /// a lost wager) apart from a merely-stale local cache.
  Future<int> loadWalletVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_walletVersionKey) ?? 0;
  }

  Future<void> saveWalletVersion(int version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_walletVersionKey, version);
  }

  /// Null means the level-up reward baseline has never been established
  /// (first run of the currency feature on this install).
  Future<int?> loadLastRewardedLevel() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_lastRewardedLevelKey);
  }

  Future<void> saveLastRewardedLevel(int level) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastRewardedLevelKey, level);
  }

  /// Day index (days since epoch, local calendar day) the daily reward was
  /// last claimed, and the current consecutive-day streak. Epoch day is
  /// null if the reward has never been claimed.
  Future<({int? epochDay, int streak})> loadDailyRewardState() async {
    final prefs = await SharedPreferences.getInstance();
    final epochDay = prefs.getInt(_lastDailyRewardEpochDayKey);
    final streak = prefs.getInt(_dailyStreakKey) ?? 0;
    return (epochDay: epochDay, streak: streak);
  }

  Future<void> saveDailyRewardState({
    required int epochDay,
    required int streak,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastDailyRewardEpochDayKey, epochDay);
    await prefs.setInt(_dailyStreakKey, streak);
  }
}
