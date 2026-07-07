import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/services/ads_service.dart';
import '../../../../core/services/player_level_service.dart';
import '../widgets/locker_cosmetics_tabs.dart';
import '../widgets/locker_effects_tab.dart';
import '../widgets/locker_reactions_tab.dart';
import '../widgets/locker_theme_tab.dart';

/// XP granted for watching a rewarded ad to completion (see [_RewardedXpButton]).
const int kRewardedAdXpBonus = 100;

/// The single home for every cosmetic customization surface in the app:
/// card backs, joker covers, card faces, reaction wheel, table theme and
/// visual effects.
///
/// Replaces the previously scattered "Card Styles" sheet, "Theme" sheet,
/// and reaction-wheel sheet, plus the duplicate "Animated Card Effects"
/// toggle that used to live in Settings.
class LockerScreen extends StatefulWidget {
  const LockerScreen({super.key, this.initialTabIndex = 0});

  /// Which tab to open on. See [LockerTab] for named indices.
  final int initialTabIndex;

  @override
  State<LockerScreen> createState() => _LockerScreenState();
}

/// Named tab indices for [LockerScreen.initialTabIndex], so callers don't
/// have to hardcode magic numbers.
abstract final class LockerTab {
  static const cardBacks = 0;
  static const jokers = 1;
  static const faces = 2;
  static const reactions = 3;
  static const tableTheme = 4;
  static const effects = 5;
}

class _LockerScreenState extends State<LockerScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  static const _tabs = [
    Tab(text: 'Card backs'),
    Tab(text: 'Jokers'),
    Tab(text: 'Faces'),
    Tab(text: 'Reactions'),
    Tab(text: 'Table theme'),
    Tab(text: 'Effects'),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: _tabs.length,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, _tabs.length - 1),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'The locker',
          style: GoogleFonts.playfairDisplay(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: colors.primary,
            letterSpacing: 0.3,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: colors.primary,
          unselectedLabelColor: colors.onSurface.withValues(alpha: 0.55),
          indicatorColor: colors.primary,
          labelStyle: GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.w500),
          unselectedLabelStyle: GoogleFonts.dmSans(fontSize: 13),
          tabs: _tabs,
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 8),
            child: _RewardedXpButton(),
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          LockerCardBacksTab(),
          LockerJokersTab(),
          LockerFacesTab(),
          LockerReactionsTab(),
          LockerThemeTab(),
          LockerEffectsTab(),
        ],
      ),
    );
  }
}

/// "Watch an ad, earn bonus XP" — the app's only rewarded-ad surface. XP
/// speeds up the level-gated cosmetic unlocks elsewhere in the Locker.
class _RewardedXpButton extends StatefulWidget {
  const _RewardedXpButton();

  @override
  State<_RewardedXpButton> createState() => _RewardedXpButtonState();
}

class _RewardedXpButtonState extends State<_RewardedXpButton> {
  bool _showing = false;

  Future<void> _watchAd() async {
    if (_showing) return;
    setState(() => _showing = true);
    final shown = await AdsService.instance.showRewardedAd(
      onEarnedReward: (_) {
        unawaited(PlayerLevelService.instance.awardXP(kRewardedAdXpBonus));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('+$kRewardedAdXpBonus XP earned!')),
        );
      },
    );
    if (!mounted) return;
    setState(() => _showing = false);
    if (!shown) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ad not ready yet — try again in a moment.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return TextButton.icon(
      onPressed: _showing ? null : _watchAd,
      icon: _showing
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: colors.primary),
            )
          : Icon(Icons.ondemand_video_rounded, color: colors.primary, size: 18),
      label: Text(
        '+$kRewardedAdXpBonus XP',
        style: GoogleFonts.dmSans(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: colors.primary,
        ),
      ),
    );
  }
}

/// Convenience push helper — mirrors the old `showCardStylesModal` /
/// `_showThemeSelector` / `showReactionWheelCustomizeSheet` entry points,
/// all now unified into this one call.
void showLocker(BuildContext context, {int initialTabIndex = 0}) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => LockerScreen(initialTabIndex: initialTabIndex)),
  );
}
