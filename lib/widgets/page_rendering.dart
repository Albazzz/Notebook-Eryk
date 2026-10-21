import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models.dart';

/// Vẽ giấy và nét mực của một trang; dùng chung cho editor và bìa vở.

class InkStrokesPainter extends CustomPainter {
  const InkStrokesPainter(this.strokes);
  final List<InkStroke> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      paintInkStroke(
        canvas,
        stroke.points,
        stroke.color,
        stroke.width,
        highlight: stroke.tool == EditorTool.highlighter,
        style: stroke.penStyle,
      );
    }
  }

  @override
  bool shouldRepaint(covariant InkStrokesPainter oldDelegate) =>
      !identical(oldDelegate.strokes, strokes) ||
      oldDelegate.strokes.length != strokes.length;
}

class PaperPainter extends CustomPainter {
  const PaperPainter({
    required this.style,
    required this.isPdf,
    required this.lineOpacity,
    this.lineColor = defaultPaperLineColor,
  });
  final PaperStyle style;
  final bool isPdf;
  final double lineOpacity;
  final Color lineColor;
  @override
  void paint(Canvas canvas, Size size) {
    if (isPdf || style == PaperStyle.blank) return;
    final paint = Paint()
      ..color = lineColor.withValues(alpha: lineOpacity)
      ..strokeWidth = .8;
    if (style == PaperStyle.lined) {
      for (double y = 72; y < size.height; y += 30) {
        canvas.drawLine(Offset(40, y), Offset(size.width - 30, y), paint);
      }
    } else {
      for (double y = 0; y < size.height; y += 24) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      }
      for (double x = 0; x < size.width; x += 24) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      }
    }
    canvas.drawLine(
      const Offset(36, 0),
      Offset(36, size.height),
      Paint()
        ..color = const Color(
          0xffd9822b,
        ).withValues(alpha: (lineOpacity * 1.5).clamp(.04, .5))
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant PaperPainter oldDelegate) =>
      oldDelegate.style != style ||
      oldDelegate.isPdf != isPdf ||
      oldDelegate.lineOpacity != lineOpacity ||
      oldDelegate.lineColor != lineColor;
}

/// Vẽ một nét mực theo kiểu bút. Dùng chung cho canvas và ô xem trước.
void paintInkStroke(
  Canvas canvas,
  List<StrokePoint> points,
  Color color,
  double width, {
  required bool highlight,
  PenStyle style = PenStyle.calligraphy,
}) {
  if (points.length < 2) return;

  // Build a smoothed centerline from quadratic midpoints.
  final centers = <Offset>[points.first.offset];
  for (var i = 0; i < points.length - 1; i++) {
    centers.add(
      Offset(
        (points[i].offset.dx + points[i + 1].offset.dx) / 2,
        (points[i].offset.dy + points[i + 1].offset.dy) / 2,
      ),
    );
  }
  centers.add(points.last.offset);

  if (!highlight && (style == PenStyle.marker || style == PenStyle.pencil)) {
    _paintUniformStroke(canvas, centers, color, width, style);
    return;
  }

  // Expand the centerline into a filled left/right mesh. This gives every
  // point its own radius, unlike Canvas.drawPath(strokeWidth), and produces
  // natural tapering.
  final radii = <double>[];
  for (var i = 0; i < centers.length; i++) {
    final sourceIndex = (i * points.length / centers.length).floor().clamp(
      0,
      points.length - 1,
    );
    final previous = centers[i == 0 ? 0 : i - 1];
    final next = centers[i == centers.length - 1 ? i : i + 1];
    final direction = (next - previous).direction;
    final pressure = points[sourceIndex].pressure.clamp(.35, 1.0);
    final dt = i == 0
        ? 0
        : (points[sourceIndex].timeMicros -
                  points[(sourceIndex - 1).clamp(0, points.length - 1)]
                      .timeMicros)
              .clamp(1, 1000000);
    final distance = (next - previous).distance;
    final speed = dt == 0 ? 0 : distance / dt;
    final speedFactor = (1 - speed * 1800).clamp(.58, 1.0);
    final double radius;
    final double startTaperLength;
    final double endTaperLength;
    if (highlight) {
      radius = width * .5 * speedFactor;
      startTaperLength = 4;
      endTaperLength = 5;
    } else {
      switch (style) {
        case PenStyle.fountain:
          // Thin hairline at light pressure, swelling as the nib is pressed.
          radius = width * .5 * (.3 + .95 * pressure) * speedFactor;
          startTaperLength = 3;
          endTaperLength = 8;
        case PenStyle.ballpoint:
          radius = width * .5 * (.82 + .18 * pressure);
          startTaperLength = 1.5;
          endTaperLength = 1.5;
        case PenStyle.calligraphy || PenStyle.marker || PenStyle.pencil:
          final nibFactor = .76 + .28 * math.sin(direction + math.pi / 5).abs();
          radius = width * .5 * pressure * speedFactor * nibFactor;
          startTaperLength = 4;
          endTaperLength = 5;
      }
    }
    final startTaper = (i / startTaperLength).clamp(0, 1);
    final endTaper = ((centers.length - 1 - i) / endTaperLength).clamp(0, 1);
    radii.add(radius * math.min(startTaper, endTaper));
  }
  final path = Path();
  for (var i = 0; i < centers.length; i++) {
    final tangent =
        (centers[i == centers.length - 1 ? i : i + 1] -
                centers[i == 0 ? i : i - 1])
            .direction;
    final normal = Offset(-math.sin(tangent), math.cos(tangent));
    final left = centers[i] + normal * radii[i];
    if (i == 0) {
      path.moveTo(left.dx, left.dy);
    } else {
      path.lineTo(left.dx, left.dy);
    }
  }
  for (var i = centers.length - 1; i >= 0; i--) {
    final tangent =
        (centers[i == centers.length - 1 ? i : i + 1] -
                centers[i == 0 ? i : i - 1])
            .direction;
    final normal = Offset(-math.sin(tangent), math.cos(tangent));
    final right = centers[i] - normal * radii[i];
    path.lineTo(right.dx, right.dy);
  }
  path.close();
  final paint = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.fill
    ..color = color;
  if (highlight) paint.blendMode = BlendMode.multiply;
  canvas.drawPath(path, paint);
  if (!highlight && style == PenStyle.ballpoint) {
    // Round end caps keep the nearly uniform line from looking clipped.
    final cap = Paint()
      ..isAntiAlias = true
      ..color = color;
    canvas
      ..drawCircle(centers.first, radii[1.clamp(0, radii.length - 1)], cap)
      ..drawCircle(
        centers.last,
        radii[(radii.length - 2).clamp(0, radii.length - 1)],
        cap,
      );
  }
}

/// Bút dạ và bút chì: nét có độ rộng cố định, đầu tròn.
void _paintUniformStroke(
  Canvas canvas,
  List<Offset> centers,
  Color color,
  double width,
  PenStyle style,
) {
  final path = Path()..moveTo(centers.first.dx, centers.first.dy);
  for (var i = 1; i < centers.length - 1; i++) {
    final control = centers[i];
    final end = Offset.lerp(centers[i], centers[i + 1], .5)!;
    path.quadraticBezierTo(control.dx, control.dy, end.dx, end.dy);
  }
  path.lineTo(centers.last.dx, centers.last.dy);
  final paint = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  if (style == PenStyle.marker) {
    canvas.drawPath(
      path,
      paint
        ..color = color
        ..strokeWidth = width * 1.5,
    );
    return;
  }
  // Graphite: a solid core at ~90% of the chosen opacity plus two offset
  // grain passes. No blur, so thin pencil notes stay legible.
  final strokeWidth = (width * .7).clamp(1.0, 7.0);
  final alpha = color.a;
  canvas.drawPath(
    path,
    paint
      ..color = color.withValues(alpha: alpha * .9)
      ..strokeWidth = strokeWidth,
  );
  final grain = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeWidth = strokeWidth * .5
    ..color = color.withValues(alpha: alpha * .35);
  canvas
    ..drawPath(path.shift(Offset(strokeWidth * .25, -strokeWidth * .2)), grain)
    ..drawPath(
      path.shift(Offset(-strokeWidth * .22, strokeWidth * .22)),
      grain,
    );
}

/// Các điểm giả lập dọc một đường cong để xem trước kiểu bút, áp lực tăng
/// rồi giảm như khi viết thật.
List<StrokePoint> previewStrokePoints(Size size) {
  final path = Path()
    ..moveTo(20, size.height * .68)
    ..cubicTo(
      size.width * .25,
      size.height * .08,
      size.width * .48,
      size.height * .92,
      size.width * .67,
      size.height * .35,
    )
    ..quadraticBezierTo(
      size.width * .78,
      size.height * .12,
      size.width - 18,
      size.height * .55,
    );
  final points = <StrokePoint>[];
  for (final metric in path.computeMetrics()) {
    const steps = 48;
    for (var step = 0; step <= steps; step++) {
      final t = step / steps;
      final tangent = metric.getTangentForOffset(metric.length * t);
      if (tangent == null) continue;
      points.add(
        StrokePoint(
          tangent.position,
          .45 + .55 * math.sin(t * math.pi),
          step * 8000,
        ),
      );
    }
  }
  return points;
}
