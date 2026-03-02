import 'package:flutter/material.dart';

import '../../../../core/services/card_back_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimensions.dart';

/// Premium card back — deep green/burgundy base with a gold geometric
/// border pattern and a centred emblem, drawn entirely in [CustomPaint].
class CardBackWidget extends StatelessWidget {
  const CardBackWidget({
    super.key,
    this.width = AppDimensions.cardWidthMedium,
  });

  final double width;

  @override
  Widget build(BuildContext context) {
    final height = AppDimensions.cardHeight(width);

    return ValueListenableBuilder<String>(
      valueListenable: CardBackService.instance.selectedDesignId,
      builder: (context, selectedDesign, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: CardBackService.instance.animatedEffectsEnabled,
          builder: (context, animatedEnabled, _) {
            return Container(
              width: width,
              height: height,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppDimensions.radiusCard),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
                border: Border.all(
                  color: AppColors.goldDark,
                  width: 1,
                ),
              ),
              child: ClipRRect(
                borderRadius:
                    BorderRadius.circular(AppDimensions.radiusCard - 1),
                child: _buildBackFace(
                  selectedDesign: selectedDesign,
                  animatedEnabled: animatedEnabled,
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildBackFace({
    required String selectedDesign,
    required bool animatedEnabled,
  }) {
    // Cardbackcover (or any asset path) selection
    if (selectedDesign.startsWith('assets/')) {
      final covers = CardBackService.instance.cardBackCoverDesigns.value;
      final fallbackPath = covers.isNotEmpty ? covers.first.assetPath! : null;
      return Image.asset(
        selectedDesign,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) {
          if (fallbackPath != null) {
            return Image.asset(fallbackPath, fit: BoxFit.cover);
          }
          return Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1D2B50), Color(0xFF2D1B2D)],
              ),
            ),
          );
        },
      );
    }
    if (selectedDesign == 'uploaded') {
      final uploaded = CardBackService.instance.uploadedAnimatedAssetPath.value;
      if (uploaded != null) {
        final covers = CardBackService.instance.cardBackCoverDesigns.value;
        final fallbackPath = covers.isNotEmpty ? covers.first.assetPath! : null;
        return Image.asset(
          uploaded,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) {
            if (fallbackPath != null) {
              return Image.asset(fallbackPath, fit: BoxFit.cover);
            }
            return Image.asset(
              'assets/images/cardbackcover/two lions.png',
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF1D2B50), Color(0xFF2D1B2D)],
                  ),
                ),
              ),
            );
          },
        );
      }
    }

    Widget fallback;

    switch (selectedDesign) {
      case 'obsidian':
        fallback = Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF171717), Color(0xFF2B2B2B)],
            ),
          ),
        );
        break;
      case 'ruby':
        fallback = Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF5C0A12), Color(0xFF9D2235)],
            ),
          ),
        );
        break;
      case 'royal':
        fallback = Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1D2B64), Color(0xFF5A189A)],
            ),
          ),
        );
        if (animatedEnabled) {
          fallback = _AnimatedRoyalBack(child: fallback);
        }
        break;
      case 'classic':
      default:
        final covers = CardBackService.instance.cardBackCoverDesigns.value;
        final path = covers.isNotEmpty ? covers.first.assetPath! : null;
        fallback = path != null
            ? Image.asset(path, fit: BoxFit.cover)
            : Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF1D2B50), Color(0xFF2D1B2D)],
                  ),
                ),
              );
        break;
    }

    // If you drop a matching GIF (e.g. assets/animated_cards/royal.gif),
    // it overrides the built-in back for that design.
    return Image.asset(
      'assets/animated_cards/$selectedDesign.gif',
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => fallback,
    );
  }
}

class _AnimatedRoyalBack extends StatefulWidget {
  const _AnimatedRoyalBack({required this.child});

  final Widget child;

  @override
  State<_AnimatedRoyalBack> createState() => _AnimatedRoyalBackState();
}

class _AnimatedRoyalBackState extends State<_AnimatedRoyalBack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final shimmerX = (_controller.value * 2.4) - 1.2;
        return Stack(
          fit: StackFit.expand,
          children: [
            child!,
            IgnorePointer(
              child: Transform.translate(
                offset: Offset(shimmerX * 180, 0),
                child: Container(
                  width: 80,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x00FFFFFF),
                        Color(0x44FFFFFF),
                        Color(0x00FFFFFF),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
      child: widget.child,
    );
  }
}
