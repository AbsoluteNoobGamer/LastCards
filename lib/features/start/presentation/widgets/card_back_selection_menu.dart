import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/services/card_back_service.dart';
import '../../../../core/services/player_level_service.dart';
import '../../../../core/theme/app_dimensions.dart';

/// Defines the supported style sections so we can add more tabs/sections later.
enum CardStyleSection {
  backCover,
}

/// Reusable card style selection UI.
///
/// This widget intentionally reuses [CardBackService] listeners and
/// [CardBackService.selectDesign] so selection behavior stays centralized.
class CardBackSelectionMenu extends StatefulWidget {
  const CardBackSelectionMenu({
    super.key,
    this.section = CardStyleSection.backCover,
    this.onSelectionApplied,
    this.showSectionTitle = true,
  });

  final CardStyleSection section;
  final VoidCallback? onSelectionApplied;
  final bool showSectionTitle;

  @override
  State<CardBackSelectionMenu> createState() => _CardBackSelectionMenuState();
}

enum _CardStyleMenuView {
  root,
  animatedBacks,
  coverBacks,
  jokerCovers,
  cardFaces,
}

class _CardBackSelectionMenuState extends State<CardBackSelectionMenu> {
  _CardStyleMenuView _view = _CardStyleMenuView.root;

  @override
  Widget build(BuildContext context) {
    CardBackService.instance.init();

    if (widget.section != CardStyleSection.backCover) {
      return const SizedBox.shrink();
    }

    return ValueListenableBuilder<String>(
      valueListenable: CardBackService.instance.selectedDesignId,
      builder: (context, selectedDesignId, _) {
        final content = switch (_view) {
          _CardStyleMenuView.root => _buildRootMenu(selectedDesignId),
          _CardStyleMenuView.animatedBacks =>
            _buildAnimatedStylesMenu(selectedDesignId),
          _CardStyleMenuView.coverBacks =>
            _buildCoverStylesMenu(selectedDesignId),
          _CardStyleMenuView.jokerCovers =>
            _buildJokerCoversMenu(selectedDesignId),
          _CardStyleMenuView.cardFaces => _buildCardFacesMenu(),
        };

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.showSectionTitle &&
                _view == _CardStyleMenuView.root) ...[
              const Text(
                'Card Back',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
            ],
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeOutCubic,
              child: KeyedSubtree(
                key: ValueKey(_view),
                child: content,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildRootMenu(String selectedDesignId) {
    final isAnimatedSelected = _isAnimatedSelection(selectedDesignId);
    final isCoverSelected = !isAnimatedSelected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CardStyleTile(
          option: const _CardStyleOption(
            id: 'animated_root',
            title: 'Animated Cards',
            subtitle: 'Back Cover',
            icon: Icons.auto_awesome_rounded,
          ),
          isSelected: isAnimatedSelected,
          trailing:
              const Icon(Icons.chevron_right_rounded, color: Colors.white70),
          onTap: () => setState(() => _view = _CardStyleMenuView.animatedBacks),
        ),
        const SizedBox(height: 8),
        _CardStyleTile(
          option: const _CardStyleOption(
            id: 'cover_root',
            title: 'Cards',
            subtitle: 'Back Cover',
            icon: Icons.style_rounded,
          ),
          isSelected: isCoverSelected,
          trailing:
              const Icon(Icons.chevron_right_rounded, color: Colors.white70),
          onTap: () => setState(() => _view = _CardStyleMenuView.coverBacks),
        ),
        const SizedBox(height: 8),
        _CardStyleTile(
          option: const _CardStyleOption(
            id: 'joker_root',
            title: 'Joker',
            subtitle: 'Cover',
            icon: Icons.celebration_rounded,
          ),
          isSelected: false,
          trailing:
              const Icon(Icons.chevron_right_rounded, color: Colors.white70),
          onTap: () => setState(() => _view = _CardStyleMenuView.jokerCovers),
        ),
        const SizedBox(height: 8),
        _CardStyleTile(
          option: const _CardStyleOption(
            id: 'cardfaces_root',
            title: 'Card Faces',
            subtitle: 'Default or classic',
            icon: Icons.dashboard_rounded,
          ),
          isSelected: false,
          trailing:
              const Icon(Icons.chevron_right_rounded, color: Colors.white70),
          onTap: () => setState(() => _view = _CardStyleMenuView.cardFaces),
        ),
      ],
    );
  }

  Widget _buildCardFacesMenu() {
    return ValueListenableBuilder<String>(
      valueListenable: CardBackService.instance.selectedCardFaceSetId,
      builder: (context, selectedId, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SubmenuHeader(
              title: 'Card Faces',
              onBack: () => setState(() => _view = _CardStyleMenuView.root),
            ),
            const SizedBox(height: 8),
            _CardStyleTile(
              option: const _CardStyleOption(
                id: 'default',
                title: 'Default',
                subtitle: 'Traditional face cards',
                icon: Icons.style_rounded,
              ),
              isSelected: selectedId == 'default',
              trailing: selectedId == 'default'
                  ? const Icon(Icons.check_rounded, color: Colors.green)
                  : null,
              onTap: () async {
                await CardBackService.instance.selectCardFaceSet('default');
                HapticFeedback.selectionClick();
                setState(() {});
              },
            ),
            const SizedBox(height: 8),
            _CardStyleTile(
              option: const _CardStyleOption(
                id: 'classic',
                title: 'Classic',
                subtitle: 'Symbols and pips',
                icon: Icons.abc_rounded,
              ),
              isSelected: selectedId == 'classic',
              trailing: selectedId == 'classic'
                  ? const Icon(Icons.check_rounded, color: Colors.green)
                  : null,
              onTap: () async {
                await CardBackService.instance.selectCardFaceSet('classic');
                HapticFeedback.selectionClick();
                setState(() {});
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildAnimatedStylesMenu(String selectedDesignId) {
    return ValueListenableBuilder<int>(
      valueListenable: PlayerLevelService.instance.currentLevel,
      builder: (context, currentLevel, _) {
        return ValueListenableBuilder<List<CardBackDesign>>(
          valueListenable: CardBackService.instance.animatedGifDesigns,
          builder: (context, animatedGifDesigns, _) {
            final options = <_CardStyleOption>[
              ...CardBackService.designs.map(
                (design) => _CardStyleOption(
                  id: design.id,
                  title: design.label,
                  subtitle: null,
                  requiredUnlockLevel: design.unlockLevel,
                  icon: Icons.auto_awesome_rounded,
                  previewDesignId: design.id,
                ),
              ),
              ...animatedGifDesigns.map(
                (gifDesign) => _CardStyleOption(
                  id: gifDesign.id,
                  title: gifDesign.label,
                  subtitle: null,
                  requiredUnlockLevel: null,
                  icon: Icons.auto_awesome_rounded,
                  previewAssetPath: gifDesign.id,
                ),
              ),
            ];

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SubmenuHeader(
                  title: 'Animated Cards',
                  onBack: () =>
                      setState(() => _view = _CardStyleMenuView.root),
                ),
                ...options.map(
                  (option) {
                    final requiredLevel = option.requiredUnlockLevel;
                    final unlocked = option.id == 'uploaded'
                        ? true
                        : requiredLevel != null
                            ? currentLevel >= requiredLevel
                            : CardBackService.instance.isUnlocked(option.id);
                    final isSelected = selectedDesignId == option.id;

                    final lockedTitle = requiredLevel == null
                        ? '${option.title} (locked)'
                        : '${option.title} (Level $requiredLevel)';

                    final lockedSubtitle = requiredLevel != null
                        ? 'Your level: $currentLevel / Required: $requiredLevel'
                        : option.subtitle;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _CardStyleTile(
                        option: _CardStyleOption(
                          id: option.id,
                          title: unlocked ? option.title : lockedTitle,
                          subtitle: unlocked ? option.subtitle : lockedSubtitle,
                          icon: option.icon,
                        ),
                        isSelected: isSelected,
                        onTap: () => _selectOption(context, option.id),
                      ),
                    );
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildJokerCoversMenu(String selectedDesignId) {
    return ValueListenableBuilder<int>(
      valueListenable: PlayerLevelService.instance.currentLevel,
      builder: (context, currentLevel, _) {
        return ValueListenableBuilder<String>(
          valueListenable: CardBackService.instance.selectedJokerCoverId,
          builder: (context, selectedJokerId, _) {
            return ValueListenableBuilder<List<CardBackDesign>>(
              valueListenable: CardBackService.instance.jokerCoverDesigns,
              builder: (context, jokerDesigns, _) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SubmenuHeader(
                      title: 'Joker Cover',
                      onBack: () =>
                          setState(() => _view = _CardStyleMenuView.root),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _CardStyleTile(
                        option: const _CardStyleOption(
                          id: 'classic',
                          title: 'Classic',
                          subtitle: 'Default design',
                          icon: Icons.celebration_rounded,
                          previewDesignId: 'classic',
                        ),
                        isSelected: selectedJokerId == 'classic',
                        onTap: () => _selectJokerOption(context, 'classic'),
                      ),
                    ),
                    if (jokerDesigns.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'Add images to assets/images/jokercover/',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ),
                    ...jokerDesigns.map((design) {
                      final unlocked = currentLevel >= design.unlockLevel;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _CardStyleTile(
                          option: _CardStyleOption(
                            id: design.id,
                            title: unlocked
                                ? design.label
                                : '${design.label} (Level ${design.unlockLevel})',
                            subtitle: unlocked
                                ? null
                                : 'Your level: $currentLevel / Required: ${design.unlockLevel}',
                            icon: Icons.celebration_rounded,
                            previewAssetPath: design.assetPath,
                          ),
                          isSelected: selectedJokerId == design.id,
                          onTap: () => _selectJokerOption(context, design.id),
                        ),
                      );
                    }),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _selectJokerOption(BuildContext context, String designId) async {
    final ok = await CardBackService.instance.selectJokerCover(designId);
    if (!context.mounted) return;
    if (ok) {
      HapticFeedback.selectionClick();
      widget.onSelectionApplied?.call();
      return;
    }

    // Locked: show why selection failed.
    CardBackDesign? design;
    for (final candidate in CardBackService.instance.jokerCoverDesigns.value) {
      if (candidate.id == designId) {
        design = candidate;
        break;
      }
    }

    final requiredLevel = design?.unlockLevel;
    final msg = requiredLevel == null
        ? 'Could not select this joker cover.'
        : 'Unlock ${design!.label} at Level $requiredLevel.';

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Widget _buildCoverStylesMenu(String selectedDesignId) {
    return ValueListenableBuilder<List<CardBackDesign>>(
      valueListenable: CardBackService.instance.cardBackCoverDesigns,
      builder: (context, coverDesigns, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SubmenuHeader(
              title: 'Cards (Back Cover)',
              onBack: () => setState(() => _view = _CardStyleMenuView.root),
            ),
            if (coverDesigns.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No styles found in assets/images/cardbackcover',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ...coverDesigns.map(
              (design) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _CardStyleTile(
                  option: _CardStyleOption(
                    id: design.id,
                    title: design.label,
                    subtitle: null,
                    icon: Icons.style_rounded,
                    previewAssetPath: design.assetPath,
                  ),
                  isSelected: selectedDesignId == design.id,
                  onTap: () => _selectOption(context, design.id),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  bool _isAnimatedSelection(String selectedDesignId) {
    if (selectedDesignId.startsWith('assets/animated_cards/')) return true;
    return CardBackService.designs.any((d) => d.id == selectedDesignId);
  }

  Future<void> _selectOption(BuildContext context, String designId) async {
    final ok = await CardBackService.instance.selectDesign(designId);
    if (!context.mounted) return;

    if (!ok) {
      CardBackDesign? design;
      for (final candidate in CardBackService.designs) {
        if (candidate.id == designId) {
          design = candidate;
          break;
        }
      }
      final isLockedAnimated =
          design != null && !CardBackService.instance.isUnlocked(design.id);
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              isLockedAnimated
                  ? 'Unlock ${design.label} at Level ${design.unlockLevel}.'
                  : 'Could not select this card style.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }

    HapticFeedback.selectionClick();
    widget.onSelectionApplied?.call();
  }
}

/// Opens the Card Styles sheet (same UI as Start → Card Styles icon row).
void showCardStylesModal(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const CardStylesModal(),
  );
}

class CardStylesModal extends StatelessWidget {
  const CardStylesModal({super.key});

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isMobile = math.min(media.size.width, media.size.height) <
        AppDimensions.breakpointMobile;
    // Taller sheet so nested sections (animated / covers / jokers / faces) breathe.
    final initialSize = isMobile ? 0.78 : 0.68;
    final minSize = isMobile ? 0.42 : 0.38;
    final maxSize = isMobile ? 0.92 : 0.88;

    return DraggableScrollableSheet(
      initialChildSize: initialSize,
      minChildSize: minSize,
      maxChildSize: maxSize,
      expand: false,
      builder: (context, scrollController) {
        final bottomInset = media.viewInsets.bottom;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1E),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            border: Border.all(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.22),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 24,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            child: SafeArea(
              top: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 10),
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade600,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Card styles',
                          style: GoogleFonts.inter(
                            fontSize: isMobile ? 21 : 23,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Customize backs, joker art, and faces. Some options unlock as you level up.',
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.4,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: EdgeInsets.fromLTRB(
                        16,
                        16,
                        16,
                        20 + bottomInset,
                      ),
                      children: [
                        CardBackSelectionMenu(
                          showSectionTitle: false,
                          onSelectionApplied: () =>
                              Navigator.of(context).maybePop(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CardStyleOption {
  const _CardStyleOption({
    required this.id,
    required this.title,
    this.subtitle,
    this.requiredUnlockLevel,
    required this.icon,
    this.previewAssetPath,
    this.previewDesignId,
  });

  final String id;
  final String title;
  final String? subtitle;
  final int? requiredUnlockLevel;
  final IconData icon;
  final String? previewAssetPath;
  final String? previewDesignId;
}

class _CardStyleTile extends StatelessWidget {
  const _CardStyleTile({
    required this.option,
    required this.isSelected,
    required this.onTap,
    this.trailing,
  });

  final _CardStyleOption option;
  final bool isSelected;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected
          ? Colors.amber.withValues(alpha: 0.15)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(AppDimensions.radiusCard),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDimensions.radiusCard),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              _StylePreview(
                assetPath: option.previewAssetPath,
                previewDesignId: option.previewDesignId,
                fallbackIcon: option.icon,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.subtitle == 'Back Cover'
                          ? '${option.title} (${option.subtitle})'
                          : option.title,
                      style: TextStyle(
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.w500,
                        color: isSelected ? Colors.amber : Colors.white,
                      ),
                    ),
                    if (option.subtitle != null &&
                        option.subtitle != 'Back Cover') ...[
                      const SizedBox(height: 2),
                      Text(
                        option.subtitle!,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing!,
              if (trailing == null && isSelected)
                const Icon(
                  Icons.check_circle,
                  color: Colors.amber,
                  size: 22,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StylePreview extends StatelessWidget {
  const _StylePreview({
    required this.assetPath,
    required this.previewDesignId,
    required this.fallbackIcon,
  });

  final String? assetPath;
  final String? previewDesignId;
  final IconData fallbackIcon;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(8);

    return Container(
      width: 36,
      height: AppDimensions.cardHeight(36).clamp(50.0, 54.0),
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        border: Border.all(color: const Color(0x55FFFFFF)),
        color: const Color(0x22111111),
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: assetPath != null
            ? Image.asset(
                assetPath!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    Icon(fallbackIcon, color: Colors.white70, size: 18),
              )
            : _AnimatedStyleFallback(
                designId: previewDesignId,
                fallbackIcon: fallbackIcon,
              ),
      ),
    );
  }
}

class _AnimatedStyleFallback extends StatelessWidget {
  const _AnimatedStyleFallback({
    required this.designId,
    required this.fallbackIcon,
  });

  final String? designId;
  final IconData fallbackIcon;

  @override
  Widget build(BuildContext context) {
    final gradient = switch (designId) {
      'obsidian' => const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF171717), Color(0xFF2B2B2B)],
        ),
      'ruby' => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF5C0A12), Color(0xFF9D2235)],
        ),
      'royal' => const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1D2B64), Color(0xFF5A189A)],
        ),
      'classic' => const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1D2B50), Color(0xFF2D1B2D)],
        ),
      _ => null,
    };

    if (gradient == null) {
      return Icon(fallbackIcon, color: Colors.white70, size: 18);
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(decoration: BoxDecoration(gradient: gradient)),
        Center(
          child: Icon(
            Icons.auto_awesome_rounded,
            color: Colors.white.withValues(alpha: 0.7),
            size: 16,
          ),
        ),
      ],
    );
  }
}

class _SubmenuHeader extends StatelessWidget {
  const _SubmenuHeader({
    required this.title,
    required this.onBack,
  });

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded),
            color: Colors.white,
            splashRadius: 20,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 28, height: 28),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
