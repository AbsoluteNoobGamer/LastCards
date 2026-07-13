import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:profanity_filter/profanity_filter.dart';

import '../../../../core/providers/auth_provider.dart';
import '../../../../core/providers/theme_provider.dart';
import '../../../../core/providers/user_profile_provider.dart';
import '../../../../core/services/display_name_registry_service.dart';
import '../../../../shared/leaderboard/display_name_leaderboard_rules.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_theme_data.dart';
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
    } else if (isDefaultOrReservedDisplayName(trimmed)) {
      error =
          'Choose a unique name — Guest and Player cannot appear on leaderboards';
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
    final name = _nameController.text.trim();
    try {
      final taken = await DisplayNameRegistryService()
          .validateNameForProfile(name: name, uid: user.uid);
      if (taken != null) {
        if (mounted) {
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(SnackBar(
              content: Text(taken),
              behavior: SnackBarBehavior.floating,
            ));
        }
        return;
      }

      await ref.read(firestoreProfileServiceProvider).updateProfile(
            uid: user.uid,
            displayName: name,
          );
    } on DisplayNameTakenException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(
            content: Text(e.message),
            behavior: SnackBarBehavior.floating,
          ));
      }
      return;
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

  void _showCooldownDialog(DateTime nextEditDate, AppThemeData theme) {
    final formatted = formatProfileCooldownDate(nextEditDate);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: theme.surfacePanel,
        title: Text(
          'Profile change cooldown',
          style: TextStyle(color: theme.textPrimary),
        ),
        content: Text(
          'You can change your profile name and photo again on $formatted.',
          style: TextStyle(color: theme.textSecondary, fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('OK', style: TextStyle(color: theme.accentPrimary)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider).theme;
    final authAsync = ref.watch(authStateProvider);
    final userProfileAsync = ref.watch(userProfileProvider);

    if (authAsync.value == null) {
      return Scaffold(
        backgroundColor: theme.backgroundDeep,
        appBar: AppBar(
          backgroundColor: theme.backgroundDeep,
          foregroundColor: theme.textPrimary,
          iconTheme: IconThemeData(color: theme.accentPrimary),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(
            'YOUR PROFILE',
            style: TextStyle(
              color: theme.accentPrimary,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.4,
              fontSize: 16,
            ),
          ),
          centerTitle: true,
        ),
        body: Center(
          child: Text(
            'Sign in to edit your profile',
            style: TextStyle(color: theme.textPrimary, fontSize: 16),
          ),
        ),
      );
    }

    final profile = userProfileAsync.valueOrNull;
    final profileLoaded = userProfileAsync.hasValue;
    final cooldown = profileEditCooldown(profile?.profileLastChangedAt);
    final canEdit = profileLoaded && cooldown.canEdit;
    final nextEditDate = cooldown.nextEditDate;

    return Scaffold(
      backgroundColor: theme.backgroundDeep,
      appBar: AppBar(
        backgroundColor: theme.backgroundDeep,
        foregroundColor: theme.textPrimary,
        iconTheme: IconThemeData(color: theme.accentPrimary),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'YOUR PROFILE',
          style: TextStyle(
            color: theme.accentPrimary,
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
            CircleAvatar(
              radius: 55,
              backgroundColor: theme.surfacePanel,
              child: Icon(Icons.person, size: 56, color: theme.accentPrimary),
            ),
            const SizedBox(height: 14),
            TextButton.icon(
              onPressed: () {
                if (!canEdit && nextEditDate != null) {
                  _showCooldownDialog(nextEditDate, theme);
                  return;
                }
                _showUnsupported();
              },
              icon: Icon(Icons.upload_rounded,
                  color: theme.accentPrimary, size: 18),
              label: Text(
                'Upload Photo',
                style: TextStyle(
                  color: theme.accentPrimary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(height: 32),
            GestureDetector(
              onTap: !canEdit && nextEditDate != null
                  ? () => _showCooldownDialog(nextEditDate, theme)
                  : null,
              child: AbsorbPointer(
                absorbing: !canEdit && nextEditDate != null,
                child: TextField(
                  controller: _nameController,
                  maxLength: kMaxNameLength,
                  readOnly: !canEdit,
                  style: TextStyle(color: theme.textPrimary, fontSize: 15),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: theme.surfacePanel,
                    counterText: '',
                    hintText: 'Enter your name…',
                    hintStyle: TextStyle(color: theme.textSecondary),
                    enabledBorder: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(AppDimensions.radiusButton),
                      borderSide:
                          BorderSide(color: _nameError != null ? AppColors.redAccent : theme.accentDark, width: 1.8),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(AppDimensions.radiusButton),
                      borderSide:
                          BorderSide(color: _nameError != null ? AppColors.redAccent : theme.accentDark, width: 2.2),
                    ),
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
                    ? () => _showCooldownDialog(nextEditDate, theme)
                    : _canSave
                        ? _saveProfile
                        : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.accentPrimary,
                  disabledBackgroundColor:
                      theme.accentDark.withValues(alpha: 0.35),
                  foregroundColor: theme.backgroundDeep,
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
                        ? theme.backgroundDeep
                        : theme.textSecondary,
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
