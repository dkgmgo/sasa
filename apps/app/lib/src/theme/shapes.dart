import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'pwani.dart';

/// Outline of a Zanzibar-door arch: a half-ellipse across the full width on
/// top, small rounded corners at the bottom.
Path archPath(Size size, {double bottomRadius = 12, double? archHeight}) {
  final w = size.width;
  final h = size.height;
  final ah = math.min(archHeight ?? w / 2, h);
  final br = math.min(bottomRadius, math.min(w / 2, (h - ah).abs() + 1));
  return Path()
    ..moveTo(0, ah)
    ..arcToPoint(Offset(w, ah), radius: Radius.elliptical(w / 2, ah))
    ..lineTo(w, h - br)
    ..quadraticBezierTo(w, h, w - br, h)
    ..lineTo(br, h)
    ..quadraticBezierTo(0, h, 0, h - br)
    ..close();
}

class _ArchClipper extends CustomClipper<Path> {
  const _ArchClipper(this.bottomRadius, this.archHeight);
  final double bottomRadius;
  final double? archHeight;

  @override
  Path getClip(Size size) =>
      archPath(size, bottomRadius: bottomRadius, archHeight: archHeight);

  @override
  bool shouldReclip(_ArchClipper old) =>
      old.bottomRadius != bottomRadius || old.archHeight != archHeight;
}

/// A coloured panel with an arch top, e.g. the Today header.
class Arch extends StatelessWidget {
  const Arch({
    super.key,
    required this.color,
    required this.child,
    this.archHeight,
    this.bottomRadius = 12,
    this.padding = EdgeInsets.zero,
  });

  final Color color;
  final Widget child;

  /// Height of the curved part; defaults to half the width (a full arch).
  final double? archHeight;
  final double bottomRadius;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => ClipPath(
    clipper: _ArchClipper(bottomRadius, archHeight),
    child: ColoredBox(
      color: color,
      child: Padding(padding: padding, child: child),
    ),
  );
}

/// A small solid arch, used as a colour marker (categories, swatches).
class ArchMark extends StatelessWidget {
  const ArchMark({
    super.key,
    required this.color,
    this.width = 12,
    this.height = 14,
    this.border,
  });

  final Color color;
  final double width;
  final double height;
  final Color? border;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: height,
    child: CustomPaint(painter: _ArchMarkPainter(color, border)),
  );
}

class _ArchMarkPainter extends CustomPainter {
  const _ArchMarkPainter(this.color, this.border);
  final Color color;
  final Color? border;

  @override
  void paint(Canvas canvas, Size size) {
    final path = archPath(size, bottomRadius: size.width * 0.15);
    canvas.drawPath(path, Paint()..color = color);
    if (border case final b?) {
      canvas.drawPath(
        path,
        Paint()
          ..color = b
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(_ArchMarkPainter old) =>
      old.color != color || old.border != border;
}

Path _wave(Size size, {required double amplitude, required double length}) {
  final path = Path()..moveTo(0, size.height / 2);
  for (var x = 0.0; x <= size.width; x += 2) {
    path.lineTo(
      x,
      size.height / 2 + amplitude * math.sin(2 * math.pi * x / length),
    );
  }
  return path;
}

/// A thin sine line that closes a section.
class WaveLine extends StatelessWidget {
  const WaveLine({super.key, this.height = 12});
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    width: double.infinity,
    child: CustomPaint(painter: _WaveLinePainter(PwaniColors.of(context).wave)),
  );
}

class _WaveLinePainter extends CustomPainter {
  const _WaveLinePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) => canvas.drawPath(
    _wave(size, amplitude: size.height / 4, length: 84),
    Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round,
  );

  @override
  bool shouldRepaint(_WaveLinePainter old) => old.color != color;
}

/// Two layers of waves (Lagoon over Ocean in light) closing a screen.
class WaveFooter extends StatelessWidget {
  const WaveFooter({super.key, this.height = 48});
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = PwaniColors.of(context);
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _WaveFooterPainter(c.waveShallow, c.waveDeep),
      ),
    );
  }
}

class _WaveFooterPainter extends CustomPainter {
  const _WaveFooterPainter(this.light, this.deep);
  final Color light;
  final Color deep;

  Path _filled(Size size, double top, double phase) {
    final path = Path()..moveTo(0, size.height);
    for (var x = 0.0; x <= size.width; x += 2) {
      path.lineTo(x, top + 6 * math.sin(2 * math.pi * (x + phase) / 160));
    }
    return path
      ..lineTo(size.width, size.height)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..drawPath(_filled(size, size.height * 0.3, 0), Paint()..color = light)
      ..drawPath(_filled(size, size.height * 0.6, 60), Paint()..color = deep);
  }

  @override
  bool shouldRepaint(_WaveFooterPainter old) =>
      old.light != light || old.deep != deep;
}
