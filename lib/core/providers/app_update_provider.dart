import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/app_update_suggestion.dart';

/// Resolves once per app launch (and when provider is invalidated) whether to
/// show the optional “new update available” banner on the start screen.
final appUpdateSuggestionProvider =
    FutureProvider<AppUpdateSuggestion?>((ref) async {
  return fetchAppUpdateSuggestion();
});
