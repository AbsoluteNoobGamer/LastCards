/// How a wager's stake is contested.
enum WagerMode {
  /// Whole-table pot — every seated player stakes the same amount, winner
  /// takes it all. Degenerates to a plain 1v1 wager when only two seats are
  /// filled.
  pot,

  /// Targeted 1v1 side-bet between two specific seated players inside a
  /// larger table. Settled independently of who wins the overall match.
  sideBet,
}

/// Per-seat accept status. For [WagerMode.pot] every non-initiator seat must
/// reach `accepted`; for [WagerMode.sideBet] only the challenged
/// [WagerConfig.targetPlayerId] needs to.
enum WagerAcceptStatus { pending, accepted, declined }

/// A proposed (or locked-in) wager, set by whoever initiated it.
///
/// For [WagerMode.pot] the initiator is the private-lobby host; for
/// [WagerMode.sideBet] it's whichever player issued the challenge.
/// [stakeCoins] is the amount *each* participant stakes, not the total pot.
class WagerConfig {
  WagerConfig({
    required this.mode,
    required this.stakeCoins,
    required this.initiatorPlayerId,
    this.targetPlayerId,
  })  : assert(stakeCoins > 0, 'stakeCoins must be positive'),
        assert(
          mode != WagerMode.sideBet || targetPlayerId != null,
          'sideBet requires a targetPlayerId',
        );

  final WagerMode mode;
  final int stakeCoins;
  final String initiatorPlayerId;

  /// The challenged opponent's playerId. Only set for [WagerMode.sideBet].
  final String? targetPlayerId;
}

/// Live wager state for one [GameSession] — at most one active wager per
/// session (a whole-table pot and a side-bet are mutually exclusive).
///
/// Tracks the proposed [config], per-seat acceptance for the pot mode's
/// unanimous-consent gate, which participants have had their stake actually
/// charged, and whether settlement has already run (so a match-end hook
/// can't double-settle).
class WagerState {
  WagerConfig? config;
  final Map<String, WagerAcceptStatus> acceptStatus = {};
  final Set<String> lockedPlayerIds = {};
  bool settled = false;

  /// Replaces the current proposal and clears all acceptance/lock state —
  /// a new config invalidates any prior accepts.
  void setConfig(WagerConfig? newConfig) {
    config = newConfig;
    acceptStatus.clear();
    lockedPlayerIds.clear();
    settled = false;
  }

  void setAccept(String playerId, bool accepted) {
    acceptStatus[playerId] =
        accepted ? WagerAcceptStatus.accepted : WagerAcceptStatus.declined;
  }

  /// The playerIds staking coins under the current [config].
  ///
  /// For [WagerMode.pot] that's every currently seated player; for
  /// [WagerMode.sideBet] it's just the initiator and target.
  Set<String> participantPlayerIds(Iterable<String> seatedPlayerIds) {
    final cfg = config;
    if (cfg == null) return const {};
    if (cfg.mode == WagerMode.sideBet) {
      return {cfg.initiatorPlayerId, cfg.targetPlayerId!};
    }
    return seatedPlayerIds.toSet();
  }

  /// Whether every required seat has explicitly accepted — the gate that
  /// unlocks charging stakes. For [WagerMode.pot] that's every seat other
  /// than the initiator (unanimous consent); for [WagerMode.sideBet] it's
  /// just the challenged [WagerConfig.targetPlayerId].
  bool isFullyAccepted(Iterable<String> seatedPlayerIds) {
    final cfg = config;
    if (cfg == null) return false;
    if (cfg.mode == WagerMode.sideBet) {
      return acceptStatus[cfg.targetPlayerId] == WagerAcceptStatus.accepted;
    }
    return seatedPlayerIds
        .where((id) => id != cfg.initiatorPlayerId)
        .every((id) => acceptStatus[id] == WagerAcceptStatus.accepted);
  }

  /// Clears all wager state — call on settlement, refund, or lobby teardown.
  void reset() {
    config = null;
    acceptStatus.clear();
    lockedPlayerIds.clear();
    settled = false;
  }

  Map<String, dynamic> toJson() {
    final cfg = config;
    return {
      'mode': cfg?.mode.name,
      'stakeCoins': cfg?.stakeCoins,
      'initiatorPlayerId': cfg?.initiatorPlayerId,
      'targetPlayerId': cfg?.targetPlayerId,
      'acceptStatus': {
        for (final e in acceptStatus.entries) e.key: e.value.name,
      },
      'settled': settled,
    };
  }
}
