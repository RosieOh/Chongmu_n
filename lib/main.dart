import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import 'models/round_item.dart';
import 'screens/splash_screen.dart';
import 'screens/settings_screen.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 세로 화면 고정
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // 로컬 저장소 준비 + PRO 상태 불러오기
  await AppStorage.init();
  ProManager.instance.load();
  ThemeModeController.instance.load();

  // TODO(AdMob 2단계): google_mobile_ads 주석 해제 후 아래 줄 활성화
  // await MobileAds.instance.initialize();

  runApp(const ChongmuApp());
}

class ChongmuApp extends StatelessWidget {
  const ChongmuApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 설정에서 화면 모드를 바꾸면 앱 전체가 화면 이동 없이 부드럽게 전환됩니다.
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeModeController.instance.mode,
      builder: (context, mode, _) => MaterialApp(
        title: '똑똑한 총무',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: mode,
        // 시스템 글자 크기를 너무 크게 설정해도 레이아웃이 깨지지 않도록 제한
        builder: (context, child) {
          final mq = MediaQuery.of(context);
          return MediaQuery(
            data: mq.copyWith(
              textScaler: mq.textScaler.clamp(maxScaleFactor: 1.3),
            ),
            child: child!,
          );
        },
        home: const SplashScreen(),
      ),
    );
  }
}
