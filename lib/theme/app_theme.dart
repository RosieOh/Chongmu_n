import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// 🎨 퍼스널 컬러 — 여기 값만 바꾸면 앱 전체 색이 한 번에 바뀝니다.
/// Hex 코드 #00A88F 를 쓰려면 Color(0xFF00A88F) 처럼 앞에 0xFF 를 붙이세요.
///
/// - 라이트/다크 모드와 상관없이 항상 같은 색: [AppColors] 의 상수들
/// - 모드에 따라 바뀌는 색(배경, 카드, 글자 등): [AppPalette] → 화면에서는 `context.colors.xxx`
class AppColors {
  AppColors._();

  /// 메인 브랜드 포인트 컬러 (버튼, 뱃지, 강조 숫자)
  static const Color primary = Color(0xFF00A88F);

  /// 딥 차콜 (로고 그라데이션 등 모드와 무관하게 쓰는 브랜드 보조색)
  static const Color charcoal = Color(0xFF1E2229);

  /// 로고 조각·포인트 강조용 웜 옐로
  static const Color accent = Color(0xFFFFC94D);

  static const Color danger = Color(0xFFF04452);
  static const Color kakao = Color(0xFFFEE500);
  static const Color kakaoText = Color(0xFF191919);

  /// 현재 모드(라이트/다크)의 팔레트
  static AppPalette of(BuildContext context) =>
      Theme.of(context).extension<AppPalette>() ?? AppPalette.light;
}

/// 모드별로 달라지는 색 묶음
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.primaryLight,
    required this.text,
    required this.background,
    required this.card,
    required this.subText,
    required this.hint,
    required this.border,
    required this.inverse,
    required this.shadow,
  });

  /// ☀️ 라이트 모드
  static final AppPalette light = AppPalette(
    primaryLight: AppColors.primary.withValues(alpha: 0.10), // 메인 컬러 10% 틴트
    text: AppColors.charcoal, // 금액·핵심 숫자 딥 차콜
    background: const Color(0xFFF4F6F8), // 눈이 편한 라이트 그레이
    card: const Color(0xFFFFFFFF), // 순백색 카드
    subText: const Color(0xFF8B95A1),
    hint: const Color(0xFFB0B8C1),
    border: const Color(0xFFE5E8EB),
    inverse: AppColors.charcoal, // 안내 카드·스낵바 같은 진한 배경
    shadow: Colors.black.withValues(alpha: 0.05),
  );

  /// 🌙 다크 모드
  static final AppPalette dark = AppPalette(
    primaryLight: AppColors.primary.withValues(alpha: 0.18),
    text: const Color(0xFFECEEF1),
    background: const Color(0xFF111418),
    card: const Color(0xFF1C2026),
    subText: const Color(0xFF9BA3AE),
    hint: const Color(0xFF5E6673),
    border: const Color(0xFF2C323A),
    inverse: const Color(0xFF2C323A),
    shadow: Colors.black.withValues(alpha: 0.30),
  );

  /// 선택된 칩, 연한 강조 배경
  final Color primaryLight;

  /// 기본 글자색 (금액·제목)
  final Color text;

  /// 화면 배경
  final Color background;

  /// 카드 배경
  final Color card;

  /// 보조 글자색 (설명, 라벨)
  final Color subText;

  /// 힌트·비활성 글자색
  final Color hint;

  /// 테두리·구분선
  final Color border;

  /// 진한 배경 (안내 카드, PRO 뱃지, 스낵바) — 위에 흰 글씨
  final Color inverse;

  /// 카드 그림자
  final Color shadow;

  @override
  AppPalette copyWith({
    Color? primaryLight,
    Color? text,
    Color? background,
    Color? card,
    Color? subText,
    Color? hint,
    Color? border,
    Color? inverse,
    Color? shadow,
  }) {
    return AppPalette(
      primaryLight: primaryLight ?? this.primaryLight,
      text: text ?? this.text,
      background: background ?? this.background,
      card: card ?? this.card,
      subText: subText ?? this.subText,
      hint: hint ?? this.hint,
      border: border ?? this.border,
      inverse: inverse ?? this.inverse,
      shadow: shadow ?? this.shadow,
    );
  }

  /// 모드 전환 시 색이 부드럽게 바뀌도록 보간
  @override
  AppPalette lerp(covariant AppPalette? other, double t) {
    if (other == null) return this;
    return AppPalette(
      primaryLight: Color.lerp(primaryLight, other.primaryLight, t)!,
      text: Color.lerp(text, other.text, t)!,
      background: Color.lerp(background, other.background, t)!,
      card: Color.lerp(card, other.card, t)!,
      subText: Color.lerp(subText, other.subText, t)!,
      hint: Color.lerp(hint, other.hint, t)!,
      border: Color.lerp(border, other.border, t)!,
      inverse: Color.lerp(inverse, other.inverse, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
    );
  }
}

/// 화면 코드에서 `context.colors.card` 처럼 짧게 쓰기 위한 확장
extension AppPaletteContext on BuildContext {
  AppPalette get colors => AppColors.of(this);
}

/// 카드·입력창 등 반복되는 꾸밈 요소
class AppDecor {
  AppDecor._();

  static const double radius = 18;

  static List<BoxShadow> shadow(BuildContext context) => [
        BoxShadow(
          color: context.colors.shadow,
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ];

  /// 기본 카드 — 회색 배경 위 그림자 없는 흰 카드 (메인 화면과 같은 톤)
  static BoxDecoration card(BuildContext context) => BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(radius),
      );

  /// 회색 박스형 입력창
  static InputDecoration boxInput(BuildContext context, String hint) {
    final base = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide.none,
    );
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: context.colors.background,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: base,
      enabledBorder: base,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
    );
  }
}

class AppTheme {
  AppTheme._();

  static final ThemeData light = _build(AppPalette.light, Brightness.light);
  static final ThemeData dark = _build(AppPalette.dark, Brightness.dark);

  static ThemeData _build(AppPalette p, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      brightness: brightness,
    ).copyWith(
      surface: p.card,
      onSurface: p.text,
      onPrimary: Colors.white,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
    );

    return base.copyWith(
      extensions: [p],
      scaffoldBackgroundColor: p.background,
      canvasColor: p.background,
      // 기본 글자색 — Text 에 color 를 안 주면 이 색이 적용됩니다
      textTheme: base.textTheme.apply(bodyColor: p.text, displayColor: p.text),
      iconTheme: IconThemeData(color: p.text),
      appBarTheme: AppBarTheme(
        backgroundColor: p.background,
        foregroundColor: p.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        // 상단 상태바(시계·배터리) 아이콘 색
        systemOverlayStyle:
            isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: p.text,
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: AppColors.primary,
        selectionHandleColor: AppColors.primary,
        selectionColor: AppColors.primary.withValues(alpha: 0.25),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        border: InputBorder.none,
        hintStyle: TextStyle(color: p.hint, fontWeight: FontWeight.w500),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.5),
          disabledForegroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDecor.radius),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.text,
          backgroundColor: p.card,
          side: BorderSide(color: p.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDecor.radius),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: p.inverse,
        actionTextColor: AppColors.primary,
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      dividerTheme: DividerThemeData(color: p.border, thickness: 1, space: 1),
      progressIndicatorTheme:
          const ProgressIndicatorThemeData(color: AppColors.primary),
    );
  }
}

/// 🖼 앱 로고 — 동전(파이)에서 한 조각이 빠져나온 모양 = "N빵 나누기"
///
/// 벡터로 그려서 어떤 크기에서도 선명합니다. 앱 아이콘 PNG 도 이 그림으로 만들어요.
/// - [badge] true: 브랜드 컬러 둥근 사각형 배지 위에 흰 마크 (기본)
/// - [badge] false: 배경 없이 마크만 (스플래시처럼 컬러 배경 위에 올릴 때)
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 32, this.badge = true});

  final double size;
  final bool badge;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: LogoPainter(badge: badge)),
    );
  }
}

/// [AppLogo] 를 그리는 페인터 (아이콘 이미지 생성에도 사용)
class LogoPainter extends CustomPainter {
  const LogoPainter({this.badge = true, this.rounded = true});

  final bool badge;

  /// false 면 배지를 꽉 찬 사각형으로 (iOS 앱 아이콘은 시스템이 모서리를 깎아요)
  final bool rounded;

  static const double _deg = math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final rect = Offset.zero & Size.square(s);

    if (badge) {
      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(AppColors.primary, Colors.white, 0.08)!,
            Color.lerp(AppColors.primary, AppColors.charcoal, 0.28)!,
          ],
        ).createShader(rect);
      if (rounded) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(s * 0.28)),
          paint,
        );
      } else {
        canvas.drawRect(rect, paint);
      }
    }

    // 마크 크기: 배지 안에서는 여백을 두고, 단독일 때는 꽉 채워요
    final scale = badge ? 1.0 : 1.32;
    final r = s * 0.27 * scale;
    final c = Offset(s * 0.47, s * 0.53);

    // ① 한 조각(60°)이 빠진 동전
    final pie = Path()
      ..moveTo(c.dx, c.dy)
      ..arcTo(Rect.fromCircle(center: c, radius: r), 0, 300 * _deg, false)
      ..close();
    canvas.drawPath(pie, Paint()..color = Colors.white);

    // 동전 안쪽 테두리 (동전 느낌) — 빠진 조각 자리엔 그리지 않아요
    canvas.save();
    canvas.clipPath(pie);
    canvas.drawCircle(
      c,
      r * 0.62,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.11
        ..color = AppColors.primary.withValues(alpha: 0.22),
    );
    canvas.restore();

    // ② 빠져나온 조각 — 오른쪽 위로 살짝 떨어져서
    const mid = -30 * _deg;
    final gap = r * 0.26;
    final sc = c + Offset(math.cos(mid), math.sin(mid)) * gap;
    final slice = Path()
      ..moveTo(sc.dx, sc.dy)
      ..arcTo(
          Rect.fromCircle(center: sc, radius: r), -60 * _deg, 60 * _deg, false)
      ..close();
    canvas.drawPath(slice, Paint()..color = AppColors.accent);
  }

  @override
  bool shouldRepaint(LogoPainter old) =>
      old.badge != badge || old.rounded != rounded;
}

/// "똑똑한 총무" 워드마크 (로고 옆 글자)
class AppWordmark extends StatelessWidget {
  const AppWordmark({super.key, this.fontSize = 20, this.color});

  final double fontSize;

  /// null 이면 모드별 기본 글자색 + '총무'만 브랜드 컬러
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w900,
      letterSpacing: -0.6,
      height: 1.1,
      color: color ?? context.colors.text,
    );
    return Text.rich(
      TextSpan(children: [
        const TextSpan(text: '똑똑한 '),
        TextSpan(
          text: '총무',
          style: TextStyle(color: color ?? AppColors.primary),
        ),
      ]),
      style: base,
      maxLines: 1,
    );
  }
}
