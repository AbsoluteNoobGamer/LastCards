import 'package:flutter/material.dart';

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
        borderRadius: BorderRadius.circular(AppDimensions.radiusCard - 1),
        child: Image.asset(
          'assets/images/card_back.jpg',
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}
