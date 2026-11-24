import 'package:chongmu_n/models/round_item.dart';
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

    test('불러온 기록을 수정해도 저장본은 그대로 (복사본)', () async {
      final s = Settlement.blank();
      s.rounds.first.amount = 50000;
      await AppStorage.saveSettlement(s);

      AppStorage.historyById(s.id)!.rounds.first.amount = 1;
      expect(AppStorage.historyById(s.id)!.totalSpent, 50000);
    });
  });
}
