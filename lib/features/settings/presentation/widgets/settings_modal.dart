import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/services/card_back_service.dart';
import '../../../gameplay/presentation/controllers/audio_service.dart';
import '../../../../services/audio_service.dart' as game_audio;

// Create a simple provider to manage SharedPreferences settings globally
final settingsProvider =
    StateNotifierProvider<SettingsNotifier, SettingsState>((ref) {
  return SettingsNotifier();
});

class SettingsState {
  final double soundVolume;

  SettingsState({this.soundVolume = 100.0});

  SettingsState copyWith({double? soundVolume}) {
    return SettingsState(
      soundVolume: soundVolume ?? this.soundVolume,
    );
  }
}

class SettingsNotifier extends StateNotifier<SettingsState> {
  SharedPreferences? _prefs;

  SettingsNotifier() : super(SettingsState()) {
    _initPrefs();
  }

  Future<void> _initPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    state = SettingsState(
      soundVolume: _prefs?.getDouble('soundVolume') ?? 100.0,
    );
  }

  void updateSound(double val) {
    state = state.copyWith(soundVolume: val);
    _prefs?.setDouble('soundVolume', val);
    // Propagate to the low-level audio singleton immediately so sounds
    // reflect the new volume without requiring an app restart.
    game_audio.AudioService.instance.setVolume(val / 100.0);
  }
}

class SettingsModal extends ConsumerWidget {
  const SettingsModal({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final audioService = ref.watch(audioServiceProvider);
    CardBackService.instance.init();
    final media = MediaQuery.of(context);
    final isMobile = math.min(media.size.width, media.size.height) < 600;
    final initialSize = isMobile ? 0.9 : 0.82;
    final minSize = isMobile ? 0.55 : 0.45;
    final maxSize = isMobile ? 0.96 : 0.9;

    return DraggableScrollableSheet(
      initialChildSize: initialSize,
      minChildSize: minSize,
      maxChildSize: maxSize,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1E1E1E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            top: false,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final horizontal = isMobile ? 16.0 : 24.0;
                final titleSize = isMobile ? 22.0 : 24.0;
                final contentWidth =
                    constraints.maxWidth > 760 ? 760.0 : constraints.maxWidth;

                return Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: contentWidth,
                    child: ListView(
                      controller: scrollController,
                      padding: EdgeInsets.fromLTRB(
                        horizontal,
                        16,
                        horizontal,
                        16 + media.viewInsets.bottom,
                      ),
                      children: [
                        // Handle bump
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            margin: const EdgeInsets.only(bottom: 24),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade600,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        Text(
                          'Settings',
                          style: TextStyle(
                            fontSize: titleSize,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 24),
                        _SliderRow(
                          label: 'Sound Effects Volume',
                          value: settings.soundVolume,
                          min: 0,
                          max: 100,
                          onChanged: notifier.updateSound,
                        ),
                        const Divider(height: 40, color: Colors.grey),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: isMobile,
                          title: const Text('Enable Sound Effects'),
                          value: audioService.soundEffectsEnabled,
                          onChanged: (val) =>
                              audioService.setSoundEffectsEnabled(val),
                          activeThumbColor: Colors.amber,
                        ),
                        ValueListenableBuilder<bool>(
                          valueListenable:
                              CardBackService.instance.animatedEffectsEnabled,
                          builder: (context, enabled, _) {
                            return SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: isMobile,
                              title: const Text('Animated Card Effects'),
                              value: enabled,
                              onChanged: (val) => CardBackService.instance
                                  .setAnimatedEffectsEnabled(val),
                              activeThumbColor: Colors.amber,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _SliderRow extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChanged;
  final String? valueLabel;

  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    required this.onChanged,
    this.valueLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 16)),
            Text(valueLabel ?? '${value.toInt()}%',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.amber)),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          activeColor: Colors.amber,
          onChanged: onChanged,
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
