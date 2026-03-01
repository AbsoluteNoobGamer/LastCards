import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:profanity_filter/profanity_filter.dart';

import '../../../../core/providers/profile_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimensions.dart';

const Set<String> kReservedNames = {'Player 2', 'Player 3', 'Player 4'};
const int kMaxNameLength = 17;

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

  bool get _canSave {
    final currentName = ref.read(profileProvider).name;
    final nameChanged = _nameController.text.trim() != currentName;
    return nameChanged && _nameValid && _nameError == null;
  }

  @override
  void initState() {
    super.initState();
    final profile = ref.read(profileProvider);
    _nameController = TextEditingController(text: profile.name);
    _validateName(profile.name);
    _nameController.addListener(() => _validateName(_nameController.text));
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
    await ref.read(profileProvider.notifier).updateProfile(
          name: _nameController.text.trim(),
        );
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

  @override
  Widget build(BuildContext context) {
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
              onPressed: _showUnsupported,
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
            TextField(
              controller: _nameController,
              maxLength: kMaxNameLength,
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
                onPressed: _canSave ? _saveProfile : null,
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
                  elevation: _canSave ? 4 : 0,
                ),
                child: Text(
                  'SAVE PROFILE',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                    fontSize: 15,
                    color: _canSave
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
