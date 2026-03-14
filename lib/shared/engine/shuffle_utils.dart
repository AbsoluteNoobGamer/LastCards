import 'dart:math' as math;

/// Performs an in-place Fisher-Yates shuffle on [list] and returns it.
///
/// If [seed] is provided, a seeded [math.Random] is used for reproducible
/// results (useful in tests). Otherwise a default [math.Random] is used.
///
/// This is the canonical shuffle implementation shared by the client
/// (game_engine, bust_engine, table_screen) and the server (game_session).
List<T> fisherYatesShuffle<T>(List<T> list, [int? seed]) {
  final rng = seed != null ? math.Random(seed) : math.Random();
  for (int i = list.length - 1; i > 0; i--) {
    final j = rng.nextInt(i + 1);
    final tmp = list[i];
    list[i] = list[j];
    list[j] = tmp;
  }
  return list;
}
