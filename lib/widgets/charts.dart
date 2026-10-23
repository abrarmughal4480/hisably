import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/providers.dart';
import '../theme/hisably_theme.dart';

/// Hand-drawn charts for Reports (v0.6.8) — no chart package, only the
/// app's palette. All values are integer paisa.

void _label(Canvas canvas, String text, Offset center,
    {double size = 10,
    Color color = HisablyColors.textTertiary,
    FontWeight weight = FontWeight.w500}) {
  final tp = TextPainter(
    text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: size, fontWeight: weight)),
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.center,
  )..layout();
  tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
}

/// Grouped income/expense bars, one group per bucket (month).
class GroupedBarsPainter extends CustomPainter {
  GroupedBarsPainter({
    required this.ins,
    required this.outs,
    required this.labels,
    required this.inColor,
    required this.outColor,
  });
  final List<int> ins;
  final List<int> outs;
  final List<String> labels;
  final Color inColor;
  final Color outColor;

  @override
  void paint(Canvas canvas, Size size) {
    final n = ins.length;
    if (n == 0) return;
    final maxV = math.max(1, [...ins, ...outs].fold(0, math.max));
    const labelH = 18.0;
    final baseY = size.height - labelH;
    final plotH = baseY - 8;
    final groupW = size.width / n;
    final barW = math.min(13.0, groupW * 0.26);
    final baseline = Paint()
      ..color = HisablyColors.border
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, baseY), Offset(size.width, baseY), baseline);
    for (var i = 0; i < n; i++) {
      final cx = groupW * i + groupW / 2;
      _bar(canvas, cx - barW - 2, baseY, barW, plotH * ins[i] / maxV, inColor);
      _bar(canvas, cx + 2, baseY, barW, plotH * outs[i] / maxV, outColor);
      _label(canvas, labels[i], Offset(cx, baseY + labelH / 2 + 1));
    }
  }

  void _bar(Canvas canvas, double x, double baseY, double w, double h,
      Color color) {
    final height = math.max(h, 2.0);
    final rect = RRect.fromRectAndCorners(
      Rect.fromLTWH(x, baseY - height, w, height),
      topLeft: const Radius.circular(4),
      topRight: const Radius.circular(4),
    );
    canvas.drawRRect(rect, Paint()..color = color);
  }

  @override
  bool shouldRepaint(GroupedBarsPainter old) =>
      old.ins != ins || old.outs != outs || old.labels != labels;
}

/// Cumulative balance as a soft area line.
class TrendPainter extends CustomPainter {
  TrendPainter({required this.values, required this.labels});
  final List<int> values; // paisa, chronological
  final List<String> labels; // same length; '' = no label

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    const labelH = 18.0;
    const topPad = 20.0;
    final baseY = size.height - labelH;
    final plotH = baseY - topPad;
    var minV = values.fold(values.first, math.min);
    var maxV = values.fold(values.first, math.max);
    if (minV == maxV) {
      minV -= 100;
      maxV += 100;
    }
    final pad = (maxV - minV) * 0.15;
    minV = (minV - pad).floor();
    maxV = (maxV + pad).ceil();
    double xFor(int i) =>
        values.length == 1 ? size.width / 2 : 6 + (size.width - 12) * i / (values.length - 1);
    double yFor(int v) => topPad + plotH * (1 - (v - minV) / (maxV - minV));

    final points = [
      for (var i = 0; i < values.length; i++) Offset(xFor(i), yFor(values[i]))
    ];
    // Area fill.
    final area = Path()
      ..moveTo(points.first.dx, baseY)
      ..lineTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      area.lineTo(points[i].dx, points[i].dy);
    }
    area
      ..lineTo(points.last.dx, baseY)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            HisablyColors.accent.withValues(alpha: 0.30),
            HisablyColors.accent.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );
    // Line.
    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      line.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = HisablyColors.accent
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    // Baseline + dots.
    canvas.drawLine(Offset(0, baseY), Offset(size.width, baseY),
        Paint()..color = HisablyColors.border..strokeWidth = 1);
    for (final p in points) {
      canvas.drawCircle(p, 4.5, Paint()..color = HisablyColors.background);
      canvas.drawCircle(p, 3, Paint()..color = HisablyColors.accent);
    }
    // Extremes + month labels.
    _label(canvas, formatCompact(maxV), Offset(26, 9),
        color: HisablyColors.textSecondary);
    _label(canvas, formatCompact(minV), Offset(26, baseY - 8),
        color: HisablyColors.textSecondary);
    for (var i = 0; i < labels.length; i++) {
      if (labels[i].isEmpty) continue;
      _label(canvas, labels[i], Offset(xFor(i), baseY + labelH / 2 + 1));
    }
  }

  @override
  bool shouldRepaint(TrendPainter old) =>
      old.values != values || old.labels != labels;
}

/// Donut of category shares.
class DonutPainter extends CustomPainter {
  DonutPainter({required this.values, required this.colors});
  final List<int> values;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold(0, (a, b) => a + b);
    if (total <= 0) return;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 6;
    final rect = Rect.fromCircle(center: center, radius: radius);
    var start = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final sweep = values[i] / total * math.pi * 2;
      final gap = values.length > 1 ? 0.035 : 0.0;
      canvas.drawArc(
        rect,
        start + gap / 2,
        math.max(sweep - gap, 0.01),
        false,
        Paint()
          ..color = colors[i % colors.length]
          ..style = PaintingStyle.stroke
          ..strokeWidth = 24,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(DonutPainter old) =>
      old.values != values || old.colors != colors;
}

/// One thin bar per day (expense) for short ranges.
class DailyBarsPainter extends CustomPainter {
  DailyBarsPainter({required this.values, required this.dayNumbers});
  final List<int> values;
  final List<int> dayNumbers; // calendar day for each bar

  @override
  void paint(Canvas canvas, Size size) {
    final n = values.length;
    if (n == 0) return;
    final maxV = math.max(1, values.fold(0, math.max));
    const labelH = 16.0;
    final baseY = size.height - labelH;
    final plotH = baseY - 6;
    final slot = size.width / n;
    final barW = math.max(3.0, slot * 0.55);
    canvas.drawLine(Offset(0, baseY), Offset(size.width, baseY),
        Paint()..color = HisablyColors.border..strokeWidth = 1);
    for (var i = 0; i < n; i++) {
      final x = slot * i + (slot - barW) / 2;
      final h = values[i] == 0 ? 2.0 : math.max(2.0, plotH * values[i] / maxV);
      final rect = RRect.fromRectAndCorners(
        Rect.fromLTWH(x, baseY - h, barW, h),
        topLeft: const Radius.circular(2.5),
        topRight: const Radius.circular(2.5),
      );
      canvas.drawRRect(
          rect,
          Paint()
            ..color = values[i] == 0
                ? HisablyColors.border
                : HisablyColors.expense);
      // Sparse day labels: first, every 7th, last.
      if (i == 0 || (i + 1) % 7 == 0 || i == n - 1) {
        _label(canvas, '${dayNumbers[i]}',
            Offset(slot * i + slot / 2, baseY + labelH / 2 + 1), size: 9);
      }
    }
  }

  @override
  bool shouldRepaint(DailyBarsPainter old) => old.values != values;
}
