// Launcher icon generator (v0.6.9): draws the Hisably H at a balanced
// size — glyph height 54% of the canvas, centred — into every mipmap
// density, plus a before/after preview sheet for visual checking.
// Run: flutter test tool/icon_gen_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _greenLight = Color(0xFF4ADE80);
const _greenDeep = Color(0xFF16A34A);

void _drawH(Canvas canvas, double size, {double glyphFraction = 0.54}) {
  // The glyph's outer box on the 96 grid: x 24.5..71.5 (47 wide),
  // y 14.5..81.5 (67 tall) including the 11-unit round-cap stroke.
  final gridSide = glyphFraction * size * 96 / 67;
  final o = (size - gridSide) / 2;
  final u = gridSide / 96;
  final glyphRect = Rect.fromLTWH(
      o + 24.5 * u, o + 14.5 * u, 47 * u, 67 * u);
  final paint = Paint()
    ..shader = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [_greenLight, _greenDeep],
    ).createShader(glyphRect)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 11 * u
    ..strokeCap = StrokeCap.round;
  canvas.drawLine(
      Offset(o + 30 * u, o + 20 * u), Offset(o + 30 * u, o + 76 * u), paint);
  canvas.drawLine(
      Offset(o + 66 * u, o + 20 * u), Offset(o + 66 * u, o + 76 * u), paint);
  canvas.drawLine(
      Offset(o + 30 * u, o + 48 * u), Offset(o + 66 * u, o + 48 * u), paint);
}

Future<void> _render(double size, void Function(Canvas) draw, String path) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  draw(canvas);
  final image = await recorder.endRecording().toImage(size.toInt(), size.toInt());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  await File(path).writeAsBytes(bytes!.buffer.asUint8List());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('generate launcher icons + preview', () async {
    const resDir = 'android/app/src/main/res';
    const fgSizes = {
      'mdpi': 108, 'hdpi': 162, 'xhdpi': 216, 'xxhdpi': 324, 'xxxhdpi': 432,
    };
    const legacySizes = {
      'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192,
    };
    for (final e in fgSizes.entries) {
      final dir = '$resDir/mipmap-${e.key}';
      await _render(e.value.toDouble(), (c) => _drawH(c, e.value.toDouble()),
          '$dir/ic_launcher_foreground.png');
    }
    for (final e in legacySizes.entries) {
      final dir = '$resDir/mipmap-${e.key}';
      final s = e.value.toDouble();
      await _render(s, (c) {
        c.drawRect(Rect.fromLTWH(0, 0, s, s), Paint()..color = Colors.black);
        _drawH(c, s);
      }, '$dir/ic_launcher.png');
      await _render(s, (c) {
        c.clipPath(Path()..addOval(Rect.fromLTWH(0, 0, s, s)));
        c.drawRect(Rect.fromLTWH(0, 0, s, s), Paint()..color = Colors.black);
        _drawH(c, s);
      }, '$dir/ic_launcher_round.png');
    }

    // Preview sheet: OLD icon (as installed) vs NEW, each shown the way
    // launchers mask it (circle + squircle), at a realistic size.
    const cell = 216.0;
    final old = await _loadImage('/home/hatch/workspace/icon-fix/old-foreground.png');
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, cell * 4, cell));
    canvas.drawRect(const Rect.fromLTWH(0, 0, cell * 4, cell),
        Paint()..color = const Color(0xFF222222));
    // old: circle + squircle (glyph drawn at its native old padding)
    _maskedCell(canvas, 0, cell, (c, s) => c.drawImage(old, Offset.zero, Paint()));
    _maskedCell(canvas, cell, cell, (c, s) => c.drawImage(old, Offset.zero, Paint()), squircle: true);
    // new
    _maskedCell(canvas, cell * 2, cell, (c, s) => _drawH(c, s, glyphFraction: 0.54));
    _maskedCell(canvas, cell * 3, cell, (c, s) => _drawH(c, s, glyphFraction: 0.54), squircle: true);
    final sheet = await recorder.endRecording().toImage((cell * 4).toInt(), cell.toInt());
    final bytes = await sheet.toByteData(format: ui.ImageByteFormat.png);
    await File('/home/hatch/workspace/icon-fix/preview-old-vs-new.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
  });
}

Future<ui.Image> _loadImage(String path) async {
  final data = await File(path).readAsBytes();
  final codec = await ui.instantiateImageCodec(data);
  return (await codec.getNextFrame()).image;
}

void _maskedCell(Canvas parent, double dx, double cell,
    void Function(Canvas, double) drawGlyph, {bool squircle = false}) {
  parent.save();
  parent.translate(dx, 0);
  final path = Path();
  if (squircle) {
    path.addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, cell, cell), Radius.circular(cell * 0.22)));
  } else {
    path.addOval(Rect.fromLTWH(0, 0, cell, cell));
  }
  parent.clipPath(path);
  parent.drawRect(Rect.fromLTWH(0, 0, cell, cell),
      Paint()..color = Colors.black);
  // Foreground layer scaled to the cell (432-native art scales down).
  parent.save();
  parent.scale(cell / 432);
  // For image-based (old) cells the image is already 216 — draw at 2x.
  drawGlyph(parent, 432);
  parent.restore();
  parent.restore();
}
