import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:profanity_filter/profanity_filter.dart';

import '../../../../core/providers/auth_provider.dart';
import '../../../../core/providers/user_profile_provider.dart';
import '../../../../core/services/firestore_profile_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/services/nsfw_scan_service.dart';
import '../../../../core/utils/profile_cooldown_utils.dart';
import '../../widgets/profile_stats_section.dart';

/// The opponent display names that the local player cannot use.
const Set<String> kReservedNames = {'Player 2', 'Player 3', 'Player 4'};

/// Maximum allowed character count for a profile name.
const int kMaxNameLength = 17;

// ── Provider ─────────────────────────────────────────────────────────────────

final nsfwScanServiceProvider = Provider<NsfwScanService>(
  (_) => DefaultNsfwScanService(),
);

// ── Screen ───────────────────────────────────────────────────────────────────

/// Profile customization screen.
///
/// Requires sign-in. Uses Firestore for display name and avatar.
/// - Upload avatar (gallery or camera) with NSFW scanning.
/// - Edit display name with real-time validation.
/// - Save to Firestore via [FirestoreProfileService].
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  late TextEditingController _nameController;
  final ProfanityFilter _filter = ProfanityFilter();
  final ImagePicker _picker = ImagePicker();

  // Pending image (not yet saved) - store path for display, bytes for upload
  String? _pendingAvatarPath;
  Uint8List? _pendingAvatarBytes;
  bool _pendingAvatarValid = false;

  // Validation state
  String? _nameError;
  bool _nameValid = false;
  bool _hasInitializedName = false;

  bool get _canSave {
    final currentName = ref.read(userProfileProvider).valueOrNull?.displayName ?? '';
    final nameChanged = _nameController.text.trim() != currentName;
    final avatarChanged = _pendingAvatarPath != null && _pendingAvatarValid;
    return (nameChanged || avatarChanged) && _nameValid && _nameError == null;
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

  // ── Validation ────────────────────────────────────────────────────────────

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

  // ── Image picker ──────────────────────────────────────────────────────────

  Future<void> _pickImage(ImageSource source) async {
    try {
      final xfile = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 512,
        maxHeight: 512,
      );
      if (xfile == null) return;

      final file = File(xfile.path);
      final scanner = ref.read(nsfwScanServiceProvider);
      final flagged = await scanner.isNsfw(file);

      if (!mounted) return;

      if (flagged) {
        _showError('Image contains inappropriate content');
        setState(() {
          _pendingAvatarPath = null;
          _pendingAvatarBytes = null;
          _pendingAvatarValid = false;
        });
      } else {
        final bytes = await xfile.readAsBytes();
        if (mounted) {
          setState(() {
            _pendingAvatarPath = xfile.path;
            _pendingAvatarBytes = bytes;
            _pendingAvatarValid = true;
          });
        }
      }
    } catch (_) {
      if (mounted) _showError('Could not load image. Please try again.');
    }
  }

  // ── Save ─────────────────────────────────────────────────────────────────

  Future<void> _saveProfile() async {
    if (!_canSave) return;
    final user = ref.read(authStateProvider).value;
    if (user == null) {
      _showError('You must be signed in to save your profile');
      return;
    }

    final firestoreService = ref.read(firestoreProfileServiceProvider);
    final name = _nameController.text.trim();
    String? avatarUrl;

    try {
      if (_pendingAvatarValid && _pendingAvatarBytes != null) {
        avatarUrl = await firestoreService.uploadAvatar(user.uid, _pendingAvatarBytes!);
      }

      await firestoreService.updateProfile(
        uid: user.uid,
        displayName: name,
        avatarUrl: avatarUrl,
      );
    } catch (e) {
      if (mounted) _showError('Could not save profile. Please try again.');
      return;
    }

    if (mounted) {
      setState(() {
        _pendingAvatarPath = null;
        _pendingAvatarBytes = null;
        _pendingAvatarValid = false;
      });
      Navigator.of(context).pop();
    }
  }

  // ── Source sheet ─────────────────────────────────────────────────────────

  void _showImageSourceSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfacePanel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_outlined,
                    color: AppColors.goldPrimary),
                title: const Text('Choose from Gallery',
                    style: TextStyle(color: AppColors.textPrimary)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined,
                    color: AppColors.goldPrimary),
                title: const Text('Take a Photo',
                    style: TextStyle(color: AppColors.textPrimary)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.camera);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.redAccent,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
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

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final authAsync = ref.watch(authStateProvider);
    final userProfileAsync = ref.watch(userProfileProvider);

    // Must be signed in
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
    final displayAvatarPath = _pendingAvatarValid ? _pendingAvatarPath : null;
    final displayAvatarUrl = displayAvatarPath == null ? profile?.avatarUrl : null;
    final profileLoaded = userProfileAsync.hasValue;
    final cooldown = profileEditCooldown(profile?.profileLastChangedAt);
    final canEdit = profileLoaded && cooldown.canEdit;
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
            _AvatarSection(
              avatarPath: displayAvatarPath,
              avatarUrl: displayAvatarUrl,
              onUpload: () {
                if (!canEdit && nextEditDate != null) {
                  _showCooldownDialog(nextEditDate);
                  return;
                }
                _showImageSourceSheet();
              },
            ),
            const ProfileStatsSection(
              statsHeaderTopSpacing: 24,
            ),
            const SizedBox(height: 32),
            _NameField(
              controller: _nameController,
              maxLength: kMaxNameLength,
              isValid: _nameValid,
              errorText: _nameError,
              readOnly: !canEdit,
              onTapWhenLocked: (!canEdit && nextEditDate != null)
                  ? () => _showCooldownDialog(nextEditDate)
                  : null,
            ),
            const SizedBox(height: 36),
            SizedBox(
              width: double.infinity,
              child: _SaveButton(
                enabled: _canSave || (!canEdit && nextEditDate != null),
                onPressed: () {
                  if (!canEdit && nextEditDate != null) {
                    _showCooldownDialog(nextEditDate);
                    return;
                  }
                  _saveProfile();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Avatar section ────────────────────────────────────────────────────────────

class _AvatarSection extends StatelessWidget {
  const _AvatarSection({
    this.avatarPath,
    this.avatarUrl,
    required this.onUpload,
  });

  final String? avatarPath;
  final String? avatarUrl;
  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    final Widget inner;
    if (avatarPath != null) {
      inner = CircleAvatar(
        key: const ValueKey('avatar-image-file'),
        radius: 55,
        backgroundImage: FileImage(File(avatarPath!)),
        backgroundColor: AppColors.surfacePanel,
      );
    } else if (avatarUrl != null) {
      inner = CircleAvatar(
        key: const ValueKey('avatar-image-network'),
        radius: 55,
        backgroundImage: NetworkImage(avatarUrl!),
        backgroundColor: AppColors.surfacePanel,
      );
    } else {
      inner = const CircleAvatar(
        key: ValueKey('avatar-default'),
        radius: 55,
        backgroundColor: AppColors.surfacePanel,
        child: Icon(Icons.person, size: 56, color: AppColors.goldPrimary),
      );
    }

    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.goldPrimary, width: 3),
          ),
          child: inner,
        ),
        const SizedBox(height: 14),
        TextButton.icon(
          key: const ValueKey('upload-photo-button'),
          onPressed: onUpload,
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
      ],
    );
  }
}

// ── Name field ────────────────────────────────────────────────────────────────

class _NameField extends StatelessWidget {
  const _NameField({
    required this.controller,
    required this.maxLength,
    required this.isValid,
    this.errorText,
    this.readOnly = false,
    this.onTapWhenLocked,
  });

  final TextEditingController controller;
  final int maxLength;
  final bool isValid;
  final String? errorText;
  final bool readOnly;
  final VoidCallback? onTapWhenLocked;

  @override
  Widget build(BuildContext context) {
    final Color borderColor;
    if (errorText != null) {
      borderColor = AppColors.redAccent;
    } else if (isValid) {
      borderColor = Colors.green;
    } else {
      borderColor = AppColors.goldDark;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'DISPLAY NAME',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: readOnly && onTapWhenLocked != null ? onTapWhenLocked : null,
          child: AbsorbPointer(
            absorbing: readOnly && onTapWhenLocked != null,
            child: TextField(
              key: const ValueKey('name-field'),
              controller: controller,
              maxLength: maxLength,
              readOnly: readOnly,
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
                  borderSide: BorderSide(color: borderColor, width: 1.8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(AppDimensions.radiusButton),
                  borderSide: BorderSide(color: borderColor, width: 2.2),
                ),
              ),
            ),
          ),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 6),
          Text(
            errorText!,
            key: const ValueKey('name-error'),
            style: const TextStyle(
              color: AppColors.redAccent,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ] else if (isValid) ...[
          const SizedBox(height: 6),
          const Text(
            '✓ Name looks good',
            key: ValueKey('name-valid'),
            style: TextStyle(
              color: Colors.green,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

// ── Save button ───────────────────────────────────────────────────────────────

class _SaveButton extends StatelessWidget {
  const _SaveButton({required this.enabled, required this.onPressed});

  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      key: const ValueKey('save-profile-button'),
      onPressed: enabled ? onPressed : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.goldPrimary,
        disabledBackgroundColor: AppColors.goldDark.withValues(alpha: 0.35),
        foregroundColor: AppColors.feltDeep,
        padding: const EdgeInsets.symmetric(vertical: 15),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radiusButton),
        ),
        elevation: enabled ? 4 : 0,
      ),
      child: Text(
        'SAVE PROFILE',
        style: TextStyle(
          fontWeight: FontWeight.w900,
          letterSpacing: 1.4,
          fontSize: 15,
          color: enabled ? AppColors.feltDeep : AppColors.textSecondary,
        ),
      ),
    );
  }
}
