import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:profanity_filter/profanity_filter.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/providers/profile_provider.dart';
import '../../../../core/services/nsfw_scan_service.dart';

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
/// Allows the local player to:
/// - Upload a custom avatar (gallery or camera) with NSFW scanning.
/// - Edit their display name with real-time validation.
/// - Save valid changes to SharedPreferences via [ProfileNotifier].
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  late TextEditingController _nameController;
  final ProfanityFilter _filter = ProfanityFilter();
  final ImagePicker _picker = ImagePicker();

  // Pending image (not yet saved)
  String? _pendingAvatarPath;
  bool _pendingAvatarValid = false;

  // Validation state
  String? _nameError;
  bool _nameValid = false;

  bool get _canSave {
    final currentName = ref.read(profileProvider).name;
    final nameChanged = _nameController.text.trim() != currentName;
    final avatarChanged = _pendingAvatarPath != null && _pendingAvatarValid;
    return (nameChanged || avatarChanged) && _nameValid && _nameError == null;
  }

  @override
  void initState() {
    super.initState();
    final profile = ref.read(profileProvider);
    _nameController = TextEditingController(text: profile.name);
    _validateName(profile.name);
    _nameController.addListener(() => _validateName(_nameController.text));

    // Load the latest profile from SharedPreferences asynchronously so saved
    // name and avatar are reflected if they haven't been loaded yet.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(profileProvider.notifier).loadFromPrefs();
      if (mounted) {
        final latest = ref.read(profileProvider);
        _nameController.text = latest.name;
        _validateName(latest.name);
      }
    });
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
          _pendingAvatarValid = false;
        });
      } else {
        setState(() {
          _pendingAvatarPath = xfile.path;
          _pendingAvatarValid = true;
        });
      }
    } catch (_) {
      if (mounted) _showError('Could not load image. Please try again.');
    }
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  Future<void> _saveProfile() async {
    if (!_canSave) return;
    final name = _nameController.text.trim();
    final currentProfile = ref.read(profileProvider);
    final avatarPath =
        _pendingAvatarValid ? _pendingAvatarPath : currentProfile.avatarPath;

    await ref.read(profileProvider.notifier).updateProfile(
          name: name,
          avatarPath: avatarPath,
        );
    if (mounted) Navigator.of(context).pop();
  }

  // ── Source sheet ──────────────────────────────────────────────────────────

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

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    final displayAvatarPath =
        _pendingAvatarValid ? _pendingAvatarPath : profile.avatarPath;

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
              onUpload: _showImageSourceSheet,
            ),
            const SizedBox(height: 32),
            _NameField(
              controller: _nameController,
              maxLength: kMaxNameLength,
              isValid: _nameValid,
              errorText: _nameError,
            ),
            const SizedBox(height: 36),
            SizedBox(
              width: double.infinity,
              child: _SaveButton(
                enabled: _canSave,
                onPressed: _saveProfile,
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
  const _AvatarSection({required this.avatarPath, required this.onUpload});

  final String? avatarPath;
  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    final Widget inner = avatarPath != null
        ? CircleAvatar(
            key: const ValueKey('avatar-image'),
            radius: 55,
            backgroundImage: FileImage(File(avatarPath!)),
            backgroundColor: AppColors.surfacePanel,
          )
        : const CircleAvatar(
            key: ValueKey('avatar-default'),
            radius: 55,
            backgroundColor: AppColors.surfacePanel,
            child: Icon(Icons.person, size: 56, color: AppColors.goldPrimary),
          );

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
  });

  final TextEditingController controller;
  final int maxLength;
  final bool isValid;
  final String? errorText;

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
        TextField(
          key: const ValueKey('name-field'),
          controller: controller,
          maxLength: maxLength,
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
