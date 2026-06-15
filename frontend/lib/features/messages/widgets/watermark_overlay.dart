import 'dart:math';
import 'package:flutter/material.dart';

class WatermarkOverlay extends StatelessWidget {
  final Widget child;
  final String label;
  final double opacity;

  const WatermarkOverlay({
    super.key,
    required this.child,
    required this.label,
    this.opacity = 0.08,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _WatermarkPainter(label: label, opacity: opacity),
            ),
          ),
        ),
      ],
    );
  }
}

class _WatermarkPainter extends CustomPainter {
  final String label;
  final double opacity;

  _WatermarkPainter({required this.label, required this.opacity});

  @override
  void paint(Canvas canvas, Size size) {
    final textStyle = TextStyle(
      color: Colors.grey.withValues(alpha: opacity),
      fontSize: 20,
      fontWeight: FontWeight.bold,
    );
    final textSpan = TextSpan(text: ' $label ', style: textStyle);
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    final textWidth = textPainter.width;
    final textHeight = textPainter.height;

    canvas.save();
    // Rotate canvas by -30 degrees
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(-30 * pi / 180);
    canvas.translate(-size.width, -size.height);

    for (double dy = -size.height; dy < size.height * 2; dy += textHeight * 3) {
      for (double dx = -size.width; dx < size.width * 2; dx += textWidth) {
        textPainter.paint(canvas, Offset(dx, dy));
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _WatermarkPainter oldDelegate) {
    return oldDelegate.label != label || oldDelegate.opacity != opacity;
  }
}
