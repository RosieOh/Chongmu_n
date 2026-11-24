import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../models/round_item.dart';
import '../theme/app_theme.dart';
import 'history_screen.dart';
import 'receipt_screen.dart';
import 'settings_screen.dart';

/// ① 메인 화면 — 차수별 정산 입력
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// 차수마다 다른 장소 예시 (입력칸 힌트)
  static const _placeHints = ['삼겹살', '호프집', '노래방', '포장마차', '해장국'];

  late Settlement _s;
  late final TextEditingController _titleCtrl;
  final Map<String, TextEditingController> _amountCtrls = {};
  final Map<String, TextEditingController> _nameCtrls = {};
  Timer? _saveTimer;

  /// 방금 추가한 차수 → 금액칸 자동 포커스
  String? _autofocusRoundId;

  /// 첫 실행 안내 카드 표시 여부
  bool _showTip = !AppStorage.onboardingDone;

  @override
  void initState() {
    super.initState();
    _s = AppStorage.loadSettlement();
    _titleCtrl = TextEditingController(text: _s.title);
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    AppStorage.saveSettlement(_s);
    _titleCtrl.dispose();
    for (final c in _amountCtrls.values) {
      c.dispose();
    }
    for (final c in _nameCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  // ───────────────── 상태 변경 + 자동 저장 ─────────────────

  /// 사용자가 정산 내용을 바꿀 때 사용 (예시 데이터 표시 해제 + 자동 저장)
  void _update(VoidCallback fn) {
    setState(() {
      _s.isSample = false;
      fn();
    });
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(
      const Duration(milliseconds: 400),
      () => AppStorage.saveSettlement(_s),
    );
  }

  TextEditingController _amountCtrl(RoundItem r) => _amountCtrls.putIfAbsent(
        r.id,
        () => TextEditingController(
            text: r.amount > 0 ? Fmt.number(r.amount) : ''),
      );

  TextEditingController _nameCtrl(RoundItem r) =>
      _nameCtrls.putIfAbsent(r.id, () => TextEditingController(text: r.name));

  /// 다른 정산으로 바꾸기 (새 정산 / 예시 / 지난 정산 불러오기)
  /// 바꾸기 직전의 정산은 '지난 정산' 기록에 저장해 둡니다.
  void _replaceSettlement(Settlement next) {
    _saveTimer?.cancel();
    AppStorage.saveSettlement(_s);

    final old = [..._amountCtrls.values, ..._nameCtrls.values];
    _amountCtrls.clear();
    _nameCtrls.clear();
    _titleCtrl.text = next.title;
    setState(() {
      _s = next;
      _autofocusRoundId = null;
    });
    _scheduleSave();
    // 화면에서 완전히 떨어진 뒤 정리
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final c in old) {
        c.dispose();
      }
    });
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 2),
      ));
  }

  void _dismissTip({bool startBlank = false}) {
    HapticFeedback.lightImpact();
    AppStorage.setOnboardingDone();
    setState(() => _showTip = false);
    if (startBlank) {
      _replaceSettlement(Settlement.blank());
      _toast('빈 정산으로 시작해요. 멤버 이름부터 바꿔 보세요!');
    }
  }

  // ───────────────── 차수 조작 ─────────────────

  void _addRound() {
    HapticFeedback.lightImpact();
    _update(() => _autofocusRoundId = _s.addRound().id);
  }

  void _deleteRound(RoundItem r) {
    if (_s.rounds.length <= 1) {
      _toast('차수는 최소 1개 필요해요');
      return;
    }
    HapticFeedback.lightImpact();
    FocusScope.of(context).unfocus();
    final index = _s.rounds.indexOf(r);
    _update(() => _s.rounds.removeAt(index));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('${index + 1}차를 삭제했어요'),
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: '되돌리기',
          onPressed: () => _update(
            () => _s.rounds.insert(math.min(index, _s.rounds.length), r),
          ),
        ),
      ));
  }

  void _addAmount(RoundItem r, int add) {
    HapticFeedback.lightImpact();
    _update(() => r.amount = math.min(r.amount + add, 999999999999));
    _amountCtrl(r).text = Fmt.number(r.amount);
  }

  void _clearAmount(RoundItem r) {
    HapticFeedback.lightImpact();
    _update(() => r.amount = 0);
    _amountCtrl(r).text = '';
  }

  void _incPeople(RoundItem r) {
    HapticFeedback.lightImpact();
    _update(() {
      final candidates =
          _s.members.where((m) => !r.participantIds.contains(m.id));
      if (candidates.isNotEmpty) {
        r.participantIds.add(candidates.first.id);
      } else {
        // 모두 참석 중이면 새 멤버를 만들어 추가
        r.participantIds.add(_s.addMember().id);
      }
    });
  }

  void _decPeople(RoundItem r) {
    if (r.headCount <= 1) {
      _toast('최소 1명은 참석해야 해요');
      return;
    }
    HapticFeedback.lightImpact();
    _update(() {
      final last = _s.members.lastWhere((m) => r.participantIds.contains(m.id));
      r.removeParticipant(last.id);
    });
  }

  void _toggleParticipant(RoundItem r, Member m) {
    final selected = r.participantIds.contains(m.id);
    if (selected && r.headCount <= 1) {
      _toast('최소 1명은 참석해야 해요');
      return;
    }
    HapticFeedback.lightImpact();
    _update(() {
      if (selected) {
        r.removeParticipant(m.id);
      } else {
        r.participantIds.add(m.id);
      }
    });
  }

  void _toggleSober(RoundItem r, Member m) {
    HapticFeedback.lightImpact();
    _update(() {
      if (!r.soberIds.remove(m.id)) r.soberIds.add(m.id);
    });
  }

  // ───────────────── 멤버 조작 ─────────────────

  Future<void> _addMember() async {
    HapticFeedback.lightImpact();
    final res = await showDialog<_NameResult>(
      context: context,
      builder: (_) => const _NameDialog(title: '멤버 추가', initial: ''),
    );
    if (res == null || res.delete || !mounted) return;
    _update(() => _s.addMember(res.name));
    _toast('각 차수 카드에서 ${res.name}님의 참석 여부를 선택해 주세요');
  }

  Future<void> _editMember(Member m) async {
    HapticFeedback.lightImpact();
    final res = await showDialog<_NameResult>(
      context: context,
      builder: (_) => _NameDialog(
        title: '멤버 이름 수정',
        initial: m.name,
        showDelete: true,
      ),
    );
    if (res == null || !mounted) return;
    if (res.delete) {
      if (_s.members.length <= 1) {
        _toast('멤버는 최소 1명 필요해요');
        return;
      }
      _update(() => _s.removeMember(m.id));
    } else {
      _update(() => m.name = res.name);
    }
  }

  // ───────────────── 화면 이동 ─────────────────

  Future<void> _openReceipt() async {
    HapticFeedback.lightImpact();
    FocusScope.of(context).unfocus();
    if (_s.totalSpent <= 0) {
      _toast('결제 금액을 먼저 입력해 주세요');
      return;
    }
    if (_s.buildResults().isEmpty) {
      _toast('참석 인원을 선택해 주세요');
      return;
    }
    await AppStorage.saveSettlement(_s);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ReceiptScreen(settlement: _s)),
    );
    // 영수증 화면에서 바뀐 입금 확인 상태를 하단 버튼에 반영
    if (mounted) setState(() {});
  }

  /// 하단 버튼에 표시할 입금 진행 상황 (체크한 사람이 있을 때만)
  String? _paidProgressText() {
    final results = _s.buildResults();
    final paid = results.where((p) => _s.isPaid(p.member.id)).length;
    if (paid == 0) return null;
    return '입금 $paid/${results.length}명';
  }

  Future<void> _openHistory() async {
    HapticFeedback.lightImpact();
    FocusScope.of(context).unfocus();
    // 방금 입력한 내용까지 기록에 반영한 뒤 목록 열기
    _saveTimer?.cancel();
    await AppStorage.saveSettlement(_s);
    if (!mounted) return;

    final id = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => HistoryScreen(currentId: _s.id)),
    );
    if (!mounted || id == null) return;
    final picked = AppStorage.historyById(id);
    if (picked == null) return;
    _replaceSettlement(picked);
    final title =
        picked.title.trim().isEmpty ? '이름 없는 모임' : picked.title.trim();
    _toast('"$title" 정산을 불러왔어요');
  }

  Future<void> _openSettings() async {
    HapticFeedback.lightImpact();
    FocusScope.of(context).unfocus();
    final action = await Navigator.of(context).push<SettingsAction>(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case SettingsAction.newSettlement:
        _replaceSettlement(
          Settlement.fresh(members: _s.members, roundUnit: _s.roundUnit),
        );
        _toast('새 정산을 시작했어요');
      case SettingsAction.loadSample:
        _replaceSettlement(Settlement.sample());
        _toast('예시 데이터를 불러왔어요');
    }
  }

  // ───────────────── UI ─────────────────

  @override
  Widget build(BuildContext context) {
    // 키보드가 올라오면 하단 CTA 대신 [완료] 바를 키보드 바로 위에 보여줍니다.
    // (iOS 숫자 키패드에는 '완료' 키가 없기 때문)
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    return ValueListenableBuilder<bool>(
      valueListenable: ProManager.instance.isPro,
      builder: (context, isPro, _) {
        return GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: Scaffold(
            appBar: _buildAppBar(isPro),
            body: Column(
              children: [
                _SummaryBanner(
                  total: _s.totalSpent,
                  people: _s.involvedCount,
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AnimatedSize(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOutCubic,
                          alignment: Alignment.topCenter,
                          child: _showTip
                              ? Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: _TipCard(
                                    onOk: () => _dismissTip(),
                                    onStartBlank: () =>
                                        _dismissTip(startBlank: true),
                                  ),
                                )
                              : const SizedBox(width: double.infinity),
                        ),
                        _buildMembersCard(),
                        const SizedBox(height: 12),
                        for (var i = 0; i < _s.rounds.length; i++) ...[
                          _buildRoundCard(i, _s.rounds[i]),
                          const SizedBox(height: 12),
                        ],
                        _DashedAddButton(
                          label: '${_s.rounds.length + 1}차 추가하기',
                          onTap: _addRound,
                        ),
                        const SizedBox(height: 12),
                        _buildRoundingCard(),
                      ],
                    ),
                  ),
                ),
                if (keyboardOpen) const _KeyboardDoneBar(),
              ],
            ),
            bottomNavigationBar: keyboardOpen
                ? null
                : _BottomBar(
                    isPro: isPro,
                    paidText: _paidProgressText(),
                    onTap: _openReceipt,
                  ),
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(bool isPro) {
    return AppBar(
      titleSpacing: 16,
      toolbarHeight: 60,
      title: Row(
        children: [
          const AppLogo(size: 32),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _titleCtrl,
              maxLength: 20,
              textInputAction: TextInputAction.done,
              onChanged: (v) => _update(() => _s.title = v),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: context.colors.text,
              ),
              decoration: InputDecoration(
                hintText: '모임 이름 (예: 불금 팀 회식)',
                counterText: '',
                contentPadding: EdgeInsets.zero,
                suffixIcon: Icon(Icons.edit_rounded,
                    size: 16, color: context.colors.hint),
                suffixIconConstraints:
                    BoxConstraints(minWidth: 24, minHeight: 24),
              ),
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: '지난 정산',
          onPressed: _openHistory,
          icon: Icon(Icons.history_rounded, color: context.colors.text),
        ),
        _ProBadgeButton(isPro: isPro, onTap: _openSettings),
        const SizedBox(width: 12),
      ],
    );
  }

  Widget _buildMembersCard() {
    return Container(
      decoration: AppDecor.card(context),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('모임 멤버', style: _Txt.cardTitle),
              const SizedBox(width: 6),
              Text(
                '${_s.members.length}명',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
              const Spacer(),
              Text('탭하면 이름 수정', style: _Txt.caption(context)),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in _s.members)
                _PillButton(
                  label: m.name,
                  icon: Icons.person_rounded,
                  onTap: () => _editMember(m),
                ),
              _PillButton(
                label: '멤버 추가',
                icon: Icons.add_rounded,
                highlight: true,
                onTap: _addMember,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRoundCard(int index, RoundItem r) {
    final unit = _s.roundUnit;
    final per = r.perPerson(unit);
    final attendees =
        _s.members.where((m) => r.participantIds.contains(m.id)).toList();
    final amountCtrl = _amountCtrl(r);

    return Container(
      key: ValueKey(r.id),
      decoration: AppDecor.card(context),
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 헤더: 뱃지 + 장소명 + 삭제 ──
          Row(
            children: [
              _RoundBadge(label: '${index + 1}차'),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _nameCtrl(r),
                  maxLength: 15,
                  textInputAction: TextInputAction.done,
                  onChanged: (v) => _update(() => r.name = v),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: context.colors.text,
                  ),
                  decoration: InputDecoration(
                    hintText:
                        '장소 이름 (예: ${_placeHints[index % _placeHints.length]})',
                    counterText: '',
                  ),
                ),
              ),
              IconButton(
                tooltip: '${index + 1}차 삭제',
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.delete_outline_rounded,
                    color: context.colors.subText, size: 22),
                onPressed: () => _deleteRound(r),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // ── 금액 입력 + 1인당 금액 (실시간 애니메이션) ──
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('결제 금액', style: _Txt.caption(context)),
                      TextField(
                        controller: amountCtrl,
                        autofocus: r.id == _autofocusRoundId,
                        keyboardType: TextInputType.number,
                        inputFormatters: [ThousandsFormatter()],
                        // 탭하면 전체 선택 → 바로 새 금액 입력 가능
                        onTap: () {
                          if (amountCtrl.text.isEmpty) return;
                          amountCtrl.selection = TextSelection(
                            baseOffset: 0,
                            extentOffset: amountCtrl.text.length,
                          );
                        },
                        onChanged: (v) => _update(() {
                          r.amount = int.tryParse(v.replaceAll(',', '')) ?? 0;
                          _autofocusRoundId = null;
                        }),
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: context.colors.text,
                        ),
                        decoration: InputDecoration(
                          hintText: '0',
                          suffixText: '원',
                          suffixStyle: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: context.colors.text,
                          ),
                          contentPadding: EdgeInsets.symmetric(vertical: 6),
                          enabledBorder: UnderlineInputBorder(
                            borderSide:
                                BorderSide(color: context.colors.border),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide:
                                BorderSide(color: AppColors.primary, width: 2),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('1인당', style: _Txt.caption(context)),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 150),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: _AnimatedWon(
                          per,
                          emptyText: '-',
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            color: AppColors.primary,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                    ),
                    if (r.hasSober && per > 0)
                      Text(
                        '술X ${Fmt.won(r.soberPerPerson(unit))}',
                        style: _Txt.caption(context),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // ── 원터치 금액 칩 ──
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final a in const [10000, 30000, 50000, 100000])
                _QuickChip(
                  label: '+${a ~/ 10000}만',
                  onTap: () => _addAmount(r, a),
                ),
              if (r.amount > 0)
                _QuickChip(
                  label: '지우기',
                  muted: true,
                  onTap: () => _clearAmount(r),
                ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(0, 16, 8, 14),
            child: Divider(),
          ),
          // ── 참석 인원 ──
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('참석 인원', style: _Txt.label),
                    const Spacer(),
                    _CounterButton(
                      icon: Icons.remove_rounded,
                      tooltip: '인원 빼기',
                      onTap: () => _decPeople(r),
                    ),
                    SizedBox(
                      width: 48,
                      child: Text(
                        '${r.headCount}명',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: context.colors.text,
                        ),
                      ),
                    ),
                    _CounterButton(
                      icon: Icons.add_rounded,
                      tooltip: '인원 추가',
                      onTap: () => _incPeople(r),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final m in _s.members)
                      _SelectChip(
                        label: m.name,
                        selected: r.participantIds.contains(m.id),
                        onTap: () => _toggleParticipant(r, m),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                // ── 술 안 마신 인원 할인 ──
                Row(
                  children: [
                    Icon(Icons.local_drink_outlined,
                        size: 18, color: context.colors.subText),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '술 안 마신 인원 ${r.discountPercent}% 할인',
                        style: _Txt.label,
                      ),
                    ),
                    Switch.adaptive(
                      value: r.soberDiscount,
                      activeTrackColor: AppColors.primary,
                      onChanged: (v) {
                        HapticFeedback.lightImpact();
                        _update(() => r.soberDiscount = v);
                      },
                    ),
                  ],
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: !r.soberDiscount
                      ? const SizedBox(width: double.infinity)
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Text('할인율', style: _Txt.caption(context)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: [
                                      for (final p in RoundItem.discountOptions)
                                        _SelectChip(
                                          label: '$p%',
                                          dense: true,
                                          selected: r.discountPercent == p,
                                          onTap: () {
                                            HapticFeedback.lightImpact();
                                            _update(
                                                () => r.discountPercent = p);
                                          },
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              r.soberIds.isEmpty
                                  ? '👇 술 안 마신 사람을 눌러 주세요'
                                  : '술 안 마신 사람 ${r.soberIds.length}명은 ${r.discountPercent}% 덜 내요',
                              style: r.soberIds.isEmpty
                                  ? const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primary,
                                    )
                                  : _Txt.caption(context),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final m in attendees)
                                  _SelectChip(
                                    label: '🥤 ${m.name}',
                                    selected: r.soberIds.contains(m.id),
                                    onTap: () => _toggleSober(r, m),
                                  ),
                              ],
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoundingCard() {
    final showPreview = _s.totalSpent > 0;
    final surplus = showPreview ? _s.surplus : 0;

    return Container(
      decoration: AppDecor.card(context),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('자투리 올림 단위', style: _Txt.cardTitle),
          const SizedBox(height: 4),
          Text(
            '1인당 금액을 올림해서 총무가 손해 보지 않아요',
            style: _Txt.caption(context),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final u in Settlement.unitOptions)
                _SelectChip(
                  label: '${Fmt.number(u)}원 단위',
                  selected: _s.roundUnit == u,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    _update(() => _s.roundUnit = u);
                  },
                ),
            ],
          ),
          if (showPreview) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: context.colors.primaryLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.savings_outlined,
                      size: 18, color: AppColors.primary),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '지금 설정이면 총무 자투리',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  _AnimatedWon(
                    surplus,
                    prefix: '+',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════
// 입력 포맷터: 숫자 입력 시 자동 천 단위 콤마
// ═════════════════════════════════════════════

class ThousandsFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return const TextEditingValue(text: '');
    final capped = digits.length > 12 ? digits.substring(0, 12) : digits;
    final text = Fmt.number(int.parse(capped));
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

// ═════════════════════════════════════════════
// 작은 위젯들
// ═════════════════════════════════════════════

class _Txt {
  // 글자색을 지정하지 않으면 테마의 기본 글자색(라이트/다크 자동)이 적용됩니다.
  static const cardTitle = TextStyle(fontSize: 15, fontWeight: FontWeight.w800);
  static const label = TextStyle(fontSize: 14, fontWeight: FontWeight.w600);

  static TextStyle caption(BuildContext context) => TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: context.colors.subText,
      );
}

/// 금액이 바뀔 때 숫자가 촤라락 올라가는 애니메이션
class _AnimatedWon extends StatelessWidget {
  const _AnimatedWon(
    this.value, {
    required this.style,
    this.prefix = '',
    this.emptyText,
  });

  final int value;
  final TextStyle style;
  final String prefix;

  /// 0원일 때 대신 보여줄 글자 (예: '-')
  final String? emptyText;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: value.toDouble()),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) {
        final shown = v.round();
        final text = shown == 0 && emptyText != null
            ? emptyText!
            : '$prefix${Fmt.won(shown)}';
        return Text(text, style: style);
      },
    );
  }
}

/// 누르는 동안 살짝 작아지는 손맛 효과 (탭 처리는 자식이 그대로 담당)
class _PressScale extends StatefulWidget {
  const _PressScale({required this.child, this.scale = 0.95});

  final Widget child;
  final double scale;

  @override
  State<_PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<_PressScale> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: const Duration(milliseconds: 90),
        child: widget.child,
      ),
    );
  }
}

/// 첫 실행 안내 카드
class _TipCard extends StatelessWidget {
  const _TipCard({required this.onOk, required this.onStartBlank});

  final VoidCallback onOk;
  final VoidCallback onStartBlank;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: BoxDecoration(
        color: context.colors.inverse,
        borderRadius: BorderRadius.circular(AppDecor.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '👋 예시 회식으로 채워 두었어요',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '금액이나 참석 인원을 바꿔 보세요. 1인당 금액이 바로 계산돼요.',
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: Colors.white.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: onStartBlank,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white.withValues(alpha: 0.75),
                ),
                child: const Text('비우고 새로 시작'),
              ),
              TextButton(
                onPressed: onOk,
                style: TextButton.styleFrom(foregroundColor: AppColors.primary),
                child: const Text(
                  '알겠어요',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 상단 고정 요약 배너 (퍼스널 컬러 테두리)
class _SummaryBanner extends StatelessWidget {
  const _SummaryBanner({required this.total, required this.people});

  final int total;
  final int people;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(AppDecor.radius),
        border: Border.all(color: AppColors.primary, width: 1.5),
        boxShadow: AppDecor.shadow(context),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('총 지출 합계', style: _Txt.caption(context)),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: _AnimatedWon(
                    total,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: context.colors.text,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 1,
            height: 36,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            color: context.colors.border,
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('총 참여 인원', style: _Txt.caption(context)),
              const SizedBox(height: 2),
              Text(
                '$people명',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoundBadge extends StatelessWidget {
  const _RoundBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// 선택형 칩 (참석자, 올림 단위 등)
class _SelectChip extends StatelessWidget {
  const _SelectChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.dense = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// 작은 칩 (할인율 선택 등)
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return _PressScale(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: dense
              ? const EdgeInsets.symmetric(horizontal: 10, vertical: 5)
              : const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? context.colors.primaryLight : context.colors.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? AppColors.primary : context.colors.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected && !dense) ...[
                const Icon(Icons.check_rounded,
                    size: 15, color: AppColors.primary),
                const SizedBox(width: 3),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: dense ? 13 : 14,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? AppColors.primary : context.colors.subText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// +1만, +3만 같은 원터치 금액 칩
class _QuickChip extends StatelessWidget {
  const _QuickChip(
      {required this.label, required this.onTap, this.muted = false});

  final String label;
  final VoidCallback onTap;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return _PressScale(
      child: Material(
        color: muted ? context.colors.card : context.colors.background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: muted
              ? BorderSide(color: context.colors.border)
              : BorderSide.none,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: muted ? context.colors.subText : context.colors.text,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 멤버 이름 / 멤버 추가 버튼
class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.highlight = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final fg = highlight ? AppColors.primary : context.colors.text;
    return _PressScale(
      child: Material(
        color:
            highlight ? context.colors.primaryLight : context.colors.background,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 14, 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon,
                    size: 16,
                    color:
                        highlight ? AppColors.primary : context.colors.subText),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CounterButton extends StatelessWidget {
  const _CounterButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: _PressScale(
        scale: 0.9,
        child: Material(
          color: context.colors.card,
          shape: CircleBorder(side: BorderSide(color: context.colors.border)),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 36,
              height: 36,
              child: Icon(icon, size: 20, color: context.colors.text),
            ),
          ),
        ),
      ),
    );
  }
}

/// 점선 테두리 [+ N차 추가하기] 버튼
class _DashedAddButton extends StatelessWidget {
  const _DashedAddButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _PressScale(
      scale: 0.98,
      child: CustomPaint(
        painter: _DashedRRectPainter(color: AppColors.primary),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppDecor.radius),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppDecor.radius),
            onTap: onTap,
            child: SizedBox(
              height: 56,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.add_rounded, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  _DashedRRectPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final rrect = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(0.75),
      const Radius.circular(AppDecor.radius),
    );
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 6), paint);
        d += 11;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// 앱바 우측: 설정 + PRO 뱃지
class _ProBadgeButton extends StatelessWidget {
  const _ProBadgeButton({required this.isPro, required this.onTap});

  final bool isPro;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.card,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.settings_rounded,
                  size: 20, color: context.colors.text),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isPro ? AppColors.primary : context.colors.inverse,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  isPro ? 'PRO ✓' : 'PRO',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
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

/// 키보드 바로 위 [완료] 바
class _KeyboardDoneBar extends StatelessWidget {
  const _KeyboardDoneBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: context.colors.card,
        border: Border(top: BorderSide(color: context.colors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.centerRight,
      child: TextButton(
        onPressed: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: const Text(
          '완료',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.primary,
          ),
        ),
      ),
    );
  }
}

/// 하단 고정: CTA 버튼 + 배너 광고 자리
class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.isPro, required this.onTap, this.paidText});

  final bool isPro;
  final VoidCallback onTap;

  /// 예: '입금 2/4명' (없으면 표시 안 함)
  final String? paidText;

  @override
  Widget build(BuildContext context) {
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: _PressScale(
                scale: 0.97,
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: onTap,
                    icon: const Icon(Icons.receipt_long_rounded),
                    label: FittedBox(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            '정산 영수증 만들기',
                            style: TextStyle(
                                fontSize: 17, fontWeight: FontWeight.w800),
                          ),
                          if (paidText != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.22),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                paidText!,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
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
            if (!isPro) const BannerAdPlaceholder(),
          ],
        ),
      ),
    );
  }
}

/// 배너 광고 자리 (AdMob 연동 전 Placeholder)
class BannerAdPlaceholder extends StatelessWidget {
  const BannerAdPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    // TODO(AdMob 2단계): 이 Container 를 AdWidget(ad: _bannerAd) 로 교체
    return Container(
      width: double.infinity,
      height: 50,
      color: context.colors.background,
      alignment: Alignment.center,
      child: Text(
        'AD · 배너 광고 영역 (320×50)',
        style: TextStyle(fontSize: 12, color: context.colors.hint),
      ),
    );
  }
}

// ── 멤버 이름 입력 다이얼로그 ──

class _NameResult {
  const _NameResult.save(this.name) : delete = false;
  const _NameResult.remove()
      : name = '',
        delete = true;

  final String name;
  final bool delete;
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.initial,
    this.showDelete = false,
  });

  final String title;
  final String initial;
  final bool showDelete;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _c =
      TextEditingController(text: widget.initial)
        ..selection =
            TextSelection(baseOffset: 0, extentOffset: widget.initial.length);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _c.text.trim();
    if (v.isEmpty) return;
    Navigator.of(context).pop(_NameResult.save(v));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.colors.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(
        widget.title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
      ),
      content: TextField(
        controller: _c,
        autofocus: true,
        maxLength: 10,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration:
            AppDecor.boxInput(context, '이름 입력').copyWith(counterText: ''),
      ),
      actions: [
        if (widget.showDelete)
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(const _NameResult.remove()),
            child: const Text('삭제', style: TextStyle(color: AppColors.danger)),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('취소', style: TextStyle(color: context.colors.subText)),
        ),
        TextButton(
          onPressed: _submit,
          child: const Text(
            '저장',
            style: TextStyle(
                color: AppColors.primary, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}
