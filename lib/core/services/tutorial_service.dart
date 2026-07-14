import 'package:shared_preferences/shared_preferences.dart';

/// Tracks whether the first-launch "want a quick tutorial?" prompt has
/// already been shown, mirroring
/// [AnalyticsConsentService.shouldShowFirstLaunchNotice]'s set-then-check-once
/// pattern against a [SharedPreferences] flag.
class TutorialService {
  TutorialService._();

  static final TutorialService instance = TutorialService._();

  static const String _promptShownPrefsKey = 'tutorial_prompt_shown';

  /// True exactly once — the first time this is called on a fresh install —
  /// so the first-launch tutorial prompt only ever appears a single time.
  Future<bool> shouldShowFirstLaunchPrompt() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_promptShownPrefsKey) ?? false) return false;
    await prefs.setBool(_promptShownPrefsKey, true);
    return true;
  }
}
