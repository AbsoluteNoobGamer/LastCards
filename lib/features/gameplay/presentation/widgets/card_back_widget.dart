import 'dart:math' as math;
import 'dart:ui' as ui;

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
      case 'midas':
        fallback = const _MidasBack();
        break;
      case 'ivory_onyx':
        fallback = const _IvoryOnyxBack();
        break;
      case 'platinum':
        fallback = const _PlatinumBack();
        break;
      case 'midnight_forest':
        fallback = const _MidnightForestBack();
        break;
      case 'ocean_depths':
        fallback = const _OceanDepthsBack();
        break;
      case 'inferno':
        fallback = animatedEnabled
            ? const _InfernoBack()
            : const _InfernoBackStatic();
        break;
      case 'circuit_board':
        fallback = const _CircuitBoardBack();
        break;
      case 'mosaic':
        fallback = const _MosaicBack();
        break;
      case 'labyrinth':
        fallback = const _LabyrinthBack();
        break;
      case 'aurora':
        fallback = animatedEnabled
            ? const _AuroraBack()
            : const _AuroraBackStatic();
        break;
      case 'lava_flow':
        fallback = animatedEnabled
            ? const _LavaFlowBack()
            : const _InfernoBackStatic();
        break;
      case 'hologram':
        fallback = animatedEnabled
            ? const _HologramBack()
            : const _HologramBackStatic();
        break;
      case 'galaxy':
        fallback = const _GalaxyBack();
        break;
      case 'vintage_casino':
        fallback = const _VintageCasinoBack();
        break;
      case 'zodiac':
        fallback = const _ZodiacBack();
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
    // Sheen: horizontal translate only; outer card [BoxShadow] is static.
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

// ── Static card backs ───────────────────────────────────────────────────────

class _MidasBack extends StatelessWidget {
  const _MidasBack();

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(painter: _MidasBackPainter());
  }
}

class _MidasBackPainter extends CustomPainter {
  const _MidasBackPainter();

  static const _black = Color(0xFF000000);
  static const _gold = Color(0xFFFFD700);
  static const _darkGold = Color(0xFFB8960C);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = _black);
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = size.shortestSide * 0.38;
    for (int i = 0; i < 6; i++) {
      final r = maxR * (1 - i * 0.14);
      final alpha = 0.85 - i * 0.12;
      final paint = Paint()
        ..style = i.isEven ? PaintingStyle.fill : PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = (i.isEven ? _gold : _darkGold).withValues(alpha: alpha);
      final path = Path();
      for (int j = 0; j < 4; j++) {
        final angle = (j * 90 + 45) * math.pi / 180;
        final pt = Offset(
          center.dx + r * math.cos(angle),
          center.dy + r * math.sin(angle),
        );
        if (j == 0) {
          path.moveTo(pt.dx, pt.dy);
        } else {
          path.lineTo(pt.dx, pt.dy);
        }
      }
      path.close();
      canvas.drawPath(path, paint);
    }
    canvas.drawCircle(
      center,
      maxR + 4,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = _gold.withValues(alpha: 0.9),
    );
  }

  @override
  bool shouldRepaint(covariant _MidasBackPainter oldDelegate) => false;
}

class _IvoryOnyxBack extends StatelessWidget {
  const _IvoryOnyxBack();

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(painter: _IvoryOnyxBackPainter());
  }
}

class _IvoryOnyxBackPainter extends CustomPainter {
  const _IvoryOnyxBackPainter();

  static const _ivory = Color(0xFFF5F0E8);
  static const _black = Color(0xFF000000);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = _ivory);
    const inset = 8.0;
    const corner = 6.0;
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = _black;
    final rect = Rect.fromLTWH(
      inset, inset, size.width - inset * 2, size.height - inset * 2,
    );
    canvas.drawRect(rect, border);
    for (final offset in [
      Offset(inset, inset),
      Offset(size.width - inset - corner, inset),
      Offset(inset, size.height - inset - corner),
      Offset(size.width - inset - corner, size.height - inset - corner),
    ]) {
      canvas.drawRect(
        Rect.fromLTWH(offset.dx, offset.dy, corner, corner),
        Paint()..color = _black,
      );
    }
    final center = Offset(size.width / 2, size.height / 2);
    final diamond = Path()
      ..moveTo(center.dx, center.dy - 14)
      ..lineTo(center.dx + 14, center.dy)
      ..lineTo(center.dx, center.dy + 14)
      ..lineTo(center.dx - 14, center.dy)
      ..close();
    canvas.drawPath(diamond, Paint()..color = _black);
    canvas.drawCircle(center, 4, Paint()..color = _ivory);
  }

  @override
  bool shouldRepaint(covariant _IvoryOnyxBackPainter oldDelegate) => false;
}

class _PlatinumBack extends StatelessWidget {
  const _PlatinumBack();

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(painter: _PlatinumBackPainter());
  }
}

class _PlatinumBackPainter extends CustomPainter {
  const _PlatinumBackPainter();

  static const _charcoal = Color(0xFF1A1A1E);
  static const _silver = Color(0xFFC0C0C0);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = _charcoal);
    final hatch = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = _silver.withValues(alpha: 0.15);
    const step = 6.0;
    for (double d = -size.height; d < size.width + size.height; d += step) {
      canvas.drawLine(Offset(d, 0), Offset(d + size.height, size.height), hatch);
      canvas.drawLine(
        Offset(d + step / 2, 0),
        Offset(d + step / 2 - size.height, size.height),
        hatch,
      );
    }
    canvas.drawRect(
      Rect.fromLTWH(6, 6, size.width - 12, size.height - 12),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = _silver.withValues(alpha: 0.5),
    );
    final center = Offset(size.width / 2, size.height / 2);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          colors: [_silver.withValues(alpha: 0.08), Colors.transparent],
        ).createShader(
          Rect.fromCircle(center: center, radius: size.shortestSide * 0.5),
        ),
    );
  }

  @override
  bool shouldRepaint(covariant _PlatinumBackPainter oldDelegate) => false;
}

class _MidnightForestBack extends StatelessWidget {
  const _MidnightForestBack();

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(painter: _MidnightForestBackPainter());
  }
}

class _MidnightForestBackPainter extends CustomPainter {
  const _MidnightForestBackPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF0A1A0F),
    );
    final treePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = const Color(0xFFC0C0C0).withValues(alpha: 0.20);
    final bases = [0.12, 0.32, 0.52, 0.72, 0.88];
    for (final bx in bases) {
      _drawTree(canvas, Offset(size.width * bx, size.height), size.height * 0.45, treePaint);
    }
    final starPaint = Paint()
      ..color = const Color(0xFFC0C0C0).withValues(alpha: 0.20);
    const phi = 0.6180339887;
    for (int i = 0; i < 30; i++) {
      final x = ((i + 1) * phi) % 1.0 * size.width;
      final y = ((i + 1) * (1 - phi)) % 1.0 * size.height * 0.55;
      canvas.drawCircle(Offset(x, y), 0.8 + (i % 3) * 0.3, starPaint);
    }
  }

  void _drawTree(Canvas canvas, Offset base, double height, Paint paint) {
    canvas.drawLine(base, Offset(base.dx, base.dy - height), paint);
    _drawBranch(canvas, base.dx, base.dy - height * 0.6, height * 0.25, -0.5, paint, 2);
    _drawBranch(canvas, base.dx, base.dy - height * 0.75, height * 0.2, 0.5, paint, 2);
  }

  void _drawBranch(
    Canvas canvas, double x, double y, double len, double dir, Paint paint, int depth,
  ) {
    if (depth <= 0) return;
    final end = Offset(x + len * dir, y - len * 0.7);
    canvas.drawLine(Offset(x, y), end, paint);
    _drawBranch(canvas, end.dx, end.dy, len * 0.55, dir - 0.4, paint, depth - 1);
    _drawBranch(canvas, end.dx, end.dy, len * 0.55, dir + 0.4, paint, depth - 1);
  }

  @override
  bool shouldRepaint(covariant _MidnightForestBackPainter oldDelegate) => false;
}

class _OceanDepthsBack extends StatelessWidget {
  const _OceanDepthsBack();

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(painter: _OceanDepthsBackPainter());
  }
}

class _OceanDepthsBackPainter extends CustomPainter {
  const _OceanDepthsBackPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF050D28), Color(0xFF0A2A3A)],
        ).createShader(Offset.zero & size),
    );
    final jelly = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = const Color(0xFF00E5FF).withValues(alpha: 0.12);
    final positions = [
      Offset(size.width * 0.25, size.height * 0.35),
      Offset(size.width * 0.65, size.height * 0.55),
      Offset(size.width * 0.45, size.height * 0.75),
    ];
    for (final pos in positions) {
      canvas.drawArc(
        Rect.fromCenter(center: pos, width: 28, height: 20),
        math.pi, math.pi, false, jelly,
      );
      for (int t = 0; t < 4; t++) {
        final tx = pos.dx - 8 + t * 5.0;
        canvas.drawLine(
          Offset(tx, pos.dy + 10),
          Offset(tx + math.sin(t) * 2, pos.dy + 28),
          jelly,
        );
      }
    }
    final dotPaint = Paint()
      ..color = const Color(0xFF00E5FF).withValues(alpha: 0.15);
    const phi = 0.3819660113;
    for (int i = 0; i < 25; i++) {
      final x = ((i + 3) * phi) % 1.0 * size.width;
      final y = ((i + 7) * (1 - phi)) % 1.0 * size.height;
      canvas.drawCircle(Offset(x, y), 1.0 + (i % 2), dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _OceanDepthsBackPainter oldDelegate) => false;
}

class _CircuitBoardBack extends StatelessWidget {
  const _CircuitBoardBack();

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(painter: _CircuitBoardBackPainter());
  }
}

class _CircuitBoardBackPainter extends CustomPainter {
  const _CircuitBoardBackPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF001A00),
    );
    const cols = 5;
    const rows = 7;
    final cellW = size.width / (cols + 1);
    final cellH = size.height / (rows + 1);
    final nodes = <Offset>[];
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        nodes.add(Offset(cellW * (c + 1), cellH * (r + 1)));
      }
    }
    final trace = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = const Color(0xFF00FF41).withValues(alpha: 0.20);
    final pad = Paint()
      ..color = const Color(0xFF00FF41).withValues(alpha: 0.35);
    for (int i = 0; i < nodes.length; i++) {
      final n = nodes[i];
      if (i + cols < nodes.length) {
        final next = nodes[i + cols];
        canvas.drawLine(n, Offset(n.dx, next.dy), trace);
        canvas.drawLine(Offset(n.dx, next.dy), next, trace);
      }
      if (i % cols != cols - 1) {
        final next = nodes[i + 1];
        if ((i + i ~/ cols) % 2 == 0) {
          canvas.drawLine(n, Offset(next.dx, n.dy), trace);
          canvas.drawLine(Offset(next.dx, n.dy), next, trace);
        } else {
          canvas.drawLine(n, next, trace);
        }
      }
      canvas.drawCircle(n, 2.5, pad);
    }
  }

  @override
  bool shouldRepaint(covariant _CircuitBoardBackPainter oldDelegate) => false;
}

class _MosaicBack extends StatelessWidget {
  const _MosaicBack();

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(painter: _MosaicBackPainter());
  }
}

class _MosaicBackPainter extends CustomPainter {
  const _MosaicBackPainter();

  static const _palette = [
    Color(0xFF4A148C),
    Color(0xFF6D1B3A),
    Color(0xFF006064),
    Color(0xFFB8860B),
    Color(0xFF0D1B3E),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF080808),
    );
    const tileW = 16.0;
    const tileH = 20.0;
    final grout = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = Colors.black.withValues(alpha: 0.6);
    int idx = 0;
    for (double y = 0; y < size.height; y += tileH) {
      for (double x = 0; x < size.width; x += tileW) {
        final rect = Rect.fromLTWH(x, y, tileW, tileH);
        canvas.drawRect(
          rect,
          Paint()..color = _palette[idx % _palette.length].withValues(alpha: 0.35),
        );
        canvas.drawRect(rect, grout);
        idx++;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MosaicBackPainter oldDelegate) => false;
}

class _LabyrinthBack extends StatelessWidget {
  const _LabyrinthBack();

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(painter: _LabyrinthBackPainter());
  }
}

class _LabyrinthBackPainter extends CustomPainter {
  const _LabyrinthBackPainter();

  // Walls: top, right, bottom, left
  static const _configs = [
    [true, true, false, true],
    [true, false, true, true],
    [false, true, true, true],
    [true, true, true, false],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF080818),
    );
    const cell = 14.0;
    final wall = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0xFFC9A84C).withValues(alpha: 0.18);
    int idx = 0;
    for (double y = 0; y < size.height; y += cell) {
      for (double x = 0; x < size.width; x += cell) {
        final cfg = _configs[idx % _configs.length];
        if (cfg[0]) {
          canvas.drawLine(Offset(x, y), Offset(x + cell, y), wall);
        }
        if (cfg[1]) {
          canvas.drawLine(Offset(x + cell, y), Offset(x + cell, y + cell), wall);
        }
        if (cfg[2]) {
          canvas.drawLine(Offset(x, y + cell), Offset(x + cell, y + cell), wall);
        }
        if (cfg[3]) {
          canvas.drawLine(Offset(x, y), Offset(x, y + cell), wall);
        }
        idx++;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LabyrinthBackPainter oldDelegate) => false;
}

class _GalaxyBack extends StatelessWidget {
  const _GalaxyBack();

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(painter: _GalaxyBackPainter());
  }
}

class _GalaxyBackPainter extends CustomPainter {
  const _GalaxyBackPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black);
    final center = Offset(size.width / 2, size.height / 2);
    const phi = 0.6180339887;
    final bgStar = Paint()..color = Colors.white.withValues(alpha: 0.25);
    for (int i = 0; i < 60; i++) {
      final x = ((i + 1) * phi) % 1.0 * size.width;
      final y = ((i + 3) * (1 - phi)) % 1.0 * size.height;
      canvas.drawCircle(Offset(x, y), 0.6 + (i % 3) * 0.3, bgStar);
    }
    for (int arm = 0; arm < 2; arm++) {
      for (double t = 0; t < 4 * math.pi; t += 0.15) {
        final r = t * 3.5;
        final angle = t + arm * math.pi;
        final x = center.dx + r * math.cos(angle);
        final y = center.dy + r * math.sin(angle) * 0.6;
        if (x < 0 || x > size.width || y < 0 || y > size.height) continue;
        final dist = r / (size.shortestSide * 0.5);
        final color = Color.lerp(Colors.white, const Color(0xFF6A5ACD), dist.clamp(0.0, 1.0))!;
        canvas.drawCircle(
          Offset(x, y),
          0.8 + (t % 3) * 0.4,
          Paint()..color = color.withValues(alpha: 0.7),
        );
      }
    }
    canvas.drawCircle(
      center,
      12,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.9)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 10),
    );
  }

  @override
  bool shouldRepaint(covariant _GalaxyBackPainter oldDelegate) => false;
}

class _VintageCasinoBack extends StatelessWidget {
  const _VintageCasinoBack();

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(painter: _VintageCasinoBackPainter());
  }
}

class _VintageCasinoBackPainter extends CustomPainter {
  const _VintageCasinoBackPainter();

  static const _red = Color(0xFF8B0000);
  static const _gold = Color(0xFFC9A84C);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = _red);
    final lattice = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..color = _gold.withValues(alpha: 0.25);
    const gap = 18.0;
    for (double d = -size.height; d < size.width + size.height; d += gap) {
      canvas.drawLine(Offset(d, 0), Offset(d + size.height, size.height), lattice);
      canvas.drawLine(Offset(d + size.height, 0), Offset(d, size.height), lattice);
    }
    canvas.drawRect(
      Rect.fromLTWH(5, 5, size.width - 10, size.height - 10),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = _gold.withValues(alpha: 0.6),
    );
    _drawFlower(canvas, Offset(size.width / 2, size.height / 2), 10);
    for (final pt in [
      Offset(size.width * 0.15, size.height * 0.15),
      Offset(size.width * 0.85, size.height * 0.15),
      Offset(size.width * 0.15, size.height * 0.85),
      Offset(size.width * 0.85, size.height * 0.85),
    ]) {
      _drawFlower(canvas, pt, 6);
    }
  }

  void _drawFlower(Canvas canvas, Offset center, double r) {
    final petal = Paint()..color = _gold.withValues(alpha: 0.35);
    for (int i = 0; i < 4; i++) {
      final angle = (i * 90) * math.pi / 180;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(
            center.dx + r * math.cos(angle),
            center.dy + r * math.sin(angle),
          ),
          width: r, height: r * 0.6,
        ),
        petal,
      );
    }
    canvas.drawCircle(center, r * 0.25, Paint()..color = _gold.withValues(alpha: 0.5));
  }

  @override
  bool shouldRepaint(covariant _VintageCasinoBackPainter oldDelegate) => false;
}

class _ZodiacBack extends StatelessWidget {
  const _ZodiacBack();

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(painter: _ZodiacBackPainter());
  }
}

class _ZodiacBackPainter extends CustomPainter {
  const _ZodiacBackPainter();

  static const _symbols = '♈♉♊♋♌♍♎♏♐♑♒♓';

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF0A0010),
    );
    final center = Offset(size.width / 2, size.height / 2);
    final outerR = size.shortestSide * 0.38;
    final innerR = outerR * 0.55;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = const Color(0xFFC9A84C).withValues(alpha: 0.35);
    canvas.drawCircle(center, outerR, ring);
    canvas.drawCircle(center, innerR, ring);
    for (int i = 0; i < 12; i++) {
      final angle = (i * 30 - 90) * math.pi / 180;
      canvas.drawLine(
        Offset(center.dx + innerR * math.cos(angle), center.dy + innerR * math.sin(angle)),
        Offset(center.dx + outerR * math.cos(angle), center.dy + outerR * math.sin(angle)),
        ring,
      );
      final symAngle = (i * 30 - 90 + 15) * math.pi / 180;
      final symPos = Offset(
        center.dx + (outerR * 0.82) * math.cos(symAngle),
        center.dy + (outerR * 0.82) * math.sin(symAngle),
      );
      final tp = TextPainter(
        text: TextSpan(
          text: _symbols[i],
          style: TextStyle(
            fontSize: outerR * 0.18,
            color: const Color(0xFFC9A84C).withValues(alpha: 0.40),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, symPos - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _ZodiacBackPainter oldDelegate) => false;
}

// ── Animated card backs ─────────────────────────────────────────────────────

class _AuroraBack extends StatefulWidget {
  const _AuroraBack();

  @override
  State<_AuroraBack> createState() => _AuroraBackState();
}

class _AuroraBackState extends State<_AuroraBack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
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
      builder: (_, __) => CustomPaint(
        painter: _AuroraBackPainter(time: _controller.value),
      ),
    );
  }
}

class _AuroraBackStatic extends StatelessWidget {
  const _AuroraBackStatic();

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(painter: _AuroraBackPainter(time: 0.5));
  }
}

class _AuroraBackPainter extends CustomPainter {
  const _AuroraBackPainter({required this.time});

  final double time;

  static const _bands = [
    Color(0xFF00E676),
    Color(0xFFAA00FF),
    Color(0xFF00E5FF),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF060A14),
    );
    for (int i = 0; i < _bands.length; i++) {
      final shift = math.sin(time * 2 * math.pi + i * 1.2) * size.width * 0.15;
      final bandTop = size.height * (0.15 + i * 0.12);
      final bandH = size.height * 0.18;
      final rect = Rect.fromLTWH(shift, bandTop, size.width, bandH);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            colors: [
              _bands[i].withValues(alpha: 0.0),
              _bands[i].withValues(alpha: 0.25),
              _bands[i].withValues(alpha: 0.0),
            ],
            stops: const [0.0, 0.5, 1.0],
          ).createShader(rect),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AuroraBackPainter oldDelegate) =>
      oldDelegate.time != time;
}

class _InfernoBack extends StatefulWidget {
  const _InfernoBack();

  @override
  State<_InfernoBack> createState() => _InfernoBackState();
}

class _InfernoBackState extends State<_InfernoBack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
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
      builder: (_, __) => CustomPaint(
        painter: _InfernoBackPainter(
          time: _controller.value * 2 * math.pi,
          fillRatio: 0.40,
          amplitude: 8,
        ),
      ),
    );
  }
}

class _InfernoBackStatic extends StatelessWidget {
  const _InfernoBackStatic();

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(
      painter: _InfernoBackPainter(time: 0, fillRatio: 0.40, amplitude: 8),
    );
  }
}

class _LavaFlowBack extends StatefulWidget {
  const _LavaFlowBack();

  @override
  State<_LavaFlowBack> createState() => _LavaFlowBackState();
}

class _LavaFlowBackState extends State<_LavaFlowBack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
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
      builder: (_, __) => CustomPaint(
        painter: _InfernoBackPainter(
          time: _controller.value * 2 * math.pi,
          fillRatio: 0.60,
          amplitude: 6,
          deepRed: const Color(0xFF8B0000),
        ),
      ),
    );
  }
}

class _InfernoBackPainter extends CustomPainter {
  const _InfernoBackPainter({
    required this.time,
    required this.fillRatio,
    required this.amplitude,
    this.deepRed,
  });

  final double time;
  final double fillRatio;
  final double amplitude;
  final Color? deepRed;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF0A0500));
    final path = Path()..moveTo(0, size.height);
    for (double x = 0; x <= size.width; x += 2) {
      final y = size.height * (1 - fillRatio) +
          math.sin(time + x / size.width * math.pi * 3) * amplitude;
      path.lineTo(x, y);
    }
    path.lineTo(size.width, size.height);
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            deepRed ?? const Color(0xFFBF360C),
            const Color(0xFFFF5722),
            const Color(0xFFFF8A50).withValues(alpha: 0.3),
          ],
        ).createShader(Offset.zero & size),
    );
    final crackAlpha = 0.15 + 0.15 * math.sin(time);
    final crack = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = const Color(0xFFFF5722).withValues(alpha: crackAlpha);
    final cracks = [
      [Offset(size.width * 0.2, size.height * 0.5), Offset(size.width * 0.45, size.height * 0.65)],
      [Offset(size.width * 0.55, size.height * 0.45), Offset(size.width * 0.7, size.height * 0.7)],
      [Offset(size.width * 0.35, size.height * 0.55), Offset(size.width * 0.5, size.height * 0.75)],
    ];
    for (final c in cracks) {
      canvas.drawLine(c[0], c[1], crack);
    }
  }

  @override
  bool shouldRepaint(covariant _InfernoBackPainter oldDelegate) =>
      oldDelegate.time != time ||
      oldDelegate.fillRatio != fillRatio ||
      oldDelegate.amplitude != amplitude ||
      oldDelegate.deepRed != deepRed;
}

class _HologramBack extends StatefulWidget {
  const _HologramBack();

  @override
  State<_HologramBack> createState() => _HologramBackState();
}

class _HologramBackState extends State<_HologramBack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
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
      builder: (_, __) => CustomPaint(
        painter: _HologramBackPainter(sweep: _controller.value),
      ),
    );
  }
}

class _HologramBackStatic extends StatelessWidget {
  const _HologramBackStatic();

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(painter: _HologramBackPainter(sweep: 0.35));
  }
}

class _HologramBackPainter extends CustomPainter {
  const _HologramBackPainter({required this.sweep});

  final double sweep;

  static const _rainbow = [
    Color(0xFFFF0000),
    Color(0xFFFF8800),
    Color(0xFFFFFF00),
    Color(0xFF00FF00),
    Color(0xFF00FFFF),
    Color(0xFF0088FF),
    Color(0xFF8800FF),
    Color(0xFFFF0000),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFE8E8EC),
    );
    final texture = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = Colors.white.withValues(alpha: 0.08);
    for (double d = -size.height; d < size.width + size.height; d += 8) {
      canvas.drawLine(Offset(d, 0), Offset(d + size.height, size.height), texture);
    }
    final sweepX = sweep * size.width * 1.5 - size.width * 0.25;
    final bandW = size.width * 0.35;
    canvas.drawRect(
      Rect.fromLTWH(sweepX, 0, bandW, size.height),
      Paint()
        ..shader = LinearGradient(colors: _rainbow).createShader(
          Rect.fromLTWH(sweepX, 0, bandW, size.height),
        )
        ..blendMode = BlendMode.overlay
        ..color = Colors.white.withValues(alpha: 0.45),
    );
  }

  @override
  bool shouldRepaint(covariant _HologramBackPainter oldDelegate) =>
      oldDelegate.sweep != sweep;
}
