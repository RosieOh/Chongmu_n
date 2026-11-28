import 'package:chongmu_n/models/round_item.dart';
import 'package:chongmu_n/screens/history_screen.dart';
import 'package:chongmu_n/screens/ledger_screen.dart';
import 'package:chongmu_n/services/reminder_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('예시 데이터: 1차 120,000원/4명 + 2차 64,000원/3명, 100원 올림', () {
    final s = Settlement.sample();
    expect(s.totalSpent, 184000);

    final results = s.buildResults();
    expect(results.length, 4);
    expect(results[0].pay, 51400); // 30,000 + 21,333.3 → 51,400
    expect(results[3].pay, 30000); // 1차만 참석
    expect(s.surplus, 200); // 총무 자투리
  });

  test('입금 확인: 토글 + 저장/불러오기 + 멤버 삭제 시 정리', () {
    final s = Settlement.sample();
    final minsu = s.members[1];
    expect(s.togglePaid(minsu.id), isTrue);
    expect(s.isPaid(minsu.id), isTrue);

    final restored = Settlement.fromJson(s.toJson());
    expect(restored.isPaid(minsu.id), isTrue);

    expect(s.togglePaid(minsu.id), isFalse);
    s.togglePaid(minsu.id);
    s.removeMember(minsu.id);
    expect(s.paidIds, isEmpty);

    // 새 정산을 시작하면 입금 체크는 초기화
    expect(Settlement.fresh(members: s.members).paidIds, isEmpty);
  });

  test('빈 정산: 멤버 4명 + 빈 차수 1개', () {
    final s = Settlement.blank();
    expect(s.members.map((m) => m.name), ['나(총무)', '참석자2', '참석자3', '참석자4']);
    expect(s.rounds.length, 1);
    expect(s.rounds.first.headCount, 4);
    expect(s.totalSpent, 0);
  });

  test('술 안 마신 사람 20% 할인', () {
    final s = Settlement.sample();
    final r = s.rounds.first
      ..amount = 100000
      ..soberDiscount = true;
    r.soberIds.add(s.members.last.id);
    // 가중치 합 3.8 → 술O 26,315.8 / 술X 21,052.6
    expect(r.perPerson(10), 26320);
    expect(r.soberPerPerson(10), 21060);
  });

  test('할인율 선택: 50% 할인 + 저장/불러오기, 잘못된 값은 기본 20%', () {
    final s = Settlement.sample();
    final r = s.rounds.first
      ..amount = 70000
      ..soberDiscount = true
      ..discountPercent = 50;
    r.soberIds.add(s.members.last.id);
    // 가중치 합 3.5 → 술O 20,000 / 술X 10,000
    expect(r.perPerson(100), 20000);
    expect(r.soberPerPerson(100), 10000);

    final restored = RoundItem.fromJson(r.toJson());
    expect(restored.discountPercent, 50);

    final legacy = r.toJson()..remove('discountPercent');
    expect(RoundItem.fromJson(legacy).discountPercent, 20);
    expect(
        RoundItem.fromJson(r.toJson()..['discountPercent'] = 77)
            .discountPercent,
        20);
  });

  test('개별 추가 금액: 먼저 빼고 나머지 N빵 + 참석 해제 시 정리', () {
    final s = Settlement.sample();
    final r = s.rounds.first; // 120,000원 / 4명
    final minsu = s.members[1];
    r.setExtra(minsu.id, 20000);
    expect(r.sharedAmount, 100000);
    expect(r.perPerson(100), 25000);
    expect(r.exactShareFor(minsu.id), 45000);
    expect(r.exactShareFor(s.members[0].id), 25000);
    // 총액은 그대로 맞아야 함
    final sum = r.participantIds
        .fold<double>(0, (acc, id) => acc + r.exactShareFor(id));
    expect(sum, closeTo(120000, 0.001));

    final restored = RoundItem.fromJson(r.toJson());
    expect(restored.extraOf(minsu.id), 20000);

    r.setExtra(minsu.id, 0);
    expect(r.extras, isEmpty);

    // 참석자가 아니면 설정 안 됨, 참석 해제하면 추가금도 삭제
    r.setExtra(minsu.id, 5000);
    r.removeParticipant(minsu.id);
    expect(r.extras, isEmpty);
    r.setExtra(minsu.id, 5000);
    expect(r.extras, isEmpty);

    r.setExtra(s.members[0].id, 999999);
    expect(r.extrasOverflow, isTrue);
    expect(r.sharedAmount, 0);
  });

  test('지난 정산 검색: 모임·멤버·장소 이름, 대소문자 무시', () {
    final s = Settlement.sample()..title = 'Friday 회식';
    expect(matchesHistoryQuery(s, ''), isTrue);
    expect(matchesHistoryQuery(s, 'friday'), isTrue);
    expect(matchesHistoryQuery(s, '지영'), isTrue);
    expect(matchesHistoryQuery(s, '호프'), isTrue);
    expect(matchesHistoryQuery(s, '노래방'), isFalse);
  });

  test('월별 지출: 최근 6개월(연도 넘김 포함), 짧은 금액 표시', () {
    Settlement at(DateTime d, int amount) => Settlement(
          createdAt: d,
          members: [Member(id: 'm', name: '나')],
          rounds: [
            RoundItem(id: 'r', amount: amount, participantIds: {'m'})
          ],
        );
    final items = [
      at(DateTime(2026, 2, 3), 184000),
      at(DateTime(2026, 2, 20), 16000),
      at(DateTime(2025, 10, 1), 50000),
      at(DateTime(2025, 8, 1), 99999), // 6개월 밖
    ];
    final data = monthlyTotals(items, DateTime(2026, 2, 24));
    expect(data.map((e) => e.$1.month), [9, 10, 11, 12, 1, 2]);
    expect(data.map((e) => e.$2), [0, 50000, 0, 0, 0, 200000]);

    expect(shortWon(0), '-');
    expect(shortWon(9500), '9,500');
    expect(shortWon(184000), '18.4만');
    expect(shortWon(200000), '20만');
    expect(shortWon(1250000), '125만');
  });

  test('이 멤버로 새 정산: 제목·멤버 유지, 금액·입금 초기화', () {
    final s = Settlement.sample()..togglePaid('x');
    final next =
        Settlement.fresh(members: s.members, roundUnit: 1000, title: s.title);
    expect(next.id, isNot(s.id));
    expect(next.title, '불금 팀 회식');
    expect(next.members.map((m) => m.name), s.members.map((m) => m.name));
    expect(next.totalSpent, 0);
    expect(next.roundUnit, 1000);
  });

  test('면제 인원: 0원, 나머지가 나눠 냄, 추가금도 나머지 부담, 입금 대상 제외', () {
    final s = Settlement.sample();
    final r = s.rounds.first; // 120,000원 / 4명
    final me = s.members[0], minsu = s.members[1];
    r.setExtra(minsu.id, 12000);
    r
      ..freeMode = true
      ..freeIds.add(minsu.id);
    expect(r.payingCount, 3);
    expect(r.exactShareFor(minsu.id), 0);
    expect(r.exactShareFor(me.id), 40000);
    expect(r.perPerson(100), 40000);

    s.rounds.removeAt(1); // 1차만 남김
    final dues = s.buildDues();
    expect(dues.any((d) => d.member.id == minsu.id), isFalse);
    expect(dues.length, 3);

    // 토글을 끄면 원래대로 (추가금도 다시 본인 부담)
    r.freeMode = false;
    expect(r.exactShareFor(minsu.id), 39000);

    final restored = RoundItem.fromJson((r..freeMode = true).toJson());
    expect(restored.isFree(minsu.id), isTrue);
  });

  test('자투리 계산 방식: 반올림 / 1원 단위 정확히', () {
    final s = Settlement.sample(); // 51,333.3원
    s.roundMode = RoundMode.nearest;
    expect(s.buildResults().first.pay, 51300);
    expect(s.surplus, lessThan(0));
    expect(s.roundingLabel, '100원 단위 반올림');

    s.roundUnit = 1;
    expect(s.buildResults().first.pay, 51333);
    expect(s.roundingLabel, '1원 단위 정확히');

    final restored = Settlement.fromJson(s.toJson());
    expect(restored.roundMode, RoundMode.nearest);
    expect(restored.roundUnit, 1);
    expect(Settlement.fromJson(s.toJson()..remove('roundMode')).roundMode,
        RoundMode.up);

    // 총무가 모자라도 송금 정리가 맞아떨어짐
    s.roundUnit = 1000;
    s.rounds[1].payerId = s.members[1].id;
    final sent = s.buildTransfers().fold(0, (a, t) => a + t.amount);
    expect(sent, greaterThan(0));
  });

  test('차수 복제: 참석자·할인·결제자 유지, 금액·추가금은 비움', () {
    final s = Settlement.sample();
    final r = s.rounds[1]
      ..soberDiscount = true
      ..payerId = s.members[1].id;
    r.soberIds.add(s.members[2].id);
    r.setExtra(s.members[0].id, 5000);
    final copy = r.duplicate();
    expect(copy.id, isNot(r.id));
    expect(copy.participantIds, r.participantIds);
    expect(identical(copy.participantIds, r.participantIds), isFalse);
    expect(copy.soberIds, r.soberIds);
    expect(copy.payerId, r.payerId);
    expect(copy.amount, 0);
    expect(copy.extras, isEmpty);
  });

  test('송금 링크 정리: 토스 아이디/주소, 카카오페이 주소만 허용', () {
    expect(normalizeTossLink(''), '');
    expect(normalizeTossLink('chongmu'), 'https://toss.me/chongmu');
    expect(normalizeTossLink(' toss.me/chongmu/ '), 'https://toss.me/chongmu');
    expect(normalizeTossLink('http://toss.me/a_b'), 'https://toss.me/a_b');
    expect(normalizeTossLink('https://evil.com/x'), isNull);
    expect(normalizeTossLink('한글 아이디'), isNull);

    expect(normalizeKakaoPayLink(''), '');
    expect(normalizeKakaoPayLink('qr.kakaopay.com/Ej7abc123'),
        'https://qr.kakaopay.com/Ej7abc123');
    expect(normalizeKakaoPayLink('https://toss.me/x'), isNull);
  });

  test('미입금 알림: 시각 계산(월말 넘김), 라벨, ID 고정, 저장/불러오기', () {
    final at = reminderTimeAfter(DateTime(2026, 11, 29, 23, 50), 3);
    expect(at, DateTime(2026, 12, 2, 20));
    expect(reminderLabel(at), '12월 2일 (수) 오후 8시');
    expect(reminderLabel(DateTime(2026, 12, 6, 0)), '12월 6일 (일) 오전 12시');

    expect(reminderIdFor('abc'), reminderIdFor('abc'));
    expect(reminderIdFor('abc'), isNot(reminderIdFor('abd')));
    expect(reminderIdFor('x'), greaterThanOrEqualTo(0));

    final s = Settlement.sample()..remindAt = at;
    final restored = Settlement.fromJson(s.toJson());
    expect(restored.remindAt, at);
    expect(restored.hasPendingReminder(DateTime(2026, 12, 1)), isTrue);
    expect(restored.hasPendingReminder(DateTime(2026, 12, 3)), isFalse);
    expect(Settlement.sample().toJson().containsKey('remindAt'), isFalse);
  });

  group('결제자 지정 / 송금 정리', () {
    test('총무 혼자 결제하면 기존처럼 전원이 총무에게 입금', () {
      final s = Settlement.sample();
      expect(s.usesTransfers, isFalse);
      final dues = s.buildDues();
      expect(dues.length, 4);
      expect(dues.first.amount, 51400);
    });

    test('2차를 민수가 결제: 송금 정리 + 자투리는 총무 몫', () {
      final s = Settlement.sample();
      final me = s.members[0], minsu = s.members[1];
      s.rounds[1].payerId = minsu.id; // 호프집 64,000원
      expect(s.usesTransfers, isTrue);

      // 부담액: 나 51,400 / 민수 51,400 / 지영 51,400 / 현우 30,000 (합 184,200)
      // 결제액: 나 120,000 / 민수 64,000 → 민수는 12,600 받아야 함
      final transfers = s.buildTransfers();
      final received = <String, int>{};
      final sent = <String, int>{};
      for (final t in transfers) {
        expect(t.amount, greaterThan(0));
        expect(t.from.id, isNot(t.to.id));
        received[t.to.id] = (received[t.to.id] ?? 0) + t.amount;
        sent[t.from.id] = (sent[t.from.id] ?? 0) + t.amount;
      }
      expect(received[minsu.id], 12600);
      // 총무는 120,000 - 51,400 + 자투리 200 = 68,800 받음
      expect(received[me.id], 68800);
      expect(sent.values.fold(0, (a, b) => a + b), 81400);

      // 입금 확인은 돈을 보내는 지영·현우만
      final dues = s.buildDues();
      expect(dues.map((d) => d.member.name).toSet(), {'지영', '현우'});
      expect(dues.fold(0, (a, d) => a + d.amount), 81400);
    });

    test('결제자 저장/불러오기, 결제자 삭제 시 총무로 되돌림', () {
      final s = Settlement.sample();
      final minsu = s.members[1];
      s.rounds[1].payerId = minsu.id;
      final restored = Settlement.fromJson(s.toJson());
      expect(restored.payerOf(restored.rounds[1]).name, '민수');

      s.removeMember(minsu.id);
      expect(s.rounds[1].payerId, isNull);
      expect(s.usesTransfers, isFalse);
    });
  });

  group('지난 정산 기록', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await AppStorage.init();
    });

    test('예시 데이터는 기록에 저장하지 않음', () async {
      await AppStorage.saveSettlement(Settlement.sample());
      expect(AppStorage.loadHistory(), isEmpty);
    });

    test('금액이 0원인 새 정산은 저장하지 않고, 금액 입력 후 저장', () async {
      final s = Settlement.blank();
      await AppStorage.saveSettlement(s);
      expect(AppStorage.loadHistory(), isEmpty);

      s.rounds.first.amount = 80000;
      await AppStorage.saveSettlement(s);
      expect(AppStorage.loadHistory().single.id, s.id);

      // 같은 정산을 다시 저장하면 새 항목이 아니라 갱신
      s.title = '주말 등산';
      await AppStorage.saveSettlement(s);
      final history = AppStorage.loadHistory();
      expect(history.length, 1);
      expect(history.single.title, '주말 등산');
    });

    test('수정한 예시 데이터는 저장, 최신순 정렬, 앱 재시작 후에도 유지', () async {
      final older = Settlement.sample()..isSample = false;
      final newer = Settlement(
        createdAt: older.createdAt.add(const Duration(days: 1)),
        members: [Member(id: 'm1', name: '나')],
        rounds: [
          RoundItem(id: 'r1', amount: 10000, participantIds: {'m1'})
        ],
      );
      await AppStorage.saveSettlement(older);
      await AppStorage.saveSettlement(newer);

      await AppStorage.init(); // 앱 재시작 흉내
      final history = AppStorage.loadHistory();
      expect(history.map((e) => e.id), [newer.id, older.id]);
      expect(history.last.totalSpent, 184000);
    });

    test('삭제와 되돌리기', () async {
      final s = Settlement.blank();
      s.rounds.first.amount = 50000;
      await AppStorage.saveSettlement(s);

      final copy = AppStorage.historyById(s.id)!;
      await AppStorage.deleteHistory(s.id);
      expect(AppStorage.loadHistory(), isEmpty);

      await AppStorage.restoreHistory(copy);
      expect(AppStorage.historyById(s.id)?.totalSpent, 50000);
    });

    test('지난 멤버 이름: 자주 함께한 순, 기본 이름·총무 제외', () async {
      Settlement make(List<String> names, int day) => Settlement(
            createdAt: DateTime(2026, 1, day),
            members: [
              for (var i = 0; i < names.length; i++)
                Member(id: 'm$i', name: names[i])
            ],
            rounds: [
              RoundItem(id: 'r', amount: 10000, participantIds: {'m0'})
            ],
          );
      await AppStorage.saveSettlement(make(['나(총무)', '민수', '참석자3'], 1));
      await AppStorage.saveSettlement(make(['나(총무)', '지영', '민수'], 2));
      await AppStorage.saveSettlement(make(['나(총무)', '현우'], 3));
      expect(AppStorage.recentMemberNames(), ['민수', '현우', '지영']);
    });

    test('백업/복원: 기록·계좌 옮기기, PRO 는 제외, 잘못된 형식은 거부', () async {
      final a = Settlement.blank()..title = 'A';
      a.rounds.first.amount = 30000;
      a.rounds.first.payerId = a.members[1].id;
      await AppStorage.saveSettlement(a);
      await AppStorage.setAccountNumber('3333-01');
      await AppStorage.setPro(true);
      await AppStorage.setTossLink('https://toss.me/chongmu');
      final current = Settlement.blank()..title = '작성 중';
      current.rounds.first.amount = 5000;
      final backup = AppStorage.exportBackup(current);

      // 새 휴대폰
      SharedPreferences.setMockInitialValues({});
      await AppStorage.init();
      expect(await AppStorage.importBackup(backup), 2);
      final history = AppStorage.loadHistory();
      expect(history.map((e) => e.title).toSet(), {'A', '작성 중'});
      final restored = history.firstWhere((e) => e.title == 'A');
      expect(restored.usesTransfers, isTrue);
      expect(AppStorage.accountNumber, '3333-01');
      expect(AppStorage.isPro, isFalse);
      expect(AppStorage.tossLink, 'https://toss.me/chongmu');

      // 두 번 복원해도 중복되지 않음
      await AppStorage.importBackup(backup);
      expect(AppStorage.loadHistory().length, 2);

      expect(() => AppStorage.importBackup('hello'), throwsFormatException);
      expect(() => AppStorage.importBackup('{"app":"other"}'),
          throwsFormatException);
    });

    test('멤버 계좌: 정산에 저장 + 이름 기준으로 기억', () async {
      final m = Member(id: 'a', name: '지영', account: '토스 1000');
      expect(Member.fromJson(m.toJson()).account, '토스 1000');
      expect(
          Member(id: 'b', name: 'x').toJson().containsKey('account'), isFalse);

      await AppStorage.rememberAccount(' 지영 ', '토스 1000');
      expect(AppStorage.accountForName('지영'), '토스 1000');
      await AppStorage.rememberAccount('지영', '');
      expect(AppStorage.accountForName('지영'), '');
    });

    test('불러온 기록을 수정해도 저장본은 그대로 (복사본)', () async {
      final s = Settlement.blank();
      s.rounds.first.amount = 50000;
      await AppStorage.saveSettlement(s);

      AppStorage.historyById(s.id)!.rounds.first.amount = 1;
      expect(AppStorage.historyById(s.id)!.totalSpent, 50000);
    });

    test('모임 그룹: 저장(같은 이름 덮어쓰기), 삭제, 백업에 포함', () async {
      await AppStorage.saveGroup(MemberGroup(name: '동기', names: ['나', '민수']));
      await AppStorage.saveGroup(MemberGroup(name: '팀', names: ['나', '지영']));
      await AppStorage.saveGroup(
          MemberGroup(name: '동기', names: ['나', '민수', '현우']));
      expect(AppStorage.groups.map((g) => g.name), ['동기', '팀']);
      expect(AppStorage.groups.first.names, ['나', '민수', '현우']);

      final backup = AppStorage.exportBackup(Settlement.blank());
      await AppStorage.deleteGroup('동기');
      expect(AppStorage.groups.map((g) => g.name), ['팀']);

      await AppStorage.importBackup(backup);
      expect(AppStorage.groups.map((g) => g.name).toSet(), {'동기', '팀'});

      expect(
          MemberGroup.fromJson({
            'name': '',
            'names': ['a']
          }),
          isNull);
      expect(MemberGroup.fromJson({'name': 'x', 'names': []}), isNull);
    });

    test('미수금 장부: 기록에서 입금 처리', () async {
      final s = Settlement.sample()..isSample = false;
      await AppStorage.saveSettlement(s);
      final minsu = s.members[1];
      expect(buildLedger(AppStorage.loadHistory()).length, 3);

      await AppStorage.setHistoryPaid(s.id, minsu.id, true);
      expect(AppStorage.historyById(s.id)!.isPaid(minsu.id), isTrue);
      expect(buildLedger(AppStorage.loadHistory()).map((e) => e.name),
          isNot(contains('민수')));

      await AppStorage.init(); // 재시작 후에도 유지
      expect(AppStorage.historyById(s.id)!.isPaid(minsu.id), isTrue);
    });
  });

  test('금액 계산식: 사칙연산, 곱셈 먼저, 잘못된 식은 null', () {
    expect(evalAmount('32,000+15,000'), 47000);
    expect(evalAmount('120000÷4'), 30000);
    expect(evalAmount('10000+2×3000'), 16000);
    expect(evalAmount('50000-12000-8000'), 30000);
    expect(evalAmount('10000/3'), 3333);
    expect(evalAmount(' 5 000 '), 5000);
    expect(evalAmount(''), isNull);
    expect(evalAmount('1000+'), isNull);
    expect(evalAmount('+1000'), isNull);
    expect(evalAmount('1000÷0'), isNull);
    expect(evalAmount('1000-5000'), isNull);
    expect(evalAmount('12a'), isNull);
    expect(isAmountExpr('32,000+15,000'), isTrue);
    expect(isAmountExpr('32,000'), isFalse);
  });

  test('할인·쿠폰: 할인율 먼저, 쿠폰 차감, 결제 금액 초과 방지, 저장', () {
    final s = Settlement.sample();
    final r = s.rounds.first; // 120,000원 / 4명
    r.setSale(percent: 10, coupon: 8000); // 120,000 - 12,000 - 8,000
    expect(r.saleTotal, 20000);
    expect(r.netAmount, 100000);
    expect(r.perPerson(100), 25000);
    expect(s.totalSpent, 164000);
    expect(s.totalSaved, 20000);

    final restored = RoundItem.fromJson(r.toJson());
    expect(restored.salePercent, 10);
    expect(restored.couponAmount, 8000);
    expect(RoundItem(id: 'x').toJson().containsKey('salePercent'), isFalse);

    r.setSale(percent: 150, coupon: -1);
    expect(r.salePercent, 100);
    expect(r.couponAmount, 0);
    expect(r.netAmount, 0);

    r.setSale(percent: 0, coupon: 999999);
    expect(r.netAmount, 0);
    expect(r.extrasOverflow, isFalse);
    r.setExtra(s.members[1].id, 1000);
    expect(r.extrasOverflow, isTrue);
  });

  test('할인 + 다른 사람 결제: 실제 결제 금액 기준으로 송금 정리', () {
    final s = Settlement.sample();
    final minsu = s.members[1];
    s.rounds[1]
      ..payerId = minsu.id
      ..setSale(percent: 0, coupon: 4000); // 64,000 → 60,000 / 3명
    final res = s.buildResults();
    final collected = Settlement.totalCollected(res);
    expect(collected - s.totalSpent, inInclusiveRange(0, 400));
    // 민수가 받을 돈 = 60,000 - 민수 몫
    final minsuPay = res.firstWhere((p) => p.member.id == minsu.id).pay;
    final toMinsu = s
        .buildTransfers(res)
        .where((t) => t.to.id == minsu.id)
        .fold(0, (sum, t) => sum + t.amount);
    expect(toMinsu, 60000 - minsuPay);
  });

  test('미수금 장부: 사람별 합산, 입금·예시·총무 제외, 많은 순', () {
    final a = Settlement.sample()..isSample = false;
    final b = Settlement.sample()..isSample = false;
    b.members[1].name = ' 민수 ';
    b.rounds.removeLast(); // 1차만: 1인 30,000원
    a.togglePaid(a.members[2].id); // 지영 입금

    final ledger = buildLedger([a, b, Settlement.sample()]);
    final names = ledger.map((e) => e.name).toList();
    expect(names, isNot(contains('나(총무)')));
    expect(names.first, '민수'); // 51,400 + 30,000
    expect(ledger.first.total, 81400);
    expect(ledger.first.items.length, 2);
    // 지영은 b 정산 한 건만
    expect(ledger.firstWhere((e) => e.name == '지영').items.single.settlement,
        same(b));
  });

  test('미수금 안내 메시지: 정산별 금액·합계·계좌, 송금 정리 섞이면 계좌 생략', () {
    final a = Settlement.sample()
      ..isSample = false
      ..title = '불금';
    final b = Settlement.sample()..isSample = false;
    b.rounds.removeLast();
    final entry = buildLedger([a, b]).firstWhere((e) => e.name == '민수');

    final text = ledgerReminderText(entry,
        account: '토스뱅크 1000 (나)', payLinks: ['· 토스 https://toss.me/me']);
    expect(text, contains('민수님'));
    expect(text, contains('· 불금 ('));
    expect(text, contains('· 불금 팀 회식 ('));
    expect(text, contains('= 합계 81,400원'));
    expect(text, contains('토스뱅크 1000 (나)'));
    expect(text, contains('https://toss.me/me'));

    b.rounds.first.payerId = b.members[2].id; // 지영이 결제 → 송금 정리
    final mixed = buildLedger([a, b]).firstWhere((e) => e.name == '민수');
    expect(ledgerReminderText(mixed, account: '토스뱅크 1000'),
        isNot(contains('토스뱅크')));
  });

  // ───────── v1.4: 술값 따로 · 비율 · 찬조 · 적립금 ─────────

  Settlement four(int amount) {
    final ms = [
      for (final n in ['나', 'A', 'B', 'C']) Member(id: n, name: n),
    ];
    return Settlement(
      members: ms,
      rounds: [
        RoundItem(
            id: 'r1', amount: amount, participantIds: {'나', 'A', 'B', 'C'}),
      ],
    );
  }

  test('술값 따로: 술값은 마신 사람끼리, 나머지는 모두가', () {
    final s = four(100000);
    final r = s.rounds.first
      ..soberDiscount = true
      ..soberMode = SoberMode.split
      ..alcoholAmount = 40000
      ..soberIds.add('C');
    // 음식 60,000/4 = 15,000 · 술 40,000/3 = 13,333.3
    expect(r.exactShareFor('C'), closeTo(15000, 0.01));
    expect(r.exactShareFor('A'), closeTo(28333.33, 0.01));
    expect(r.perPerson(100), 28400);
    expect(r.soberPerPerson(100), 15000);
    final pays = {for (final p in s.buildResults()) p.member.id: p.pay};
    expect(pays['C'], 15000);
    expect(pays['A'], 28400);

    // 술값이 공통 금액보다 크면 경고 + 공통 금액까지만
    r.alcoholAmount = 150000;
    expect(r.alcoholOverflow, isTrue);
    expect(r.alcoholPart, 100000);

    // 모두 안 마셨으면 술값을 따로 나누지 않음
    r
      ..alcoholAmount = 40000
      ..soberIds.addAll(['나', 'A', 'B']);
    expect(r.alcoholPart, 0);
    expect(r.exactShareFor('A'), closeTo(25000, 0.01));
  });

  test('사람별 비율: 0.5배는 절반만, 할인율 모드와 함께 곱해짐', () {
    final s = four(90000);
    final r = s.rounds.first..removeParticipant('C');
    r.setWeight('A', 0.5); // 총 비율 2.5 → 1배 36,000
    expect(r.exactShareFor('A'), closeTo(18000, 0.01));
    expect(r.exactShareFor('B'), closeTo(36000, 0.01));
    r.setWeight('A', 1.0);
    expect(r.hasWeights, isFalse);

    r
      ..setWeight('A', 0.5)
      ..soberDiscount = true
      ..soberMode = SoberMode.discount
      ..discountPercent = 50
      ..soberIds.add('A'); // 0.5 × 0.5 = 0.25 → 총 2.25
    expect(r.exactShareFor('A'), closeTo(10000, 0.01));
    expect(Settlement.fromJson(s.toJson()).rounds.first.weights['A'], 0.5);
  });

  test('차수 찬조: 나눌 금액에서 먼저 빼고, 찬조자는 찬조금 + 자기 몫', () {
    final s = four(100000);
    final r = s.rounds.first..setSponsor('A', 20000);
    final pays = {for (final p in s.buildResults()) p.member.id: p.pay};
    expect(pays['B'], 20000);
    expect(pays['A'], 40000);
    expect(s.totalToCollect, 100000);

    // 외부(회사) 지원은 아무도 내지 않고, 걷을 돈이 줄어요
    r
      ..setSponsor('A', 0)
      ..setSponsor(kExternalSponsor, 20000);
    expect(s.externalTotal, 20000);
    expect(s.totalToCollect, 80000);
    expect(s.surplus, 0);

    // 찬조가 나눌 금액보다 크면 비율대로 줄여서 계산
    r.setSponsor('A', 180000); // 합계 200,000 → 절반씩
    expect(r.sponsorsOverflow, isTrue);
    expect(r.sponsorOf('A'), 90000);
    expect(r.externalSponsor, 10000);
  });

  test('전체 찬조: 모두의 몫에서 같은 비율로 빠지고 산식에 표시', () {
    final s = Settlement.sample()..isSample = false;
    final minsu = s.members[1];
    s.setSponsor(minsu.id, 46000); // 184,000 중 46,000 → 모두 75%
    final results = s.buildResults();
    final hyunwoo = results.firstWhere((p) => p.member.name == '현우');
    expect(hyunwoo.exactTotal, closeTo(22500, 0.01));
    final m = results.firstWhere((p) => p.member.id == minsu.id);
    expect(m.sponsorPaid, 46000);
    expect(s.formulaFor(m), contains('찬조 46,000'));
    expect(s.formulaFor(hyunwoo), '1차 30,000 − 지원·적립 7,500 = 22,500');
    expect(s.totalToCollect, 184000);

    final restored = Settlement.fromJson(s.toJson());
    expect(restored.sponsors[minsu.id], 46000);
  });

  test('모임 적립금: 자투리가 쌓이고 다음 정산에서 쓰면 줄어요', () async {
    SharedPreferences.setMockInitialValues({});
    await AppStorage.init();

    Settlement make() => Settlement.sample()
      ..isSample = false
      ..groupName = '동기'
      ..roundUnit = 1000;

    final s1 = make();
    expect(s1.surplus, 2000); // 186,000 걷고 184,000 지출
    await AppStorage.saveSettlement(s1);
    expect(AppStorage.groupFund('동기'), 2000);

    final s2 = make()..carryIn = AppStorage.groupFund('동기');
    expect(s2.effectiveCarryIn, 2000);
    expect(s2.totalToCollect, 182000);
    expect(s2.surplus, 1000); // 183,000 걷음
    await AppStorage.saveSettlement(s2);
    expect(AppStorage.groupFund('동기'), 1000);
    expect(AppStorage.groupFund('동기', excludeId: s2.id), 2000);
    expect(Settlement.fromJson(s2.toJson()).carryIn, 2000);
  });

  test('모임 그룹 자투리 규칙 저장 + 백업 권유 시점', () async {
    final g = MemberGroup(
      name: '동기',
      names: const ['나', '민수'],
      roundUnit: 1000,
      roundMode: RoundMode.nearest,
    );
    final back = MemberGroup.fromJson(g.toJson())!;
    expect(back.roundUnit, 1000);
    expect(back.roundMode, RoundMode.nearest);
    expect(back.ruleLabel, '1,000원 단위 반올림');
    expect(MemberGroup.fromJson({'name': 'x', 'names': ['a']})!.hasRule, isFalse);

    SharedPreferences.setMockInitialValues({});
    await AppStorage.init();
    final now = DateTime(2026, 11, 29);
    expect(AppStorage.backupDue(now), isFalse); // 기록이 적으면 권하지 않음
    for (var i = 0; i < 3; i++) {
      await AppStorage.saveSettlement(Settlement.sample()..isSample = false);
    }
    expect(AppStorage.backupDue(now), isTrue);
    await AppStorage.markBackedUp(now.subtract(const Duration(days: 3)));
    expect(AppStorage.backupDue(now), isFalse);
  });
}
