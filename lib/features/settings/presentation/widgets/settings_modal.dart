import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/services/card_back_service.dart';
import '../../../gameplay/presentation/controllers/audio_service.dart';
import '../../../../services/audio_service.dart' as game_audio;
import '../../../../services/start_screen_bgm.dart';
import '../../../../core/monetization/monetization_config.dart';
import '../../../../core/monetization/monetization_provider.dart';

// Create a simple provider to manage SharedPreferences settings globally
final settingsProvider =
    StateNotifierProvider<SettingsNotifier, SettingsState>((ref) {
  return SettingsNotifier();
});

class SettingsState {
  final double soundVolume;
  /// 0–100; scales turn timer tick on top of [soundVolume] (watch-style tick each second).
  final double timerTickVolume;
  /// 0–100; applied to start-screen background music only.
  final double musicVolume;
  final bool reduceMotion;

  SettingsState({
    this.soundVolume = 100.0,
    this.timerTickVolume = 65.0,
    this.musicVolume = 55.0,
    this.reduceMotion = false,
  });

  SettingsState copyWith({
    double? soundVolume,
    double? timerTickVolume,
    double? musicVolume,
    bool? reduceMotion,
  }) {
    return SettingsState(
      soundVolume: soundVolume ?? this.soundVolume,
      timerTickVolume: timerTickVolume ?? this.timerTickVolume,
      musicVolume: musicVolume ?? this.musicVolume,
      reduceMotion: reduceMotion ?? this.reduceMotion,
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
      timerTickVolume: _prefs?.getDouble('timer_tick_volume') ?? 65.0,
      musicVolume: _prefs?.getDouble('musicVolume') ?? 55.0,
      reduceMotion: _prefs?.getBool('reduceMotion') ?? false,
    );
    StartScreenBgm.instance
        .setMusicVolume(state.musicVolume / 100.0);
  }

  void setReduceMotion(bool value) {
    state = state.copyWith(reduceMotion: value);
    _prefs?.setBool('reduceMotion', value);
  }

  void updateSound(double val) {
    state = state.copyWith(soundVolume: val);
    _prefs?.setDouble('soundVolume', val);
    // Propagate to the low-level audio singleton immediately so sounds
    // reflect the new volume without requiring an app restart.
    game_audio.AudioService.instance.setVolume(val / 100.0);
  }

  Future<void> updateTimerTickVolume(double val) async {
    state = state.copyWith(timerTickVolume: val);
    _prefs?.setDouble('timer_tick_volume', val);
    await game_audio.AudioService.instance.setTimerTickVolume(val / 100.0);
  }

  void updateMusic(double val) {
    state = state.copyWith(musicVolume: val);
    _prefs?.setDouble('musicVolume', val);
    StartScreenBgm.instance.setMusicVolume(val / 100.0);
  }
}

/// User preference; [StackAndFlowApp] also merges this into [MediaQuery.disableAnimations].
final reduceMotionProvider = Provider<bool>((ref) {
  return ref.watch(settingsProvider).reduceMotion;
});

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
                        _SliderRow(
                          label: 'Turn timer tick',
                          subtitle:
                              'Quiet watch-style tick each second on your turn. '
                              'Scales with sound effects volume above.',
                          value: settings.timerTickVolume,
                          min: 0,
                          max: 100,
                          onChanged: (v) {
                            unawaited(notifier.updateTimerTickVolume(v));
                          },
                        ),
                        _SliderRow(
                          label: 'Music Volume',
                          value: settings.musicVolume,
                          min: 0,
                          max: 100,
                          onChanged: notifier.updateMusic,
                        ),
                        const Divider(height: 40, color: Colors.grey),
                        if (kSupportsStoreMonetization()) ...[
                          Consumer(
                            builder: (context, ref, _) {
                              final mono = ref.watch(monetizationProvider);
                              final notifier =
                                  ref.read(monetizationProvider.notifier);
                              if (mono.adsRemoved) {
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  dense: isMobile,
                                  leading: Icon(
                                    Icons.block_flipped,
                                    color: Colors.green.shade400,
                                  ),
                                  title: const Text('Ads removed'),
                                  subtitle: Text(
                                    'Thanks for supporting Last Cards.',
                                    style: TextStyle(
                                      fontSize: isMobile ? 11 : 12,
                                      color: Colors.grey.shade500,
                                    ),
                                  ),
                                );
                              }
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    dense: isMobile,
                                    leading: const Icon(
                                      Icons.ads_click_rounded,
                                      color: Colors.amber,
                                    ),
                                    title: const Text('Remove ads'),
                                    subtitle: Text(
                                      mono.removeAdsProduct != null
                                          ? '${mono.removeAdsProduct!.title} — ${mono.removeAdsProduct!.price} (one-time)'
                                          : 'Product not available yet. Add “remove_ads_lifetime” in Play Console and App Store Connect.',
                                      style: TextStyle(
                                        fontSize: isMobile ? 11 : 12,
                                        color: Colors.grey.shade500,
                                      ),
                                    ),
                                    trailing: mono.purchaseInFlight
                                        ? const SizedBox(
                                            width: 28,
                                            height: 28,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : FilledButton(
                                            onPressed: mono.removeAdsProduct ==
                                                    null
                                                ? null
                                                : () => notifier
                                                    .purchaseRemoveAds(),
                                            child: const Text('Buy'),
                                          ),
                                  ),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: TextButton(
                                      onPressed: mono.purchaseInFlight
                                          ? null
                                          : () => notifier.restorePurchases(),
                                      child: const Text('Restore purchases'),
                                    ),
                                  ),
                                  if (mono.lastError != null)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Text(
                                        mono.lastError!,
                                        style: TextStyle(
                                          color: Colors.red.shade300,
                                          fontSize: isMobile ? 12 : 13,
                                        ),
                                      ),
                                    ),
                                ],
                              );
                            },
                          ),
                          const Divider(height: 40, color: Colors.grey),
                        ],
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: isMobile,
                          title: const Text('Reduce Motion'),
                          subtitle: Text(
                            'Less animation for card flights, table ambience, and win effects.',
                            style: TextStyle(
                              fontSize: isMobile ? 11 : 12,
                              color: Colors.grey.shade500,
                            ),
                          ),
                          value: settings.reduceMotion,
                          onChanged: (val) => notifier.setReduceMotion(val),
                          activeThumbColor: Colors.amber,
                        ),
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
  final String? subtitle;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  const _SliderRow({
    required this.label,
    this.subtitle,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontSize: 16)),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                          height: 1.25,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Text('${value.toInt()}%',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.amber)),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          activeColor: Colors.amber,
          onChanged: onChanged,
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
