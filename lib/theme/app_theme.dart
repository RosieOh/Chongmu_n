import 'package:material_ui/material_ui.dart';

/// 🎨 퍼스널 컬러 — 여기 값만 바꾸면 앱 전체 색이 한 번에 바뀝니다.
/// Hex 코드 #00A88F 를 쓰려면 Color(0xFF00A88F) 처럼 앞에 0xFF 를 붙이세요.
class AppColors {
  AppColors._();

  /// 메인 브랜드 포인트 컬러 (버튼, 뱃지, 강조 숫자)
  static const Color primary = Color(0xFF00A88F);

  /// 메인 컬러의 10% 틴트 (선택된 칩, 연한 강조 배경) — primary 를 바꾸면 자동으로 따라 바뀜
  static final Color primaryLight = primary.withValues(alpha: 0.10);

  /// 금액·핵심 숫자용 딥 차콜
  static const Color darkText = Color(0xFF1E2229);

  /// 화면 배경 라이트 그레이
  static const Color background = Color(0xFFF4F6F8);

  /// 카드 배경 순백색
  static const Color cardBg = Color(0xFFFFFFFF);

  // ── 보조 컬러 ──
  static const Color subText = Color(0xFF8B95A1);
  static const Color hint = Color(0xFFB0B8C1);
  static const Color border = Color(0xFFE5E8EB);
  static const Color danger = Color(0xFFF04452);
  static const Color kakao = Color(0xFFFEE500);
  static const Color kakaoText = Color(0xFF191919);
}

/// 카드·입력창 등 반복되는 꾸밈 요소
class AppDecor {
  AppDecor._();

  static const double radius = 14;

  static final List<BoxShadow> shadow = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.05),
      blurRadius: 8,
      offset: const Offset(0, 2),
    ),
  ];

  /// 직방 스타일 흰색 카드 (radius 14 + 은은한 그림자)
  static final BoxDecoration card = BoxDecoration(
    color: AppColors.cardBg,
    borderRadius: BorderRadius.circular(radius),
    boxShadow: shadow,
  );

  /// 회색 박스형 입력창
  static InputDecoration boxInput(String hint) {
    final base = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide.none,
    );
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: AppColors.background,
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

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      brightness: Brightness.light,
    ).copyWith(surface: AppColors.cardBg);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.darkText,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.darkText,
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: AppColors.primary,
        selectionHandleColor: AppColors.primary,
        selectionColor: AppColors.primary.withValues(alpha: 0.25),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        isDense: true,
        border: InputBorder.none,
        hintStyle: TextStyle(color: AppColors.hint, fontWeight: FontWeight.w500),
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
          foregroundColor: AppColors.darkText,
          backgroundColor: AppColors.cardBg,
          side: const BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDecor.radius),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.darkText,
        actionTextColor: AppColors.primary,
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),
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
            Color.lerp(AppColors.primary, AppColors.darkText, 0.25)!,
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
