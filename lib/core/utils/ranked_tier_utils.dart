/// Rank tier thresholds (MMR): Bronze < 1100, Silver < 1300, Gold < 1500,
/// Diamond < 1800, Master 1800+
({String label, String emoji}) rankTierForMmr(int mmr) {
  if (mmr >= 1800) return (label: 'Master', emoji: '👑');
  if (mmr >= 1500) return (label: 'Diamond', emoji: '💎');
  if (mmr >= 1300) return (label: 'Gold', emoji: '🥇');
  if (mmr >= 1100) return (label: 'Silver', emoji: '🥈');
  return (label: 'Bronze', emoji: '🥉');
}
