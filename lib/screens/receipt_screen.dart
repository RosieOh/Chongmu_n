import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/round_item.dart';
import '../services/reminder_service.dart';
import '../theme/app_theme.dart';
import 'settings_screen.dart';

/// ② 결과 화면 — 모바일 정산 영수증
class ReceiptScreen extends StatefulWidget {
  const ReceiptScreen({super.key, required this.settlement});

  final Settlement settlement;

  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  final GlobalKey _receiptKey = GlobalKey();
  final DateTime _now = DateTime.now();

  late final TextEditingController _bankCtrl =
      TextEditingController(text: AppStorage.bankName);
  late final TextEditingController _holderCtrl =
      TextEditingController(text: AppStorage.accountHolder);
  late final TextEditingController _accountCtrl =
      TextEditingController(text: AppStorage.accountNumber);

  late final List<PersonResult> _results = widget.settlement.buildResults();

  /// 입금 확인 대상 (총무 혼자 결제면 전원, 여러 명 결제면 송금할 사람만)
  late final List<Due> _dues = widget.settlement.buildDues(_results);

  late final bool _transferMode = widget.settlement.usesTransfers;

  final FocusNode _bankFocus = FocusNode();
  final FocusNode _accountFocus = FocusNode();

  late final TextEditingController _tossCtrl =
      TextEditingController(text: AppStorage.tossLink);
  late final TextEditingController _kakaoCtrl =
      TextEditingController(text: AppStorage.kakaoPayLink);
  bool _tossError = false;
  bool _kakaoError = false;

  /// 송금 정리에서 돈을 받는 사람 중 총무가 아닌 사람 (각자 계좌 필요)
  late final List<Member> _payees = () {
    final s = widget.settlement;
    final seen = <String>{};
    return [
      for (final d in _dues)
        for (final t in d.transfers)
          if (t.to.id != s.treasurer.id && seen.add(t.to.id)) t.to,
    ];
  }();

  late final Map<String, TextEditingController> _payeeCtrls = {
    for (final m in _payees) m.id: TextEditingController(text: m.account),
  };

  @override
  void initState() {
    super.initState();
    // 예전에 입력한 계좌가 있으면 자동으로 채워요
    var filled = false;
    for (final m in _payees) {
      if (m.account.isEmpty) {
        final saved = AppStorage.accountForName(m.name);
        if (saved.isNotEmpty) {
          m.account = saved;
          _payeeCtrls[m.id]!.text = saved;
          filled = true;
        }
      }
    }
    if (filled) AppStorage.saveSettlement(widget.settlement);
  }

  /// 총무의 바로 송금 링크 ('· 토스 https://toss.me/...')
  List<String> get _payLinkLines => [
        if (AppStorage.tossLink.isNotEmpty) '· 토스 ${AppStorage.tossLink}',
        if (AppStorage.kakaoPayLink.isNotEmpty)
          '· 카카오페이 ${AppStorage.kakaoPayLink}',
      ];

  void _writePayLinks(StringBuffer b) {
    final lines = _payLinkLines;
    if (lines.isEmpty) return;
    b
      ..writeln()
      ..writeln('👉 눌러서 바로 송금');
    lines.forEach(b.writeln);
  }

  Future<void> _openLink(String link) async {
    HapticFeedback.lightImpact();
    var ok = false;
    try {
      ok = await launchUrl(Uri.parse(link),
          mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!ok && mounted) _toast('링크를 열지 못했어요. 주소를 다시 확인해 주세요');
  }

  /// 받는 사람의 계좌 (총무는 '내 입금 계좌')
  String _accountOf(Member m) => m.id == widget.settlement.treasurer.id
      ? _accountLine()
      : m.account.trim();

  /// 영수증·텍스트에 함께 표시할 받는 사람 계좌 (멤버 ID → 계좌)
  Map<String, String> get _payeeAccounts => {
        for (final m in _payees)
          if (m.account.trim().isNotEmpty) m.id: m.account.trim(),
      };

  bool _saving = false;

  /// 계좌가 비어 있을 때만 상단 안내 배너 표시 (누르면 닫힘)
  bool _showNudge = AppStorage.accountNumber.isEmpty;

  @override
  void dispose() {
    _bankCtrl.dispose();
    _holderCtrl.dispose();
    _accountCtrl.dispose();
    _bankFocus.dispose();
    _accountFocus.dispose();
    _tossCtrl.dispose();
    _kakaoCtrl.dispose();
    for (final c in _payeeCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// 계좌 입력칸으로 이동 (포커스가 잡히면 화면이 자동으로 스크롤됩니다)
  void _goToAccount() {
    HapticFeedback.lightImpact();
    setState(() => _showNudge = false);
    if (_bankCtrl.text.trim().isEmpty) {
      _bankFocus.requestFocus();
    } else {
      _accountFocus.requestFocus();
    }
  }

  // ───────────────── 입금 확인 ─────────────────

  bool _isPaid(Due d) => widget.settlement.isPaid(d.member.id);

  bool _isMemberPaid(String id) => widget.settlement.isPaid(id);

  void _togglePaid(Due d) {
    final s = widget.settlement;
    final nowPaid = s.togglePaid(d.member.id);
    final allPaid = _dues.every(_isPaid);
    if (nowPaid && allPaid) {
      HapticFeedback.mediumImpact();
      _toast('🎉 모두 입금 완료! 수고했어요, 총무님');
      // 다 받았으니 예약한 미입금 알림은 취소
      if (s.remindAt != null) {
        s.remindAt = null;
        ReminderService.instance.cancel(s.id);
      }
    } else {
      HapticFeedback.lightImpact();
    }
    setState(() {});
    AppStorage.saveSettlement(s);
  }

  String _buildReminderText() {
    final s = widget.settlement;
    final title = s.title.trim().isEmpty ? '모임' : s.title.trim();
    final b = StringBuffer()
      ..writeln('📢 [$title] 정산 입금 안내')
      ..writeln('아직 입금 확인이 안 된 분들이에요 🙏')
      ..writeln();
    for (final d in _dues.where((d) => !_isPaid(d))) {
      if (_transferMode) {
        for (final t in d.transfers) {
          b.writeln('· ${t.from.name} → ${t.to.name}  ${Fmt.won(t.amount)}');
        }
      } else {
        b.writeln('· ${d.member.name}  ${Fmt.won(d.amount)}');
      }
    }
    if (_transferMode) {
      final receivers = <String, Member>{
        for (final d in _dues.where((d) => !_isPaid(d)))
          for (final t in d.transfers) t.to.id: t.to,
      };
      final lines = [
        for (final m in receivers.values)
          if (_accountOf(m).isNotEmpty) '🏦 ${m.name}: ${_accountOf(m)}',
      ];
      if (lines.isNotEmpty) {
        b.writeln();
        lines.forEach(b.writeln);
      }
    } else {
      final account = _accountLine();
      if (account.isNotEmpty) {
        b
          ..writeln()
          ..writeln('🏦 $account');
      }
    }
    if (!_transferMode ||
        _dues.any((d) =>
            !_isPaid(d) && d.transfers.any((t) => t.to.id == s.treasurer.id))) {
      _writePayLinks(b);
    }
    return b.toString().trimRight();
  }

  // ───────────────── 미입금 리마인드 알림 ─────────────────

  Future<void> _pickReminder() async {
    HapticFeedback.lightImpact();
    final now = DateTime.now();
    final days = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      backgroundColor: context.colors.card,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                '언제 다시 알려드릴까요?',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: context.colors.text,
                ),
              ),
            ),
            for (final (d, label) in const [
              (1, '내일'),
              (3, '3일 후'),
              (7, '일주일 후')
            ])
              ListTile(
                leading: const Icon(Icons.notifications_active_outlined,
                    color: AppColors.primary),
                title: Text(
                  '$label 저녁 8시',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: context.colors.text,
                  ),
                ),
                subtitle: Text(
                  _reminderLabel(reminderTimeAfter(now, d)),
                  style: TextStyle(fontSize: 12, color: context.colors.subText),
                ),
                onTap: () => Navigator.of(ctx).pop(d),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (days == null || !mounted) return;
    final s = widget.settlement;
    final at = reminderTimeAfter(DateTime.now(), days);
    final unpaid = _dues.where((d) => !_isPaid(d)).length;
    final ok = await ReminderService.instance.schedule(s, at, unpaid: unpaid);
    if (!mounted) return;
    if (!ok) {
      _toast('알림을 예약하지 못했어요. 휴대폰 설정에서 알림을 허용해 주세요');
      return;
    }
    setState(() => s.remindAt = at);
    AppStorage.saveSettlement(s);
    _toast('${_reminderLabel(at)}에 알려드릴게요 🔔');
  }

  Future<void> _cancelReminder() async {
    HapticFeedback.lightImpact();
    final s = widget.settlement;
    await ReminderService.instance.cancel(s.id);
    if (!mounted) return;
    setState(() => s.remindAt = null);
    AppStorage.saveSettlement(s);
    _toast('미입금 알림을 취소했어요');
  }

  /// '11월 27일 (목) 오후 8시'
  String _reminderLabel(DateTime at) => reminderLabel(at);

  // ───────────────── 개인별 상세 ─────────────────

  /// 한 사람에게 보낼 개인 메시지 (갠톡용)
  String _buildPersonText(PersonResult p) {
    final s = widget.settlement;
    final title = s.title.trim().isEmpty ? '모임' : s.title.trim();
    final b = StringBuffer()
      ..writeln('📢 [$title] ${p.member.name}님 정산 안내')
      ..writeln();
    for (var i = 0; i < s.rounds.length; i++) {
      final r = s.rounds[i];
      final share = p.roundShares[r.id];
      if (share == null) continue;
      b.writeln('· ${s.roundLabel(i)}  ${_shareText(r, p.member.id, share)}');
    }
    if (p.pay == 0) {
      b
        ..writeln()
        ..writeln('🎂 이번 정산은 면제예요!');
      return b.toString().trimRight();
    }
    b.writeln('= ${Fmt.won(p.pay)} (${s.roundingLabel})');

    final due = _dues.where((d) => d.member.id == p.member.id).firstOrNull;
    if (_transferMode) {
      b.writeln();
      if (due == null) {
        b.writeln('보낼 돈은 없어요 (먼저 결제해 주셨어요 🙏)');
      } else {
        b.writeln('🔁 이렇게 보내 주세요');
        for (final t in due.transfers) {
          final acc = _accountOf(t.to);
          b.writeln('· ${t.to.name}에게 ${Fmt.won(t.amount)}'
              '${acc.isEmpty ? '' : '\n  🏦 $acc'}');
        }
        if (due.transfers.any((t) => t.to.id == s.treasurer.id)) {
          _writePayLinks(b);
        }
      }
    } else {
      final account = _accountLine();
      if (account.isNotEmpty) {
        b
          ..writeln()
          ..writeln('🏦 $account');
      }
      _writePayLinks(b);
    }
    return b.toString().trimRight();
  }

  String _shareText(RoundItem r, String memberId, double share) {
    if (r.isFree(memberId)) return '면제';
    final tags = <String>[
      if (r.hasSober && r.soberIds.contains(memberId))
        '술X ${r.discountPercent}% 할인',
      if (r.extraOf(memberId) > 0) '추가 ${Fmt.won(r.extraOf(memberId))} 포함',
    ];
    final won = Fmt.won(share.round());
    return tags.isEmpty ? won : '$won (${tags.join(', ')})';
  }

  Future<void> _showPerson(PersonResult p) async {
    HapticFeedback.lightImpact();
    FocusScope.of(context).unfocus();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: context.colors.card,
      builder: (ctx) => _PersonSheet(
        settlement: widget.settlement,
        result: p,
        due: _dues.where((d) => d.member.id == p.member.id).firstOrNull,
        transferMode: _transferMode,
        shareText: _shareText,
        accountOf: _accountOf,
        onCopy: () async {
          await Clipboard.setData(ClipboardData(text: _buildPersonText(p)));
          if (!ctx.mounted) return;
          Navigator.of(ctx).pop();
          _toast('${p.member.name}님 메시지 복사 완료! 갠톡에 붙여넣기 하세요');
        },
      ),
    );
  }

  Future<void> _copyReminder() async {
    HapticFeedback.lightImpact();
    await Clipboard.setData(ClipboardData(text: _buildReminderText()));
    if (!mounted) return;
    _toast('독촉 메시지 복사 완료! 단톡방에 붙여넣기 하세요');
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 2),
      ));
  }

  // ───────────────── 카톡 텍스트 ─────────────────

  String _buildShareText(bool isPro) {
    final s = widget.settlement;
    final b = StringBuffer();
    final title = s.title.trim().isEmpty ? '모임' : s.title.trim();

    b.writeln('📢 [$title] 정산 안내');
    b.writeln(DateFormat('yyyy.MM.dd').format(_now));
    b.writeln();
    b.writeln('🧾 차수별 내역');
    for (var i = 0; i < s.rounds.length; i++) {
      final r = s.rounds[i];
      if (r.amount <= 0) continue;
      final payer = _transferMode ? ' · ${s.payerOf(r).name} 결제' : '';
      b.writeln(
          '· ${s.roundLabel(i)}  ${Fmt.won(r.amount)} (${r.headCount}명$payer)');
    }
    b.writeln('= 총 ${Fmt.won(s.totalSpent)}');
    b.writeln();
    if (_transferMode) {
      b.writeln('💸 1인별 부담액');
      for (final p in _results) {
        b.writeln('· ${p.member.name}  ${Fmt.won(p.pay)}');
      }
      b.writeln();
      b.writeln('🔁 송금 정리');
      for (final d in _dues) {
        for (final t in d.transfers) {
          b.writeln('· ${t.from.name} → ${t.to.name}  ${Fmt.won(t.amount)}'
              '${_isPaid(d) ? ' ✅완료' : ''}');
        }
      }
      if (_payeeAccounts.isNotEmpty) {
        b.writeln();
        b.writeln('🏦 받는 계좌');
        for (final m in _payees) {
          final acc = _payeeAccounts[m.id];
          if (acc != null) b.writeln('· ${m.name}: $acc');
        }
      }
    } else {
      b.writeln('💸 1인별 입금액');
      for (final p in _results) {
        if (p.pay == 0) {
          b.writeln('· ${p.member.name}  면제 🎂');
          continue;
        }
        b.writeln('· ${p.member.name}  ${Fmt.won(p.pay)}'
            '${_isMemberPaid(p.member.id) ? ' ✅입금완료' : ''}');
      }
    }

    final account = _accountLine();
    if (account.isNotEmpty) {
      b.writeln();
      b.writeln(_transferMode ? '🏦 ${s.treasurer.name} 계좌' : '🏦 입금 계좌');
      b.writeln(account);
    }
    _writePayLinks(b);

    b.writeln();
    b.writeln('※ ${s.roundingLabel} 정산');
    if (!isPro) b.writeln('— 똑똑한 총무 앱으로 정산했어요');
    return b.toString().trimRight();
  }

  String _accountLine() {
    final bank = _bankCtrl.text.trim();
    final number = _accountCtrl.text.trim();
    final holder = _holderCtrl.text.trim();
    if (number.isEmpty) return '';
    final head = [bank, number].where((e) => e.isNotEmpty).join(' ');
    return holder.isEmpty ? head : '$head ($holder)';
  }

  Future<void> _copyText() async {
    HapticFeedback.lightImpact();
    await Clipboard.setData(
      ClipboardData(text: _buildShareText(ProManager.instance.isPro.value)),
    );
    if (!mounted) return;
    _toast(_accountLine().isEmpty
        ? '복사 완료! (계좌를 입력하면 함께 복사돼요)'
        : '복사 완료! 카톡 대화방에 붙여넣기 하세요 💬');
  }

  // ───────────────── 영수증 이미지 ─────────────────

  Future<void> _saveImage(BuildContext buttonContext) async {
    HapticFeedback.lightImpact();
    FocusScope.of(context).unfocus();

    // iPad 공유 시트 위치 (아이폰에선 무시됨)
    final box = buttonContext.findRenderObject() as RenderBox?;
    final origin =
        box == null ? null : box.localToGlobal(Offset.zero) & box.size;

    // ───────── 🎬 보상형 광고 연동 위치 ─────────
    // TODO(AdMob 2단계): 무료 사용자는 RewardedAd 를 먼저 보여주고,
    // onUserEarnedReward 콜백 안에서 아래 캡처/공유 로직을 실행하세요.
    // if (!ProManager.instance.isPro.value) {
    //   final rewarded = await showRewardedAd();
    //   if (!rewarded) return;
    // }
    // ───────────────────────────────────────────

    setState(() => _saving = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      final boundary = _receiptKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('receipt not ready');

      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) throw StateError('encode failed');

      final bytes = data.buffer.asUint8List();
      final fileName =
          'chongmu_${DateFormat('yyyyMMdd_HHmm').format(_now)}.png';

      // iOS 공유 시트가 열리면 '이미지 저장'을 눌러 사진첩에 저장할 수 있어요.
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(bytes, mimeType: 'image/png', name: fileName)],
          sharePositionOrigin: origin,
        ),
      );
    } catch (_) {
      if (mounted) _toast('이미지를 만들지 못했어요. 다시 시도해 주세요');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ───────────────── UI ─────────────────

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ProManager.instance.isPro,
      builder: (context, isPro, _) {
        return GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: Scaffold(
            appBar: AppBar(title: const Text('정산 영수증')),
            body: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_showNudge) ...[
                    _AccountNudge(onTap: _goToAccount),
                    const SizedBox(height: 4),
                  ],
                  RepaintBoundary(
                    key: _receiptKey,
                    // 영수증은 다크 모드에서도 항상 밝은 종이 (저장 이미지 통일)
                    child: Theme(
                      data: AppTheme.light,
                      child: DefaultTextStyle.merge(
                        style: TextStyle(color: AppPalette.light.text),
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppPalette.light.background,
                            borderRadius:
                                BorderRadius.circular(AppDecor.radius),
                          ),
                          padding: const EdgeInsets.all(12),
                          child: _ReceiptPaper(
                            settlement: widget.settlement,
                            results: _results,
                            transfers: _transferMode
                                ? [for (final d in _dues) ...d.transfers]
                                : const [],
                            date: _now,
                            accountLine: _accountLine(),
                            payeeAccounts: _payeeAccounts,
                            showWatermark: !isPro,
                            onPersonTap: _showPerson,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '💡 영수증에서 이름을 누르면 개인별 상세와 갠톡 메시지를 볼 수 있어요',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: context.colors.subText,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildPaymentCard(),
                  if (_payees.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _buildPayeeAccountsCard(),
                  ],
                  const SizedBox(height: 12),
                  _buildAccountCard(),
                ],
              ),
            ),
            bottomNavigationBar: _buildBottomBar(isPro),
          ),
        );
      },
    );
  }

  Widget _buildPaymentCard() {
    int sum(Iterable<Due> list) => list.fold(0, (a, d) => a + d.amount);
    final total = sum(_dues);
    final paid = _dues.where(_isPaid).toList();
    final received = sum(paid);
    final remain = total - received;
    final allPaid = paid.length == _dues.length;
    final progress = _dues.isEmpty ? 1.0 : paid.length / _dues.length;

    return Container(
      decoration: AppDecor.card(context),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.fact_check_rounded,
                  color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                _transferMode ? '송금 확인' : '입금 확인',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: context.colors.text,
                ),
              ),
              const Spacer(),
              Text(
                '${paid.length}/${_dues.length}명',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            allPaid
                ? '🎉 모두 입금 완료! 수고했어요, 총무님'
                : _transferMode
                    ? '여러 명이 나눠 결제해서, 아래처럼 보내면 끝나요'
                    : '입금한 사람을 눌러서 체크하세요',
            style: TextStyle(
              fontSize: 12,
              fontWeight: allPaid ? FontWeight.w700 : FontWeight.w500,
              color: allPaid ? AppColors.primary : context.colors.subText,
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(end: progress),
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => LinearProgressIndicator(
                value: v,
                minHeight: 8,
                backgroundColor: context.colors.background,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(height: 10),
          // 작은 화면(아이폰 SE)에서도 넘치지 않도록 양쪽을 반씩 나누고 필요하면 축소
          Row(
            children: [
              Expanded(
                child: _MoneyLabel(
                  label: '받은 금액',
                  amount: received,
                  color: context.colors.text,
                  alignment: Alignment.centerLeft,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MoneyLabel(
                  label: '남은 금액',
                  amount: remain,
                  color: remain > 0 ? AppColors.danger : AppColors.primary,
                  alignment: Alignment.centerRight,
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(top: 12, bottom: 4),
            child: Divider(),
          ),
          for (final d in _dues)
            _PaidRow(
              name: d.member.name,
              amount: d.amount,
              detail: _transferMode
                  ? d.transfers
                      .map((t) => '→ ${t.to.name} ${Fmt.won(t.amount)}')
                      .join(' · ')
                  : null,
              paid: _isPaid(d),
              onTap: () => _togglePaid(d),
            ),
          if (!allPaid) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: _copyReminder,
                icon: const Icon(Icons.campaign_outlined, size: 18),
                label: const Text('미입금자 독촉 메시지 복사'),
              ),
            ),
            const SizedBox(height: 4),
            _buildReminderRow(),
          ],
        ],
      ),
    );
  }

  Widget _buildReminderRow() {
    final s = widget.settlement;
    if (!s.hasPendingReminder(DateTime.now())) {
      return Center(
        child: TextButton.icon(
          onPressed: _pickReminder,
          style: TextButton.styleFrom(foregroundColor: AppColors.primary),
          icon: const Icon(Icons.alarm_add_rounded, size: 18),
          label: const Text(
            '나중에 미입금 알림 받기',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      decoration: BoxDecoration(
        color: context.colors.primaryLight,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.notifications_active_rounded,
              size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${_reminderLabel(s.remindAt!)} 알림 예약됨',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ),
          TextButton(
            onPressed: _cancelReminder,
            child: Text('취소', style: TextStyle(color: context.colors.subText)),
          ),
        ],
      ),
    );
  }

  /// 송금 정리: 총무가 아닌 결제자의 계좌 입력
  Widget _buildPayeeAccountsCard() {
    return Container(
      decoration: AppDecor.card(context),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.people_alt_rounded,
                  color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                '받는 사람 계좌',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: context.colors.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '먼저 결제한 사람의 계좌를 적으면 영수증과 메시지에 함께 나와요',
            style: TextStyle(fontSize: 12, color: context.colors.subText),
          ),
          for (final m in _payees) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _payeeCtrls[m.id],
              textInputAction: TextInputAction.done,
              decoration: AppDecor.boxInput(
                context,
                '${m.name} 계좌 (예: 토스뱅크 1000-1234 ${m.name})',
              ).copyWith(
                prefixIcon: Padding(
                  padding: const EdgeInsets.only(left: 12, right: 8),
                  child: Text(
                    m.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                prefixIconConstraints:
                    const BoxConstraints(minWidth: 0, minHeight: 0),
              ),
              onChanged: (v) {
                m.account = v.trim();
                AppStorage.rememberAccount(m.name, v);
                AppStorage.saveSettlement(widget.settlement);
                setState(() {});
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAccountCard() {
    return Container(
      decoration: AppDecor.card(context),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_rounded,
                  color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                '내 입금 계좌',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: context.colors.text,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: context.colors.primaryLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '자동 저장',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _bankCtrl,
                  focusNode: _bankFocus,
                  textInputAction: TextInputAction.next,
                  decoration: AppDecor.boxInput(context, '은행 (예: 카카오뱅크)'),
                  onChanged: (v) {
                    AppStorage.setBankName(v.trim());
                    setState(() {});
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 1,
                child: TextField(
                  controller: _holderCtrl,
                  textInputAction: TextInputAction.next,
                  decoration: AppDecor.boxInput(context, '예금주'),
                  onChanged: (v) {
                    AppStorage.setAccountHolder(v.trim());
                    setState(() {});
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _accountCtrl,
            focusNode: _accountFocus,
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.done,
            decoration: AppDecor.boxInput(context, '계좌번호 (예: 3333-01-1234567)'),
            onChanged: (v) {
              AppStorage.setAccountNumber(v.trim());
              setState(() {});
            },
          ),
          const SizedBox(height: 16),
          Text(
            '바로 송금 링크 (선택)',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: context.colors.text,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '토스·카카오페이 앱의 \'내 송금 링크\'를 넣으면 카톡 메시지에서 눌러서 바로 송금할 수 있어요',
            style: TextStyle(fontSize: 12, color: context.colors.subText),
          ),
          const SizedBox(height: 8),
          _payLinkField(
            controller: _tossCtrl,
            hint: '토스 아이디 또는 toss.me/아이디',
            error: _tossError ? 'toss.me/아이디 형식으로 넣어 주세요' : null,
            saved: AppStorage.tossLink,
            onChanged: (v) {
              final link = normalizeTossLink(v);
              setState(() => _tossError = link == null);
              if (link != null) AppStorage.setTossLink(link);
            },
          ),
          const SizedBox(height: 8),
          _payLinkField(
            controller: _kakaoCtrl,
            hint: '카카오페이 송금 링크 (qr.kakaopay.com/...)',
            error: _kakaoError ? 'qr.kakaopay.com/... 링크를 붙여 넣어 주세요' : null,
            saved: AppStorage.kakaoPayLink,
            onChanged: (v) {
              final link = normalizeKakaoPayLink(v);
              setState(() => _kakaoError = link == null);
              if (link != null) AppStorage.setKakaoPayLink(link);
            },
          ),
          const SizedBox(height: 8),
          Text(
            '입력한 계좌는 이 휴대폰에만 저장되고, 영수증과 카톡 텍스트에 함께 표시돼요.',
            style: TextStyle(fontSize: 12, color: context.colors.subText),
          ),
        ],
      ),
    );
  }

  Widget _payLinkField({
    required TextEditingController controller,
    required String hint,
    required String? error,
    required String saved,
    required ValueChanged<String> onChanged,
  }) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.url,
      autocorrect: false,
      textInputAction: TextInputAction.done,
      onChanged: onChanged,
      decoration: AppDecor.boxInput(context, hint).copyWith(
        errorText: error,
        suffixIcon: saved.isEmpty || error != null
            ? null
            : IconButton(
                tooltip: '링크 열어서 확인',
                icon: const Icon(Icons.open_in_new_rounded,
                    size: 20, color: AppColors.primary),
                onPressed: () => _openLink(saved),
              ),
      ),
    );
  }

  Widget _buildBottomBar(bool isPro) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.card,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 54,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.kakao,
                      foregroundColor: AppColors.kakaoText,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    onPressed: _copyText,
                    icon: const Icon(Icons.chat_bubble_rounded, size: 18),
                    label: const FittedBox(child: Text('카톡 정산 텍스트 복사')),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Builder(
                  builder: (buttonContext) => SizedBox(
                    height: 54,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      onPressed:
                          _saving ? null : () => _saveImage(buttonContext),
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.download_rounded, size: 20),
                      label: FittedBox(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('영수증 이미지로 저장'),
                            if (!isPro) ...[
                              const SizedBox(width: 6),
                              // 🎬 보상형 광고 연동 예정 표시
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'AD',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// '받은 금액 51,400원' 처럼 라벨 + 금액 (공간이 모자라면 글자를 줄여서 표시)
class _MoneyLabel extends StatelessWidget {
  const _MoneyLabel({
    required this.label,
    required this.amount,
    required this.color,
    required this.alignment,
  });

  final String label;
  final int amount;
  final Color color;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: alignment,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label ',
            style: TextStyle(fontSize: 12, color: context.colors.subText),
          ),
          Text(
            Fmt.won(amount),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// 입금 확인 체크 행
class _PaidRow extends StatelessWidget {
  const _PaidRow({
    required this.name,
    required this.amount,
    required this.paid,
    required this.onTap,
    this.detail,
  });

  final String name;
  final int amount;
  final bool paid;

  /// 송금 정리 모드: '→ 지영 30,000원' 처럼 받는 사람 표시
  final String? detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      checked: paid,
      label: '$name 입금 확인',
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: paid ? AppColors.primary : context.colors.card,
                  border: Border.all(
                    color: paid ? AppColors.primary : context.colors.hint,
                    width: 1.5,
                  ),
                ),
                child: paid
                    ? const Icon(Icons.check_rounded,
                        size: 18, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color:
                            paid ? context.colors.subText : context.colors.text,
                      ),
                    ),
                    if (detail != null)
                      Text(
                        detail!,
                        style: TextStyle(
                          fontSize: 12,
                          color: context.colors.subText,
                        ),
                      ),
                  ],
                ),
              ),
              if (paid) ...[
                const _PaidTag(),
                const SizedBox(width: 8),
              ],
              Text(
                Fmt.won(amount),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: paid ? context.colors.subText : context.colors.text,
                  decoration: paid ? TextDecoration.lineThrough : null,
                  decorationColor: context.colors.subText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// '입금완료' 작은 태그 (영수증 이미지에도 표시됨)
class _PaidTag extends StatelessWidget {
  const _PaidTag();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: context.colors.primaryLight,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        '입금완료',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

/// 계좌 미입력 시 상단 안내 배너
class _AccountNudge extends StatelessWidget {
  const _AccountNudge({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.primaryLight,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.account_balance_wallet_outlined,
                  size: 20, color: AppColors.primary),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  '입금 계좌를 입력하면 영수증과 카톡 텍스트에 함께 표시돼요',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ),
              SizedBox(width: 8),
              Text(
                '입력하기 ›',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════
// 종이 영수증 위젯 (이 부분이 그대로 이미지로 저장됩니다)
// ═════════════════════════════════════════════

class _ReceiptPaper extends StatelessWidget {
  const _ReceiptPaper({
    required this.settlement,
    required this.results,
    required this.transfers,
    required this.date,
    required this.accountLine,
    required this.showWatermark,
    this.payeeAccounts = const {},
    this.onPersonTap,
  });

  /// 총무가 아닌 받는 사람 계좌 (멤버 ID → 계좌)
  final Map<String, String> payeeAccounts;

  /// 이름을 누르면 개인별 상세 (이미지에는 영향 없음)
  final ValueChanged<PersonResult>? onPersonTap;

  final Settlement settlement;
  final List<PersonResult> results;

  /// 송금 정리 (여러 명이 결제했을 때만)
  final List<Transfer> transfers;
  final DateTime date;
  final String accountLine;
  final bool showWatermark;

  static const _num = [ui.FontFeature.tabularFigures()];

  /// 영수증 종이는 다크 모드에서도 항상 밝은 종이색 (공유 이미지 통일)
  static final AppPalette _paper = AppPalette.light;

  static final _sub = TextStyle(fontSize: 12, color: _paper.subText);
  static final _body = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: _paper.text,
    fontFeatures: _num,
  );
  static final _bold = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w800,
    color: _paper.text,
    fontFeatures: _num,
  );
  static final _section = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w800,
    color: _paper.subText,
    letterSpacing: 0.5,
  );

  @override
  Widget build(BuildContext context) {
    final s = settlement;
    final collected = Settlement.totalCollected(results);
    final surplus = collected - s.totalSpent;
    final title = s.title.trim().isEmpty ? '우리 모임' : s.title.trim();

    return ClipPath(
      clipper: _ZigzagClipper(),
      child: Container(
        color: context.colors.card,
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 헤더 ──
            const Text(
              'RECEIPT · 정산 영수증',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: context.colors.text,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              DateFormat('yyyy.MM.dd HH:mm').format(date),
              textAlign: TextAlign.center,
              style: _sub,
            ),
            const _DashedLine(),

            // ── 총 지출액 ──
            Row(
              children: [
                Text('총 지출액', style: _bold),
                const Spacer(),
                Text(
                  Fmt.won(s.totalSpent),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: context.colors.text,
                    fontFeatures: _num,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // ── 차수별 상세 ──
            Text('차수별 내역', style: _section),
            const SizedBox(height: 8),
            for (var i = 0; i < s.rounds.length; i++)
              if (s.rounds[i].amount > 0) _roundRow(i),
            const _DashedLine(),

            // ── 인원별 입금액 ──
            Text(transfers.isEmpty ? '인원별 입금액' : '인원별 부담액', style: _section),
            const SizedBox(height: 8),
            for (final p in results) _personRow(p),
            const _DashedLine(),

            // ── 송금 정리 ──
            if (transfers.isNotEmpty) ...[
              Text('송금 정리', style: _section),
              const SizedBox(height: 8),
              for (final t in transfers)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _row(
                        '${t.from.name} → ${t.to.name}',
                        Fmt.won(t.amount),
                        _body,
                      ),
                      if (payeeAccounts[t.to.id] != null)
                        Text('🏦 ${payeeAccounts[t.to.id]}', style: _sub),
                    ],
                  ),
                ),
              const _DashedLine(),
            ],

            // ── 합계 / 자투리 ──
            _row('총 걷는 금액', Fmt.won(collected), _body),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: context.colors.primaryLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Text(
                    '총무 자투리 잔액',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${surplus >= 0 ? '+' : ''}${Fmt.won(surplus)}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: AppColors.primary,
                      fontFeatures: _num,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              s.roundUnit == 1
                  ? '1원 단위까지 정확히 나눴어요'
                  : '${s.roundingLabel}으로 생긴 금액이에요',
              style: _sub,
              textAlign: TextAlign.right,
            ),

            // ── 입금 계좌 ──
            if (accountLine.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: context.colors.border),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.account_balance_rounded,
                        size: 18, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        accountLine,
                        style: _body,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // ── 로고 워터마크 (PRO 구매 시 제거) ──
            if (showWatermark) ...[
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AppLogo(size: 18),
                  SizedBox(width: 6),
                  Text(
                    '똑똑한 총무로 정산했어요',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: context.colors.hint,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(String left, String right, TextStyle style) {
    return Row(
      children: [
        Expanded(child: Text(left, style: style)),
        const SizedBox(width: 12),
        Text(right, style: style),
      ],
    );
  }

  Widget _roundRow(int i) {
    final r = settlement.rounds[i];
    final unit = settlement.roundUnit;
    final mode = settlement.roundMode;
    final detail = StringBuffer(
        '${r.headCount}명 · 1인 ${Fmt.won(r.perPerson(unit, mode))}');
    if (r.hasSober) {
      detail.write(' · 술X ${Fmt.won(r.soberPerPerson(unit, mode))}');
    }
    if (r.hasFree) {
      detail.write(' · 면제 ${r.freeIds.length}명');
    }
    if (r.extras.isNotEmpty) {
      detail.write(' · 개별 추가 ${Fmt.won(r.extrasTotal)}');
    }
    if (transfers.isNotEmpty) {
      detail.write(' · ${settlement.payerOf(r).name} 결제');
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row(settlement.roundLabel(i), Fmt.won(r.amount), _body),
          const SizedBox(height: 2),
          Text(detail.toString(), style: _sub),
        ],
      ),
    );
  }

  /// '1차', '2차(술X)', '1차(+12,000)' 처럼 참석 차수 표시
  String _attendLabel(int i, RoundItem r, String memberId) {
    final tags = <String>[
      if (r.isFree(memberId)) '면제',
      if (r.hasSober && r.soberIds.contains(memberId)) '술X',
      if (r.extraOf(memberId) > 0) '+${Fmt.number(r.extraOf(memberId))}',
    ];
    return tags.isEmpty ? '${i + 1}차' : '${i + 1}차(${tags.join(', ')})';
  }

  Widget _personRow(PersonResult p) {
    final rounds = settlement.rounds;
    final attended = <String>[
      for (var i = 0; i < rounds.length; i++)
        if (p.roundShares.containsKey(rounds[i].id))
          _attendLabel(i, rounds[i], p.member.id),
    ];
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPersonTap == null ? null : () => onPersonTap!(p),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(child: Text(p.member.name, style: _body)),
                      if (settlement.isPaid(p.member.id)) ...[
                        const SizedBox(width: 6),
                        const _PaidTag(),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(attended.join(' · '), style: _sub),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(p.pay == 0 ? '면제' : Fmt.won(p.pay), style: _bold),
          ],
        ),
      ),
    );
  }
}

class _DashedLine extends StatelessWidget {
  const _DashedLine();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final count = (constraints.maxWidth / 8).floor();
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(
              count,
              (_) =>
                  Container(width: 4, height: 1.2, color: context.colors.hint),
            ),
          );
        },
      ),
    );
  }
}

/// 영수증 하단 지그재그(톱니) 모양
class _ZigzagClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    const tooth = 12.0;
    const depth = 6.0;
    final path = Path()
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height - depth);
    var x = size.width;
    var down = true;
    while (x > 0) {
      x -= tooth / 2;
      if (x < 0) x = 0;
      path.lineTo(x, down ? size.height : size.height - depth);
      down = !down;
    }
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

// ═════════════════════════════════════════════
// 개인별 상세 (바텀시트)
// ═════════════════════════════════════════════

class _PersonSheet extends StatelessWidget {
  const _PersonSheet({
    required this.settlement,
    required this.result,
    required this.due,
    required this.transferMode,
    required this.shareText,
    required this.accountOf,
    required this.onCopy,
  });

  final Settlement settlement;
  final PersonResult result;
  final Due? due;
  final bool transferMode;
  final String Function(RoundItem r, String memberId, double share) shareText;
  final String Function(Member m) accountOf;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final s = settlement;
    final p = result;
    final sub = TextStyle(fontSize: 13, color: context.colors.subText);
    final body = TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      color: context.colors.text,
    );
    final received = transferMode
        ? s
            .buildTransfers()
            .where((t) => t.to.id == p.member.id)
            .fold(0, (a, t) => a + t.amount)
        : 0;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    p.member.name,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: context.colors.text,
                    ),
                  ),
                ),
                Text(
                  p.pay == 0 ? '면제 🎂' : Fmt.won(p.pay),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '정확히 ${Fmt.won(p.exactTotal.round())} → ${s.roundingLabel}',
              style: sub,
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Divider(),
            ),
            for (var i = 0; i < s.rounds.length; i++)
              if (p.roundShares[s.rounds[i].id] case final share?)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: Text(s.roundLabel(i), style: body)),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          shareText(s.rounds[i], p.member.id, share),
                          textAlign: TextAlign.right,
                          style: body,
                        ),
                      ),
                    ],
                  ),
                ),
            if (transferMode) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Divider(),
              ),
              if (due != null)
                for (final t in due!.transfers)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '→ ${t.to.name}에게 ${Fmt.won(t.amount)} 보내기',
                          style: body,
                        ),
                        if (accountOf(t.to).isNotEmpty)
                          Text('🏦 ${accountOf(t.to)}', style: sub),
                      ],
                    ),
                  )
              else if (received > 0)
                Text('← 다른 사람들에게 ${Fmt.won(received)} 받을 차례예요', style: body)
              else
                Text('주고받을 돈이 없어요', style: body),
            ],
            const SizedBox(height: 16),
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: onCopy,
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('개인 메시지 복사'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
