import 'dart:math' as math;

import 'package:flutter/material.dart';

class CalibrationOverlay extends StatelessWidget {
  const CalibrationOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _CalibrationPainter(),
        child: Container(),
      ),
    );
  }
}

class _CalibrationPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = const Color(0xAA8EC5FF)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final fillPaint = Paint()
      ..color = const Color(0x332B7CD3)
      ..style = PaintingStyle.fill;

    final centerX = size.width / 2;
    final topY = size.height * 0.14;
    final bottomY = size.height * 0.88;

    final bodyPath = Path()
      ..moveTo(centerX, topY)
      ..addOval(Rect.fromCircle(center: Offset(centerX, topY + 28), radius: 28))
      ..moveTo(centerX, topY + 56)
      ..lineTo(centerX, size.height * 0.58)
      ..moveTo(centerX, size.height * 0.28)
      ..lineTo(centerX - size.width * 0.16, size.height * 0.42)
      ..moveTo(centerX, size.height * 0.28)
      ..lineTo(centerX + size.width * 0.16, size.height * 0.42)
      ..moveTo(centerX, size.height * 0.58)
      ..lineTo(centerX - size.width * 0.12, bottomY)
      ..moveTo(centerX, size.height * 0.58)
      ..lineTo(centerX + size.width * 0.12, bottomY);

    canvas.drawPath(bodyPath, linePaint);

    final contour = Path()
      ..moveTo(centerX, topY + 6)
      ..quadraticBezierTo(centerX - size.width * 0.27, size.height * 0.36,
          centerX - size.width * 0.16, bottomY)
      ..lineTo(centerX + size.width * 0.16, bottomY)
      ..quadraticBezierTo(centerX + size.width * 0.27, size.height * 0.36,
          centerX, topY + 6)
      ..close();

    canvas.drawPath(contour, fillPaint);

    final dashPaint = Paint()
      ..color = const Color(0x88FFFFFF)
      ..strokeWidth = 1.5;

    _drawDashedLine(
      canvas,
      Offset(centerX, topY - 10),
      Offset(centerX, bottomY + 6),
      dashPaint,
    );

    final guideText = TextPainter(
      text: const TextSpan(
        text: 'Joint Alignment Calibration',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width - 24);

    guideText.paint(canvas, Offset((size.width - guideText.width) / 2, 10));
  }

  void _drawDashedLine(
    Canvas canvas,
    Offset p1,
    Offset p2,
    Paint paint,
  ) {
    const dashWidth = 6.0;
    const dashSpace = 4.0;
    final totalDistance = (p2 - p1).distance;
    final dx = p2.dx - p1.dx;
    final dy = p2.dy - p1.dy;
    final direction = Offset(dx / totalDistance, dy / totalDistance);
    double current = 0;

    while (current < totalDistance) {
      final start = p1 + direction * current;
      final end = p1 + direction * math.min(current + dashWidth, totalDistance);
      canvas.drawLine(start, end, paint);
      current += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
