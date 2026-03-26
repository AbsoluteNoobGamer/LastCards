import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../data/local_leaderboard_store.dart';

import '../../../../core/providers/theme_provider.dart';
import '../../../../core/widgets/themed_shimmer.dart';
import '../../../../core/theme/app_theme_data.dart';

/// Game mode categories for the leaderboard, aligned with main menu entry points.
enum LeaderboardMode {
  ranked('Ranked', Icons.emoji_events),
  singlePlayer('Single Player', Icons.smart_toy),
  online('Online (Quick Match)', Icons.people),
  tournamentVsAi('Tournament (vs AI)', Icons.shield),
  tournamentOnline('Tournament (Online)', Icons.public),
  bustOffline('Bust (Offline)', Icons.auto_awesome_rounded),
  bustOnline('Bust (Online)', Icons.language_rounded);

  const LeaderboardMode(this.label, this.icon);
  final String label;
  final IconData icon;
}

// ── Data model ────────────────────────────────────────────────────────────────

class _RankedEntry {
  const _RankedEntry({
    required this.uid,
    required this.displayName,
    required this.rating,
    required this.wins,
    required this.losses,
    required this.leaves,
    required this.gamesPlayed,
  });

  final String uid;
  final String displayName;
  final int rating;
  final int wins;
  final int losses;
  final int leaves;
  final int gamesPlayed;

  factory _RankedEntry.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return _RankedEntry(
      uid: doc.id,
      displayName: d['displayName'] as String? ?? 'Player',
      rating: (d['rating'] as num?)?.toInt() ?? 1000,
      wins: (d['wins'] as num?)?.toInt() ?? 0,
      losses: (d['losses'] as num?)?.toInt() ?? 0,
      leaves: (d['leaves'] as num?)?.toInt() ?? 0,
      gamesPlayed: (d['gamesPlayed'] as num?)?.toInt() ?? 0,
    );
  }
}

// Firestore entries for non-ranked modes.
class _ModeEntry {
  const _ModeEntry({
    required this.uid,
    required this.displayName,
    required this.wins,
    required this.losses,
    required this.gamesPlayed,
    this.rating,
  });

  final String uid;
  final String displayName;
  final int wins;
  final int losses;
  final int gamesPlayed;
  final int? rating;

  /// Build from a Firestore document. When [playerCount] is non-null (2–7),
  /// the per-bracket fields (`wins_N`, etc.) are preferred over the global
  /// totals so the "N players" filter shows bracket-specific stats.
  factory _ModeEntry.fromDoc(DocumentSnapshot doc, {int? playerCount}) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    final suffix = (playerCount != null && playerCount >= 2 && playerCount <= 7)
        ? '_$playerCount'
        : '';
    return _ModeEntry(
      uid: doc.id,
      displayName: d['displayName'] as String? ?? 'Player',
      wins: (d['wins$suffix'] as num?)?.toInt() ?? 0,
      losses: (d['losses$suffix'] as num?)?.toInt() ?? 0,
      gamesPlayed: (d['gamesPlayed$suffix'] as num?)?.toInt() ?? 0,
      rating: (d['rating'] as num?)?.toInt(),
    );
  }
}

// ── Screen ────────────────────────────────────────────────────────────────────

class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen> {
  LeaderboardMode _selectedMode = LeaderboardMode.ranked;

  /// null = "All" (global totals); 2–7 = bracket-specific filter.
  int? _playerCountFilter;

  /// Which modes support the player-count filter (server-written, multi-bracket).
  static const _filterableModes = {
    LeaderboardMode.ranked,
    LeaderboardMode.online,
    LeaderboardMode.bustOnline,
  };

  // ── Ranked Firestore data ─────────────────────────────────────────────────

  Future<List<_RankedEntry>> _fetchRanked() async {
    final n = _playerCountFilter;
    final snap = await FirebaseFirestore.instance
        .collection('ranked_stats')
        .orderBy('rating', descending: true)
        .limit(50)
        .get();
    final entries = snap.docs.map((doc) {
      if (n == null) return _RankedEntry.fromDoc(doc);
      // Overlay per-bracket win/loss/gamesPlayed onto the ranked entry so the
      // "N players" filter shows bracket-specific stats while keeping MMR.
      // Ranked always sorts by MMR (correct regardless of bracket), so no
      // orderBy change is needed here — only the zero-activity guard below.
      final d = doc.data() as Map<String, dynamic>? ?? {};
      final base = _RankedEntry.fromDoc(doc);
      return _RankedEntry(
        uid: base.uid,
        displayName: base.displayName,
        rating: base.rating,
        wins: (d['wins_$n'] as num?)?.toInt() ?? 0,
        losses: (d['losses_$n'] as num?)?.toInt() ?? 0,
        leaves: base.leaves,
        gamesPlayed: (d['gamesPlayed_$n'] as num?)?.toInt() ?? 0,
      );
    }).toList();

    // Drop players who have never played an N-player ranked game so the
    // bracket-filtered view only shows relevant entries.
    if (n != null) {
      return entries.where((e) => e.gamesPlayed > 0).toList();
    }
    return entries;
  }

  _RankedEntry? _findLocalEntry(List<_RankedEntry> entries) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return entries.firstWhereOrNull((e) => e.uid == uid);
  }

  int _localRank(List<_RankedEntry> entries) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return -1;
    final idx = entries.indexWhere((e) => e.uid == uid);
    return idx == -1 ? -1 : idx + 1;
  }

  String _collectionForMode(LeaderboardMode mode) {
    switch (mode) {
      case LeaderboardMode.singlePlayer:
        return 'leaderboard_single_player';
      case LeaderboardMode.online:
        return 'leaderboard_online';
      case LeaderboardMode.tournamentVsAi:
        return 'leaderboard_tournament_ai';
      case LeaderboardMode.tournamentOnline:
        return 'leaderboard_tournament_online';
      case LeaderboardMode.ranked:
        return 'ranked_stats';
      case LeaderboardMode.bustOffline:
        return 'leaderboard_bust_offline';
      case LeaderboardMode.bustOnline:
        return 'leaderboard_bust_online';
    }
  }

  Future<List<_ModeEntry>> _fetchMode(LeaderboardMode mode) async {
    final collectionName = _collectionForMode(mode);
    final n = _playerCountFilter;

    // When a bracket filter is active, order by the bracket-specific wins
    // field so the ranking is correct for that player count.
    // This requires a Firestore composite index on (wins_N DESC) for each N
    // in each filterable collection — Firestore will log a link to create it
    // on first use if the index is missing.
    final orderField = n != null ? 'wins_$n' : 'wins';

    // Local cache only holds global totals — used as offline fallback.
    final localEntries =
        await LocalLeaderboardStore.instance.loadEntries(collectionName);

    try {
      final snap = await FirebaseFirestore.instance
          .collection(collectionName)
          .orderBy(orderField, descending: true)
          .limit(50)
          .get();

      var remoteEntries =
          snap.docs.map((d) => _ModeEntry.fromDoc(d, playerCount: n)).toList();

      // Drop entries with zero bracket activity so players who have never
      // played an N-player game don't appear in the bracket-filtered view.
      if (n != null) {
        remoteEntries =
            remoteEntries.where((e) => e.gamesPlayed > 0).toList();
      }

      if (remoteEntries.isEmpty) {
        // Fall back to local cache for global view; bracket view shows empty.
        if (n != null) return [];
        return localEntries
            .map((e) => _ModeEntry(
                  uid: e.uid,
                  displayName: e.displayName,
                  wins: e.wins,
                  losses: e.losses,
                  gamesPlayed: e.gamesPlayed,
                  rating: null,
                ))
            .toList(growable: false);
      }

      final mergedByUid = <String, _ModeEntry>{
        for (final e in remoteEntries) e.uid: e,
      };

      // Prefer local entry values for the current player since Firestore
      // propagation can lag behind match end. Only merge when showing global
      // totals (local cache doesn't track per-bracket stats).
      if (n == null) {
        final currentUid = FirebaseAuth.instance.currentUser?.uid;
        for (final e in localEntries) {
          if (currentUid != null && e.uid == currentUid) {
            mergedByUid[e.uid] = _ModeEntry(
              uid: e.uid,
              displayName: e.displayName,
              wins: e.wins,
              losses: e.losses,
              gamesPlayed: e.gamesPlayed,
              rating: null,
            );
          }
        }
      }

      final merged = mergedByUid.values.toList(growable: false);
      // Firestore already ordered by the correct field; re-sort client-side
      // only for the global view where local-cache merging may have changed
      // the current player's position.
      merged.sort((a, b) => b.wins.compareTo(a.wins));
      return merged;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Mode leaderboard fetch error for $collectionName: $e');
      }
      if (n != null) return [];
      return localEntries
          .map((e) => _ModeEntry(
                uid: e.uid,
                displayName: e.displayName,
                wins: e.wins,
                losses: e.losses,
                gamesPlayed: e.gamesPlayed,
                rating: null,
              ))
          .toList(growable: false);
    }
  }

  _ModeEntry? _findLocalModeEntry(List<_ModeEntry> entries) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return entries.firstWhereOrNull((e) => e.uid == uid);
  }

  int _localModeRank(List<_ModeEntry> entries) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return -1;
    final idx = entries.indexWhere((e) => e.uid == uid);
    return idx == -1 ? -1 : idx + 1;
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider).theme;
    return Scaffold(
      backgroundColor: theme.backgroundDeep,
      appBar: AppBar(
        backgroundColor: theme.backgroundMid,
        elevation: 0,
        title: Text(
          '${_selectedMode.label} Leaderboard',
          style: GoogleFonts.cinzel(
            color: theme.accentPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 17,
            letterSpacing: 1.5,
          ),
        ),
        iconTheme: IconThemeData(color: theme.accentPrimary),
      ),
      body: Column(
        children: [
          // ── Mode chips ───────────────────────────────────────────────────
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: LeaderboardMode.values.map((mode) {
                final isSelected = _selectedMode == mode;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    selected: isSelected,
                    backgroundColor: theme.surfacePanel,
                    selectedColor: theme.accentPrimary,
                    checkmarkColor: theme.backgroundDeep,
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          mode.icon,
                          size: 15,
                          color: isSelected
                              ? theme.backgroundDeep
                              : theme.accentPrimary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          mode.label,
                          style: TextStyle(
                            color: isSelected
                                ? theme.backgroundDeep
                                : theme.textSecondary.withValues(alpha: 0.9),
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                    onSelected: (_) => setState(() {
                      _selectedMode = mode;
                      // Reset bracket filter when switching modes.
                      _playerCountFilter = null;
                    }),
                  ),
                );
              }).toList(),
            ),
          ),

          // ── Player-count filter (only for filterable modes) ───────────────
          if (_filterableModes.contains(_selectedMode))
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Row(
                children: [
                  _CountChip(
                    label: 'All',
                    selected: _playerCountFilter == null,
                    theme: theme,
                    onTap: () => setState(() => _playerCountFilter = null),
                  ),
                  for (final n in [2, 3, 4, 5, 6, 7])
                    _CountChip(
                      label: '$n players',
                      selected: _playerCountFilter == n,
                      theme: theme,
                      onTap: () => setState(() => _playerCountFilter = n),
                    ),
                ],
              ),
            ),

          // ── Body ─────────────────────────────────────────────────────────
          Expanded(
            child: _selectedMode == LeaderboardMode.ranked
                ? _RankedLeaderboard(
                    fetchRanked: _fetchRanked,
                    findLocalEntry: _findLocalEntry,
                    localRank: _localRank,
                    theme: theme,
                    // Rebuild when filter changes.
                    filterKey: _playerCountFilter,
                  )
                : _ModeLeaderboard(
                    mode: _selectedMode,
                    fetchEntries: () => _fetchMode(_selectedMode),
                    findLocalEntry: _findLocalModeEntry,
                    localRank: _localModeRank,
                    theme: theme,
                    filterKey: _playerCountFilter,
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Small bracket-filter chip ─────────────────────────────────────────────────

class _CountChip extends StatelessWidget {
  const _CountChip({
    required this.label,
    required this.selected,
    required this.theme,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final AppThemeData theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: selected
                ? theme.accentPrimary.withValues(alpha: 0.18)
                : theme.surfacePanel,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? theme.accentPrimary
                  : theme.textSecondary.withValues(alpha: 0.25),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.inter(
              color: selected
                  ? theme.accentPrimary
                  : theme.textSecondary.withValues(alpha: 0.7),
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Ranked leaderboard ────────────────────────────────────────────────────────

class _RankedLeaderboard extends StatefulWidget {
  const _RankedLeaderboard({
    required this.fetchRanked,
    required this.findLocalEntry,
    required this.localRank,
    required this.theme,
    this.filterKey,
  });

  final Future<List<_RankedEntry>> Function() fetchRanked;
  final _RankedEntry? Function(List<_RankedEntry>) findLocalEntry;
  final int Function(List<_RankedEntry>) localRank;
  final AppThemeData theme;
  /// When this changes, the list is re-fetched (parent passes playerCountFilter).
  final int? filterKey;

  @override
  State<_RankedLeaderboard> createState() => _RankedLeaderboardState();
}

class _RankedLeaderboardState extends State<_RankedLeaderboard> {
  late Future<List<_RankedEntry>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.fetchRanked();
  }

  @override
  void didUpdateWidget(covariant _RankedLeaderboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filterKey != widget.filterKey) {
      _future = widget.fetchRanked();
    }
  }

  Future<void> _refresh() async {
    setState(() => _future = widget.fetchRanked());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_RankedEntry>>(
      future: _future,
      builder: (context, snap) {
        final theme = widget.theme;
        if (snap.connectionState == ConnectionState.waiting) {
          return Center(
            child: Consumer(
              builder: (context, ref, _) {
                return SizedBox(
                  width: 220,
                  height: 180,
                  child: ThemedShimmer(
                    width: 220,
                    height: 180,
                    borderRadius: 16,
                  ),
                );
              },
            ),
          );
        }

        if (snap.hasError || !snap.hasData) {
          if (kDebugMode) {
            debugPrint('Leaderboard fetch error: ${snap.error}');
          }
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_off, color: theme.textSecondary.withValues(alpha: 0.6), size: 48),
                const SizedBox(height: 12),
                Text(
                  'Failed to load rankings.',
                  style: GoogleFonts.inter(color: theme.textSecondary.withValues(alpha: 0.6)),
                ),
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: _refresh,
                  icon: Icon(Icons.refresh, color: theme.accentPrimary),
                  label: Text('Retry',
                      style: GoogleFonts.inter(color: theme.accentPrimary)),
                ),
              ],
            ),
          );
        }

        final entries = snap.data!;
        if (entries.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🏆', style: TextStyle(fontSize: 48)),
                const SizedBox(height: 12),
                Text(
                  'No ranked games yet.\nBe the first to compete!',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    color: theme.textSecondary.withValues(alpha: 0.8),
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          );
        }

        final localEntry = widget.findLocalEntry(entries);
        final rank = widget.localRank(entries);

        return RefreshIndicator(
          onRefresh: _refresh,
          color: theme.accentPrimary,
          backgroundColor: theme.surfacePanel,
          child: CustomScrollView(
            slivers: [
              // "Your Rank" banner
              SliverToBoxAdapter(
                child: _YourRankBanner(
                  entry: localEntry,
                  rank: rank,
                  theme: theme,
                ),
              ),

              // Top-3 podium
              if (entries.length >= 3)
                SliverToBoxAdapter(
                  child: _Podium(top3: entries.take(3).toList(), theme: theme),
                ),

              // Full list
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) => _RankedTile(
                    index: i,
                    entry: entries[i],
                    isLocal: entries[i].uid ==
                        FirebaseAuth.instance.currentUser?.uid,
                    theme: theme,
                  ),
                  childCount: entries.length,
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        );
      },
    );
  }
}

// ── Your Rank Banner ──────────────────────────────────────────────────────────

class _YourRankBanner extends StatelessWidget {
  const _YourRankBanner({required this.entry, required this.rank, required this.theme});

  final _RankedEntry? entry;
  final int rank;
  final AppThemeData theme;

  @override
  Widget build(BuildContext context) {
    final hasData = entry != null && rank > 0;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.surfacePanel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.accentPrimary.withValues(alpha: 0.4),
          width: 1.5,
        ),
      ),
      child: hasData
          ? Row(
              children: [
                const Text('🏅', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your Rank: #$rank',
                        style: GoogleFonts.outfit(
                          color: theme.accentPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'W ${entry!.wins}  ·  L ${entry!.losses}  ·  '
                        '${entry!.gamesPlayed} games',
                        style: GoogleFonts.inter(
                          color: theme.textSecondary.withValues(alpha: 0.8),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${entry!.rating}',
                      style: GoogleFonts.outfit(
                        color: theme.accentPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'MMR',
                      style: GoogleFonts.inter(
                        color: theme.textSecondary.withValues(alpha: 0.6),
                        fontSize: 10,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ],
            )
          : Text(
              'Play a ranked game to appear on the leaderboard.',
              style: GoogleFonts.inter(color: theme.textSecondary.withValues(alpha: 0.6), fontSize: 13),
            ),
    );
  }
}

// ── Podium ────────────────────────────────────────────────────────────────────

class _Podium extends StatelessWidget {
  const _Podium({required this.top3, required this.theme});

  final List<_RankedEntry> top3;
  final AppThemeData theme;

  @override
  Widget build(BuildContext context) {
    if (top3.length < 3) {
      return const SizedBox.shrink();
    }
    const podiumColors = [
      Color(0xFFFFD700), // gold
      Color(0xFFB0BEC5), // silver
      Color(0xFFBF8970), // bronze
    ];
    const podiumLabels = ['1st', '2nd', '3rd'];
    const podiumEmojis = ['🥇', '🥈', '🥉'];

    // Reorder to podium layout: 2nd | 1st | 3rd
    final ordered = [top3[1], top3[0], top3[2]];
    final orderedColors = [podiumColors[1], podiumColors[0], podiumColors[2]];
    final orderedLabels = [podiumLabels[1], podiumLabels[0], podiumLabels[2]];
    final orderedEmojis = [podiumEmojis[1], podiumEmojis[0], podiumEmojis[2]];
    final heights = [80.0, 110.0, 60.0];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(3, (i) {
          final e = ordered[i];
          return Expanded(
            child: Column(
              children: [
                Text(orderedEmojis[i],
                    style: const TextStyle(fontSize: 24)),
                const SizedBox(height: 4),
                Text(
                  e.displayName,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: orderedColors[i],
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                Text(
                  '${e.rating} MMR',
                  style: GoogleFonts.inter(
                    color: theme.textSecondary.withValues(alpha: 0.8),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  height: heights[i],
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: orderedColors[i].withValues(alpha: 0.15),
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(8)),
                    border: Border.all(
                      color: orderedColors[i].withValues(alpha: 0.5),
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      orderedLabels[i],
                      style: TextStyle(
                        color: orderedColors[i],
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

// ── Ranked list tile ──────────────────────────────────────────────────────────

class _RankedTile extends StatelessWidget {
  const _RankedTile({
    required this.index,
    required this.entry,
    required this.isLocal,
    required this.theme,
  });

  final int index;
  final _RankedEntry entry;
  final bool isLocal;
  final AppThemeData theme;

  @override
  Widget build(BuildContext context) {
    final rank = index + 1;
    final isTop3 = rank <= 3;
    const medalColors = [
      Color(0xFFFFD700),
      Color(0xFFB0BEC5),
      Color(0xFFBF8970),
    ];
    final rankColor = isTop3 ? medalColors[rank - 1] : theme.textSecondary.withValues(alpha: 0.6);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      decoration: BoxDecoration(
        color: isLocal
            ? theme.accentPrimary.withValues(alpha: 0.08)
            : theme.backgroundMid,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isLocal
              ? theme.accentPrimary.withValues(alpha: 0.4)
              : theme.textPrimary.withValues(alpha: 0.05),
          width: isLocal ? 1.5 : 1,
        ),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: rankColor.withValues(alpha: 0.15),
          child: Text(
            '#$rank',
            style: TextStyle(
              color: rankColor,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                entry.displayName,
                style: GoogleFonts.outfit(
                  color: isLocal ? theme.accentPrimary : theme.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isLocal)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.accentPrimary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'YOU',
                  style: GoogleFonts.inter(
                    color: theme.accentPrimary,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Text(
          'W ${entry.wins}  ·  L ${entry.losses}  ·  ${entry.gamesPlayed} games',
          style: GoogleFonts.inter(color: theme.textSecondary.withValues(alpha: 0.6), fontSize: 11),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${entry.rating}',
              style: GoogleFonts.outfit(
                color: theme.accentPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              'MMR',
              style: GoogleFonts.inter(color: theme.textSecondary.withValues(alpha: 0.6), fontSize: 9),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Mode leaderboard (non-ranked modes) ───────────────────────────────────────

class _ModeLeaderboard extends StatefulWidget {
  const _ModeLeaderboard({
    required this.mode,
    required this.fetchEntries,
    required this.findLocalEntry,
    required this.localRank,
    required this.theme,
    this.filterKey,
  });

  final LeaderboardMode mode;
  final Future<List<_ModeEntry>> Function() fetchEntries;
  final _ModeEntry? Function(List<_ModeEntry>) findLocalEntry;
  final int Function(List<_ModeEntry>) localRank;
  final AppThemeData theme;
  /// When this changes, the list is re-fetched.
  final int? filterKey;

  @override
  State<_ModeLeaderboard> createState() => _ModeLeaderboardState();
}

class _ModeLeaderboardState extends State<_ModeLeaderboard> {
  late Future<List<_ModeEntry>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.fetchEntries();
  }

  @override
  void didUpdateWidget(covariant _ModeLeaderboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode ||
        oldWidget.filterKey != widget.filterKey) {
      _future = widget.fetchEntries();
    }
  }

  Future<void> _refresh() async {
    setState(() => _future = widget.fetchEntries());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_ModeEntry>>(
      future: _future,
      builder: (context, snap) {
        final theme = widget.theme;

        if (snap.connectionState == ConnectionState.waiting) {
          return Center(
            child: Consumer(
              builder: (context, ref, _) {
                return SizedBox(
                  width: 220,
                  height: 180,
                  child: ThemedShimmer(
                    width: 220,
                    height: 180,
                    borderRadius: 16,
                  ),
                );
              },
            ),
          );
        }

        if (snap.hasError || !snap.hasData) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_off,
                    color: theme.textSecondary.withValues(alpha: 0.6), size: 48),
                const SizedBox(height: 12),
                Text(
                  'Failed to load ${widget.mode.label} leaderboard.',
                  style:
                      GoogleFonts.inter(color: theme.textSecondary.withValues(alpha: 0.6)),
                ),
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: _refresh,
                  icon: Icon(Icons.refresh, color: theme.accentPrimary),
                  label: Text(
                    'Retry',
                    style: GoogleFonts.inter(color: theme.accentPrimary),
                  ),
                ),
              ],
            ),
          );
        }

        final entries = snap.data!;

        if (entries.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🏅', style: TextStyle(fontSize: 48)),
                const SizedBox(height: 12),
                Text(
                  'Leaderboard coming soon for this mode.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    color: theme.textSecondary.withValues(alpha: 0.8),
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          );
        }

        final localEntry = widget.findLocalEntry(entries);
        final rank = widget.localRank(entries);

        return RefreshIndicator(
          onRefresh: _refresh,
          color: theme.accentPrimary,
          backgroundColor: theme.surfacePanel,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: _ModeYourRankBanner(
                  entry: localEntry,
                  rank: rank,
                  mode: widget.mode,
                  theme: theme,
                ),
              ),
              if (entries.length >= 3)
                SliverToBoxAdapter(
                  child: _ModePodium(top3: entries.take(3).toList(), theme: theme),
                ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) => _ModeTile(
                    index: i,
                    entry: entries[i],
                    isLocal: entries[i].uid == FirebaseAuth.instance.currentUser?.uid,
                    theme: theme,
                  ),
                  childCount: entries.length,
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        );
      },
    );
  }
}

class _ModeYourRankBanner extends StatelessWidget {
  const _ModeYourRankBanner({
    required this.entry,
    required this.rank,
    required this.mode,
    required this.theme,
  });

  final _ModeEntry? entry;
  final int rank;
  final LeaderboardMode mode;
  final AppThemeData theme;

  @override
  Widget build(BuildContext context) {
    final hasData = entry != null && rank > 0;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.surfacePanel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.accentPrimary.withValues(alpha: 0.4),
          width: 1.5,
        ),
      ),
      child: hasData
          ? Row(
              children: [
                const Text('🏅', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your Rank: #$rank',
                        style: GoogleFonts.outfit(
                          color: theme.accentPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'W ${entry!.wins}  ·  L ${entry!.losses}  ·  ${entry!.gamesPlayed} games',
                        style: GoogleFonts.inter(
                          color: theme.textSecondary.withValues(alpha: 0.8),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            )
          : Text(
              'Play ${mode.label} games to appear on the leaderboard.',
              style: GoogleFonts.inter(
                color: theme.textSecondary.withValues(alpha: 0.6),
                fontSize: 13,
              ),
            ),
    );
  }
}

class _ModePodium extends StatelessWidget {
  const _ModePodium({required this.top3, required this.theme});

  final List<_ModeEntry> top3;
  final AppThemeData theme;

  @override
  Widget build(BuildContext context) {
    if (top3.length < 3) {
      return const SizedBox.shrink();
    }
    const podiumColors = [
      Color(0xFFFFD700), // gold
      Color(0xFFB0BEC5), // silver
      Color(0xFFBF8970), // bronze
    ];
    const podiumLabels = ['1st', '2nd', '3rd'];
    const podiumEmojis = ['🥇', '🥈', '🥉'];

    final ordered = [top3[1], top3[0], top3[2]];
    final orderedColors = [podiumColors[1], podiumColors[0], podiumColors[2]];
    final orderedLabels = [podiumLabels[1], podiumLabels[0], podiumLabels[2]];
    final orderedEmojis = [podiumEmojis[1], podiumEmojis[0], podiumEmojis[2]];
    final heights = [80.0, 110.0, 60.0];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(3, (i) {
          final e = ordered[i];
          return Expanded(
            child: Column(
              children: [
                Text(orderedEmojis[i], style: const TextStyle(fontSize: 24)),
                const SizedBox(height: 4),
                Text(
                  e.displayName,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: orderedColors[i],
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                Text(
                  'W ${e.wins}',
                  style: GoogleFonts.inter(
                    color: theme.textSecondary.withValues(alpha: 0.8),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  height: heights[i],
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: orderedColors[i].withValues(alpha: 0.15),
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(8)),
                    border: Border.all(
                      color: orderedColors[i].withValues(alpha: 0.5),
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      orderedLabels[i],
                      style: TextStyle(
                        color: orderedColors[i],
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.index,
    required this.entry,
    required this.isLocal,
    required this.theme,
  });

  final int index;
  final _ModeEntry entry;
  final bool isLocal;
  final AppThemeData theme;

  @override
  Widget build(BuildContext context) {
    final rank = index + 1;
    final isTop3 = rank <= 3;
    const medalColors = [
      Color(0xFFFFD700),
      Color(0xFFB0BEC5),
      Color(0xFFBF8970),
    ];
    final rankColor =
        isTop3 ? medalColors[rank - 1] : theme.textSecondary.withValues(alpha: 0.6);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      decoration: BoxDecoration(
        color: isLocal
            ? theme.accentPrimary.withValues(alpha: 0.08)
            : theme.backgroundMid,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isLocal
              ? theme.accentPrimary.withValues(alpha: 0.4)
              : theme.textPrimary.withValues(alpha: 0.05),
          width: isLocal ? 1.5 : 1,
        ),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: rankColor.withValues(alpha: 0.15),
          child: Text(
            '#$rank',
            style: TextStyle(
              color: rankColor,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                entry.displayName,
                style: GoogleFonts.outfit(
                  color: isLocal ? theme.accentPrimary : theme.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isLocal)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.accentPrimary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'YOU',
                  style: GoogleFonts.inter(
                    color: theme.accentPrimary,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Text(
          'W ${entry.wins}  ·  L ${entry.losses}  ·  ${entry.gamesPlayed} games',
          style: GoogleFonts.inter(
              color: theme.textSecondary.withValues(alpha: 0.6), fontSize: 11),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${entry.wins}',
              style: GoogleFonts.outfit(
                color: theme.accentPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              'Wins',
              style: GoogleFonts.inter(
                color: theme.textSecondary.withValues(alpha: 0.6),
                fontSize: 9,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
