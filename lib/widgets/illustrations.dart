import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

/// 메인 화면 카드에 들어가는 납작한 일러스트 (이미지 파일 없이 코드로 그려요)
enum ArtKind { receipt, coins, people, glass, transfer }

class Illustration extends StatelessWidget {
  const Illustration(this.kind, {super.key, required this.width, this.height});

  final ArtKind kind;
  final double width;

  /// null 이면 정사각형
  final double? height;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: width,
      height: height ?? width,
      child: CustomPaint(painter: _ArtPainter(kind, dark: dark)),
    );
  }
}

class _ArtPainter extends CustomPainter {
  _ArtPainter(this.kind, {required this.dark});

  final ArtKind kind;
  final bool dark;

  static const _paper = Colors.white;
  static final _line = AppPalette.light.border;
  static final _ink = AppColors.charcoal;
  static final _coinEdge =
      Color.lerp(AppColors.accent, AppColors.charcoal, 0.22)!;
  static final _mint = Color.lerp(AppColors.primary, Colors.white, 0.55)!;

  Paint _fill(Color c) => Paint()
    ..color = c
    ..isAntiAlias = true;

  @override
  void paint(Canvas canvas, Size size) {
    switch (kind) {
      case ArtKind.receipt:
        _receipt(canvas, size);
      case ArtKind.coins:
        _coins(canvas, size);
      case ArtKind.people:
        _people(canvas, size);
      case ArtKind.glass:
        _glass(canvas, size);
      case ArtKind.transfer:
        _transfer(canvas, size);
    }
  }

  // ── 영수증 + 동전 ──
  void _receipt(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    canvas.save();
    canvas.translate(w * 0.46, h * 0.5);
    canvas.rotate(-8 * math.pi / 180);
    canvas.translate(-w * 0.46, -h * 0.5);

    final left = w * 0.14, right = w * 0.78, top = h * 0.06, bottom = h * 0.9;
    final paper = Path()
      ..moveTo(left, top + 8)
      ..quadraticBezierTo(left, top, left + 8, top)
      ..lineTo(right - 8, top)
      ..quadraticBezierTo(right, top, right, top + 8)
      ..lineTo(right, bottom);
    // 아래 톱니
    const teeth = 7;
    final step = (right - left) / teeth;
    for (var i = 0; i < teeth; i++) {
      final x = right - step * i;
      paper
        ..lineTo(x - step / 2, bottom - 7)
        ..lineTo(x - step, bottom);
    }
    paper.close();
    canvas.drawShadow(paper, Colors.black, 6, false);
    canvas.drawPath(paper, _fill(_paper));

    final lw = right - left;
    final p = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = h * 0.035;
    void bar(double y, double x0, double x1, Color c) => canvas.drawLine(
        Offset(left + lw * x0, y), Offset(left + lw * x1, y), p..color = c);

    bar(top + h * 0.1, 0.3, 0.7, _ink);
    for (var i = 0; i < 3; i++) {
      final y = top + h * (0.24 + i * 0.1);
      bar(y, 0.14, 0.46, _line);
      bar(y, 0.64, 0.86, _line);
    }
    // 점선
    final dashY = top + h * 0.56;
    for (var x = 0.14; x < 0.86; x += 0.09) {
      bar(dashY, x, x + 0.04, _line);
    }
    bar(top + h * 0.66, 0.14, 0.38, _ink);
    bar(top + h * 0.66, 0.56, 0.86, AppColors.primary);
    canvas.restore();

    // 동전
    final c = Offset(w * 0.8, h * 0.78);
    final r = w * 0.15;
    canvas.drawCircle(c + Offset(0, r * 0.16), r, _fill(_coinEdge));
    canvas.drawCircle(c, r, _fill(AppColors.accent));
    canvas.drawCircle(
      c,
      r * 0.62,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.14
        ..color = _coinEdge,
    );
  }

  // ── 쌓인 동전 ──
  void _coins(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final rx = w * 0.3, ry = h * 0.1, thick = h * 0.1;

    void stack(double cx, double baseY, int n) {
      for (var i = 0; i < n; i++) {
        final y = baseY - i * thick;
        final side = Rect.fromLTRB(cx - rx, y - thick, cx + rx, y);
        canvas.drawOval(
            Rect.fromCenter(
                center: Offset(cx, y), width: rx * 2, height: ry * 2),
            _fill(_coinEdge));
        canvas.drawRect(side, _fill(_coinEdge));
        canvas.drawOval(
            Rect.fromCenter(
                center: Offset(cx, y - thick), width: rx * 2, height: ry * 2),
            _fill(AppColors.accent));
      }
    }

    stack(w * 0.38, h * 0.88, 3);
    stack(w * 0.68, h * 0.92, 2);

    // 위로 향하는 화살표 (진행 중)
    final a = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.06
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final tip = Offset(w * 0.78, h * 0.12);
    canvas.drawLine(Offset(w * 0.78, h * 0.5), tip, a);
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx - w * 0.1, tip.dy + h * 0.1)
        ..lineTo(tip.dx, tip.dy)
        ..lineTo(tip.dx + w * 0.1, tip.dy + h * 0.1),
      a,
    );
  }

  // ── 사람 셋 ──
  void _people(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    void person(double cx, double scale, Color c) {
      final head = w * 0.11 * scale;
      final baseY = h * 0.94;
      final bodyW = w * 0.3 * scale;
      final bodyH = h * 0.32 * scale;
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(cx - bodyW / 2, baseY - bodyH, bodyW, bodyH),
          topLeft: Radius.circular(bodyW / 2),
          topRight: Radius.circular(bodyW / 2),
        ),
        _fill(c),
      );
      canvas.drawCircle(
          Offset(cx, baseY - bodyH - head * 1.15), head, _fill(c));
    }

    person(w * 0.24, 0.9, _mint);
    person(w * 0.76, 0.9, AppColors.accent);
    person(w * 0.5, 1.12, AppColors.primary);
  }

  // ── 맥주잔 ──
  void _glass(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final body = Rect.fromLTRB(w * 0.2, h * 0.28, w * 0.66, h * 0.92);
    // 손잡이
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTRB(w * 0.56, h * 0.42, w * 0.86, h * 0.76),
          Radius.circular(w * 0.12)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.07
        ..color = _paper.withValues(alpha: 0.9),
    );
    canvas.drawRRect(RRect.fromRectAndRadius(body, Radius.circular(w * 0.06)),
        _fill(AppColors.accent));
    // 거품
    final foam = _fill(_paper);
    for (final (x, r) in [(0.27, 0.11), (0.43, 0.13), (0.59, 0.1)]) {
      canvas.drawCircle(Offset(w * x, h * 0.28), w * r, foam);
    }
    canvas.drawRect(Rect.fromLTRB(w * 0.2, h * 0.26, w * 0.66, h * 0.36), foam);
    // 기포
    final bubble = _fill(_paper.withValues(alpha: 0.55));
    canvas.drawCircle(Offset(w * 0.34, h * 0.62), w * 0.03, bubble);
    canvas.drawCircle(Offset(w * 0.48, h * 0.74), w * 0.025, bubble);
    canvas.drawCircle(Offset(w * 0.4, h * 0.82), w * 0.02, bubble);
  }

  // ── 송금 화살표 ──
  void _transfer(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final r = w * 0.17;
    final a = Offset(w * 0.22, h * 0.66);
    final b = Offset(w * 0.78, h * 0.66);
    canvas.drawCircle(a, r, _fill(AppColors.primary));
    canvas.drawCircle(b, r, _fill(_ink.withValues(alpha: dark ? 1 : 0.85)));
    final arc = Paint()
      ..color = AppColors.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.06
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(a.dx + r * 0.2, a.dy - r * 1.2)
      ..quadraticBezierTo(w * 0.5, h * 0.0, b.dx - r * 0.2, b.dy - r * 1.2);
    canvas.drawPath(path, arc);
    final tip = Offset(b.dx - r * 0.2, b.dy - r * 1.2);
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx - w * 0.1, tip.dy - h * 0.04)
        ..lineTo(tip.dx, tip.dy)
        ..lineTo(tip.dx - w * 0.02, tip.dy - h * 0.13),
      arc..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_ArtPainter old) => old.kind != kind || old.dark != dark;
}
