import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../models/round_item.dart';
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
    final account = _accountLine();
    if (account.isNotEmpty) {
      b
        ..writeln()
        ..writeln('🏦 $account');
    }
    return b.toString().trimRight();
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
    } else {
      b.writeln('💸 1인별 입금액');
      for (final p in _results) {
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

    b.writeln();
    b.writeln('※ ${Fmt.number(s.roundUnit)}원 단위 올림 정산');
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
                            showWatermark: !isPro,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildPaymentCard(),
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
                icon: const Icon(Icons.notifications_active_outlined, size: 18),
                label: const Text('미입금자 독촉 메시지 복사'),
              ),
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
          const SizedBox(height: 8),
          Text(
            '입력한 계좌는 이 휴대폰에만 저장되고, 영수증과 카톡 텍스트에 함께 표시돼요.',
            style: TextStyle(fontSize: 12, color: context.colors.subText),
          ),
        ],
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
  });

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
                  child: _row(
                    '${t.from.name} → ${t.to.name}',
                    Fmt.won(t.amount),
                    _body,
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
              '${Fmt.number(s.roundUnit)}원 단위 올림으로 생긴 금액이에요',
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
    final detail =
        StringBuffer('${r.headCount}명 · 1인 ${Fmt.won(r.perPerson(unit))}');
    if (r.hasSober) {
      detail.write(' · 술X ${Fmt.won(r.soberPerPerson(unit))}');
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
    return Padding(
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
          Text(Fmt.won(p.pay), style: _bold),
        ],
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
