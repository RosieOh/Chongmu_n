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

  static const double radius = 14;

  static List<BoxShadow> shadow(BuildContext context) => [
        BoxShadow(
          color: context.colors.shadow,
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ];

  /// 직방 스타일 카드 (radius 14 + 은은한 그림자)
  static BoxDecoration card(BuildContext context) => BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: shadow(context),
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

/// 🖼 내가 만든 로고 (assets/images/logo.png)
/// 파일이 아직 없으면 퍼스널 컬러 배경의 기본 아이콘 로고가 대신 표시됩니다.
class AppLogo extends StatelessWidget {
  const AppLogo({
    super.key,
    this.size = 32,
    this.assetPath = 'assets/images/logo.png',
  });

  final double size;
  final String assetPath;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.28),
      child: Image.asset(
        assetPath,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _FallbackLogo(size: size),
      ),
    );
  }
}

class _FallbackLogo extends StatelessWidget {
  const _FallbackLogo({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary,
            Color.lerp(AppColors.primary, AppColors.charcoal, 0.25)!,
          ],
        ),
      ),
      child: Icon(
        Icons.receipt_long_rounded,
        color: Colors.white,
        size: size * 0.58,
      ),
    );
  }
}
