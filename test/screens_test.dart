import 'package:chongmu_n/models/round_item.dart';
import 'package:chongmu_n/screens/history_screen.dart';
import 'package:chongmu_n/screens/home_screen.dart';
import 'package:chongmu_n/screens/receipt_screen.dart';
import 'package:chongmu_n/screens/settings_screen.dart';
import 'package:chongmu_n/theme/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 모든 화면이 라이트/다크 모드에서 에러·레이아웃 깨짐 없이 그려지는지 확인
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppStorage.init();
    ProManager.instance.load();
  });

  Future<void> pumpScreen(
    WidgetTester tester,
    Widget screen,
    ThemeMode mode,
  ) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3); // iPhone 14 크기
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const SizedBox()); // 이전 화면 상태 초기화
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: mode,
      home: screen,
    ));
    await tester.pumpAndSettle();
  }

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    group('${mode.name} 모드', () {
      testWidgets('메인 화면', (tester) async {
        await pumpScreen(tester, const HomeScreen(), mode);
        expect(find.text('정산 영수증 만들기'), findsOneWidget);
        expect(find.text('184,000원'), findsOneWidget); // 총 지출 합계
      });

      testWidgets('영수증 화면 (입금 확인 포함)', (tester) async {
        final s = Settlement.sample();
        s.togglePaid(s.members.first.id);
        await pumpScreen(tester, ReceiptScreen(settlement: s), mode);
        expect(find.text('입금 확인'), findsOneWidget);
        expect(find.text('1/4명'), findsOneWidget);
      });

      testWidgets('설정 화면 (화면 모드 선택)', (tester) async {
        await pumpScreen(tester, const SettingsScreen(), mode);
        expect(find.text('화면 모드'), findsOneWidget);
        expect(find.text('다크'), findsOneWidget);
      });

      testWidgets('지난 정산 화면 (빈 목록 / 기록 있음)', (tester) async {
        await pumpScreen(tester, const HistoryScreen(currentId: 'none'), mode);
        expect(find.text('아직 정산 기록이 없어요'), findsOneWidget);

        final s = Settlement.blank()..title = '주말 등산';
        s.rounds.first.amount = 80000;
        await AppStorage.saveSettlement(s);
        await pumpScreen(tester, HistoryScreen(currentId: s.id), mode);
        expect(find.text('주말 등산'), findsOneWidget);
      });
    });
  }

  testWidgets('설정에서 다크 모드 선택 시 저장', (tester) async {
    ThemeModeController.instance.load();
    await pumpScreen(tester, const SettingsScreen(), ThemeMode.light);
    await tester.tap(find.text('다크'));
    await tester.pumpAndSettle();
    expect(ThemeModeController.instance.mode.value, ThemeMode.dark);
    expect(AppStorage.themeMode, 'dark');
  });
}
