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
    int discountPercent = defaultDiscount,
  })  : discountPercent = discountOptions.contains(discountPercent)
            ? discountPercent
            : defaultDiscount,
        participantIds = participantIds ?? <String>{},
        soberIds = soberIds ?? <String>{};

  /// 술 안 마신 사람 할인율 선택지 (%)
  static const List<int> discountOptions = [10, 20, 30, 50];
  static const int defaultDiscount = 20;

  final String id;
  String name;
  int amount;

  /// 이 차수에 참석한 멤버 ID
  final Set<String> participantIds;

  /// '술 안 마신 인원 할인' 토글
  bool soberDiscount;

  /// 술 안 마신 멤버 ID (participantIds 의 부분집합)
  final Set<String> soberIds;

  /// 술 안 마신 사람 할인율 (%) — 기본 20% (80%만 냄)
  int discountPercent;

  /// 술 안 마신 사람이 내는 비율 (20% 할인 → 0.8)
  double get soberRate => (100 - discountPercent) / 100;

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
        'discountPercent': discountPercent,
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
      discountPercent:
          (json['discountPercent'] as num?)?.toInt() ?? defaultDiscount,
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
    String? id,
    DateTime? createdAt,
    this.isSample = false,
    this.title = '',
    required this.members,
    required this.rounds,
    this.roundUnit = 100,
    Set<String>? paidIds,
  })  : id = id ?? newId(),
        createdAt = createdAt ?? DateTime.now(),
        paidIds = paidIds ?? <String>{};

  static const List<int> unitOptions = [10, 100, 1000];

  /// 정산 기록 구분용 고유 ID
  final String id;

  /// 정산을 처음 만든 시각 (기록 목록 정렬·날짜 표시)
  final DateTime createdAt;

  /// 첫 실행 예시 데이터인지. 사용자가 한 번이라도 수정하면 false 가 되고,
  /// 예시 데이터는 '지난 정산' 기록에 저장되지 않습니다.
  bool isSample;

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
      isSample: true,
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
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'isSample': isSample,
        'title': title,
        'members': members.map((m) => m.toJson()).toList(),
        'rounds': rounds.map((r) => r.toJson()).toList(),
        'roundUnit': roundUnit,
        'paidIds': paidIds.toList(),
      };

  factory Settlement.fromJson(Map<String, dynamic> json) {
    final unit = (json['roundUnit'] as num?)?.toInt() ?? 100;
    final s = Settlement(
      id: json['id'] as String?,
      createdAt: DateTime.tryParse((json['createdAt'] as String?) ?? ''),
      isSample: (json['isSample'] as bool?) ?? false,
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
  static const _kHistory = 'history_v1';
  static const _kThemeMode = 'theme_mode';

  /// 기록은 최근 100건까지만 보관 (기기 저장 공간 보호)
  static const int historyLimit = 100;

  /// 지난 정산 기록 (메모리 캐시 — 매번 JSON 을 다시 읽지 않도록)
  static List<Settlement>? _historyCache;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _historyCache = null;
  }

  static List<Settlement> get _history => _historyCache ??= _readHistory();

  static List<Settlement> _readHistory() {
    final raw = _prefs.getString(_kHistory);
    if (raw == null) return [];
    try {
      final list = (jsonDecode(raw) as List)
          .map((e) => Settlement.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      _sortHistory(list);
      return list;
    } catch (_) {
      return [];
    }
  }

  static void _sortHistory(List<Settlement> list) {
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (list.length > historyLimit) list.removeRange(historyLimit, list.length);
  }

  static Future<void> _writeHistory() => _prefs.setString(
        _kHistory,
        jsonEncode(_history.map((e) => e.toJson()).toList()),
      );

  /// 지난 정산 목록 (최신순). 화면에서 바꿔도 저장본에는 영향 없도록 복사본을 줍니다.
  static List<Settlement> loadHistory() =>
      _history.map((e) => Settlement.fromJson(e.toJson())).toList();

  static Settlement? historyById(String id) {
    for (final s in _history) {
      if (s.id == id) return Settlement.fromJson(s.toJson());
    }
    return null;
  }

  static Future<void> deleteHistory(String id) {
    _history.removeWhere((e) => e.id == id);
    return _writeHistory();
  }

  /// 삭제 되돌리기
  static Future<void> restoreHistory(Settlement s) {
    _history
      ..removeWhere((e) => e.id == s.id)
      ..add(Settlement.fromJson(s.toJson()));
    _sortHistory(_history);
    return _writeHistory();
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

  /// 현재 정산 저장 + '지난 정산' 기록에도 자동 반영.
  /// - 이미 기록에 있는 정산이면 항상 최신 내용으로 갱신
  /// - 새 정산은 금액이 입력됐고 예시 데이터가 아닐 때만 기록에 추가
  static Future<void> saveSettlement(Settlement s) async {
    final json = s.toJson();
    final writes = <Future<void>>[
      _prefs.setString(_kSettlement, jsonEncode(json)),
    ];

    final history = _history;
    final i = history.indexWhere((h) => h.id == s.id);
    if (i >= 0 || (!s.isSample && s.totalSpent > 0)) {
      final snapshot = Settlement.fromJson(json);
      if (i >= 0) {
        history[i] = snapshot;
      } else {
        history.add(snapshot);
        _sortHistory(history);
      }
      writes.add(_writeHistory());
    }
    await Future.wait(writes);
  }

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

  /// 화면 모드: 'system' / 'light' / 'dark'
  static String get themeMode => _prefs.getString(_kThemeMode) ?? 'system';
  static Future<void> setThemeMode(String v) =>
      _prefs.setString(_kThemeMode, v);
}
