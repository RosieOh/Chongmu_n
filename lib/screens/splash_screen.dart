import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';
import 'main_screen.dart';

/// 앱을 켜면 처음 보이는 화면 — 로고가 튀어오르고 메인 화면으로 넘어가요.
/// (저장소 준비는 main() 에서 이미 끝났기 때문에 여기선 연출만 합니다)
class SplashScreen extends StatefulWidget {
  const SplashScreen(
      {super.key, this.duration = const Duration(milliseconds: 1600)});

  /// 스플래시가 머무는 시간
  final Duration duration;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..forward();

  late final Animation<double> _logoScale = CurvedAnimation(
    parent: _ctrl,
    curve: const Interval(0, 0.6, curve: Curves.easeOutBack),
  );
  late final Animation<double> _textFade = CurvedAnimation(
    parent: _ctrl,
    curve: const Interval(0.35, 0.85, curve: Curves.easeOut),
  );

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.duration, _goMain);
  }

  void _goMain() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 450),
      pageBuilder: (context, animation, secondary) => const MainScreen(),
      transitionsBuilder: (context, anim, secondary, child) =>
          FadeTransition(opacity: anim, child: child),
    ));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.primary,
        body: SizedBox(
          width: double.infinity,
          child: SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 5),
                ScaleTransition(
                  scale: _logoScale,
                  child: Container(
                    width: 112,
                    height: 112,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(34),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.22),
                      ),
                    ),
                    child: const AppLogo(size: 76, badge: false),
                  ),
                ),
                const SizedBox(height: 28),
                FadeTransition(
                  opacity: _textFade,
                  child: SlideTransition(
                    position: Tween(
                      begin: const Offset(0, 0.4),
                      end: Offset.zero,
                    ).animate(_textFade),
                    child: Column(
                      children: [
                        const AppWordmark(fontSize: 32, color: Colors.white),
                        const SizedBox(height: 10),
                        Text(
                          '1/N이 안 맞는 회식도, 정산은 1분',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.82),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(flex: 6),
                FadeTransition(
                  opacity: _textFade,
                  child: Text(
                    '술 안 마신 사람도, 따로 시킨 메뉴도 공평하게',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
