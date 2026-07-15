import 'package:shared_preferences/shared_preferences.dart';

/// Tracks whether the first-launch "pick a name?" nudge has already been
/// shown, mirroring [AnalyticsConsentService.shouldShowFirstLaunchNotice] /
/// [TutorialService.shouldShowFirstLaunchPrompt]'s set-then-check-once
/// pattern against a [SharedPreferences] flag.
///
/// Covers two cases: a guest account still on the literal placeholder name
/// "Guest", and a signed-in player whose name was silently derived from
/// their email's local part (see `isEmailDerivedFallbackName`) — most
/// visibly, Apple Sign-In without a shared name.
class MissingNamePromptService {
  MissingNamePromptService._();

  static final MissingNamePromptService instance = MissingNamePromptService._();

  // Renamed from the original guest-only key so every existing install gets
  // one fresh chance at this prompt now that it also covers email-derived
  // fallback names, not just guests — installs that already dismissed the
  // guest-only version aren't otherwise reachable by the new condition.
  static const String _promptShownPrefsKey = 'missing_name_prompt_shown';

  /// True exactly once — the first time this is called on a fresh install —
  /// so the first-launch missing-name prompt only ever appears a single time.
  Future<bool> shouldShowFirstLaunchPrompt() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_promptShownPrefsKey) ?? false) return false;
    await prefs.setBool(_promptShownPrefsKey, true);
    return true;
  }
}
