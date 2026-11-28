import 'dart:convert';
import 'dart:math' as math;

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

/// 자투리 계산 방식
enum RoundMode {
  /// 올림 — 총무가 손해 보지 않음 (기본)
  up('올림'),

  /// 반올림 — 더 공평하지만 총무가 조금 모자랄 수 있음
  nearest('반올림');

  const RoundMode(this.label);

  final String label;

  static RoundMode parse(String? v) =>
      values.firstWhere((m) => m.name == v, orElse: () => up);
}

/// 술 안 마신 사람 처리 방식
enum SoberMode {
  /// 술값을 따로 입력 → 술값은 마신 사람끼리, 나머지는 모두가 나눔
  split('술값 따로'),

  /// 술값을 모를 때 → 안 마신 사람은 정한 비율만큼 덜 냄 (간편 모드)
  discount('할인율로');

  const SoberMode(this.label);

  final String label;

  static SoberMode parse(String? v) =>
      values.firstWhere((m) => m.name == v, orElse: () => discount);
}

/// 찬조·지원에서 '회사·외부 지원'(멤버가 아닌 곳에서 낸 돈)을 뜻하는 키
const String kExternalSponsor = '_external';

/// 늦게 온 사람·먼저 간 사람 비율 선택지
const List<double> kWeightOptions = [0.5, 0.7, 1.0, 1.5];

/// 1.0 → '1', 0.5 → '0.5'
String weightLabel(double w) =>
    w == w.roundToDouble() ? w.toInt().toString() : w.toString();

/// JSON 의 {id: 금액} 을 읽어요 (0 이하 버림)
Map<String, int> _readIntMap(Object? raw) {
  final out = <String, int>{};
  if (raw is Map) {
    raw.forEach((k, v) {
      final value = (v as num?)?.toInt() ?? 0;
      if (value > 0) out[k as String] = value;
    });
  }
  return out;
}

/// 단위 + 방식에 맞춰 금액 정리
int roundMoney(double value, int unit, RoundMode mode) {
  if (value <= 0) return 0;
  if (mode == RoundMode.up) return roundUpTo(value, unit);
  final u = unit <= 0 ? 1 : unit;
  return ((value / u) + 1e-9).round() * u;
}

/// 토스 송금 링크로 정리 ('chongmu' / 'toss.me/chongmu' → https://toss.me/chongmu).
/// 빈 값은 '', 알아볼 수 없는 값은 null.
String? normalizeTossLink(String input) {
  final v = input.trim();
  if (v.isEmpty) return '';
  final m =
      RegExp(r'^(?:https?://)?toss\.me/([A-Za-z0-9_.\-]+)/?$').firstMatch(v);
  if (m != null) return 'https://toss.me/${m.group(1)}';
  if (RegExp(r'^[A-Za-z0-9_.\-]{2,}$').hasMatch(v)) return 'https://toss.me/$v';
  return null;
}

/// 카카오페이 송금 링크로 정리 (qr.kakaopay.com/... 형식만 허용).
/// 빈 값은 '', 알아볼 수 없는 값은 null.
String? normalizeKakaoPayLink(String input) {
  final v = input.trim();
  if (v.isEmpty) return '';
  final m = RegExp(r'^(?:https?://)?qr\.kakaopay\.com/([A-Za-z0-9_\-]+)/?$')
      .firstMatch(v);
  if (m != null) return 'https://qr.kakaopay.com/${m.group(1)}';
  return null;
}

/// 금액 계산식 계산 ('32,000+15,000' → 47000, '120000÷4' → 30000).
/// + - × ÷ (또는 * /) 를 지원하고, 곱셈·나눗셈을 먼저 계산해요.
/// 비어 있거나 잘못된 식, 0으로 나누기, 음수 결과는 null.
int? evalAmount(String expr) {
  final src = expr
      .replaceAll(',', '')
      .replaceAll(' ', '')
      .replaceAll('×', '*')
      .replaceAll('x', '*')
      .replaceAll('÷', '/')
      .replaceAll('−', '-');
  if (src.isEmpty) return null;
  final tokens = RegExp(r'\d+|[+\-*/]').allMatches(src).map((m) => m[0]!);
  if (tokens.join() != src) return null;

  final list = tokens.toList();
  // 숫자 / 연산자가 번갈아 와야 해요 (숫자로 시작·끝)
  if (list.length.isEven) return null;
  for (var i = 0; i < list.length; i++) {
    final isNum = int.tryParse(list[i]) != null;
    if (isNum != i.isEven) return null;
  }

  // 곱셈·나눗셈 먼저
  final terms = <double>[double.parse(list[0])];
  final ops = <String>[];
  for (var i = 1; i < list.length; i += 2) {
    final op = list[i];
    final v = double.parse(list[i + 1]);
    if (op == '*') {
      terms.last *= v;
    } else if (op == '/') {
      if (v == 0) return null;
      terms.last /= v;
    } else {
      ops.add(op);
      terms.add(v);
    }
  }
  var total = terms[0];
  for (var i = 0; i < ops.length; i++) {
    total = ops[i] == '+' ? total + terms[i + 1] : total - terms[i + 1];
  }
  if (total < 0 || total > 999999999999) return null;
  return total.round();
}

/// 계산식에 연산자가 들어 있는지 (단순 숫자면 false)
bool isAmountExpr(String expr) =>
    RegExp(r'\d\s*[+\-*/×÷−x]\s*\d').hasMatch(expr);

// ─────────────────────────────────────────────
// 모임 그룹 (자주 모이는 멤버 묶음)
// ─────────────────────────────────────────────

class MemberGroup {
  MemberGroup({
    required this.name,
    required List<String> names,
    this.roundUnit,
    this.roundMode,
  }) : names = List.unmodifiable(names);

  final String name;

  /// 멤버 이름 (첫 번째 = 총무)
  final List<String> names;

  /// 이 모임의 자투리 규칙 (null 이면 정하지 않음)
  final int? roundUnit;
  final RoundMode? roundMode;

  bool get hasRule => roundUnit != null;

  /// '1,000원 단위 올림' 같은 규칙 이름
  String? get ruleLabel {
    final u = roundUnit;
    if (u == null) return null;
    return u == 1
        ? '1원 단위 정확히'
        : '${Fmt.number(u)}원 단위 ${(roundMode ?? RoundMode.up).label}';
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'names': names,
        if (roundUnit != null) 'roundUnit': roundUnit,
        if (roundMode != null) 'roundMode': roundMode!.name,
      };

  static MemberGroup? fromJson(Object? json) {
    if (json is! Map) return null;
    final name = (json['name'] as String?)?.trim() ?? '';
    final names = [
      for (final n in (json['names'] as List?) ?? const [])
        if (n is String && n.trim().isNotEmpty) n.trim(),
    ];
    if (name.isEmpty || names.isEmpty) return null;
    final unit = (json['roundUnit'] as num?)?.toInt();
    final validUnit =
        unit != null && Settlement.unitOptions.contains(unit) ? unit : null;
    return MemberGroup(
      name: name,
      names: names,
      roundUnit: validUnit,
      roundMode: validUnit == null
          ? null
          : RoundMode.parse(json['roundMode'] as String?),
    );
  }
}

// ─────────────────────────────────────────────
// 모임 멤버
// ─────────────────────────────────────────────

class Member {
  Member({required this.id, required this.name, this.account = ''});

  final String id;
  String name;

  /// 이 멤버가 돈을 받을 계좌 (송금 정리에서 총무가 아닌 결제자용, 자유 입력)
  String account;

  Member copy() => Member(id: id, name: name, account: account);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (account.isNotEmpty) 'account': account,
      };

  factory Member.fromJson(Map<String, dynamic> json) => Member(
        id: json['id'] as String,
        name: (json['name'] as String?) ?? '',
        account: (json['account'] as String?) ?? '',
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
    Map<String, int>? extras,
    this.payerId,
    this.freeMode = false,
    Set<String>? freeIds,
    int salePercent = 0,
    int couponAmount = 0,
    this.soberMode = SoberMode.discount,
    int alcoholAmount = 0,
    Map<String, double>? weights,
    Map<String, int>? sponsors,
  })  : alcoholAmount = math.max(0, alcoholAmount),
        weights = weights ?? <String, double>{},
        sponsors = sponsors ?? <String, int>{},
        salePercent = salePercent.clamp(0, 100),
        couponAmount = math.max(0, couponAmount),
        freeIds = freeIds ?? <String>{},
        extras = extras ?? <String, int>{},
        discountPercent = discountOptions.contains(discountPercent)
            ? discountPercent
            : defaultDiscount,
        participantIds = participantIds ?? <String>{},
        soberIds = soberIds ?? <String>{};

  /// 술 안 마신 사람 할인율 선택지 (%)
  static const List<int> discountOptions = [10, 20, 30, 50];
  static const int defaultDiscount = 20;

  final String id;
  String name;

  /// 영수증에 찍힌 금액 (할인·쿠폰 적용 전)
  int amount;

  /// 전체 할인율 (%) — 제휴 할인 등. 0이면 없음
  int salePercent;

  /// 쿠폰·포인트 등 정액 할인 (원). 할인율 적용 뒤에 빼요.
  int couponAmount;

  bool get hasSale => salePercent > 0 || couponAmount > 0;

  /// 할인·쿠폰으로 빠지는 금액 (결제 금액을 넘지 않음)
  int get saleTotal {
    if (amount <= 0) return 0;
    final v = (amount * salePercent / 100).round() + couponAmount;
    return math.min(v, amount);
  }

  /// 실제로 결제한 금액 (할인·쿠폰 적용 후) — 이 금액을 나눠요
  int get netAmount => amount - saleTotal;

  /// 할인·쿠폰 설정 (잘못된 값은 범위 안으로)
  void setSale({required int percent, required int coupon}) {
    salePercent = percent.clamp(0, 100);
    couponAmount = math.max(0, coupon);
  }

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

  /// '면제 인원' 토글 (생일자 등 — 한 푼도 안 냄)
  bool freeMode;

  /// 면제된 멤버 ID (participantIds 의 부분집합). 나머지가 나눠 냅니다.
  final Set<String> freeIds;

  bool isFree(String memberId) => freeMode && freeIds.contains(memberId);

  bool get hasFree => freeMode && freeIds.isNotEmpty;

  /// 실제로 돈을 내는 인원
  int get payingCount => participantIds.where((id) => !isFree(id)).length;

  /// 이 차수를 실제로 결제한 멤버 ID (null 이면 총무 = 첫 번째 멤버)
  String? payerId;

  /// 개별 추가 금액 (멤버 ID → 금액). 혼자 시킨 메뉴처럼 그 사람만 내는 돈.
  /// 결제 금액에서 추가금을 먼저 빼고, 남은 금액을 N빵합니다.
  final Map<String, int> extras;

  /// 개별 추가금 합계 (면제된 사람의 추가금은 다른 사람들이 나눠 냄)
  int get extrasTotal => extras.entries
      .where((e) => !isFree(e.key))
      .fold(0, (sum, e) => sum + e.value);

  int extraOf(String memberId) => isFree(memberId) ? 0 : extras[memberId] ?? 0;

  /// 추가금이 결제 금액보다 큰 잘못된 입력인지
  bool get extrasOverflow => extrasTotal > netAmount;

  /// N빵할 공통 금액 (결제 금액 - 개별 추가금)
  int get sharedAmount => math.max(0, netAmount - extrasTotal);

  /// 추가금 설정 (0 이하면 삭제). 참석자에게만 설정할 수 있어요.
  void setExtra(String memberId, int value) {
    if (value <= 0 || !participantIds.contains(memberId)) {
      extras.remove(memberId);
    } else {
      extras[memberId] = value;
    }
  }

  int get headCount => participantIds.length;

  // ── 술 안 마신 사람 ──

  /// 술 안 마신 사람 처리 방식 (술값 따로 / 할인율로)
  SoberMode soberMode;

  /// 술값 따로 모드에서 입력한 술값 (실제 결제 기준). 마신 사람끼리 나눠요.
  int alcoholAmount;

  bool get hasSober => soberDiscount && soberIds.isNotEmpty;

  bool get _splitMode => soberDiscount && soberMode == SoberMode.split;

  bool _isSober(String id) => soberDiscount && soberIds.contains(id);

  /// 술을 마신 (술값을 나눠 낼) 멤버인지
  bool isDrinker(String id) =>
      participantIds.contains(id) && !_isSober(id) && personWeight(id) > 0;

  bool get _hasDrinkers => participantIds.any(isDrinker);

  /// 실제로 따로 나누는 술값 (공통 금액을 넘지 않음, 마신 사람이 없으면 0)
  int get alcoholPart => _splitMode && _hasDrinkers
      ? math.min(alcoholAmount, sharedAmount)
      : 0;

  /// 술값 따로 모드인데 술값이 공통 금액보다 큰 잘못된 입력인지
  bool get alcoholOverflow => _splitMode && alcoholAmount > sharedAmount;

  // ── 사람별 비율 (늦게 온 사람·먼저 간 사람) ──

  /// 멤버 ID → 비율 (없으면 1배)
  final Map<String, double> weights;

  bool get hasWeights => weights.isNotEmpty;

  /// 사람 자체의 비율 (면제면 0)
  double personWeight(String id) => isFree(id) ? 0 : weights[id] ?? 1.0;

  void setWeight(String memberId, double w) {
    if (w == 1.0 || w <= 0 || !participantIds.contains(memberId)) {
      weights.remove(memberId);
    } else {
      weights[memberId] = w;
    }
  }

  // ── 찬조·지원 (이 차수만) ──

  /// 멤버 ID(또는 [kExternalSponsor]) → 찬조 금액. 나눌 금액에서 먼저 빼요.
  final Map<String, int> sponsors;

  int get sponsorTotal => sponsors.values.fold(0, (a, b) => a + b);

  /// 이 멤버가 이 차수에 낸 찬조금 (실제로 빼는 만큼만)
  int sponsorOf(String id) {
    final v = sponsors[id] ?? 0;
    if (v == 0 || sponsorTotal <= sharedAmount) return v;
    // 찬조가 나눌 금액보다 많으면 비율대로 줄여요
    return (v * sharedAmount / sponsorTotal).floor();
  }

  /// 외부(회사 등) 지원금 중 실제로 빠지는 금액
  int get externalSponsor => sponsorOf(kExternalSponsor);

  /// 찬조 합계가 나눌 금액보다 큰지
  bool get sponsorsOverflow => sponsorTotal > sharedAmount;

  void setSponsor(String id, int value) {
    if (value <= 0) {
      sponsors.remove(id);
    } else {
      sponsors[id] = value;
    }
  }

  /// 찬조를 빼고 실제로 나누는 금액
  double get _pool {
    final effective = sponsors.keys.fold(0, (sum, k) => sum + sponsorOf(k));
    return math.max(0, sharedAmount - effective).toDouble();
  }

  // ── 나누기 ──

  /// 술 외 금액(음식값 등)을 나눌 때의 비율
  double weightOf(String memberId) {
    if (!participantIds.contains(memberId)) return 0;
    final w = personWeight(memberId);
    if (_splitMode) return w;
    return _isSober(memberId) ? w * soberRate : w;
  }

  double get _foodWeight =>
      participantIds.fold(0.0, (sum, id) => sum + weightOf(id));

  double get _alcoholWeight => participantIds.fold(
      0.0, (sum, id) => sum + (isDrinker(id) ? personWeight(id) : 0));

  /// (음식 몫 풀, 술 몫 풀) — 찬조는 두 몫에서 같은 비율로 빠져요
  (double, double) get _pools {
    final shared = sharedAmount;
    if (shared <= 0) return (0, 0);
    final k = _pool / shared;
    final alcohol = alcoholPart.toDouble();
    return ((shared - alcohol) * k, alcohol * k);
  }

  /// 특정 멤버가 이 차수에서 내야 할 정확한 금액 (올림 전, 추가금 포함, 찬조금 제외)
  double exactShareFor(String memberId) {
    if (netAmount <= 0 || !participantIds.contains(memberId)) return 0;
    final fw = _foodWeight;
    if (fw <= 0) return 0;
    final (food, alcohol) = _pools;
    var v = food * weightOf(memberId) / fw;
    final aw = _alcoholWeight;
    if (alcohol > 0 && aw > 0 && isDrinker(memberId)) {
      v += alcohol * personWeight(memberId) / aw;
    }
    return v + extraOf(memberId);
  }

  /// 카드에 표시할 1인당 금액 (1배 · 술 마신 사람 기준, 추가금 제외)
  int perPerson(int unit, [RoundMode mode = RoundMode.up]) {
    final fw = _foodWeight;
    if (netAmount <= 0 || fw <= 0) return 0;
    final (food, alcohol) = _pools;
    final aw = _alcoholWeight;
    final v = food / fw + (alcohol > 0 && aw > 0 ? alcohol / aw : 0);
    return roundMoney(v, unit, mode);
  }

  /// 술 안 마신 사람의 1인당 금액 (1배 기준, 추가금 제외)
  int soberPerPerson(int unit, [RoundMode mode = RoundMode.up]) {
    final fw = _foodWeight;
    if (netAmount <= 0 || fw <= 0) return 0;
    final (food, _) = _pools;
    return roundMoney(
        food * (_splitMode ? 1 : soberRate) / fw, unit, mode);
  }

  void removeParticipant(String memberId) {
    participantIds.remove(memberId);
    soberIds.remove(memberId);
    freeIds.remove(memberId);
    extras.remove(memberId);
    weights.remove(memberId);
  }

  /// 다음 차수로 복제 (참석자·할인·면제는 그대로, 금액·장소·추가금은 비움)
  RoundItem duplicate() => RoundItem(
        id: newId(),
        participantIds: {...participantIds},
        soberDiscount: soberDiscount,
        soberIds: {...soberIds},
        discountPercent: discountPercent,
        payerId: payerId,
        freeMode: freeMode,
        freeIds: {...freeIds},
        soberMode: soberMode,
        weights: {...weights},
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'amount': amount,
        'participantIds': participantIds.toList(),
        'soberDiscount': soberDiscount,
        'soberIds': soberIds.toList(),
        'discountPercent': discountPercent,
        'extras': Map<String, int>.of(extras),
        if (payerId != null) 'payerId': payerId,
        'freeMode': freeMode,
        'freeIds': freeIds.toList(),
        if (salePercent > 0) 'salePercent': salePercent,
        if (couponAmount > 0) 'couponAmount': couponAmount,
        if (soberMode != SoberMode.discount) 'soberMode': soberMode.name,
        if (alcoholAmount > 0) 'alcoholAmount': alcoholAmount,
        if (weights.isNotEmpty) 'weights': Map<String, double>.of(weights),
        if (sponsors.isNotEmpty) 'sponsors': Map<String, int>.of(sponsors),
      };

  factory RoundItem.fromJson(Map<String, dynamic> json) {
    final participants =
        Set<String>.from((json['participantIds'] as List?) ?? const []);
    final sober = Set<String>.from((json['soberIds'] as List?) ?? const [])
      ..retainAll(participants);
    final extras = <String, int>{};
    final rawExtras = json['extras'];
    if (rawExtras is Map) {
      rawExtras.forEach((k, v) {
        final value = (v as num?)?.toInt() ?? 0;
        if (value > 0 && participants.contains(k)) extras[k as String] = value;
      });
    }
    final weights = <String, double>{};
    final rawWeights = json['weights'];
    if (rawWeights is Map) {
      rawWeights.forEach((k, v) {
        final w = (v as num?)?.toDouble() ?? 1.0;
        if (w > 0 && w != 1.0 && participants.contains(k)) {
          weights[k as String] = w;
        }
      });
    }
    return RoundItem(
      id: json['id'] as String,
      name: (json['name'] as String?) ?? '',
      amount: (json['amount'] as num?)?.toInt() ?? 0,
      participantIds: participants,
      soberDiscount: (json['soberDiscount'] as bool?) ?? false,
      soberIds: sober,
      discountPercent:
          (json['discountPercent'] as num?)?.toInt() ?? defaultDiscount,
      extras: extras,
      payerId: json['payerId'] as String?,
      freeMode: (json['freeMode'] as bool?) ?? false,
      freeIds: Set<String>.from((json['freeIds'] as List?) ?? const [])
        ..retainAll(participants),
      salePercent: (json['salePercent'] as num?)?.toInt() ?? 0,
      couponAmount: (json['couponAmount'] as num?)?.toInt() ?? 0,
      soberMode: SoberMode.parse(json['soberMode'] as String?),
      alcoholAmount: (json['alcoholAmount'] as num?)?.toInt() ?? 0,
      weights: weights,
      sponsors: _readIntMap(json['sponsors']),
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
    this.sponsorPaid = 0,
    this.deduction = 0,
  });

  /// 이 사람이 낸 찬조금 (차수 + 전체)
  final int sponsorPaid;

  /// 전체 찬조·외부 지원·적립금으로 줄어든 금액
  final double deduction;

  final Member member;

  /// 차수 ID → 그 차수에서 낸 정확한 금액
  final Map<String, double> roundShares;

  /// 올림 전 총액
  final double exactTotal;

  /// 최종 입금액 (단위 올림 적용)
  final int pay;
}

// ─────────────────────────────────────────────
// 송금 정리 (여러 명이 나눠 결제했을 때)
// ─────────────────────────────────────────────

/// A → B 에게 amount 원 보내기
class Transfer {
  const Transfer({
    required this.from,
    required this.to,
    required this.amount,
  });

  final Member from;
  final Member to;
  final int amount;
}

/// 송금 정리 계산용 (남은 금액)
class _Balance {
  _Balance(this.member, this.left);

  final Member member;
  int left;
}

/// 한 사람이 보내야 할 돈 (입금 확인 단위)
class Due {
  const Due({
    required this.member,
    required this.amount,
    this.transfers = const [],
  });

  final Member member;
  final int amount;

  /// 송금 정리 모드에서 누구에게 얼마씩 보내는지
  final List<Transfer> transfers;
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
    this.roundMode = RoundMode.up,
    Set<String>? paidIds,
    this.remindAt,
    Map<String, int>? sponsors,
    this.groupName = '',
    int carryIn = 0,
  })  : id = id ?? newId(),
        createdAt = createdAt ?? DateTime.now(),
        paidIds = paidIds ?? <String>{},
        sponsors = sponsors ?? <String, int>{},
        carryIn = math.max(0, carryIn);

  /// 정산 전체에 대한 찬조·지원 (멤버 ID 또는 [kExternalSponsor] → 금액).
  /// 모두의 몫에서 같은 비율로 빠지고, 찬조한 멤버는 그만큼 더 내요.
  final Map<String, int> sponsors;

  /// 연결된 모임 그룹 이름 (자투리 적립금 계산용, 없으면 '')
  String groupName;

  /// 모임 적립금에서 이번 정산에 쓰는 금액
  int carryIn;

  void setSponsor(String id, int value) {
    if (value <= 0) {
      sponsors.remove(id);
    } else {
      sponsors[id] = value;
    }
  }

  /// 1원 단위 = 자투리 없이 정확히
  static const List<int> unitOptions = [1, 10, 100, 1000];

  /// 정산 기록 구분용 고유 ID
  final String id;

  /// 정산을 처음 만든 시각 (기록 목록 정렬·날짜 표시)
  final DateTime createdAt;

  /// 첫 실행 예시 데이터인지. 사용자가 한 번이라도 수정하면 false 가 되고,
  /// 예시 데이터는 '지난 정산' 기록에 저장되지 않습니다.
  bool isSample;

  /// 입금 확인된 멤버 ID
  final Set<String> paidIds;

  /// 미입금 리마인드 알림 예약 시각 (없으면 null)
  DateTime? remindAt;

  /// 아직 울리지 않은 알림이 있는지
  bool hasPendingReminder(DateTime now) =>
      remindAt != null && remindAt!.isAfter(now);

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

  /// 정리 단위: 1 / 10 / 100 / 1000
  int roundUnit;

  /// 올림 / 반올림
  RoundMode roundMode;

  /// '100원 단위 올림' / '1원 단위(정확히)'
  String get roundingLabel => roundUnit == 1
      ? '1원 단위 정확히'
      : '${Fmt.number(roundUnit)}원 단위 ${roundMode.label}';

  /// 실제 지출 합계 (할인·쿠폰 적용 후)
  int get totalSpent => rounds.fold(0, (sum, r) => sum + r.netAmount);

  /// 할인·쿠폰으로 아낀 금액 합계
  int get totalSaved => rounds.fold(0, (sum, r) => sum + r.saleTotal);

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
    sponsors.remove(memberId);
    for (final r in rounds) {
      r.removeParticipant(memberId);
      r.sponsors.remove(memberId);
      if (r.payerId == memberId) r.payerId = null;
    }
  }

  // ── 결제자 / 송금 정리 ──

  /// 총무 (첫 번째 멤버). 자투리 잔액을 갖고, 기본 결제자예요.
  Member get treasurer => members.first;

  Member memberById(String id) =>
      members.firstWhere((m) => m.id == id, orElse: () => treasurer);

  /// 이 차수를 결제한 멤버 (지정이 없거나 삭제된 멤버면 총무)
  Member payerOf(RoundItem r) {
    final id = r.payerId;
    if (id == null) return treasurer;
    return memberById(id);
  }

  /// 총무 말고 다른 사람이 결제한 차수가 있으면 '송금 정리' 모드
  bool get usesTransfers =>
      rounds.any((r) => r.netAmount > 0 && payerOf(r).id != treasurer.id);

  /// 누가 누구에게 얼마 보내면 되는지 (송금 횟수가 적도록 큰 금액부터 짝지음).
  /// 올림으로 생긴 자투리는 총무가 받아요.
  List<Transfer> buildTransfers([List<PersonResult>? results]) {
    final res = results ?? buildResults();
    final net = <String, int>{for (final m in members) m.id: 0};
    for (final p in res) {
      net[p.member.id] = net[p.member.id]! + p.pay;
    }
    for (final r in rounds) {
      if (r.netAmount <= 0) continue;
      final id = payerOf(r).id;
      net[id] = net[id]! - r.netAmount;
    }
    // 자투리(걷는 돈 - 실제 지출)는 총무 몫
    final rest = net.values.fold(0, (a, b) => a + b);
    net[treasurer.id] = net[treasurer.id]! - rest;

    final debtors = [
      for (final m in members)
        if (net[m.id]! > 0) _Balance(m, net[m.id]!)
    ]..sort((a, b) => b.left.compareTo(a.left));
    final creditors = [
      for (final m in members)
        if (net[m.id]! < 0) _Balance(m, -net[m.id]!)
    ]..sort((a, b) => b.left.compareTo(a.left));

    final out = <Transfer>[];
    var i = 0, j = 0;
    while (i < debtors.length && j < creditors.length) {
      final d = debtors[i], c = creditors[j];
      final x = math.min(d.left, c.left);
      out.add(Transfer(from: d.member, to: c.member, amount: x));
      d.left -= x;
      c.left -= x;
      if (d.left == 0) i++;
      if (c.left == 0) j++;
    }
    return out;
  }

  /// 입금 확인 목록.
  /// - 총무 혼자 결제: 참석한 모든 사람이 총무에게 자기 몫을 냄
  /// - 여러 명 결제: 송금 정리에서 돈을 보내야 하는 사람만
  List<Due> buildDues([List<PersonResult>? results]) {
    final res = results ?? buildResults();
    if (!usesTransfers) {
      // 면제 등으로 낼 돈이 0원인 사람은 입금 확인 대상이 아니에요
      return [
        for (final p in res)
          if (p.pay > 0) Due(member: p.member, amount: p.pay),
      ];
    }
    final transfers = buildTransfers(res);
    return [
      for (final m in members)
        if (transfers.any((t) => t.from.id == m.id))
          Due(
            member: m,
            amount: transfers
                .where((t) => t.from.id == m.id)
                .fold(0, (sum, t) => sum + t.amount),
            transfers: transfers.where((t) => t.from.id == m.id).toList(),
          ),
    ];
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

  /// 차수별 몫의 합계 (찬조금·전체 차감 전)
  double get _sharesTotal {
    var t = 0.0;
    for (final m in members) {
      for (final r in rounds) {
        if (r.netAmount > 0) t += r.exactShareFor(m.id);
      }
    }
    return t;
  }

  /// 전체 차감 (멤버 찬조 / 외부 지원 / 적립금) — 나눌 금액을 넘지 않게 줄여요.
  ({Map<String, int> members, int external, int carry}) get _globalCuts {
    final total = _sharesTotal.floor();
    var left = total;
    int take(int v) {
      final x = math.min(math.max(0, v), left);
      left -= x;
      return x;
    }

    final external = take(sponsors[kExternalSponsor] ?? 0);
    final carry = take(carryIn);
    final byMember = <String, int>{};
    for (final m in members) {
      final v = take(sponsors[m.id] ?? 0);
      if (v > 0) byMember[m.id] = v;
    }
    return (members: byMember, external: external, carry: carry);
  }

  /// 실제로 쓰이는 적립금
  int get effectiveCarryIn => _globalCuts.carry;

  /// 외부(회사 등) 지원금 합계 — 차수 + 전체
  int get externalTotal =>
      _globalCuts.external +
      rounds.fold(0, (sum, r) => sum + r.externalSponsor);

  /// 멤버가 낸 찬조금 합계 — 차수 + 전체
  int get memberSponsorTotal {
    final cuts = _globalCuts;
    var t = cuts.members.values.fold(0, (a, b) => a + b);
    for (final r in rounds) {
      for (final id in r.sponsors.keys) {
        if (id != kExternalSponsor) t += r.sponsorOf(id);
      }
    }
    return t;
  }

  bool get hasSponsors =>
      sponsors.isNotEmpty || rounds.any((r) => r.sponsors.isNotEmpty);

  /// 멤버에게서 걷어야 하는 돈 (지출 - 외부 지원 - 적립금 사용)
  int get totalToCollect => totalSpent - externalTotal - effectiveCarryIn;

  /// 인원별 최종 입금액 계산
  List<PersonResult> buildResults() {
    final cuts = _globalCuts;
    final total = _sharesTotal;
    final cutTotal = cuts.external +
        cuts.carry +
        cuts.members.values.fold(0, (a, b) => a + b);
    final factor = total > 0 ? (total - cutTotal) / total : 0.0;

    final results = <PersonResult>[];
    for (final m in members) {
      final shares = <String, double>{};
      var base = 0.0;
      var sponsor = cuts.members[m.id] ?? 0;
      for (final r in rounds) {
        if (r.netAmount <= 0) continue;
        sponsor += r.sponsorOf(m.id);
        if (!r.participantIds.contains(m.id)) continue;
        final v = r.exactShareFor(m.id);
        shares[r.id] = v;
        base += v;
      }
      if (shares.isEmpty && sponsor == 0) continue;
      final exact = base * factor + sponsor;
      results.add(PersonResult(
        member: m,
        roundShares: shares,
        exactTotal: exact,
        pay: roundMoney(exact, roundUnit, roundMode),
        sponsorPaid: sponsor,
        deduction: base - base * factor,
      ));
    }
    return results;
  }

  static int totalCollected(List<PersonResult> results) =>
      results.fold(0, (sum, p) => sum + p.pay);

  /// 총무 자투리 잔액 (걷은 돈 - 걷어야 할 돈)
  int get surplus => totalCollected(buildResults()) - totalToCollect;

  /// 이 정산이 모임 적립금을 얼마나 바꾸는지 (자투리 적립 - 적립금 사용)
  int get fundChange => surplus - effectiveCarryIn;

  /// 정산서에 적는 한 사람의 계산 근거
  /// 예: '1차 30,000 + 2차 21,334 + 찬조 50,000 − 지원 반영 4,000 = 97,334'
  String formulaFor(PersonResult p) {
    final parts = <String>[];
    for (var i = 0; i < rounds.length; i++) {
      final v = p.roundShares[rounds[i].id];
      if (v == null) continue;
      parts.add('${i + 1}차 ${Fmt.number(v.round())}');
    }
    final b = StringBuffer(parts.join(' + '));
    if (p.sponsorPaid > 0) {
      if (b.isNotEmpty) b.write(' + ');
      b.write('찬조 ${Fmt.number(p.sponsorPaid)}');
    }
    final cut = p.deduction.round();
    if (cut > 0) b.write(' − 지원·적립 ${Fmt.number(cut)}');
    final exact = p.exactTotal.round();
    final multi = parts.length > 1 || p.sponsorPaid > 0 || cut > 0;
    if (multi) b.write(' = ${Fmt.number(exact)}');
    if (p.pay != exact) b.write(' → ${Fmt.number(p.pay)}');
    return b.toString();
  }

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
  factory Settlement.fresh({
    required List<Member> members,
    int roundUnit = 100,
    RoundMode roundMode = RoundMode.up,
    String title = '',
    String groupName = '',
  }) {
    final s = Settlement(
      title: title,
      members: members.map((m) => m.copy()).toList(),
      rounds: [],
      roundUnit: roundUnit,
      roundMode: roundMode,
      groupName: groupName,
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
        'roundMode': roundMode.name,
        if (remindAt != null) 'remindAt': remindAt!.toIso8601String(),
        'paidIds': paidIds.toList(),
        if (sponsors.isNotEmpty) 'sponsors': Map<String, int>.of(sponsors),
        if (groupName.isNotEmpty) 'groupName': groupName,
        if (carryIn > 0) 'carryIn': carryIn,
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
      roundMode: RoundMode.parse(json['roundMode'] as String?),
      remindAt: DateTime.tryParse((json['remindAt'] as String?) ?? ''),
      paidIds: Set<String>.from((json['paidIds'] as List?) ?? const []),
      sponsors: _readIntMap(json['sponsors']),
      groupName: (json['groupName'] as String?)?.trim() ?? '',
      carryIn: (json['carryIn'] as num?)?.toInt() ?? 0,
    );
    s.paidIds.retainWhere((id) => s.members.any((m) => m.id == id));
    if (s.members.isEmpty) s.addMember('나(총무)');
    if (s.rounds.isEmpty) s.addRound();
    return s;
  }
}

// ─────────────────────────────────────────────
// 미수금 장부 (지난 정산 전체에서 아직 안 낸 돈 모아 보기)
// ─────────────────────────────────────────────

/// 한 정산에서 아직 안 낸 돈
class LedgerItem {
  const LedgerItem({
    required this.settlement,
    required this.member,
    required this.amount,
  });

  final Settlement settlement;
  final Member member;
  final int amount;
}

/// 한 사람(이름 기준)의 미수금 모음
class LedgerEntry {
  LedgerEntry(this.name);

  final String name;
  final List<LedgerItem> items = [];

  int get total => items.fold(0, (sum, e) => sum + e.amount);
}

/// 사람별 미수금 (많은 순). 총무가 직접 결제한 정산에서는 총무 본인은 빼요.
List<LedgerEntry> buildLedger(Iterable<Settlement> settlements) {
  final byName = <String, LedgerEntry>{};
  for (final s in settlements) {
    if (s.isSample || s.totalSpent <= 0) continue;
    final transfers = s.usesTransfers;
    for (final d in s.buildDues()) {
      if (s.isPaid(d.member.id) || d.amount <= 0) continue;
      if (!transfers && d.member.id == s.treasurer.id) continue;
      final raw = d.member.name.trim();
      final name = raw.isEmpty ? '이름 없음' : raw;
      byName
          .putIfAbsent(name, () => LedgerEntry(name))
          .items
          .add(LedgerItem(settlement: s, member: d.member, amount: d.amount));
    }
  }
  for (final e in byName.values) {
    e.items.sort(
        (a, b) => b.settlement.createdAt.compareTo(a.settlement.createdAt));
  }
  return byName.values.toList()
    ..sort((a, b) {
      final c = b.total.compareTo(a.total);
      return c != 0 ? c : a.name.compareTo(b.name);
    });
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
  static const _kMemberAccounts = 'member_accounts_v1';
  static const _kTossLink = 'pay_link_toss';
  static const _kKakaoPayLink = 'pay_link_kakaopay';
  static const _kGroups = 'member_groups_v1';
  static const _kLastBackup = 'last_backup_at';

  /// 모임 그룹은 20개까지
  static const int groupLimit = 20;

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

  /// 지난 정산에 자주 나온 멤버 이름 (많이 함께한 순, 기본 이름 제외)
  static List<String> recentMemberNames({int limit = 12}) {
    final count = <String, int>{};
    final last = <String, DateTime>{};
    final auto = RegExp(r'^참석자\d+$');
    for (final s in _history) {
      for (final m in s.members) {
        final name = m.name.trim();
        if (name.isEmpty || auto.hasMatch(name) || name.contains('총무')) {
          continue;
        }
        count[name] = (count[name] ?? 0) + 1;
        final prev = last[name];
        if (prev == null || s.createdAt.isAfter(prev)) last[name] = s.createdAt;
      }
    }
    final names = count.keys.toList()
      ..sort((a, b) {
        final c = count[b]!.compareTo(count[a]!);
        return c != 0 ? c : last[b]!.compareTo(last[a]!);
      });
    return names.take(limit).toList();
  }

  static Future<void> deleteHistory(String id) {
    _history.removeWhere((e) => e.id == id);
    return _writeHistory();
  }

  /// 지난 정산의 입금 확인 상태 바꾸기 (미수금 장부에서 사용)
  static Future<void> setHistoryPaid(
      String settlementId, String memberId, bool paid) {
    for (final s in _history) {
      if (s.id != settlementId) continue;
      if (paid) {
        s.paidIds.add(memberId);
      } else {
        s.paidIds.remove(memberId);
      }
      return _writeHistory();
    }
    return Future.value();
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

  // ── 백업 / 복원 (클립보드로 옮기기) ──

  static const _backupApp = 'chongmu_n';

  /// 지금 정산 + 지난 정산 + 계좌 정보를 JSON 문자열로.
  /// PRO 구매 여부는 넣지 않아요 (복원은 '구매 내역 복원'으로).
  static String exportBackup(Settlement current) => jsonEncode({
        'app': _backupApp,
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'current': current.toJson(),
        'history': _history.map((e) => e.toJson()).toList(),
        'groups': groups.map((g) => g.toJson()).toList(),
        'account': {
          'bank': bankName,
          'holder': accountHolder,
          'number': accountNumber,
          'toss': tossLink,
          'kakaopay': kakaoPayLink,
        },
      });

  /// 백업 문자열을 지난 정산에 합칩니다 (같은 정산은 백업 내용으로 갱신).
  /// 계좌가 비어 있으면 백업의 계좌도 채워요. 합친 정산 개수를 돌려줍니다.
  /// 형식이 맞지 않으면 [FormatException].
  static Future<int> importBackup(String raw) async {
    final Map<String, dynamic> data;
    try {
      data = Map<String, dynamic>.from(jsonDecode(raw.trim()) as Map);
    } catch (_) {
      throw const FormatException('백업 형식이 아니에요');
    }
    if (data['app'] != _backupApp) {
      throw const FormatException('똑똑한 총무 백업이 아니에요');
    }

    final incoming = <Settlement>[
      for (final e in (data['history'] as List?) ?? const [])
        Settlement.fromJson(Map<String, dynamic>.from(e as Map)),
    ];
    final current = data['current'];
    if (current is Map) {
      final s = Settlement.fromJson(Map<String, dynamic>.from(current));
      if (!s.isSample &&
          s.totalSpent > 0 &&
          !incoming.any((e) => e.id == s.id)) {
        incoming.add(s);
      }
    }

    final history = _history;
    for (final s in incoming) {
      history
        ..removeWhere((e) => e.id == s.id)
        ..add(s);
    }
    _sortHistory(history);

    final writes = <Future<void>>[_writeHistory()];
    final account = data['account'];
    if (account is Map && accountNumber.isEmpty) {
      final number = (account['number'] as String?)?.trim() ?? '';
      if (number.isNotEmpty) {
        writes
          ..add(setAccountNumber(number))
          ..add(setBankName((account['bank'] as String?)?.trim() ?? ''))
          ..add(setAccountHolder((account['holder'] as String?)?.trim() ?? ''));
      }
    }
    if (account is Map) {
      final toss = normalizeTossLink((account['toss'] as String?) ?? '');
      if (tossLink.isEmpty && toss != null && toss.isNotEmpty) {
        writes.add(setTossLink(toss));
      }
      final kakao =
          normalizeKakaoPayLink((account['kakaopay'] as String?) ?? '');
      if (kakaoPayLink.isEmpty && kakao != null && kakao.isNotEmpty) {
        writes.add(setKakaoPayLink(kakao));
      }
    }
    final rawGroups = data['groups'];
    if (rawGroups is List) {
      final list = groups;
      for (final g
          in rawGroups.map(MemberGroup.fromJson).whereType<MemberGroup>()) {
        if (!list.any((e) => e.name == g.name)) list.add(g);
      }
      writes.add(_writeGroups(list));
    }
    await Future.wait(writes);
    return incoming.length;
  }

  /// 마지막으로 백업한 시각 (없으면 null)
  static DateTime? get lastBackupAt =>
      DateTime.tryParse(_prefs.getString(_kLastBackup) ?? '');

  static Future<void> markBackedUp([DateTime? at]) => _prefs.setString(
      _kLastBackup, (at ?? DateTime.now()).toIso8601String());

  /// 백업을 권할 때인지: 기록이 3건 이상인데 백업한 적이 없거나 14일이 지났을 때
  static bool backupDue(DateTime now) {
    if (_history.where((s) => !s.isSample).length < 3) return false;
    final last = lastBackupAt;
    return last == null || now.difference(last).inDays >= 14;
  }

  /// 모임 적립금 — 그 모임의 지난 정산들에서 쌓인 자투리 - 쓴 적립금.
  /// [excludeId] 정산(지금 편집 중인 정산)은 빼고 계산해요.
  static int groupFund(String group, {String? excludeId}) {
    if (group.isEmpty) return 0;
    var fund = 0;
    for (final s in _history) {
      if (s.groupName != group || s.id == excludeId) continue;
      if (s.isSample || s.totalSpent <= 0) continue;
      fund += s.fundChange;
    }
    return fund;
  }

  // ── 모임 그룹 ──

  static List<MemberGroup> get groups {
    final raw = _prefs.getString(_kGroups);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map(MemberGroup.fromJson)
          .whereType<MemberGroup>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _writeGroups(List<MemberGroup> list) => _prefs.setString(
        _kGroups,
        jsonEncode(list.take(groupLimit).map((g) => g.toJson()).toList()),
      );

  /// 그룹 저장 (같은 이름이 있으면 덮어쓰고 맨 앞으로)
  static Future<void> saveGroup(MemberGroup group) {
    final list = groups..removeWhere((g) => g.name == group.name);
    list.insert(0, group);
    return _writeGroups(list);
  }

  static Future<void> deleteGroup(String name) =>
      _writeGroups(groups..removeWhere((g) => g.name == name));

  // ── 멤버별 계좌 (이름 기준으로 기억해서 다음 정산에 자동으로 채움) ──

  static Map<String, String> get _memberAccounts {
    final raw = _prefs.getString(_kMemberAccounts);
    if (raw == null) return {};
    try {
      return Map<String, String>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  static String accountForName(String name) =>
      _memberAccounts[name.trim()] ?? '';

  static Future<void> rememberAccount(String name, String account) {
    final key = name.trim();
    if (key.isEmpty) return Future.value();
    final map = _memberAccounts;
    if (account.trim().isEmpty) {
      map.remove(key);
    } else {
      map[key] = account.trim();
    }
    return _prefs.setString(_kMemberAccounts, jsonEncode(map));
  }

  /// 총무의 송금 링크 (카톡 메시지에 함께 붙여서 바로 송금받기)
  static String get tossLink => _prefs.getString(_kTossLink) ?? '';
  static String get kakaoPayLink => _prefs.getString(_kKakaoPayLink) ?? '';
  static Future<void> setTossLink(String v) => _prefs.setString(_kTossLink, v);
  static Future<void> setKakaoPayLink(String v) =>
      _prefs.setString(_kKakaoPayLink, v);

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
