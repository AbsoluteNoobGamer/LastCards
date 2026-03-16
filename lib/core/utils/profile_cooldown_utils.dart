/// 14-day cooldown between profile (name/avatar) edits.
const Duration kProfileEditCooldown = Duration(days: 14);

/// Returns whether the user can edit their profile and the next allowed edit date.
({bool canEdit, DateTime? nextEditDate}) profileEditCooldown(
  DateTime? profileLastChangedAt,
) {
  if (profileLastChangedAt == null) return (canEdit: true, nextEditDate: null);
  final nextEdit = profileLastChangedAt.add(kProfileEditCooldown);
  final now = DateTime.now();
  final canEdit = now.isAfter(nextEdit) ||
      now.isAtSameMomentAs(nextEdit);
  return (canEdit: canEdit, nextEditDate: canEdit ? null : nextEdit);
}

/// Formats a date for the "You can change your profile on ..." dialog.
String formatProfileCooldownDate(DateTime date) {
  const months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}
