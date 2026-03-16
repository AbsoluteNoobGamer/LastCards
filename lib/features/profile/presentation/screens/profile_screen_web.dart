import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:profanity_filter/profanity_filter.dart';

import '../../../../core/providers/auth_provider.dart';
import '../../../../core/providers/user_profile_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/utils/profile_cooldown_utils.dart';

const Set<String> kReservedNames = {'Player 2', 'Player 3', 'Player 4'};
const int kMaxNameLength = 17;

/// Profile screen for web. Requires sign-in. Name editing only (no avatar upload).
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  late TextEditingController _nameController;
  final ProfanityFilter _filter = ProfanityFilter();
  String? _nameError;
  bool _nameValid = false;
  bool _hasInitializedName = false;

  bool get _canSave {
    final currentName = ref.read(userProfileProvider).valueOrNull?.displayName ?? '';
    final nameChanged = _nameController.text.trim() != currentName;
    return nameChanged && _nameValid && _nameError == null;
  }

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _nameController.addListener(() => _validateName(_nameController.text));

    // Listen for the first emission from userProfileProvider to populate the
    // name field. The Firestore stream may not have emitted yet when initState
    // runs, so a one-shot read would see null.
    ref.listenManual(userProfileProvider, (previous, next) {
      if (_hasInitializedName) return;
      final profile = next.valueOrNull;
      if (profile != null && mounted) {
        _hasInitializedName = true;
        _nameController.text = profile.displayName;
        _validateName(profile.displayName);
      }
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _validateName(String value) {
    String? error;
    bool valid = false;
    final trimmed = value.trim();

    if (trimmed.isEmpty) {
      error = 'Name cannot be empty';
    } else if (trimmed.length > kMaxNameLength) {
      error = 'Name must be $kMaxNameLength characters or fewer';
    } else if (kReservedNames
        .any((n) => n.toLowerCase() == trimmed.toLowerCase())) {
      error = 'That name is reserved for opponents';
    } else if (_filter.hasProfanity(trimmed)) {
      error = 'Name contains inappropriate language';
    } else {
      valid = true;
    }

    if (mounted) {
      setState(() {
        _nameError = error;
        _nameValid = valid;
      });
    }
  }

  Future<void> _saveProfile() async {
    if (!_canSave) return;
    final user = ref.read(authStateProvider).value;
    if (user == null) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(
          content: Text('You must be signed in to save your profile'),
          behavior: SnackBarBehavior.floating,
        ));
      return;
    }
    try {
      await ref.read(firestoreProfileServiceProvider).updateProfile(
            uid: user.uid,
            displayName: _nameController.text.trim(),
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(const SnackBar(
            content: Text('Could not save profile. Please try again.'),
            behavior: SnackBarBehavior.floating,
          ));
      }
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  void _showUnsupported() {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(
        content: Text('Avatar upload is not supported on web build yet.'),
        behavior: SnackBarBehavior.floating,
      ));
  }

  void _showCooldownDialog(DateTime nextEditDate) {
    final formatted = formatProfileCooldownDate(nextEditDate);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfacePanel,
        title: const Text(
          'Profile change cooldown',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: Text(
          'You can change your profile name and photo again on $formatted.',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK', style: TextStyle(color: AppColors.goldPrimary)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authAsync = ref.watch(authStateProvider);
    final userProfileAsync = ref.watch(userProfileProvider);

    if (authAsync.value == null) {
      return Scaffold(
        backgroundColor: AppColors.feltDeep,
        appBar: AppBar(
          backgroundColor: AppColors.goldDark.withValues(alpha: 0.95),
          foregroundColor: AppColors.feltDeep,
          iconTheme: const IconThemeData(color: AppColors.feltDeep),
          elevation: 0,
          title: const Text(
            'YOUR PROFILE',
            style: TextStyle(
              color: AppColors.feltDeep,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.4,
              fontSize: 16,
            ),
          ),
          centerTitle: true,
        ),
        body: const Center(
          child: Text(
            'Sign in to edit your profile',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
          ),
        ),
      );
    }

    final profile = userProfileAsync.valueOrNull;
    final cooldown = profileEditCooldown(profile?.profileLastChangedAt);
    final canEdit = cooldown.canEdit;
    final nextEditDate = cooldown.nextEditDate;

    return Scaffold(
      backgroundColor: AppColors.feltDeep,
      appBar: AppBar(
        backgroundColor: AppColors.goldDark.withValues(alpha: 0.95),
        foregroundColor: AppColors.feltDeep,
        iconTheme: const IconThemeData(color: AppColors.feltDeep),
        elevation: 0,
        title: const Text(
          'YOUR PROFILE',
          style: TextStyle(
            color: AppColors.feltDeep,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.4,
            fontSize: 16,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const CircleAvatar(
              radius: 55,
              backgroundColor: AppColors.surfacePanel,
              child: Icon(Icons.person, size: 56, color: AppColors.goldPrimary),
            ),
            const SizedBox(height: 14),
            TextButton.icon(
              onPressed: () {
                if (!canEdit && nextEditDate != null) {
                  _showCooldownDialog(nextEditDate!);
                  return;
                }
                _showUnsupported();
              },
              icon: const Icon(Icons.upload_rounded,
                  color: AppColors.goldPrimary, size: 18),
              label: const Text(
                'Upload Photo',
                style: TextStyle(
                  color: AppColors.goldPrimary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(height: 32),
            GestureDetector(
              onTap: !canEdit && nextEditDate != null
                  ? () => _showCooldownDialog(nextEditDate!)
                  : null,
              child: AbsorbPointer(
                absorbing: !canEdit && nextEditDate != null,
                child: TextField(
                  controller: _nameController,
                  maxLength: kMaxNameLength,
                  readOnly: !canEdit,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
              decoration: InputDecoration(
                filled: true,
                fillColor: AppColors.surfacePanel,
                counterText: '',
                hintText: 'Enter your name…',
                hintStyle: const TextStyle(color: AppColors.textSecondary),
                enabledBorder: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(AppDimensions.radiusButton),
                  borderSide:
                      BorderSide(color: _nameError != null ? AppColors.redAccent : AppColors.goldDark, width: 1.8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(AppDimensions.radiusButton),
                  borderSide:
                      BorderSide(color: _nameError != null ? AppColors.redAccent : AppColors.goldDark, width: 2.2),
                ),
              ),
            ),
            ),
            if (_nameError != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _nameError!,
                  style: const TextStyle(
                    color: AppColors.redAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            const SizedBox(height: 36),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: !canEdit && nextEditDate != null
                    ? () => _showCooldownDialog(nextEditDate!)
                    : _canSave
                        ? _saveProfile
                        : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.goldPrimary,
                  disabledBackgroundColor:
                      AppColors.goldDark.withValues(alpha: 0.35),
                  foregroundColor: AppColors.feltDeep,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(AppDimensions.radiusButton),
                  ),
                  elevation: (_canSave && canEdit) || (!canEdit && nextEditDate != null) ? 4 : 0,
                ),
                child: Text(
                  'SAVE PROFILE',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                    fontSize: 15,
                    color: (_canSave && canEdit) || (!canEdit && nextEditDate != null)
                        ? AppColors.feltDeep
                        : AppColors.textSecondary,
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
