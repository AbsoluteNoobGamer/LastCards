import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/providers/app_update_provider.dart';
import '../features/start/presentation/widgets/forced_update_screen.dart';
import 'router/app_routes.dart';

/// Full-screen splash shown when the app loads.
/// Displays the Last Cards branding, then navigates to [AuthGate] — unless
/// [forcedUpdateGateProvider] says this build is too old, in which case it
/// routes to [ForcedUpdateScreen] instead.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  static const _kDuration = Duration(milliseconds: 2500);

  @override
  void initState() {
    super.initState();
    Future.delayed(_kDuration, _goToStart);
  }

  Future<void> _goToStart() async {
    if (!mounted) return;
    final forcedGate = await ref.read(forcedUpdateGateProvider.future);
    if (!mounted) return;
    if (forcedGate != null) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => ForcedUpdateScreen(info: forcedGate)),
      );
      return;
    }
    Navigator.of(context).pushReplacementNamed(AppRoutes.start);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060e08),
      body: const _SplashBody(),
    );
  }
}

// ---------------------------------------------------------------------------
// Animated splash body
// ---------------------------------------------------------------------------

class _SplashBody extends StatefulWidget {
  const _SplashBody();

  @override
  State<_SplashBody> createState() => _SplashBodyState();
}

class _SplashBodyState extends State<_SplashBody>
    with SingleTickerProviderStateMixin {
  static const _animDuration = Duration(milliseconds: 800);

  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _animDuration);
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _scale = Tween<double>(begin: 0.96, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: ScaleTransition(
        scale: _scale,
        child: const ColoredBox(
          color: Color(0xFF060e08),
          child: _SplashContent(),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Layout assembly
// ---------------------------------------------------------------------------

class _SplashContent extends StatelessWidget {
  const _SplashContent();

  static const _gold = Color(0xFFC9A84C);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final screenHeight = constraints.maxHeight;
        final titleSize = math.min(screenWidth * 0.22, 88.0);
        final titleShaderRect = Rect.fromLTWH(0, 0, screenWidth, titleSize * 2);

        final titleStyle = GoogleFonts.cinzel(
          fontSize: titleSize,
          fontWeight: FontWeight.w700,
          letterSpacing: 6,
          height: 1.0,
          foreground: Paint()
            ..shader = const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFFF0D060),
                Color(0xFFC9A84C),
                Color(0xFF8A6D28),
              ],
              stops: [0.0, 0.4, 1.0],
            ).createShader(titleShaderRect),
        );

        return Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _SplashPainter(),
              ),
            ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(height: screenHeight * 0.10),
                  _SplashCardFan(
                    screenWidth: screenWidth,
                    screenHeight: screenHeight,
                  ),
                  const SizedBox(height: 24),
                  _SplashDivider(screenWidth: screenWidth),
                  const SizedBox(height: 20),
                  const _SplashSuitRow(),
                  const SizedBox(height: 20),
                  _SplashDivider(screenWidth: screenWidth),
                  const SizedBox(height: 28),
                  Text('LAST', style: titleStyle, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text('CARDS', style: titleStyle, textAlign: TextAlign.center),
                  const SizedBox(height: 28),
                  Text(
                    'Play It All, Leave Nothing',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.cinzel(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 3.5,
                      color: _gold.withValues(alpha: 0.72),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Background painter — felt glow, texture, vignette, border, ornaments
// ---------------------------------------------------------------------------

class _SplashPainter extends CustomPainter {
  static const _gold = Color(0xFFC9A84C);
  static const _bg = Color(0xFF060e08);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // Layer 1 — solid fill
    canvas.drawRect(rect, Paint()..color = _bg);

    // Layer 2 — radial bloom from center-top
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.2),
          radius: 0.65,
          colors: [
            const Color(0xFF1a3d2b).withValues(alpha: 0.9),
            Colors.transparent,
          ],
        ).createShader(rect),
    );

    // Layer 3 — faint horizontal felt lines
    const lineCount = 12;
    final lineSpacing = size.height / (lineCount + 1);
    final linePaint = Paint()
      ..color = _gold.withValues(alpha: 0.03)
      ..strokeWidth = 0.5;
    for (var i = 1; i <= lineCount; i++) {
      final y = lineSpacing * i;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }

    // Layer 4 — vignette
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.65),
          ],
          radius: 1.0,
        ).createShader(rect),
    );

    // Decorative border — outer
    final outerRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(28, 28, size.width - 56, size.height - 56),
      const Radius.circular(24),
    );
    canvas.drawRRect(
      outerRect,
      Paint()
        ..color = _gold.withValues(alpha: 0.70)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Decorative border — inner
    final innerRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(36, 36, size.width - 72, size.height - 72),
      const Radius.circular(20),
    );
    canvas.drawRRect(
      innerRect,
      Paint()
        ..color = _gold.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5,
    );

    // Corner ornaments — mirror top-left to all four corners
    _drawCornerOrnament(canvas, const Offset(28, 28));
    canvas.save();
    canvas.translate(size.width, 0);
    canvas.scale(-1, 1);
    _drawCornerOrnament(canvas, const Offset(28, 28));
    canvas.restore();
    canvas.save();
    canvas.translate(0, size.height);
    canvas.scale(1, -1);
    _drawCornerOrnament(canvas, const Offset(28, 28));
    canvas.restore();
    canvas.save();
    canvas.translate(size.width, size.height);
    canvas.scale(-1, -1);
    _drawCornerOrnament(canvas, const Offset(28, 28));
    canvas.restore();
  }

  void _drawCornerOrnament(Canvas canvas, Offset corner) {
    final paint = Paint()
      ..color = _gold.withValues(alpha: 0.8)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;

    // Outer L — 40px arms
    canvas.drawLine(corner, corner + const Offset(40, 0), paint);
    canvas.drawLine(corner, corner + const Offset(0, 40), paint);

    // Inner L — 24px arms, inset 8px
    final inner = corner + const Offset(8, 8);
    canvas.drawLine(inner, inner + const Offset(24, 0), paint);
    canvas.drawLine(inner, inner + const Offset(0, 24), paint);

    // Corner dot
    canvas.drawCircle(
      corner,
      2,
      Paint()..color = _gold.withValues(alpha: 0.8),
    );
  }

  @override
  bool shouldRepaint(covariant _SplashPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// Card fan
// ---------------------------------------------------------------------------

enum _SplashCardKind { backSpade, backKing, joker, backAce, backDiamond }

class _SplashCardFan extends StatelessWidget {
  const _SplashCardFan({
    required this.screenWidth,
    required this.screenHeight,
  });

  final double screenWidth;
  final double screenHeight;

  static const _cardW = 88.0;
  static const _cardH = 123.0;

  @override
  Widget build(BuildContext context) {
    final pivotX = screenWidth / 2;
    // Column starts after 10% top padding; pivot is at 42% of screen height.
    final pivotY = screenHeight * 0.42 - screenHeight * 0.10;
    final fanHeight = pivotY + 16;

    return SizedBox(
      width: screenWidth,
      height: fanHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          _buildCard(
            pivotX: pivotX,
            pivotY: pivotY,
            degrees: -28,
            kind: _SplashCardKind.backSpade,
            gradient: true,
          ),
          _buildCard(
            pivotX: pivotX,
            pivotY: pivotY,
            degrees: 28,
            kind: _SplashCardKind.backDiamond,
            gradient: true,
          ),
          _buildCard(
            pivotX: pivotX,
            pivotY: pivotY,
            degrees: -14,
            kind: _SplashCardKind.backKing,
          ),
          _buildCard(
            pivotX: pivotX,
            pivotY: pivotY,
            degrees: 14,
            kind: _SplashCardKind.backAce,
          ),
          _buildCard(
            pivotX: pivotX,
            pivotY: pivotY,
            degrees: 0,
            kind: _SplashCardKind.joker,
          ),
        ],
      ),
    );
  }

  Widget _buildCard({
    required double pivotX,
    required double pivotY,
    required double degrees,
    required _SplashCardKind kind,
    bool gradient = false,
  }) {
    final angle = degrees * math.pi / 180;
    return Positioned(
      left: pivotX - _cardW / 2,
      top: pivotY - _cardH,
      child: Transform.rotate(
        angle: angle,
        origin: Offset(_cardW / 2, _cardH),
        child: _SplashCard(kind: kind, withGradient: gradient),
      ),
    );
  }
}

class _SplashCard extends StatelessWidget {
  const _SplashCard({
    required this.kind,
    this.withGradient = false,
  });

  final _SplashCardKind kind;
  final bool withGradient;

  static const _cardW = 88.0;
  static const _cardH = 123.0;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(_cardW, _cardH),
      painter: _SplashCardPainter(kind: kind, withGradient: withGradient),
    );
  }
}

class _SplashCardPainter extends CustomPainter {
  const _SplashCardPainter({
    required this.kind,
    required this.withGradient,
  });

  final _SplashCardKind kind;
  final bool withGradient;

  static const _gold = Color(0xFFC9A84C);
  static const _cardW = 88.0;
  static const _cardH = 123.0;
  static const _radius = 8.0;

  @override
  void paint(Canvas canvas, Size size) {
    final cardRect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(_radius),
    );

    if (kind == _SplashCardKind.joker) {
      canvas.drawRRect(
        cardRect,
        Paint()..color = const Color(0xFFF5F0E8),
      );
    } else if (withGradient) {
      canvas.drawRRect(
        cardRect,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1a2a4a), Color(0xFF080d18)],
          ).createShader(Offset.zero & size),
      );
    } else {
      canvas.drawRRect(
        cardRect,
        Paint()..color = const Color(0xFF1a2a4a),
      );
    }

    // Outer gold border
    canvas.drawRRect(
      cardRect,
      Paint()
        ..color = _gold
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    // Inner decorative border
    final innerRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(5, 5, _cardW - 10, _cardH - 10),
      const Radius.circular(_radius - 2),
    );
    canvas.drawRRect(
      innerRect,
      Paint()
        ..color = _gold.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5,
    );

    switch (kind) {
      case _SplashCardKind.backSpade:
        _paintCenterText(canvas, '♠', opacity: 0.7);
      case _SplashCardKind.backKing:
        _paintCenterText(canvas, 'K', opacity: 0.7);
      case _SplashCardKind.backAce:
        _paintCenterText(canvas, 'A', opacity: 0.7);
      case _SplashCardKind.backDiamond:
        _paintCenterText(canvas, '♦', opacity: 0.7);
      case _SplashCardKind.joker:
        _paintJokerFace(canvas);
    }
  }

  void _paintCenterText(Canvas canvas, String text, {required double opacity}) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'Georgia',
          fontFamilyFallback: const ['serif'],
          fontSize: 32,
          color: _gold.withValues(alpha: opacity),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset(
        (_cardW - painter.width) / 2,
        (_cardH - painter.height) / 2,
      ),
    );
  }

  void _paintJokerFace(Canvas canvas) {
    // Top-left J + ♥
    final cornerPainter = TextPainter(
      text: TextSpan(
        children: [
          TextSpan(
            text: 'J',
            style: TextStyle(
              fontFamily: 'Georgia',
              fontFamilyFallback: const ['serif'],
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF9B2335).withValues(alpha: 0.85),
            ),
          ),
          TextSpan(
            text: '♥',
            style: TextStyle(
              fontFamily: 'Georgia',
              fontFamilyFallback: const ['serif'],
              fontSize: 12,
              color: const Color(0xFF9B2335).withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    cornerPainter.paint(canvas, const Offset(8, 6));

    // Center red star
    final starPainter = TextPainter(
      text: TextSpan(
        text: '★',
        style: TextStyle(
          fontFamily: 'Georgia',
          fontFamilyFallback: const ['serif'],
          fontSize: 36,
          color: const Color(0xFF9B2335).withValues(alpha: 0.9),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    starPainter.paint(
      canvas,
      Offset(
        (_cardW - starPainter.width) / 2,
        (_cardH - starPainter.height) / 2 - 10,
      ),
    );

    // JOKER label
    final labelPainter = TextPainter(
      text: TextSpan(
        text: 'JOKER',
        style: TextStyle(
          fontFamily: 'Georgia',
          fontFamilyFallback: const ['serif'],
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 2,
          color: const Color(0xFF2a2018).withValues(alpha: 0.85),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    labelPainter.paint(
      canvas,
      Offset(
        (_cardW - labelPainter.width) / 2,
        (_cardH - labelPainter.height) / 2 + 22,
      ),
    );

    // Gold border emphasis on joker face
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Offset.zero & const Size(_cardW, _cardH),
        const Radius.circular(_radius),
      ),
      Paint()
        ..color = _gold
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8,
    );
  }

  @override
  bool shouldRepaint(covariant _SplashCardPainter oldDelegate) =>
      oldDelegate.kind != kind || oldDelegate.withGradient != withGradient;
}

// ---------------------------------------------------------------------------
// Dividers
// ---------------------------------------------------------------------------

class _SplashDivider extends StatelessWidget {
  const _SplashDivider({required this.screenWidth});

  final double screenWidth;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(screenWidth, 6),
      painter: _SplashDividerPainter(screenWidth: screenWidth),
    );
  }
}

class _SplashDividerPainter extends CustomPainter {
  const _SplashDividerPainter({required this.screenWidth});

  final double screenWidth;

  static const _gold = Color(0xFFC9A84C);

  @override
  void paint(Canvas canvas, Size size) {
    const leftX = 100.0;
    final rightX = screenWidth - 100;
    final centerX = screenWidth / 2;
    const y = 3.0;

    final linePaint = Paint()
      ..color = _gold.withValues(alpha: 0.6)
      ..strokeWidth = 0.8;
    canvas.drawLine(const Offset(leftX, y), Offset(rightX, y), linePaint);

    canvas.drawCircle(
      Offset(centerX, y),
      3,
      Paint()..color = _gold.withValues(alpha: 0.8),
    );
    canvas.drawCircle(
      const Offset(leftX, y),
      2,
      Paint()..color = _gold.withValues(alpha: 0.5),
    );
    canvas.drawCircle(
      Offset(rightX, y),
      2,
      Paint()..color = _gold.withValues(alpha: 0.5),
    );
  }

  @override
  bool shouldRepaint(covariant _SplashDividerPainter oldDelegate) =>
      oldDelegate.screenWidth != screenWidth;
}

// ---------------------------------------------------------------------------
// Suit symbols row
// ---------------------------------------------------------------------------

class _SplashSuitRow extends StatelessWidget {
  const _SplashSuitRow();

  static const _gold = Color(0xFFC9A84C);
  static const _red = Color(0xFF9B2335);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _suit('♠', _gold),
        const SizedBox(width: 52),
        _suit('♥', _red),
        const SizedBox(width: 52),
        Text(
          '✦',
          style: TextStyle(
            fontSize: 11,
            color: _gold.withValues(alpha: 0.35),
          ),
        ),
        const SizedBox(width: 52),
        _suit('♦', _red),
        const SizedBox(width: 52),
        _suit('♣', _gold),
      ],
    );
  }

  Widget _suit(String symbol, Color color) {
    return Text(
      symbol,
      style: TextStyle(
        fontSize: 24,
        color: color.withValues(alpha: 0.75),
      ),
    );
  }
}
