import 'dart:math';

import 'package:flutter/material.dart';

class AuthViewPortLayout extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget formBody;
  final Widget primaryActionButton;
  final Widget secondaryActionLink;
  final Widget? logo;

  const AuthViewPortLayout({
    super.key,
    required this.title,
    required this.subtitle,
    required this.formBody,
    required this.primaryActionButton,
    required this.secondaryActionLink,
    this.logo,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? Colors.black : const Color(0xFFF5F5F7);
    final cardColor = isDark ? const Color(0xFF1A1A1A) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black;
    final subTextColor = isDark ? Colors.grey.shade400 : Colors.grey.shade600;

    return Scaffold(
      backgroundColor: bgColor,
      body: Stack(
        children: [
          Positioned.fill(child: DataStreamBackground(isDark: isDark)),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 32,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Column(
                    children: [
                      const SizedBox(height: 48),
                      if (logo != null) ...[logo!, const SizedBox(height: 24)],
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(32),
                          boxShadow:
                              isDark
                                  ? const []
                                  : [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.06,
                                      ),
                                      blurRadius: 40,
                                      offset: const Offset(0, 10),
                                    ),
                                  ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.w800,
                                color: textColor,
                                letterSpacing: -0.8,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              subtitle,
                              style: TextStyle(
                                fontSize: 16,
                                color: subTextColor,
                              ),
                            ),
                            const SizedBox(height: 48),
                            formBody,
                            const SizedBox(height: 32),
                            primaryActionButton,
                            const SizedBox(height: 24),
                            Center(child: secondaryActionLink),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

InputDecoration authInputDecoration({
  required BuildContext context,
  required String hintText,
  required IconData icon,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final fillColor =
      isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF0F0F3);
  final subTextColor = isDark ? Colors.grey.shade500 : Colors.grey.shade600;
  const accentGlow = Color(0xFF20E3B2);

  return InputDecoration(
    hintText: hintText,
    hintStyle: TextStyle(color: subTextColor, fontSize: 16),
    prefixIcon: Icon(icon, color: subTextColor, size: 22),
    filled: true,
    fillColor: fillColor,
    contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(24),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(24),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(24),
      borderSide: BorderSide(
        color:
            isDark
                ? accentGlow.withValues(alpha: 0.5)
                : accentGlow.withValues(alpha: 0.2),
        width: 1.5,
      ),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(24),
      borderSide: const BorderSide(color: Colors.redAccent),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(24),
      borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
    ),
  );
}

Widget authGradientButton({
  required String label,
  required IconData icon,
  required VoidCallback? onPressed,
  bool isLoading = false,
}) {
  const brandGradient = LinearGradient(
    colors: [Color(0xFF20E3B2), Color(0xFF00A3FF)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  return Container(
    width: double.infinity,
    height: 60,
    decoration: BoxDecoration(
      gradient: brandGradient,
      borderRadius: BorderRadius.circular(100),
    ),
    child: ElevatedButton(
      onPressed: isLoading ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.transparent,
        disabledBackgroundColor: Colors.transparent,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
      ),
      child:
          isLoading
              ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                ),
              )
              : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: Colors.black, size: 22),
                  const SizedBox(width: 10),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
    ),
  );
}

class AuthLogoMark extends StatelessWidget {
  final IconData icon;

  const AuthLogoMark({super.key, required this.icon});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color:
            isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color:
              isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.04),
        ),
      ),
      child: ShaderMask(
        shaderCallback:
            (bounds) => const LinearGradient(
              colors: [Color(0xFF20E3B2), Color(0xFF00A3FF)],
            ).createShader(bounds),
        child: Icon(icon, color: Colors.white, size: 34),
      ),
    );
  }
}

class DataStreamBackground extends StatefulWidget {
  final bool isDark;

  const DataStreamBackground({super.key, required this.isDark});

  @override
  State<DataStreamBackground> createState() => _DataStreamBackgroundState();
}

class _DataStreamBackgroundState extends State<DataStreamBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isDark) {
      return Container(color: const Color(0xFFF5F5F7));
    }

    return AnimatedBuilder(
      animation: _controller,
      builder:
          (context, child) => CustomPaint(
            painter: _DataStreamPainter(_controller.value, widget.isDark),
            size: Size.infinite,
          ),
    );
  }
}

class _DataStreamPainter extends CustomPainter {
  final double progress;
  final bool isDark;

  _DataStreamPainter(this.progress, this.isDark);

  @override
  void paint(Canvas canvas, Size size) {
    if (!isDark) {
      return;
    }

    final paint =
        Paint()
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round;
    final height = size.height;
    final width = size.width;
    final random = Random(42);

    for (var i = 0; i < 35; i++) {
      final startX = random.nextDouble() * width;
      final speedMultiplier = 0.5 + random.nextDouble() * 1.5;
      final length = 100 + random.nextDouble() * 200;
      final opacity = 0.1 + random.nextDouble() * 0.5;
      final initialOffset = random.nextDouble() * height * 5;
      final currentY =
          ((progress * speedMultiplier * height * 3) + initialOffset) %
              (height + length) -
          length;

      final gradient = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          const Color(0xFF20E3B2).withValues(alpha: opacity),
          const Color(0xFF00A3FF).withValues(alpha: opacity * 0.5),
          Colors.transparent,
        ],
        stops: const [0, 0.4, 0.8, 1],
      );

      paint.shader = gradient.createShader(
        Rect.fromLTRB(startX, currentY, startX, currentY + length),
      );
      canvas.drawLine(
        Offset(startX, currentY),
        Offset(startX, currentY + length),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DataStreamPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.isDark != isDark;
  }
}
