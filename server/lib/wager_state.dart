/// How a wager's stake is contested.
enum WagerMode {
  /// Whole-table pot — every seated player stakes the same amount, winner
  /// takes it all. Degenerates to a plain 1v1 wager when only two seats are
  /// filled.
  pot,

  /// Targeted 1v1 side-bet between two specific seated players inside a
  /// larger table. Settled independently of who wins the overall match.
  sideBet,

  /// Mid-game, opt-in, multi-player table pot — proposed by any seated
  /// player once the match has started, joined freely by whoever wants in
  /// (no unanimity), and locked in only when the proposer explicitly
  /// starts it. Winner-take-all among joiners by overall match result,
  /// same settlement math as [pot].
  tablePot,
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
/// session at a time (only one of pot / side-bet / table-pot may be active,
/// and a new proposal is rejected outright while one is already locked in).
/// [WagerMode.pot] is set up before a private match starts. [WagerMode.sideBet]
/// and [WagerMode.tablePot] can each be proposed at any point during an
/// already-running private or quickplay/casual match (never ranked) —
/// sideBet settles independently of the overall result, by remaining hand
/// size; tablePot settles winner-take-all among joiners by overall result,
/// same as [pot].
///
/// Tracks the proposed [config], per-seat acceptance (unanimous-consent gate
/// for [pot], free join/leave for [tablePot]), which participants have had
/// their stake actually charged, and whether settlement has already run (so
/// a match-end hook can't double-settle).
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
  /// [WagerMode.sideBet] it's just the initiator and target; for
  /// [WagerMode.tablePot] it's the initiator plus whoever has explicitly
  /// joined (`accepted` in [acceptStatus]) so far, intersected with who's
  /// still actually seated.
  Set<String> participantPlayerIds(Iterable<String> seatedPlayerIds) {
    final cfg = config;
    if (cfg == null) return const {};
    if (cfg.mode == WagerMode.sideBet) {
      return {cfg.initiatorPlayerId, cfg.targetPlayerId!};
    }
    if (cfg.mode == WagerMode.tablePot) {
      final joined = acceptStatus.entries
          .where((e) => e.value == WagerAcceptStatus.accepted)
          .map((e) => e.key);
      final seatedSet = seatedPlayerIds.toSet();
      return {cfg.initiatorPlayerId, ...joined}
          .where(seatedSet.contains)
          .toSet();
    }
    return seatedPlayerIds.toSet();
  }

  /// Whether every required seat has explicitly accepted — the gate that
  /// unlocks charging stakes. For [WagerMode.pot] that's every seat other
  /// than the initiator (unanimous consent); for [WagerMode.sideBet] it's
  /// just the challenged [WagerConfig.targetPlayerId]. [WagerMode.tablePot]
  /// never uses this — it has no unanimity gate, entry stays open until the
  /// proposer explicitly starts it (see `GameSession._isWagerReadyToLock`).
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
      // Distinguishes "accepted, but the async balance check/charge hasn't
      // resolved yet" from "actually active" — without this, a client has
      // no reliable signal for when it's safe to show a locked-in status.
      'locked': lockedPlayerIds.isNotEmpty,
      // The actual charged participant set — for tablePot, acceptStatus
      // alone isn't enough to render "who's really in" once locked, since a
      // late joiner can show `accepted` in acceptStatus without having been
      // captured (and charged) by the in-flight lock-in.
      'lockedPlayerIds': lockedPlayerIds.toList(),
    };
  }
}
