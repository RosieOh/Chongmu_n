import 'dart:convert';

import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────
// 공용 유틸
// ─────────────────────────────────────────────

int _idSeq = 0;

/// 겹치지 않는 고유 ID 생성
String newId() => '${DateTime.now().microsecondsSinceEpoch}_${_idSeq++}';

/// 금액 포맷 (120000 → "120,000" / "120,000원")
class Fmt {
  Fmt._();

  static final NumberFormat _number = NumberFormat('#,##0');

  static String number(int value) => _number.format(value);

  static String won(int value) => '${_number.format(value)}원';
}

/// 단위 올림 (51,333.3원 → 100원 단위 → 51,400원). 총무가 손해 보지 않게!
int roundUpTo(double value, int unit) {
  if (value <= 0) return 0;
  final u = unit <= 0 ? 1 : unit;
  return ((value / u) - 1e-9).ceil() * u;
}

// ─────────────────────────────────────────────
// 모임 멤버
// ─────────────────────────────────────────────

class Member {
  Member({required this.id, required this.name});

  final String id;
  String name;

  Member copy() => Member(id: id, name: name);

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  factory Member.fromJson(Map<String, dynamic> json) => Member(
        id: json['id'] as String,
        name: (json['name'] as String?) ?? '',
      );
}

// ─────────────────────────────────────────────
// 차수 (1차, 2차, ...)
// ─────────────────────────────────────────────

class RoundItem {
  RoundItem({
    required this.id,
    this.name = '',
    this.amount = 0,
    Set<String>? participantIds,
    this.soberDiscount = false,
    Set<String>? soberIds,
  })  : participantIds = participantIds ?? <String>{},
        soberIds = soberIds ?? <String>{};

  /// 술 안 마신 사람은 80%만 냅니다 (20% 할인)
  static const double soberRate = 0.8;

  final String id;
  String name;
  int amount;

  /// 이 차수에 참석한 멤버 ID
  final Set<String> participantIds;

  /// '술 안 마신 인원 20% 할인' 토글
  bool soberDiscount;

  /// 술 안 마신 멤버 ID (participantIds 의 부분집합)
  final Set<String> soberIds;

  int get headCount => participantIds.length;

  bool get hasSober => soberDiscount && soberIds.isNotEmpty;

  double weightOf(String memberId) =>
      soberDiscount && soberIds.contains(memberId) ? soberRate : 1.0;

  double get _totalWeight {
    var w = 0.0;
    for (final id in participantIds) {
      w += weightOf(id);
    }
    return w;
  }

  /// 특정 멤버가 이 차수에서 내야 할 정확한 금액 (올림 전)
  double exactShareFor(String memberId) {
    if (amount <= 0 || !participantIds.contains(memberId)) return 0;
    final tw = _totalWeight;
    if (tw <= 0) return 0;
    return amount * weightOf(memberId) / tw;
  }

  /// 카드에 표시할 1인당 금액 (술 마신 사람 기준, 올림)
  int perPerson(int unit) {
    if (amount <= 0 || headCount == 0) return 0;
    return roundUpTo(amount / _totalWeight, unit);
  }

  /// 술 안 마신 사람의 1인당 금액 (올림)
  int soberPerPerson(int unit) {
    if (amount <= 0 || headCount == 0) return 0;
    return roundUpTo(amount * soberRate / _totalWeight, unit);
  }

  void removeParticipant(String memberId) {
    participantIds.remove(memberId);
    soberIds.remove(memberId);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'amount': amount,
        'participantIds': participantIds.toList(),
        'soberDiscount': soberDiscount,
        'soberIds': soberIds.toList(),
      };

  factory RoundItem.fromJson(Map<String, dynamic> json) {
    final participants =
        Set<String>.from((json['participantIds'] as List?) ?? const []);
    final sober = Set<String>.from((json['soberIds'] as List?) ?? const [])
      ..retainAll(participants);
    return RoundItem(
      id: json['id'] as String,
      name: (json['name'] as String?) ?? '',
      amount: (json['amount'] as num?)?.toInt() ?? 0,
      participantIds: participants,
      soberDiscount: (json['soberDiscount'] as bool?) ?? false,
      soberIds: sober,
    );
  }
}

// ─────────────────────────────────────────────
// 인원별 최종 정산 결과
// ─────────────────────────────────────────────

class PersonResult {
  const PersonResult({
    required this.member,
    required this.roundShares,
    required this.exactTotal,
    required this.pay,
  });

  final Member member;

  /// 차수 ID → 그 차수에서 낸 정확한 금액
  final Map<String, double> roundShares;

  /// 올림 전 총액
  final double exactTotal;

  /// 최종 입금액 (단위 올림 적용)
  final int pay;
}

// ─────────────────────────────────────────────
// 정산 전체 (모임 1개)
// ─────────────────────────────────────────────

class Settlement {
  Settlement({
    this.title = '',
    required this.members,
    required this.rounds,
    this.roundUnit = 100,
    Set<String>? paidIds,
  }) : paidIds = paidIds ?? <String>{};

  static const List<int> unitOptions = [10, 100, 1000];

  /// 입금 확인된 멤버 ID
  final Set<String> paidIds;

  bool isPaid(String memberId) => paidIds.contains(memberId);

  /// 입금 확인 토글. 바뀐 뒤의 상태(true=입금완료)를 돌려줍니다.
  bool togglePaid(String memberId) {
    if (paidIds.remove(memberId)) return false;
    paidIds.add(memberId);
    return true;
  }

  String title;
  final List<Member> members;
  final List<RoundItem> rounds;

  /// 올림 단위: 10 / 100 / 1000
  int roundUnit;

  int get totalSpent => rounds.fold(0, (sum, r) => sum + r.amount);

  /// 한 번이라도 참석한 사람 수
  int get involvedCount {
    final ids = <String>{};
    for (final r in rounds) {
      ids.addAll(r.participantIds);
    }
    return members.where((m) => ids.contains(m.id)).length;
  }

  String roundLabel(int index) {
    final n = rounds[index].name.trim();
    return n.isEmpty ? '${index + 1}차' : '${index + 1}차 · $n';
  }

  Member addMember([String? name]) {
    final m = Member(id: newId(), name: name ?? _nextMemberName());
    members.add(m);
    return m;
  }

  String _nextMemberName() {
    var n = members.length + 1;
    while (members.any((m) => m.name == '참석자$n')) {
      n++;
    }
    return '참석자$n';
  }

  void removeMember(String memberId) {
    members.removeWhere((m) => m.id == memberId);
    paidIds.remove(memberId);
    for (final r in rounds) {
      r.removeParticipant(memberId);
    }
  }

  /// 새 차수 (기본값: 모든 멤버 참석)
  RoundItem addRound() {
    final r = RoundItem(
      id: newId(),
      participantIds: members.map((m) => m.id).toSet(),
    );
    rounds.add(r);
    return r;
  }

  /// 인원별 최종 입금액 계산
  List<PersonResult> buildResults() {
    final results = <PersonResult>[];
    for (final m in members) {
      final shares = <String, double>{};
      var total = 0.0;
      for (final r in rounds) {
        if (r.amount <= 0 || !r.participantIds.contains(m.id)) continue;
        final v = r.exactShareFor(m.id);
        shares[r.id] = v;
        total += v;
      }
      if (shares.isEmpty) continue;
      results.add(PersonResult(
        member: m,
        roundShares: shares,
        exactTotal: total,
        pay: roundUpTo(total, roundUnit),
      ));
    }
    return results;
  }

  static int totalCollected(List<PersonResult> results) =>
      results.fold(0, (sum, p) => sum + p.pay);

  /// 총무 자투리 잔액 (걷은 돈 - 실제 지출)
  int get surplus => totalCollected(buildResults()) - totalSpent;

  // ── 프리셋 ──

  /// 첫 실행 예시: 1차 삼겹살 120,000원/4명, 2차 호프집 64,000원/3명
  factory Settlement.sample() {
    final me = Member(id: newId(), name: '나(총무)');
    final a = Member(id: newId(), name: '민수');
    final b = Member(id: newId(), name: '지영');
    final c = Member(id: newId(), name: '현우');
    return Settlement(
      title: '불금 팀 회식',
      members: [me, a, b, c],
      rounds: [
        RoundItem(
          id: newId(),
          name: '삼겹살',
          amount: 120000,
          participantIds: {me.id, a.id, b.id, c.id},
        ),
        RoundItem(
          id: newId(),
          name: '호프집',
          amount: 64000,
          participantIds: {me.id, a.id, b.id},
        ),
      ],
      roundUnit: 100,
    );
  }

  /// 완전히 빈 정산 (나 + 참석자 3명, 빈 차수 1개)
  factory Settlement.blank() {
    final s = Settlement(
      members: [Member(id: newId(), name: '나(총무)')],
      rounds: [],
    );
    for (var i = 0; i < 3; i++) {
      s.addMember();
    }
    s.addRound();
    return s;
  }

  /// 새 정산 (멤버만 유지)
  factory Settlement.fresh(
      {required List<Member> members, int roundUnit = 100}) {
    final s = Settlement(
      members: members.map((m) => m.copy()).toList(),
      rounds: [],
      roundUnit: roundUnit,
    );
    s.addRound();
    return s;
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'members': members.map((m) => m.toJson()).toList(),
        'rounds': rounds.map((r) => r.toJson()).toList(),
        'roundUnit': roundUnit,
        'paidIds': paidIds.toList(),
      };

  factory Settlement.fromJson(Map<String, dynamic> json) {
    final unit = (json['roundUnit'] as num?)?.toInt() ?? 100;
    final s = Settlement(
      title: (json['title'] as String?) ?? '',
      members: ((json['members'] as List?) ?? const [])
          .map((e) => Member.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      rounds: ((json['rounds'] as List?) ?? const [])
          .map((e) => RoundItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      roundUnit: unitOptions.contains(unit) ? unit : 100,
      paidIds: Set<String>.from((json['paidIds'] as List?) ?? const []),
    );
    s.paidIds.retainWhere((id) => s.members.any((m) => m.id == id));
    if (s.members.isEmpty) s.addMember('나(총무)');
    if (s.rounds.isEmpty) s.addRound();
    return s;
  }
}

// ─────────────────────────────────────────────
// 로컬 저장소 (shared_preferences) — 서버/로그인 없음
// ─────────────────────────────────────────────

class AppStorage {
  AppStorage._();

  static late SharedPreferences _prefs;

  static const _kSettlement = 'settlement_v1';
  static const _kBank = 'account_bank';
  static const _kHolder = 'account_holder';
  static const _kAccount = 'account_number';
  static const _kIsPro = 'is_pro';
  static const _kOnboarded = 'onboarding_done';

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  /// 저장된 정산이 없으면(첫 실행) 예시 데이터를 돌려줍니다.
  static Settlement loadSettlement() {
    final raw = _prefs.getString(_kSettlement);
    if (raw == null) return Settlement.sample();
    try {
      return Settlement.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {
      return Settlement.sample();
    }
  }

  static Future<void> saveSettlement(Settlement s) =>
      _prefs.setString(_kSettlement, jsonEncode(s.toJson()));

  static String get bankName => _prefs.getString(_kBank) ?? '';
  static String get accountHolder => _prefs.getString(_kHolder) ?? '';
  static String get accountNumber => _prefs.getString(_kAccount) ?? '';

  static Future<void> setBankName(String v) => _prefs.setString(_kBank, v);
  static Future<void> setAccountHolder(String v) =>
      _prefs.setString(_kHolder, v);
  static Future<void> setAccountNumber(String v) =>
      _prefs.setString(_kAccount, v);

  static bool get isPro => _prefs.getBool(_kIsPro) ?? false;
  static Future<void> setPro(bool v) => _prefs.setBool(_kIsPro, v);

  /// 첫 실행 안내 카드를 닫았는지
  static bool get onboardingDone => _prefs.getBool(_kOnboarded) ?? false;
  static Future<void> setOnboardingDone() => _prefs.setBool(_kOnboarded, true);
}
