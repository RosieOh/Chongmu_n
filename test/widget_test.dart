import 'package:chongmu_n/models/round_item.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
