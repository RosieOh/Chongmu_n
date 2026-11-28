import 'package:chongmu_n/models/round_item.dart';
import 'package:chongmu_n/screens/history_screen.dart';
import 'package:chongmu_n/screens/home_screen.dart';
import 'package:chongmu_n/screens/ledger_screen.dart';
import 'package:chongmu_n/screens/main_screen.dart';
import 'package:chongmu_n/screens/receipt_screen.dart';
import 'package:chongmu_n/screens/settings_screen.dart';
import 'package:chongmu_n/screens/splash_screen.dart';
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

  Future<void> pumpScreenNoSettle(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: screen));
    await tester.pump();
  }

  /// 홈 화면의 세로 스크롤 (배너 PageView 와 구분)
  final vertical = find.byWidgetPredicate(
      (w) => w is Scrollable && w.axisDirection == AxisDirection.down);

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
        expect(find.text('바로 송금 링크 (선택)'), findsOneWidget);
        expect(find.text('나중에 미입금 알림 받기'), findsOneWidget);
      });

      testWidgets('메인 화면 (할인·개별 추가·다른 결제자)', (tester) async {
        final s = Settlement.sample()..isSample = false;
        final r = s.rounds.first
          ..soberDiscount = true
          ..discountPercent = 30
          ..payerId = s.members[2].id;
        r.soberIds.add(s.members[3].id);
        r.setExtra(s.members[1].id, 12000);
        s.rounds[1]
          ..freeMode = true
          ..freeIds.add(s.members[0].id);
        s.roundMode = RoundMode.nearest;
        await AppStorage.saveSettlement(s);
        await pumpScreen(tester, const HomeScreen(), mode);
        expect(find.text('안 마신 사람 1명은 30% 덜 내요'), findsOneWidget);
        expect(find.text('민수 +12,000원'), findsOneWidget);
        expect(find.text('면제 인원 (생일자 등)'), findsNWidgets(2));
        expect(find.text('반올림'), findsOneWidget);
      });

      testWidgets('정산 입력 (술값 따로 · 비율 · 찬조 · 적립금)', (tester) async {
        final old = Settlement.sample()
          ..isSample = false
          ..groupName = '동기'
          ..roundUnit = 1000;
        await AppStorage.saveSettlement(old); // 적립금 2,000원
        final s = Settlement.sample()
          ..isSample = false
          ..groupName = '동기';
        final r = s.rounds.first
          ..soberDiscount = true
          ..soberMode = SoberMode.split
          ..alcoholAmount = 40000;
        r.soberIds.add(s.members[3].id);
        r.setWeight(s.members[2].id, 0.5);
        r.setSponsor(kExternalSponsor, 10000);
        s.setSponsor(s.members[1].id, 20000);
        await AppStorage.saveSettlement(s);
        await pumpScreen(tester, const HomeScreen(), mode);

        expect(find.text('술값 따로'), findsWidgets);
        expect(find.textContaining('술값 40,000원은 마신 3명이'), findsOneWidget);
        expect(find.text('지영 0.5배'), findsOneWidget);
        expect(find.text('회사·외부 지원 10,000원'), findsOneWidget);
        expect(find.text('민수 20,000원'), findsOneWidget);
        expect(find.text('"동기" 적립금 2,000원'), findsOneWidget);

        await tester.ensureVisible(find.text('"동기" 적립금 2,000원'));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(Switch).last);
        await tester.pumpAndSettle();
        expect(AppStorage.loadSettlement().carryIn, 2000);
      });

      testWidgets('영수증 산식 + 카카오페이 옮겨 적기', (tester) async {
        final s = Settlement.sample()..isSample = false;
        s.setSponsor(s.members[1].id, 46000);
        await pumpScreen(tester, ReceiptScreen(settlement: s), mode);
        expect(find.text('1차 30,000 − 지원·적립 7,500 = 22,500'), findsOneWidget);
        await tester.ensureVisible(find.text('카카오페이로 정산 요청하기'));
        await tester.tap(find.text('카카오페이로 정산 요청하기'));
        await tester.pumpAndSettle();
        expect(find.text('카카오페이에 옮겨 적기'), findsOneWidget);
        expect(find.text('요청 메시지 (25자까지)'), findsOneWidget);
      });

      testWidgets('영수증 화면 (송금 정리)', (tester) async {
        final s = Settlement.sample();
        s.rounds[1].payerId = s.members[1].id;
        await pumpScreen(tester, ReceiptScreen(settlement: s), mode);
        expect(find.text('송금 확인'), findsOneWidget);
        expect(find.text('송금 정리'), findsOneWidget);
        expect(find.text('받는 사람 계좌'), findsOneWidget);

        // 영수증에서 이름을 누르면 개인별 상세
        await tester.tap(find.text('지영').first);
        await tester.pumpAndSettle();
        expect(find.text('개인 메시지 복사'), findsOneWidget);
      });

      testWidgets('메인 화면 (계산기 · 할인·쿠폰)', (tester) async {
        final s = Settlement.sample()..isSample = false;
        s.rounds.first.setSale(percent: 10, coupon: 8000);
        await AppStorage.saveSettlement(s);
        await pumpScreen(tester, const HomeScreen(), mode);
        expect(
            find.text('10% 할인 + 쿠폰 8,000원 → 실제 결제 100,000원'), findsOneWidget);
        expect(find.text('164,000원'), findsOneWidget); // 할인 후 총액

        await tester.ensureVisible(find.text('계산기').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('계산기').first);
        await tester.pumpAndSettle();
        expect(find.text('금액 계산기'), findsOneWidget);
        for (final k in [
          'C',
          '3',
          '2',
          '0',
          '0',
          '0',
          '+',
          '1',
          '5',
          '00',
          '0'
        ]) {
          await tester.tap(find.text(k).last);
          await tester.pump();
        }
        expect(find.text('= 47,000원'), findsOneWidget);
        await tester.tap(find.text('47,000원 입력'));
        await tester.pumpAndSettle();
        expect(find.text('47,000'), findsOneWidget);
      });

      testWidgets('메인 화면 (모임 그룹 불러오기)', (tester) async {
        await AppStorage.saveGroup(
            MemberGroup(name: '대학 동기', names: ['나', '철수', '영희']));
        await pumpScreen(tester, const HomeScreen(), mode);
        await tester.tap(find.text('모임 그룹'));
        await tester.pumpAndSettle();
        expect(find.text('지금 멤버 4명을 그룹으로 저장'), findsOneWidget);
        expect(find.text('대학 동기 · 3명'), findsOneWidget);

        await tester.tap(find.text('대학 동기 · 3명'));
        await tester.pumpAndSettle();
        expect(find.text('철수'), findsWidgets);
        expect(find.text('영희'), findsWidgets);
        expect(find.text('민수'), findsNothing); // 예시 멤버는 빠짐
      });

      testWidgets('미수금 장부 (사람별 · 입금 확인 · 빈 화면)', (tester) async {
        await pumpScreen(tester, const LedgerScreen(currentId: 'none'), mode);
        expect(find.text('받을 돈이 없어요'), findsOneWidget);

        final s = Settlement.sample()..isSample = false;
        await AppStorage.saveSettlement(s);
        await pumpScreen(tester, const LedgerScreen(currentId: 'none'), mode);
        expect(find.text('아직 받지 못한 돈'), findsOneWidget);
        expect(find.text('3명 · 3건'), findsOneWidget);
        expect(find.text('안내 메시지 복사'), findsNWidgets(3));

        await tester.tap(find.byTooltip('민수 입금 확인'));
        await tester.pumpAndSettle();
        expect(find.text('2명 · 2건'), findsOneWidget);
        expect(AppStorage.historyById(s.id)!.isPaid(s.members[1].id), isTrue);
      });

      testWidgets('홈 화면 (첫 실행 / 기록 있음)', (tester) async {
        final now = DateTime(2026, 11, 28, 20);
        await pumpScreen(tester, MainScreen(now: now), mode);
        expect(find.text('새 정산'), findsOneWidget);
        expect(find.text('예시 정산\n둘러보기'), findsOneWidget);
        expect(find.text('계좌 등록'), findsOneWidget);
        expect(find.text('필수'), findsOneWidget);
        await tester.scrollUntilVisible(find.text('금액을 입력한 정산은 여기에 모여요'), 200, scrollable: vertical);

        final s = Settlement.sample()..isSample = false;
        s.title = '불금 팀 회식';
        await AppStorage.saveSettlement(s);
        await pumpScreen(tester, MainScreen(now: s.createdAt), mode);
        expect(find.textContaining('불금 팀 회식\n'), findsOneWidget);
        await tester.scrollUntilVisible(find.text('작성 중'), 200, scrollable: vertical);
        expect(find.text('전체보기'), findsOneWidget);
        expect(find.textContaining('아직 못 받은 돈'), findsOneWidget);
      });

      testWidgets('홈 화면 하단 탭 이동', (tester) async {
        await pumpScreen(tester, const MainScreen(), mode);
        await tester.tap(find.text('기록'));
        await tester.pumpAndSettle();
        expect(find.byType(HistoryScreen), findsOneWidget);
        await tester.tap(find.text('장부'));
        await tester.pumpAndSettle();
        expect(find.byType(LedgerScreen), findsOneWidget);
        await tester.tap(find.text('설정').last);
        await tester.pumpAndSettle();
        expect(find.byType(SettingsScreen), findsOneWidget);
        await tester.tap(find.text('홈'));
        await tester.pumpAndSettle();
        expect(find.text('새 정산'), findsOneWidget);
      });

      testWidgets('홈 화면 → 새 정산 → 뒤로 가면 갱신', (tester) async {
        final s = Settlement.sample()..isSample = false;
        s.title = '지난 회식';
        await AppStorage.saveSettlement(s);
        await pumpScreen(tester, const MainScreen(), mode);
        await tester.tap(find.text('새 정산'));
        await tester.pumpAndSettle();
        expect(find.byType(HomeScreen), findsOneWidget);
        expect(AppStorage.loadSettlement().id, isNot(s.id));

        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(MainScreen), findsOneWidget);
        expect(find.text('쓰던 정산\n마저 하기'), findsOneWidget);
        await tester.scrollUntilVisible(find.text('지난 회식'), 200, scrollable: vertical);
        expect(find.text('지난 회식'), findsOneWidget); // 최근 정산에만 남음
      });

      testWidgets('기록 탭에서 고르면 그 정산을 열어요', (tester) async {
        final old = Settlement.blank()..title = '주말 등산';
        old.rounds.first.amount = 80000;
        await AppStorage.saveSettlement(old);
        final cur = Settlement.blank()..title = '오늘 회식';
        cur.rounds.first.amount = 50000;
        await AppStorage.saveSettlement(cur);

        await pumpScreen(tester, const MainScreen(), mode);
        await tester.tap(find.text('기록'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('주말 등산'));
        await tester.pumpAndSettle();
        expect(find.byType(HomeScreen), findsOneWidget);
        expect(AppStorage.loadSettlement().id, old.id);
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
        expect(find.text('정산 횟수'), findsOneWidget);
        expect(find.textContaining('받을 돈 '), findsOneWidget);

        await tester.enterText(find.byType(TextField), '없는모임');
        await tester.pumpAndSettle();
        expect(find.text('"없는모임" 검색 결과가 없어요'), findsOneWidget);
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

  testWidgets('스플래시 → 홈 화면으로 넘어감', (tester) async {
    await pumpScreenNoSettle(tester, const SplashScreen());
    expect(find.text('1/N이 안 맞는 회식도, 정산은 1분'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1700));
    await tester.pumpAndSettle();
    expect(find.byType(MainScreen), findsOneWidget);
    expect(find.byType(SplashScreen), findsNothing);
  });
}
