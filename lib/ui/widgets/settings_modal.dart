import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/services/audio_service.dart';

// Create a simple provider to manage SharedPreferences settings globally
final settingsProvider =
    StateNotifierProvider<SettingsNotifier, SettingsState>((ref) {
  return SettingsNotifier();
});

class SettingsState {
  final double soundVolume;
  final double musicVolume;
  final double animationSpeed;
  final bool vibrateEnabled;
  final bool tooltipsEnabled;
  final bool darkMode;

  SettingsState({
    this.soundVolume = 100.0,
    this.musicVolume = 100.0,
    this.animationSpeed = 1.0,
    this.vibrateEnabled = true,
    this.tooltipsEnabled = true,
    this.darkMode = true,
  });

  SettingsState copyWith({
    double? soundVolume,
    double? musicVolume,
    double? animationSpeed,
    bool? vibrateEnabled,
    bool? tooltipsEnabled,
    bool? darkMode,
  }) {
    return SettingsState(
      soundVolume: soundVolume ?? this.soundVolume,
      musicVolume: musicVolume ?? this.musicVolume,
      animationSpeed: animationSpeed ?? this.animationSpeed,
      vibrateEnabled: vibrateEnabled ?? this.vibrateEnabled,
      tooltipsEnabled: tooltipsEnabled ?? this.tooltipsEnabled,
      darkMode: darkMode ?? this.darkMode,
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
      musicVolume: _prefs?.getDouble('musicVolume') ?? 100.0,
      animationSpeed: _prefs?.getDouble('animationSpeed') ?? 1.0,
      vibrateEnabled: _prefs?.getBool('vibrateEnabled') ?? true,
      tooltipsEnabled: _prefs?.getBool('tooltipsEnabled') ?? true,
      darkMode: _prefs?.getBool('darkMode') ?? true,
    );
  }

  void updateSound(double val) {
    state = state.copyWith(soundVolume: val);
    _prefs?.setDouble('soundVolume', val);
  }

  void updateMusic(double val) {
    state = state.copyWith(musicVolume: val);
    _prefs?.setDouble('musicVolume', val);
  }

  void updateAnimSpeed(double val) {
    state = state.copyWith(animationSpeed: val);
    _prefs?.setDouble('animationSpeed', val);
  }

  void toggleVibrate(bool val) {
    state = state.copyWith(vibrateEnabled: val);
    _prefs?.setBool('vibrateEnabled', val);
  }

  void toggleTooltips(bool val) {
    state = state.copyWith(tooltipsEnabled: val);
    _prefs?.setBool('tooltipsEnabled', val);
  }

  void toggleDarkMode(bool val) {
    state = state.copyWith(darkMode: val);
    _prefs?.setBool('darkMode', val);
  }
}

class SettingsModal extends ConsumerWidget {
  const SettingsModal({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final audioService = ref.watch(audioServiceProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1E1E1E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(24),
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

              const Text(
                'Settings',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),

              // Sliders
              _SliderRow(
                label: 'Sound Effects',
                value: settings.soundVolume,
                min: 0,
                max: 100,
                onChanged: notifier.updateSound,
              ),
              _SliderRow(
                label: 'Music',
                value: settings.musicVolume,
                min: 0,
                max: 100,
                onChanged: notifier.updateMusic,
              ),
              _SliderRow(
                label: 'Animation Speed',
                value: settings.animationSpeed,
                min: 0.5,
                max: 2.0,
                divisions: 3, // 0.5, 1.0, 1.5, 2.0
                onChanged: notifier.updateAnimSpeed,
                valueLabel: '${settings.animationSpeed}x',
              ),

              const Divider(height: 40, color: Colors.grey),

              // Toggles
              SwitchListTile(
                title: const Text('Mute All Audio'),
                value: audioService.isMuted,
                onChanged: (val) => audioService.toggleMute(),
                activeColor: Colors.amber,
              ),
              SwitchListTile(
                title: const Text('Vibration Feedback'),
                value: settings.vibrateEnabled,
                onChanged: notifier.toggleVibrate,
                activeColor: Colors.amber,
              ),
              SwitchListTile(
                title: const Text('Show Tooltips'),
                value: settings.tooltipsEnabled,
                onChanged: notifier.toggleTooltips,
                activeColor: Colors.amber,
              ),
              SwitchListTile(
                title: const Text('Dark Mode'),
                value: settings.darkMode,
                onChanged: notifier.toggleDarkMode,
                activeColor: Colors.amber,
              ),
            ],
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
