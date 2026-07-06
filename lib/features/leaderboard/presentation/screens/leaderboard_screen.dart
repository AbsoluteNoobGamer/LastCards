import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:last_cards/shared/leaderboard/display_name_leaderboard_rules.dart';

import '../../data/leaderboard_collections.dart';
import '../../data/local_leaderboard_store.dart';
import '../../data/local_combo_leaderboard_store.dart';
import '../../data/combo_leaderboard_writer.dart';

import '../../../../core/providers/theme_provider.dart';
import '../../../../core/services/analytics_service.dart';
import '../../../../core/widgets/themed_shimmer.dart';
import '../../../../core/theme/app_theme_data.dart';
import '../../../../core/models/card_model.dart';
import '../../../../core/models/offline_game_state.dart';
import '../../../gameplay/presentation/widgets/card_widget.dart';
import '../../../gameplay/presentation/widgets/multi_card_play_celebration.dart'
    show kMultiPlayCelebrationMinCards;

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

enum _LeaderboardTab { ranked, online, bust, other, combos }

const _otherLeaderboardModes = [
  LeaderboardMode.singlePlayer,
  LeaderboardMode.tournamentVsAi,
  LeaderboardMode.bustOffline,
];

class _TierInfo {
  const _TierInfo(this.label, this.color);

  final String label;
  final Color color;
}

_TierInfo _rankedTier(int mmr) {
  if (mmr >= 1600) return const _TierInfo('Master', Color(0xFFFF5722));
  if (mmr >= 1400) return const _TierInfo('Diamond', Color(0xFF7C4DFF));
  if (mmr >= 1200) return const _TierInfo('Platinum', Color(0xFF00E5FF));
  if (mmr >= 1100) return const _TierInfo('Gold', Color(0xFFFFD700));
  if (mmr >= 1000) return const _TierInfo('Silver', Color(0xFFB0BEC5));
  return const _TierInfo('Bronze', Color(0xFFBF8970));
}

_TierInfo _winsTier(int wins) {
  if (wins >= 50) return const _TierInfo('Legend', Color(0xFFFF5722));
  if (wins >= 30) return const _TierInfo('Elite', Color(0xFF00E5FF));
  if (wins >= 15) return const _TierInfo('Veteran', Color(0xFFFFD700));
  if (wins >= 5) return const _TierInfo('Regular', Color(0xFFB0BEC5));
  return const _TierInfo('Rookie', Color(0xFF8D6E63));
}

String _initialsFromName(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty || parts.first.isEmpty) return '?';
  if (parts.length == 1) {
    return parts.first.substring(0, 1).toUpperCase();
  }
  return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
}

int _winRatePercent(int wins, int losses) {
  final total = wins + losses;
  if (total == 0) return 0;
  return ((wins / total) * 100).round();
}

// ── Screen ────────────────────────────────────────────────────────────────────

class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen> {
  LeaderboardMode _selectedMode = LeaderboardMode.ranked;
  _LeaderboardTab _selectedTab = _LeaderboardTab.ranked;
  bool _rankedHardcore = false;

  /// null = "All" (global totals); 2–7 = bracket-specific filter.
  int? _playerCountFilter;

  /// Which modes support the player-count filter (server-written, multi-bracket).
  static const _filterableModes = {
    LeaderboardMode.ranked,
    LeaderboardMode.rankedHardcore,
    LeaderboardMode.online,
    LeaderboardMode.bustOnline,
  };

  /// Every [LeaderboardMode] (ranked boards use [_RankedLeaderboard]; others [_ModeLeaderboard]).
  static final List<LeaderboardMode> _screenModes =
      List<LeaderboardMode>.unmodifiable(LeaderboardMode.values);

  @override
  void initState() {
    super.initState();
    AnalyticsService.instance.logLeaderboardViewed(mode: _selectedMode.label);
  }

  void _selectTab(_LeaderboardTab tab) {
    final previousMode = _selectedMode;
    setState(() {
      _selectedTab = tab;
      _playerCountFilter = null;
      switch (tab) {
        case _LeaderboardTab.ranked:
          _selectedMode =
              _rankedHardcore ? LeaderboardMode.rankedHardcore : LeaderboardMode.ranked;
        case _LeaderboardTab.online:
          _selectedMode = LeaderboardMode.online;
        case _LeaderboardTab.bust:
          _selectedMode = LeaderboardMode.bustOnline;
        case _LeaderboardTab.other:
          if (!_otherLeaderboardModes.contains(_selectedMode)) {
            _selectedMode = _otherLeaderboardModes.first;
          }
        case _LeaderboardTab.combos:
          // Cross-mode board — doesn't use _selectedMode at all.
          break;
      }
    });
    if (_selectedMode != previousMode) {
      AnalyticsService.instance.logLeaderboardViewed(mode: _selectedMode.label);
    }
  }

  void _selectRankedVariant({required bool hardcore}) {
    final previousMode = _selectedMode;
    setState(() {
      _rankedHardcore = hardcore;
      _selectedMode =
          hardcore ? LeaderboardMode.rankedHardcore : LeaderboardMode.ranked;
      _playerCountFilter = null;
    });
    if (_selectedMode != previousMode) {
      AnalyticsService.instance.logLeaderboardViewed(mode: _selectedMode.label);
    }
  }

  // ── Ranked Firestore data ─────────────────────────────────────────────────

  Future<List<_RankedEntry>> _fetchRankedFrom(String collection) async {
    final n = _playerCountFilter;
    final snap = await FirebaseFirestore.instance
        .collection(collection)
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
      return filterLeaderboardEntriesForDisplay(
        entries.where((e) => e.gamesPlayed > 0).toList(),
        (e) => e.displayName,
      );
    }
    return filterLeaderboardEntriesForDisplay(entries, (e) => e.displayName);
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

  Future<List<_ModeEntry>> _fetchMode(LeaderboardMode mode) async {
    final collectionName = collectionForMode(mode);
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
        remoteEntries = remoteEntries.where((e) => e.gamesPlayed > 0).toList();
      }

      if (remoteEntries.isEmpty) {
        // Fall back to local cache for global view; bracket view shows empty.
        if (n != null) return [];
        final local = localEntries
            .map((e) => _ModeEntry(
                  uid: e.uid,
                  displayName: e.displayName,
                  wins: e.wins,
                  losses: e.losses,
                  gamesPlayed: e.gamesPlayed,
                  rating: null,
                ))
            .toList(growable: false);
        return filterLeaderboardEntriesForDisplay(local, (e) => e.displayName);
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
      return filterLeaderboardEntriesForDisplay(merged, (e) => e.displayName);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Mode leaderboard fetch error for $collectionName: $e');
      }
      if (n != null) return [];
      final local = localEntries
          .map((e) => _ModeEntry(
                uid: e.uid,
                displayName: e.displayName,
                wins: e.wins,
                losses: e.losses,
                gamesPlayed: e.gamesPlayed,
                rating: null,
              ))
          .toList(growable: false);
      return filterLeaderboardEntriesForDisplay(local, (e) => e.displayName);
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

  // ── Combo (longest-combo) leaderboard — cross-mode, single record per
  // player, merged from Firestore + the local device store the same way
  // [_fetchMode] merges the other boards. ─────────────────────────────────

  /// The "local" identity for combos: signed-in uid, or the shared guest id
  /// used offline — matches [ComboLeaderboardWriter]'s own uid resolution so
  /// guests still see their own record highlighted.
  String get _localComboUid =>
      FirebaseAuth.instance.currentUser?.uid ?? OfflineGameState.localId;

  Future<List<ComboLeaderboardEntry>> _fetchCombos() async {
    final localEntries = await LocalComboLeaderboardStore.instance.loadEntries();

    try {
      final snap = await FirebaseFirestore.instance
          .collection(comboLeaderboardCollection)
          .orderBy('comboCount', descending: true)
          .limit(50)
          .get();

      final remoteEntries = snap.docs.map((d) {
        final data = d.data();
        final cardsJson =
            (data['cards'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
        return ComboLeaderboardEntry(
          uid: d.id,
          displayName: data['displayName'] as String? ?? 'Player',
          comboCount: (data['comboCount'] as num?)?.toInt() ?? 0,
          cards: cardsJson.map(CardModel.fromJson).toList(),
          achievedAtMillis: 0,
        );
      }).toList();

      final mergedByUid = <String, ComboLeaderboardEntry>{
        for (final e in remoteEntries) e.uid: e,
      };

      // Prefer the local record for the current player/guest — Firestore may
      // lag, and guests have no Firestore doc at all.
      final localUid = _localComboUid;
      for (final e in localEntries) {
        if (e.uid == localUid) {
          final remote = mergedByUid[e.uid];
          if (remote == null || e.comboCount > remote.comboCount) {
            mergedByUid[e.uid] = e;
          }
        }
      }

      final merged = mergedByUid.values.toList(growable: false);
      merged.sort((a, b) => b.comboCount.compareTo(a.comboCount));
      return filterLeaderboardEntriesForDisplay(merged, (e) => e.displayName);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Combo leaderboard fetch error: $e');
      }
      final local = List.of(localEntries)
        ..sort((a, b) => b.comboCount.compareTo(a.comboCount));
      return filterLeaderboardEntriesForDisplay(local, (e) => e.displayName);
    }
  }

  ComboLeaderboardEntry? _findLocalComboEntry(List<ComboLeaderboardEntry> entries) {
    return entries.firstWhereOrNull((e) => e.uid == _localComboUid);
  }

  int _localComboRank(List<ComboLeaderboardEntry> entries) {
    final idx = entries.indexWhere((e) => e.uid == _localComboUid);
    return idx == -1 ? -1 : idx + 1;
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider).theme;
    if (!_screenModes.contains(_selectedMode)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _selectedMode = LeaderboardMode.ranked;
          _selectedTab = _LeaderboardTab.ranked;
          _rankedHardcore = false;
          _playerCountFilter = null;
        });
        AnalyticsService.instance.logLeaderboardViewed(
          mode: LeaderboardMode.ranked.label,
        );
      });
    }
    return Scaffold(
      backgroundColor: theme.backgroundDeep,
      appBar: AppBar(
        backgroundColor: theme.backgroundMid,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Leaderboard',
              style: GoogleFonts.cinzel(
                color: theme.accentPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 16,
                letterSpacing: 1.2,
              ),
            ),
            Text(
              _selectedMode.label,
              style: GoogleFonts.inter(
                color: theme.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
        iconTheme: IconThemeData(color: theme.accentPrimary),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: _LeaderboardTabBar(
              selectedTab: _selectedTab,
              theme: theme,
              onTabSelected: _selectTab,
            ),
          ),
          if (_selectedTab == _LeaderboardTab.ranked)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: _RankedVariantToggle(
                hardcore: _rankedHardcore,
                theme: theme,
                onStandard: () => _selectRankedVariant(hardcore: false),
                onHardcore: () => _selectRankedVariant(hardcore: true),
              ),
            ),
          if (_selectedTab == _LeaderboardTab.other)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: _otherLeaderboardModes.map((mode) {
                  final isSelected = _selectedMode == mode;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _SmallModeChip(
                      label: mode.label,
                      selected: isSelected,
                      theme: theme,
                      onTap: () {
                        setState(() {
                          _selectedMode = mode;
                          _playerCountFilter = null;
                        });
                        AnalyticsService.instance.logLeaderboardViewed(
                          mode: mode.label,
                        );
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
          if (_filterableModes.contains(_selectedMode))
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Row(
                children: [
                  Text(
                    'Players:',
                    style: GoogleFonts.inter(
                      color: theme.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
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
                              label: '$n',
                              selected: _playerCountFilter == n,
                              theme: theme,
                              onTap: () => setState(() => _playerCountFilter = n),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _selectedTab == _LeaderboardTab.combos
                ? _ComboLeaderboard(
                    fetchEntries: _fetchCombos,
                    findLocalEntry: _findLocalComboEntry,
                    localRank: _localComboRank,
                    theme: theme,
                  )
                : (_selectedMode == LeaderboardMode.ranked ||
                        _selectedMode == LeaderboardMode.rankedHardcore)
                    ? _RankedLeaderboard(
                        fetchRanked: () =>
                            _fetchRankedFrom(collectionForMode(_selectedMode)),
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

// ── Tab bar & filters ─────────────────────────────────────────────────────────

class _LeaderboardTabBar extends StatelessWidget {
  const _LeaderboardTabBar({
    required this.selectedTab,
    required this.theme,
    required this.onTabSelected,
  });

  final _LeaderboardTab selectedTab;
  final AppThemeData theme;
  final ValueChanged<_LeaderboardTab> onTabSelected;

  static const _tabs = [
    (_LeaderboardTab.ranked, 'Ranked'),
    (_LeaderboardTab.online, 'Online'),
    (_LeaderboardTab.bust, 'Bust'),
    (_LeaderboardTab.other, 'Offline'),
    (_LeaderboardTab.combos, 'Combos'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: theme.surfacePanel,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: _tabs.map((tab) {
          final isSelected = selectedTab == tab.$1;
          return Expanded(
            child: GestureDetector(
              onTap: () => onTabSelected(tab.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected ? theme.accentPrimary : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  tab.$2,
                  style: GoogleFonts.inter(
                    color: isSelected
                        ? theme.backgroundDeep
                        : theme.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _RankedVariantToggle extends StatelessWidget {
  const _RankedVariantToggle({
    required this.hardcore,
    required this.theme,
    required this.onStandard,
    required this.onHardcore,
  });

  final bool hardcore;
  final AppThemeData theme;
  final VoidCallback onStandard;
  final VoidCallback onHardcore;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _VariantPill(
          label: 'Standard',
          selected: !hardcore,
          theme: theme,
          onTap: onStandard,
        ),
        const SizedBox(width: 8),
        _VariantPill(
          label: 'Hardcore',
          selected: hardcore,
          theme: theme,
          onTap: onHardcore,
        ),
      ],
    );
  }
}

class _VariantPill extends StatelessWidget {
  const _VariantPill({
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
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? theme.accentPrimary.withValues(alpha: 0.18)
              : theme.surfacePanel,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? theme.accentPrimary
                : theme.textSecondary.withValues(alpha: 0.25),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            color: selected ? theme.accentPrimary : theme.textSecondary,
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _SmallModeChip extends StatelessWidget {
  const _SmallModeChip({
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
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? theme.accentPrimary.withValues(alpha: 0.18)
              : theme.surfacePanel,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? theme.accentPrimary
                : theme.textSecondary.withValues(alpha: 0.25),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            color: selected ? theme.accentPrimary : theme.textSecondary,
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

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
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? theme.accentPrimary.withValues(alpha: 0.18)
                : theme.surfacePanel,
            borderRadius: BorderRadius.circular(15),
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
              fontSize: 11,
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
                Icon(Icons.cloud_off,
                    color: theme.textSecondary.withValues(alpha: 0.6),
                    size: 48),
                const SizedBox(height: 12),
                Text(
                  'Failed to load rankings.',
                  style: GoogleFonts.inter(
                      color: theme.textSecondary.withValues(alpha: 0.6)),
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

// ── Tier badge ────────────────────────────────────────────────────────────────

class _TierBadge extends StatelessWidget {
  const _TierBadge({
    required this.label,
    required this.color,
    this.large = false,
  });

  final String label;
  final Color color;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: large ? 8 : 6,
        vertical: large ? 4 : 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text(
        label.toUpperCase(),
        style: GoogleFonts.inter(
          color: color,
          fontSize: large ? 11 : 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ── Your Rank Banner ──────────────────────────────────────────────────────────

class _YourRankBanner extends StatelessWidget {
  const _YourRankBanner(
      {required this.entry, required this.rank, required this.theme});

  final _RankedEntry? entry;
  final int rank;
  final AppThemeData theme;

  @override
  Widget build(BuildContext context) {
    final hasData = entry != null && rank > 0;
    final tier = hasData ? _rankedTier(entry!.rating) : null;
    final winRate = hasData
        ? _winRatePercent(entry!.wins, entry!.losses)
        : 0;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            theme.accentPrimary.withValues(alpha: 0.08),
            Colors.transparent,
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.accentPrimary.withValues(alpha: 0.4),
          width: 1.5,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Row(
          children: [
            Container(width: 3, color: theme.accentPrimary),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: hasData
                    ? Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      'Your Rank: #$rank',
                                      style: GoogleFonts.outfit(
                                        color: theme.accentPrimary,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    if (tier != null) ...[
                                      const SizedBox(width: 8),
                                      _TierBadge(
                                        label: tier.label,
                                        color: tier.color,
                                        large: true,
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'W ${entry!.wins}  ·  L ${entry!.losses}  ·  '
                                  '${entry!.gamesPlayed} games',
                                  style: GoogleFonts.inter(
                                    color: theme.textSecondary.withValues(alpha: 0.8),
                                    fontSize: 12,
                                  ),
                                ),
                                Text(
                                  'Win rate: $winRate%',
                                  style: GoogleFonts.inter(
                                    color: theme.textSecondary.withValues(alpha: 0.7),
                                    fontSize: 11,
                                  ),
                                ),
                                if (rank == 1)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      '👑 #1 on this leaderboard',
                                      style: GoogleFonts.inter(
                                        color: theme.accentPrimary,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  )
                                else if (rank <= 10)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      '🔥 Top 10',
                                      style: GoogleFonts.inter(
                                        color: theme.accentPrimary,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
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
                        style: GoogleFonts.inter(
                          color: theme.textSecondary.withValues(alpha: 0.6),
                          fontSize: 13,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Podium ────────────────────────────────────────────────────────────────────

class _PodiumSlotData {
  const _PodiumSlotData({
    required this.displayName,
    required this.statText,
  });

  final String displayName;
  final String statText;
}

class _PremiumPodium extends StatelessWidget {
  const _PremiumPodium({required this.slots, required this.theme});

  final List<_PodiumSlotData> slots;
  final AppThemeData theme;

  @override
  Widget build(BuildContext context) {
    const medalColors = [
      Color(0xFFFFD700),
      Color(0xFFB0BEC5),
      Color(0xFFBF8970),
    ];
    const gradientStops = [
      [Color(0xFFFFD700), Color(0xFFB8960C)],
      [Color(0xFFB0BEC5), Color(0xFF78909C)],
      [Color(0xFFBF8970), Color(0xFF795548)],
    ];
    const gradientAlphas = [
      [0.20, 0.08],
      [0.15, 0.06],
      [0.12, 0.05],
    ];
    const podiumLabels = ['1st', '2nd', '3rd'];
    const avatarSizes = [52.0, 44.0, 44.0];
    const heights = [115.0, 85.0, 65.0];

    final ordered = [slots[1], slots[0], slots[2]];
    final orderedMedals = [1, 0, 2];
    final orderedHeights = [heights[1], heights[0], heights[2]];

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
      decoration: BoxDecoration(
        color: theme.surfacePanel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.accentPrimary.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(3, (i) {
          final slot = ordered[i];
          final medalIdx = orderedMedals[i];
          final color = medalColors[medalIdx];
          final isFirst = medalIdx == 0;
          final avatarSize = avatarSizes[medalIdx];
          final initials = _initialsFromName(slot.displayName);

          return Expanded(
            child: Column(
              children: [
                if (isFirst)
                  Icon(
                    Icons.emoji_events_rounded,
                    color: color,
                    size: 20,
                  )
                else
                  const SizedBox(height: 20),
                const SizedBox(height: 6),
                Container(
                  width: avatarSize,
                  height: avatarSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withValues(alpha: 0.15),
                    border: Border.all(color: color, width: isFirst ? 2 : 1.5),
                    boxShadow: isFirst
                        ? [
                            BoxShadow(
                              color: color.withValues(alpha: 0.45),
                              blurRadius: 10,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    initials,
                    style: GoogleFonts.outfit(
                      color: color,
                      fontWeight: FontWeight.w800,
                      fontSize: isFirst ? 16 : 14,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  slot.displayName,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: GoogleFonts.outfit(
                    color: theme.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                Text(
                  slot.statText,
                  style: GoogleFonts.inter(
                    color: theme.textSecondary.withValues(alpha: 0.8),
                    fontSize: 10,
                  ),
                ),
                const SizedBox(height: 8),
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      height: orderedHeights[i],
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            gradientStops[medalIdx][0]
                                .withValues(alpha: gradientAlphas[medalIdx][0]),
                            gradientStops[medalIdx][1]
                                .withValues(alpha: gradientAlphas[medalIdx][1]),
                          ],
                        ),
                        borderRadius:
                            const BorderRadius.vertical(top: Radius.circular(8)),
                        border: Border.all(
                          color: color.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          podiumLabels[medalIdx],
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 0,
                      left: 4,
                      right: 4,
                      child: Container(
                        height: 2,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.55),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(8),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: color.withValues(alpha: 0.35),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

class _Podium extends StatelessWidget {
  const _Podium({required this.top3, required this.theme});

  final List<_RankedEntry> top3;
  final AppThemeData theme;

  @override
  Widget build(BuildContext context) {
    return _PremiumPodium(
      theme: theme,
      slots: top3
          .map(
            (e) => _PodiumSlotData(
              displayName: e.displayName,
              statText: '${e.rating} MMR',
            ),
          )
          .toList(),
    );
  }
}

// ── Shared tile helpers ───────────────────────────────────────────────────────

class _RankCircle extends StatelessWidget {
  const _RankCircle({required this.rank, required this.theme});

  final int rank;
  final AppThemeData theme;

  @override
  Widget build(BuildContext context) {
    const medalColors = [
      Color(0xFFFFD700),
      Color(0xFFB0BEC5),
      Color(0xFFBF8970),
    ];
    final isTop3 = rank <= 3;
    final color = isTop3
        ? medalColors[rank - 1]
        : theme.textSecondary;

    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isTop3
            ? color.withValues(alpha: 0.15)
            : theme.surfacePanel,
      ),
      alignment: Alignment.center,
      child: Text(
        '$rank',
        style: GoogleFonts.outfit(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _YouBadge extends StatelessWidget {
  const _YouBadge({required this.theme});

  final AppThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
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
    );
  }
}

class _StatPillsRow extends StatelessWidget {
  const _StatPillsRow({
    required this.wins,
    required this.losses,
    required this.theme,
  });

  final int wins;
  final int losses;
  final AppThemeData theme;

  @override
  Widget build(BuildContext context) {
    final rate = _winRatePercent(wins, losses);
    final rateColor =
        rate >= 50 ? const Color(0xFF4CAF50) : const Color(0xFFE53935);

    Widget pill(String text, {Color? textColor}) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: theme.surfacePanel,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          text,
          style: GoogleFonts.inter(
            color: textColor ?? theme.textSecondary,
            fontSize: 10,
          ),
        ),
      );
    }

    return Row(
      children: [
        pill('W: $wins'),
        const SizedBox(width: 4),
        pill('L: $losses'),
        const SizedBox(width: 4),
        pill('$rate%', textColor: rateColor),
      ],
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
    final isTop3 = rank <= 3 && !isLocal;
    const medalColors = [
      Color(0xFFFFD700),
      Color(0xFFB0BEC5),
      Color(0xFFBF8970),
    ];
    final tier = _rankedTier(entry.rating);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isLocal
            ? theme.accentPrimary.withValues(alpha: 0.10)
            : isTop3
                ? medalColors[rank - 1].withValues(alpha: 0.06)
                : theme.backgroundMid,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isLocal
              ? theme.accentPrimary.withValues(alpha: 0.5)
              : theme.textPrimary.withValues(alpha: 0.06),
          width: isLocal ? 1.5 : 1,
        ),
        boxShadow: isLocal
            ? [
                BoxShadow(
                  color: theme.accentPrimary.withValues(alpha: 0.12),
                  blurRadius: 8,
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          _RankCircle(rank: rank, theme: theme),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
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
                    if (isLocal) ...[
                      const SizedBox(width: 6),
                      _YouBadge(theme: theme),
                    ],
                    const SizedBox(width: 6),
                    _TierBadge(label: tier.label, color: tier.color),
                  ],
                ),
                const SizedBox(height: 4),
                _StatPillsRow(
                  wins: entry.wins,
                  losses: entry.losses,
                  theme: theme,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
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
                tier.label,
                style: GoogleFonts.inter(
                  color: tier.color,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
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
                    color: theme.textSecondary.withValues(alpha: 0.6),
                    size: 48),
                const SizedBox(height: 12),
                Text(
                  'Failed to load ${widget.mode.label} leaderboard.',
                  style: GoogleFonts.inter(
                      color: theme.textSecondary.withValues(alpha: 0.6)),
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
                const Text('🏆', style: TextStyle(fontSize: 48)),
                const SizedBox(height: 12),
                Text(
                  'No ${widget.mode.label} games recorded yet.\nBe the first to compete!',
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
                  child:
                      _ModePodium(top3: entries.take(3).toList(), theme: theme),
                ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) => _ModeTile(
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
    final tier = hasData ? _winsTier(entry!.wins) : null;
    final winRate = hasData
        ? _winRatePercent(entry!.wins, entry!.losses)
        : 0;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            theme.accentPrimary.withValues(alpha: 0.08),
            Colors.transparent,
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.accentPrimary.withValues(alpha: 0.4),
          width: 1.5,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Row(
          children: [
            Container(width: 3, color: theme.accentPrimary),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: hasData
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Your Rank: #$rank',
                                style: GoogleFonts.outfit(
                                  color: theme.accentPrimary,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (tier != null) ...[
                                const SizedBox(width: 8),
                                _TierBadge(
                                  label: tier.label,
                                  color: tier.color,
                                  large: true,
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'W ${entry!.wins}  ·  L ${entry!.losses}  ·  '
                            '${entry!.gamesPlayed} games',
                            style: GoogleFonts.inter(
                              color: theme.textSecondary.withValues(alpha: 0.8),
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            'Win rate: $winRate%',
                            style: GoogleFonts.inter(
                              color: theme.textSecondary.withValues(alpha: 0.7),
                              fontSize: 11,
                            ),
                          ),
                          if (rank == 1)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '👑 #1 on this leaderboard',
                                style: GoogleFonts.inter(
                                  color: theme.accentPrimary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            )
                          else if (rank <= 10)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '🔥 Top 10',
                                style: GoogleFonts.inter(
                                  color: theme.accentPrimary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
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
              ),
            ),
          ],
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
    return _PremiumPodium(
      theme: theme,
      slots: top3
          .map(
            (e) => _PodiumSlotData(
              displayName: e.displayName,
              statText: 'W ${e.wins}',
            ),
          )
          .toList(),
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
    final isTop3 = rank <= 3 && !isLocal;
    const medalColors = [
      Color(0xFFFFD700),
      Color(0xFFB0BEC5),
      Color(0xFFBF8970),
    ];
    final tier = _winsTier(entry.wins);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isLocal
            ? theme.accentPrimary.withValues(alpha: 0.10)
            : isTop3
                ? medalColors[rank - 1].withValues(alpha: 0.06)
                : theme.backgroundMid,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isLocal
              ? theme.accentPrimary.withValues(alpha: 0.5)
              : theme.textPrimary.withValues(alpha: 0.06),
          width: isLocal ? 1.5 : 1,
        ),
        boxShadow: isLocal
            ? [
                BoxShadow(
                  color: theme.accentPrimary.withValues(alpha: 0.12),
                  blurRadius: 8,
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          _RankCircle(rank: rank, theme: theme),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
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
                    if (isLocal) ...[
                      const SizedBox(width: 6),
                      _YouBadge(theme: theme),
                    ],
                    const SizedBox(width: 6),
                    _TierBadge(label: tier.label, color: tier.color),
                  ],
                ),
                const SizedBox(height: 4),
                _StatPillsRow(
                  wins: entry.wins,
                  losses: entry.losses,
                  theme: theme,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
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
                tier.label,
                style: GoogleFonts.inter(
                  color: tier.color,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Combos (longest-combo) leaderboard ────────────────────────────────────────
//
// Same fire palette as the in-game combo celebration — deliberately fixed,
// independent of the active table theme, so "Legendary" always reads as fire.

_TierInfo _comboTier(int count) {
  if (count >= 10) return const _TierInfo('Mythic', Color(0xFFFF3D00));
  if (count >= 7) return const _TierInfo('Legendary', Color(0xFFFF6D00));
  if (count >= 5) return const _TierInfo('Combo', Color(0xFFFFA000));
  return const _TierInfo('Nice', Color(0xFFB0BEC5));
}

class _ComboLeaderboard extends StatefulWidget {
  const _ComboLeaderboard({
    required this.fetchEntries,
    required this.findLocalEntry,
    required this.localRank,
    required this.theme,
  });

  final Future<List<ComboLeaderboardEntry>> Function() fetchEntries;
  final ComboLeaderboardEntry? Function(List<ComboLeaderboardEntry>) findLocalEntry;
  final int Function(List<ComboLeaderboardEntry>) localRank;
  final AppThemeData theme;

  @override
  State<_ComboLeaderboard> createState() => _ComboLeaderboardState();
}

class _ComboLeaderboardState extends State<_ComboLeaderboard> {
  late Future<List<ComboLeaderboardEntry>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.fetchEntries();
  }

  Future<void> _refresh() async {
    setState(() => _future = widget.fetchEntries());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return FutureBuilder<List<ComboLeaderboardEntry>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Center(
            child: ThemedShimmer(width: 220, height: 180, borderRadius: 16),
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
                  'Failed to load the combo leaderboard.',
                  style: GoogleFonts.inter(
                      color: theme.textSecondary.withValues(alpha: 0.6)),
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
                const Text('🔥', style: TextStyle(fontSize: 48)),
                const SizedBox(height: 12),
                Text(
                  'No combos recorded yet.\nStack $kMultiPlayCelebrationMinCards+ cards in one turn to set the record!',
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

        return RefreshIndicator(
          onRefresh: _refresh,
          color: theme.accentPrimary,
          backgroundColor: theme.surfacePanel,
          child: CustomScrollView(
            slivers: [
              const SliverToBoxAdapter(child: SizedBox(height: 8)),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) => _ComboTile(
                    index: i,
                    entry: entries[i],
                    isLocal: entries[i].uid == widget.findLocalEntry(entries)?.uid,
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

class _ComboTile extends StatelessWidget {
  const _ComboTile({
    required this.index,
    required this.entry,
    required this.isLocal,
    required this.theme,
  });

  final int index;
  final ComboLeaderboardEntry entry;
  final bool isLocal;
  final AppThemeData theme;

  @override
  Widget build(BuildContext context) {
    final rank = index + 1;
    final isTop3 = rank <= 3 && !isLocal;
    const medalColors = [
      Color(0xFFFFD700),
      Color(0xFFB0BEC5),
      Color(0xFFBF8970),
    ];
    final tier = _comboTier(entry.comboCount);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isLocal
            ? tier.color.withValues(alpha: 0.10)
            : isTop3
                ? medalColors[rank - 1].withValues(alpha: 0.06)
                : theme.backgroundMid,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isLocal
              ? tier.color.withValues(alpha: 0.5)
              : theme.textPrimary.withValues(alpha: 0.06),
          width: isLocal ? 1.5 : 1,
        ),
        boxShadow: isLocal
            ? [BoxShadow(color: tier.color.withValues(alpha: 0.15), blurRadius: 8)]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _RankCircle(rank: rank, theme: theme),
              const SizedBox(width: 10),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        entry.displayName,
                        style: GoogleFonts.outfit(
                          color: isLocal ? tier.color : theme.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isLocal) ...[
                      const SizedBox(width: 6),
                      _YouBadge(theme: theme),
                    ],
                    const SizedBox(width: 6),
                    _TierBadge(label: tier.label, color: tier.color),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '×${entry.comboCount}',
                style: GoogleFonts.outfit(
                  color: tier.color,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          if (entry.cards.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: entry.cards.length,
                separatorBuilder: (_, __) => const SizedBox(width: 4),
                itemBuilder: (context, i) => CardWidget(
                  card: entry.cards[i],
                  width: 28,
                  faceUp: true,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
