import 'package:shared_preferences/shared_preferences.dart';

/// Tracks whether the first-launch "pick a name?" nudge for guest accounts
/// has already been shown, mirroring
/// [AnalyticsConsentService.shouldShowFirstLaunchNotice] /
/// [TutorialService.shouldShowFirstLaunchPrompt]'s set-then-check-once
/// pattern against a [SharedPreferences] flag.
class GuestRenamePromptService {
  GuestRenamePromptService._();

  static final GuestRenamePromptService instance = GuestRenamePromptService._();

  static const String _promptShownPrefsKey = 'guest_rename_prompt_shown';

  /// True exactly once — the first time this is called on a fresh install —
  /// so the first-launch guest-rename prompt only ever appears a single time.
  Future<bool> shouldShowFirstLaunchPrompt() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_promptShownPrefsKey) ?? false) return false;
    await prefs.setBool(_promptShownPrefsKey, true);
    return true;
  }
}
