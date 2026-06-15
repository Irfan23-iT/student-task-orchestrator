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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = theme.scaffoldBackgroundColor;
    final cardColor = colorScheme.surface;
    final textColor = colorScheme.onSurface;
    final subTextColor = colorScheme.onSurfaceVariant;

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
                                  : const [
                                    BoxShadow(
                                      color: Color(0x0A000000),
                                      blurRadius: 12,
                                      offset: Offset(0, 4),
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
  final colorScheme = Theme.of(context).colorScheme;
  final fillColor = colorScheme.surfaceContainerHighest;
  final subTextColor = colorScheme.onSurfaceVariant;
  final accentGlow = colorScheme.primary;

  return InputDecoration(
    hintText: hintText,
    hintStyle: TextStyle(color: subTextColor, fontSize: 16),
    prefixIcon: Icon(icon, color: subTextColor, size: 22),
    filled: true,
    fillColor: fillColor,
    contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(28),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(28),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(28),
      borderSide: BorderSide(color: accentGlow, width: 1.6),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(28),
      borderSide: BorderSide(color: colorScheme.error),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(28),
      borderSide: BorderSide(color: colorScheme.error, width: 1.5),
    ),
  );
}

Widget authGradientButton({
  required String label,
  required IconData icon,
  required VoidCallback? onPressed,
  bool isLoading = false,
}) {
  return Builder(
    builder: (context) {
      final colorScheme = Theme.of(context).colorScheme;
      return Container(
        width: double.infinity,
        height: 60,
        decoration: BoxDecoration(
          color: colorScheme.primary,
          borderRadius: BorderRadius.circular(50),
        ),
        child: ElevatedButton(
          onPressed: isLoading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            disabledBackgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(50),
            ),
          ),
          child:
              isLoading
                  ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        colorScheme.onPrimary,
                      ),
                    ),
                  )
                  : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, color: colorScheme.onPrimary, size: 22),
                      const SizedBox(width: 10),
                      Text(
                        label,
                        style: TextStyle(
                          color: colorScheme.onPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
        ),
      );
    },
  );
}

class AuthLogoMark extends StatelessWidget {
  final IconData icon;

  const AuthLogoMark({super.key, required this.icon});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: colorScheme.outline),
      ),
      child: Icon(icon, color: colorScheme.onSurface, size: 34),
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
      return Container(color: Theme.of(context).scaffoldBackgroundColor);
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
          const Color(0xFFCDEB40).withValues(alpha: opacity),
          const Color(0xFF9EE2B8).withValues(alpha: opacity * 0.5),
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
