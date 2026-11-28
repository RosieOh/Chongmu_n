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
/// 정산 입력 화면 (멤버·차수·금액). 메인 화면에서 들어와요.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.openGroupsOnStart = false});

  /// true 면 화면이 뜨자마자 '모임 그룹' 시트를 열어요 (메인 화면 바로가기)
  final bool openGroupsOnStart;

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
  final Map<String, TextEditingController> _alcoholCtrls = {};
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
    if (widget.openGroupsOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openGroups();
      });
    }
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
    for (final c in _alcoholCtrls.values) {
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

  TextEditingController _alcoholCtrl(RoundItem r) => _alcoholCtrls.putIfAbsent(
        r.id,
        () => TextEditingController(
            text: r.alcoholAmount > 0 ? Fmt.number(r.alcoholAmount) : ''),
      );

  TextEditingController _nameCtrl(RoundItem r) =>
      _nameCtrls.putIfAbsent(r.id, () => TextEditingController(text: r.name));

  /// 다른 정산으로 바꾸기 (새 정산 / 예시 / 지난 정산 불러오기)
  /// 바꾸기 직전의 정산은 '지난 정산' 기록에 저장해 둡니다.
  void _replaceSettlement(Settlement next) {
    _saveTimer?.cancel();
    AppStorage.saveSettlement(_s);

    final old = [
      ..._amountCtrls.values,
      ..._nameCtrls.values,
      ..._alcoholCtrls.values,
    ];
    _amountCtrls.clear();
    _nameCtrls.clear();
    _alcoholCtrls.clear();
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
    final current = _s.members.map((m) => m.name.trim()).toSet();
    final suggestions = AppStorage.recentMemberNames()
        .where((n) => !current.contains(n))
        .toList();
    final res = await showDialog<_NameResult>(
      context: context,
      builder: (_) => _NameDialog(
        title: '멤버 추가',
        initial: '',
        suggestions: suggestions,
      ),
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

  // ───────────────── 모임 그룹 ─────────────────

  Future<void> _openGroups() async {
    HapticFeedback.lightImpact();
    FocusScope.of(context).unfocus();
    final action = await showModalBottomSheet<_GroupAction>(
      context: context,
      backgroundColor: context.colors.card,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _GroupSheet(
        groups: AppStorage.groups,
        memberCount: _s.members.length,
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case _GroupSave():
        await _saveGroup();
      case _GroupLoad(:final group):
        _loadGroup(group);
      case _GroupDelete(:final group):
        await AppStorage.deleteGroup(group.name);
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text('"${group.name}" 그룹을 삭제했어요'),
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: '되돌리기',
              onPressed: () => AppStorage.saveGroup(group),
            ),
          ));
    }
  }

  Future<void> _saveGroup() async {
    final names = [
      for (final m in _s.members)
        if (m.name.trim().isNotEmpty) m.name.trim(),
    ];
    if (names.isEmpty) return;
    final res = await showDialog<_NameResult>(
      context: context,
      builder: (_) => _NameDialog(
        title: '그룹 이름',
        initial: _s.title.trim().characters.take(10).toString(),
        hint: '예: 대학 동기',
      ),
    );
    if (res == null || res.delete || !mounted) return;
    final exists = AppStorage.groups.any((g) => g.name == res.name);
    await AppStorage.saveGroup(MemberGroup(
      name: res.name,
      names: names,
      roundUnit: _s.roundUnit,
      roundMode: _s.roundMode,
    ));
    if (!mounted) return;
    _update(() => _s.groupName = res.name);
    _toast(exists
        ? '"${res.name}" 그룹을 지금 멤버로 바꿨어요'
        : '"${res.name}" 그룹을 저장했어요 (${names.length}명)');
  }

  /// 그룹 멤버로 새 정산 시작 (지금 정산은 '지난 정산'에 남아요)
  void _loadGroup(MemberGroup g) {
    final members = [
      for (final n in g.names)
        Member(id: newId(), name: n, account: AppStorage.accountForName(n)),
    ];
    final keepCurrent = _s.totalSpent > 0;
    _replaceSettlement(Settlement.fresh(
      members: members,
      roundUnit: g.roundUnit ?? _s.roundUnit,
      roundMode: g.roundMode ?? _s.roundMode,
      title: keepCurrent ? '' : _s.title,
      groupName: g.name,
    ));
    final rule = g.ruleLabel == null ? '' : ' · ${g.ruleLabel}';
    _toast(keepCurrent
        ? '"${g.name}" 멤버로 새 정산을 시작했어요$rule'
        : '"${g.name}" 멤버 ${members.length}명을 불러왔어요$rule');
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
    final overflow = _s.rounds.indexWhere((r) => r.extrasOverflow);
    if (overflow >= 0) {
      _toast('${overflow + 1}차의 개별 추가 금액이 결제 금액보다 커요');
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
    final dues = _s.buildDues();
    final paid = dues.where((d) => _s.isPaid(d.member.id)).length;
    if (paid == 0) return null;
    return '입금 $paid/${dues.length}명';
  }

  Future<void> _openHistory() async {
    HapticFeedback.lightImpact();
    FocusScope.of(context).unfocus();
    // 방금 입력한 내용까지 기록에 반영한 뒤 목록 열기
    _saveTimer?.cancel();
    await AppStorage.saveSettlement(_s);
    if (!mounted) return;

    final pick = await Navigator.of(context).push<HistoryPick>(
      MaterialPageRoute(builder: (_) => HistoryScreen(currentId: _s.id)),
    );
    if (!mounted || pick == null) return;
    final picked = AppStorage.historyById(pick.id);
    if (picked == null) return;
    final title =
        picked.title.trim().isEmpty ? '이름 없는 모임' : picked.title.trim();
    if (pick.asNew) {
      _replaceSettlement(Settlement.fresh(
        members: picked.members,
        roundUnit: picked.roundUnit,
        roundMode: picked.roundMode,
        title: picked.title,
        groupName: picked.groupName,
      ));
      _toast('"$title" 멤버로 새 정산을 시작했어요');
      return;
    }
    _replaceSettlement(picked);
    _toast('"$title" 정산을 불러왔어요');
  }

  Future<void> _openSettings() async {
    HapticFeedback.lightImpact();
    FocusScope.of(context).unfocus();
    final action = await Navigator.of(context).push<SettingsAction>(
      MaterialPageRoute(builder: (_) => SettingsScreen(current: _s)),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case SettingsAction.newSettlement:
        _replaceSettlement(
          Settlement.fresh(
            members: _s.members,
            roundUnit: _s.roundUnit,
            roundMode: _s.roundMode,
            groupName: _s.groupName,
          ),
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
        // 뒤로 가는 순간 바로 저장 → 메인 화면이 최신 내용을 보여줘요
        return PopScope(
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) return;
            _saveTimer?.cancel();
            AppStorage.saveSettlement(_s);
          },
          child: GestureDetector(
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
                          _buildSettlementExtrasCard(),
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
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(bool isPro) {
    return AppBar(
      titleSpacing: Navigator.canPop(context) ? 0 : 16,
      toolbarHeight: 60,
      title: Row(
        children: [
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
        IconButton(
          tooltip: '설정',
          onPressed: _openSettings,
          icon: Icon(Icons.settings_outlined, color: context.colors.text),
        ),
        const SizedBox(width: 4),
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
              TextButton.icon(
                onPressed: _openGroups,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.groups_rounded, size: 18),
                label: const Text(
                  '모임 그룹',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          Text('이름을 누르면 수정할 수 있어요', style: _Txt.caption(context)),
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
    final mode = _s.roundMode;
    final per = r.perPerson(unit, mode);
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
              _RoundMenu(
                index: index,
                count: _s.rounds.length,
                onSelected: (action) => _onRoundMenu(action, r),
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
                        '안 마신 사람 ${Fmt.won(r.soberPerPerson(unit, mode))}',
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
              _QuickChip(
                label: '계산기',
                icon: Icons.calculate_outlined,
                onTap: () => _openCalc(r),
              ),
              if (r.amount > 0)
                _QuickChip(
                  label: '지우기',
                  muted: true,
                  onTap: () => _clearAmount(r),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _buildPayerRow(r),
          const Padding(
            padding: EdgeInsets.fromLTRB(0, 8, 8, 14),
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
                _buildSober(r, attendees),
                _buildWeights(r, attendees),
                _buildFree(r, attendees),
                const SizedBox(height: 6),
                _buildExtras(r, attendees),
                const SizedBox(height: 6),
                _buildSponsors(r),
                const SizedBox(height: 6),
                _buildSale(r),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _onRoundMenu(_RoundAction action, RoundItem r) {
    final i = _s.rounds.indexOf(r);
    switch (action) {
      case _RoundAction.up:
      case _RoundAction.down:
        final j = action == _RoundAction.up ? i - 1 : i + 1;
        if (j < 0 || j >= _s.rounds.length) return;
        HapticFeedback.lightImpact();
        _update(() {
          _s.rounds
            ..removeAt(i)
            ..insert(j, r);
        });
      case _RoundAction.duplicate:
        HapticFeedback.lightImpact();
        final copy = r.duplicate();
        _update(() {
          _s.rounds.insert(i + 1, copy);
          _autofocusRoundId = copy.id;
        });
        _toast('${i + 1}차 참석자 그대로 ${i + 2}차를 만들었어요');
      case _RoundAction.delete:
        _deleteRound(r);
    }
  }

  void _toggleFree(RoundItem r, Member m) {
    final free = r.freeIds.contains(m.id);
    if (!free && r.payingCount <= 1) {
      _toast('최소 1명은 돈을 내야 해요');
      return;
    }
    HapticFeedback.lightImpact();
    _update(() {
      if (free) {
        r.freeIds.remove(m.id);
      } else {
        r.freeIds.add(m.id);
      }
    });
  }

  /// 술 안 마신 사람 — 술값 따로(기본) / 할인율로(간편)
  Widget _buildSober(RoundItem r, List<Member> attendees) {
    final split = r.soberMode == SoberMode.split;
    final drinkers = attendees.where((m) => r.isDrinker(m.id)).length;
    final String hint;
    if (r.soberIds.isEmpty) {
      hint = '술 안 마신 사람을 눌러 주세요';
    } else if (split) {
      hint = r.alcoholOverflow
          ? '술값이 나눌 금액보다 커요'
          : r.alcoholAmount <= 0
              ? '영수증의 술값을 넣어 주세요'
              : '술값 ${Fmt.won(r.alcoholPart)}은 마신 $drinkers명이, '
                  '나머지 ${Fmt.won(r.sharedAmount - r.alcoholPart)}은 모두가 나눠요';
    } else {
      hint = '안 마신 사람 ${r.soberIds.length}명은 ${r.discountPercent}% 덜 내요';
    }
    final warn = r.soberIds.isEmpty ||
        (split && (r.alcoholOverflow || r.alcoholAmount <= 0));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.local_drink_outlined,
                size: 18, color: context.colors.subText),
            const SizedBox(width: 6),
            const Expanded(child: Text('술 안 마신 사람', style: _Txt.label)),
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
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final m in SoberMode.values)
                          _SelectChip(
                            label: m.label,
                            dense: true,
                            selected: r.soberMode == m,
                            onTap: () {
                              HapticFeedback.lightImpact();
                              _update(() => r.soberMode = m);
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (split)
                      TextField(
                        controller: _alcoholCtrl(r),
                        keyboardType: TextInputType.number,
                        inputFormatters: [ThousandsFormatter()],
                        onChanged: (v) => _update(() => r.alcoholAmount =
                            int.tryParse(v.replaceAll(',', '')) ?? 0),
                        decoration:
                            AppDecor.boxInput(context, '영수증의 술값 (예: 48,000)')
                                .copyWith(
                          prefixText: '술값  ',
                          suffixText: '원',
                        ),
                      )
                    else
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
                                      _update(() => r.discountPercent = p);
                                    },
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 10),
                    Text(
                      hint,
                      style: warn
                          ? TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: r.alcoholOverflow
                                  ? AppColors.danger
                                  : AppColors.primary,
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
                            label: m.name,
                            selected: r.soberIds.contains(m.id),
                            onTap: () => _toggleSober(r, m),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                  ],
                ),
        ),
      ],
    );
  }

  /// 늦게 온 사람·먼저 간 사람 비율
  Widget _buildWeights(RoundItem r, List<Member> attendees) {
    final set = [
      for (final m in attendees)
        if (r.weights.containsKey(m.id)) m,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.schedule_rounded,
                size: 18, color: context.colors.subText),
            const SizedBox(width: 6),
            const Expanded(
              child: Text('늦게 온·먼저 간 사람', style: _Txt.label),
            ),
            TextButton.icon(
              onPressed: () => _editWeights(r),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                visualDensity: VisualDensity.compact,
              ),
              icon: Icon(set.isEmpty ? Icons.add_rounded : Icons.edit_rounded,
                  size: 18),
              label: Text(
                set.isEmpty ? '비율' : '수정',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        Text(
          set.isEmpty
              ? '잠깐 있다 간 사람은 0.5배처럼 덜 내게 할 수 있어요'
              : set
                  .map((m) => '${m.name} ${weightLabel(r.weights[m.id]!)}배')
                  .join(' · '),
          style: set.isEmpty
              ? _Txt.caption(context)
              : const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
        ),
        const SizedBox(height: 6),
      ],
    );
  }

  Future<void> _editWeights(RoundItem r) async {
    HapticFeedback.lightImpact();
    FocusScope.of(context).unfocus();
    final attendees =
        _s.members.where((m) => r.participantIds.contains(m.id)).toList();
    final res = await showModalBottomSheet<Map<String, double>>(
      context: context,
      backgroundColor: context.colors.card,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _WeightSheet(
        members: attendees,
        initial: {for (final m in attendees) m.id: r.weights[m.id] ?? 1.0},
      ),
    );
    if (res == null || !mounted) return;
    _update(() {
      res.forEach(r.setWeight);
    });
  }

  String _sponsorName(String id) =>
      id == kExternalSponsor ? '회사·외부 지원' : _s.memberById(id).name;

  /// 이 차수 찬조·지원 (나눌 금액에서 먼저 빼요)
  Widget _buildSponsors(RoundItem r) {
    final ids = r.sponsors.keys.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.volunteer_activism_outlined,
                size: 18, color: context.colors.subText),
            const SizedBox(width: 6),
            const Expanded(child: Text('찬조·지원', style: _Txt.label)),
            TextButton.icon(
              onPressed: () => _editSponsor(r.sponsors, (id, v) {
                _update(() => r.setSponsor(id, v));
              }),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text(
                '추가',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        if (ids.isEmpty)
          Text(
            '"2차는 선배가 5만 원 보탬"처럼 이 차수에만 낸 돈을 먼저 빼요',
            style: _Txt.caption(context),
          )
        else ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final id in ids)
                _PillButton(
                  label: '${_sponsorName(id)} ${Fmt.won(r.sponsors[id]!)}',
                  icon: Icons.edit_rounded,
                  onTap: () => _editSponsor(
                    r.sponsors,
                    (id, v) => _update(() => r.setSponsor(id, v)),
                    editId: id,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            r.sponsorsOverflow
                ? '찬조 합계가 나눌 금액보다 커서 비율대로 줄여 계산해요'
                : '찬조 ${Fmt.won(r.sponsorTotal)}을 빼고 나눠요',
            style: r.sponsorsOverflow
                ? const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.danger,
                  )
                : _Txt.caption(context),
          ),
        ],
      ],
    );
  }

  Future<void> _editSponsor(
    Map<String, int> current,
    void Function(String id, int value) apply, {
    String? editId,
  }) async {
    HapticFeedback.lightImpact();
    FocusScope.of(context).unfocus();
    final res = await showDialog<_ExtraResult>(
      context: context,
      builder: (_) => _ExtraDialog(
        members: _s.members,
        initialMemberId: editId,
        initialAmount: editId == null ? 0 : current[editId] ?? 0,
        title: '찬조·지원',
        editTitle: '찬조·지원 수정',
        question: '누가 냈나요?',
        allowExternal: true,
      ),
    );
    if (res == null || !mounted) return;
    apply(res.memberId, res.amount);
  }

  /// 정산 전체 찬조·지원 + 모임 적립금
  Widget _buildSettlementExtrasCard() {
    final ids = _s.sponsors.keys.toList();
    final group = _s.groupName;
    final fund =
        group.isEmpty ? 0 : AppStorage.groupFund(group, excludeId: _s.id);

    return Container(
      decoration: AppDecor.card(context),
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('전체 찬조·지원', style: _Txt.cardTitle),
              ),
              TextButton.icon(
                onPressed: () => _editSponsor(
                  _s.sponsors,
                  (id, v) => _update(() => _s.setSponsor(id, v)),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text(
                  '추가',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              ids.isEmpty
                  ? '"부장님 10만 원", "회사 지원금"처럼 전체에 보탠 돈은 모두의 몫에서 같은 비율로 빠져요'
                  : '찬조한 사람은 찬조금 + 자기 몫을 내요',
              style: _Txt.caption(context),
            ),
          ),
          if (ids.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final id in ids)
                  _PillButton(
                    label: '${_sponsorName(id)} ${Fmt.won(_s.sponsors[id]!)}',
                    icon: Icons.edit_rounded,
                    onTap: () => _editSponsor(
                      _s.sponsors,
                      (id, v) => _update(() => _s.setSponsor(id, v)),
                      editId: id,
                    ),
                  ),
              ],
            ),
          ],
          const Padding(
            padding: EdgeInsets.fromLTRB(0, 14, 8, 10),
            child: Divider(),
          ),
          if (group.isEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                children: [
                  Icon(Icons.savings_outlined,
                      size: 18, color: context.colors.subText),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '모임 그룹에 연결하면 남은 자투리를 다음 정산에서 쓸 수 있어요',
                      style: _Txt.caption(context),
                    ),
                  ),
                ],
              ),
            )
          else
            Row(
              children: [
                const Icon(Icons.savings_outlined,
                    size: 18, color: AppColors.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '"$group" 적립금 ${Fmt.won(fund)}',
                        style: _Txt.label,
                      ),
                      Text(
                        fund > 0
                            ? '켜면 이번 정산에서 먼저 빼요'
                            : fund < 0
                                ? '지난 정산에서 총무가 ${Fmt.won(-fund)} 모자랐어요'
                                : '정산이 끝나면 남은 자투리가 여기 쌓여요',
                        style: _Txt.caption(context),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: _s.carryIn > 0,
                  activeTrackColor: AppColors.primary,
                  onChanged: fund <= 0 && _s.carryIn == 0
                      ? null
                      : (v) {
                          HapticFeedback.lightImpact();
                          _update(() => _s.carryIn = v ? fund : 0);
                        },
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// 면제 인원 (생일자 등 — 나머지가 나눠 냄)
  Widget _buildFree(RoundItem r, List<Member> attendees) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.cake_outlined, size: 18, color: context.colors.subText),
            const SizedBox(width: 6),
            const Expanded(
              child: Text('면제 인원 (생일자 등)', style: _Txt.label),
            ),
            Switch.adaptive(
              value: r.freeMode,
              activeTrackColor: AppColors.primary,
              onChanged: (v) {
                if (v && r.payingCount <= 1 && r.freeIds.isNotEmpty) {
                  _toast('최소 1명은 돈을 내야 해요');
                  return;
                }
                HapticFeedback.lightImpact();
                _update(() => r.freeMode = v);
              },
            ),
          ],
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: !r.freeMode
              ? const SizedBox(width: double.infinity)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Text(
                      r.freeIds.isEmpty
                          ? '이번 차수에 안 내는 사람을 눌러 주세요'
                          : '면제 ${r.freeIds.length}명 몫은 나머지 ${r.payingCount}명이 나눠 내요',
                      style: r.freeIds.isEmpty
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
                            label: m.name,
                            selected: r.freeIds.contains(m.id),
                            onTap: () => _toggleFree(r, m),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                  ],
                ),
        ),
      ],
    );
  }

  /// 이 차수를 결제한 사람 (기본: 총무)
  Widget _buildPayerRow(RoundItem r) {
    final payer = _s.payerOf(r);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Row(
        children: [
          Icon(Icons.credit_card_rounded,
              size: 18, color: context.colors.subText),
          const SizedBox(width: 6),
          const Text('결제한 사람', style: _Txt.label),
          const Spacer(),
          PopupMenuButton<String>(
            tooltip: '결제한 사람 선택',
            initialValue: payer.id,
            color: context.colors.card,
            position: PopupMenuPosition.under,
            onSelected: (id) {
              HapticFeedback.lightImpact();
              _update(() => r.payerId = id == _s.treasurer.id ? null : id);
            },
            itemBuilder: (_) => [
              for (final m in _s.members)
                PopupMenuItem(
                  value: m.id,
                  child: Text(
                    m.name,
                    style: TextStyle(
                      color: context.colors.text,
                      fontWeight:
                          m.id == payer.id ? FontWeight.w800 : FontWeight.w500,
                    ),
                  ),
                ),
            ],
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
              decoration: BoxDecoration(
                color: context.colors.background,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 140),
                    child: Text(
                      payer.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: context.colors.text,
                      ),
                    ),
                  ),
                  Icon(Icons.arrow_drop_down_rounded,
                      color: context.colors.subText),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 개별 추가 금액 (혼자 시킨 메뉴 등)
  Widget _buildExtras(RoundItem r, List<Member> attendees) {
    final withExtra = attendees.where((m) => r.extraOf(m.id) > 0).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.add_card_rounded,
                size: 18, color: context.colors.subText),
            const SizedBox(width: 6),
            const Expanded(child: Text('개별 추가 금액', style: _Txt.label)),
            TextButton.icon(
              onPressed: () => _editExtra(r),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text(
                '추가',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        if (withExtra.isEmpty)
          Text(
            '혼자 시킨 메뉴가 있으면 그 사람만 따로 내게 할 수 있어요',
            style: _Txt.caption(context),
          )
        else ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in withExtra)
                _PillButton(
                  label: '${m.name} +${Fmt.won(r.extraOf(m.id))}',
                  icon: Icons.edit_rounded,
                  onTap: () => _editExtra(r, m),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            r.extrasOverflow
                ? '추가 금액 합계가 결제 금액보다 커요'
                : '추가 ${Fmt.won(r.extrasTotal)}을 뺀 ${Fmt.won(r.sharedAmount)}을 나눠요',
            style: r.extrasOverflow
                ? const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.danger,
                  )
                : _Txt.caption(context),
          ),
        ],
      ],
    );
  }

  Future<void> _editExtra(RoundItem r, [Member? member]) async {
    HapticFeedback.lightImpact();
    FocusScope.of(context).unfocus();
    final attendees =
        _s.members.where((m) => r.participantIds.contains(m.id)).toList();
    final res = await showDialog<_ExtraResult>(
      context: context,
      builder: (_) => _ExtraDialog(
        members: attendees,
        initialMemberId: member?.id,
        initialAmount: member == null ? 0 : r.extraOf(member.id),
      ),
    );
    if (res == null || !mounted) return;
    _update(() => r.setExtra(res.memberId, res.amount));
  }

  /// 금액 계산기 (영수증 여러 장 더하기, 나누기 등)
  Future<void> _openCalc(RoundItem r) async {
    HapticFeedback.lightImpact();
    FocusScope.of(context).unfocus();
    final v = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: context.colors.card,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _CalcSheet(initial: r.amount),
    );
    if (v == null || !mounted) return;
    _update(() => r.amount = v);
    _amountCtrl(r).text = v > 0 ? Fmt.number(v) : '';
  }

  /// 할인·쿠폰 (결제 금액에서 먼저 빼고 나눠요)
  Widget _buildSale(RoundItem r) {
    final parts = <String>[
      if (r.salePercent > 0) '${r.salePercent}% 할인',
      if (r.couponAmount > 0) '쿠폰 ${Fmt.won(r.couponAmount)}',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.local_offer_outlined,
                size: 18, color: context.colors.subText),
            const SizedBox(width: 6),
            const Expanded(child: Text('할인·쿠폰', style: _Txt.label)),
            TextButton.icon(
              onPressed: () => _editSale(r),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                visualDensity: VisualDensity.compact,
              ),
              icon: Icon(r.hasSale ? Icons.edit_rounded : Icons.add_rounded,
                  size: 18),
              label: Text(
                r.hasSale ? '수정' : '추가',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        Text(
          !r.hasSale
              ? '제휴 할인이나 쿠폰을 먼저 빼고 나눌 수 있어요'
              : r.amount <= 0
                  ? '${parts.join(' + ')} · 결제 금액을 입력해 주세요'
                  : '${parts.join(' + ')} → 실제 결제 ${Fmt.won(r.netAmount)}',
          style: r.hasSale
              ? const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                )
              : _Txt.caption(context),
        ),
      ],
    );
  }

  Future<void> _editSale(RoundItem r) async {
    HapticFeedback.lightImpact();
    FocusScope.of(context).unfocus();
    final res = await showDialog<(int, int)>(
      context: context,
      builder: (_) => _SaleDialog(
        amount: r.amount,
        percent: r.salePercent,
        coupon: r.couponAmount,
      ),
    );
    if (res == null || !mounted) return;
    _update(() => r.setSale(percent: res.$1, coupon: res.$2));
  }

  Widget _buildRoundingCard() {
    final showPreview = _s.totalSpent > 0;
    final surplus = showPreview ? _s.surplus : 0;
    final exact = _s.roundUnit == 1;
    final short = surplus < 0;
    final color = short ? AppColors.danger : AppColors.primary;

    return Container(
      decoration: AppDecor.card(context),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('자투리 계산 방식', style: _Txt.cardTitle),
          const SizedBox(height: 4),
          Text(
            exact
                ? '1원 단위까지 정확히 나눠요 (자투리 없음)'
                : _s.roundMode == RoundMode.up
                    ? '1인당 금액을 올림해서 총무가 손해 보지 않아요'
                    : '반올림이라 공평하지만 총무가 조금 모자랄 수 있어요',
            style: _Txt.caption(context),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final u in Settlement.unitOptions)
                _SelectChip(
                  label: u == 1 ? '정확히' : '${Fmt.number(u)}원 단위',
                  selected: _s.roundUnit == u,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    _update(() => _s.roundUnit = u);
                  },
                ),
            ],
          ),
          if (!exact) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in RoundMode.values)
                  _SelectChip(
                    label: m.label,
                    dense: true,
                    selected: _s.roundMode == m,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      _update(() => _s.roundMode = m);
                    },
                  ),
              ],
            ),
          ],
          if (showPreview && !exact) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: short
                    ? AppColors.danger.withValues(alpha: 0.10)
                    : context.colors.primaryLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.savings_outlined, size: 18, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      short ? '지금 설정이면 총무가 모자라요' : '지금 설정이면 총무 자투리',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ),
                  _AnimatedWon(
                    surplus,
                    prefix: short ? '' : '+',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_s.groupName.isNotEmpty) _buildGroupRuleRow(),
        ],
      ),
    );
  }

  /// 연결된 모임 그룹의 기본 자투리 규칙으로 저장
  Widget _buildGroupRuleRow() {
    final group =
        AppStorage.groups.where((g) => g.name == _s.groupName).firstOrNull;
    if (group == null) return const SizedBox.shrink();
    final same =
        group.roundUnit == _s.roundUnit && group.roundMode == _s.roundMode;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              same
                  ? '"${group.name}" 모임의 기본 규칙이에요'
                  : group.hasRule
                      ? '"${group.name}" 기본 규칙: ${group.ruleLabel}'
                      : '"${group.name}" 모임에 이 규칙을 기본으로 둘 수 있어요',
              style: _Txt.caption(context),
            ),
          ),
          if (!same)
            TextButton(
              onPressed: () async {
                HapticFeedback.lightImpact();
                await AppStorage.saveGroup(MemberGroup(
                  name: group.name,
                  names: group.names,
                  roundUnit: _s.roundUnit,
                  roundMode: _s.roundMode,
                ));
                if (!mounted) return;
                setState(() {});
                _toast('"${group.name}" 모임은 이제 ${_s.roundingLabel}로 시작해요');
              },
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                visualDensity: VisualDensity.compact,
              ),
              child: const Text(
                '기본으로 저장',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
        ],
      ),
    );
  }
}

/// 차수 카드 우측 메뉴
enum _RoundAction { up, down, duplicate, delete }

class _RoundMenu extends StatelessWidget {
  const _RoundMenu({
    required this.index,
    required this.count,
    required this.onSelected,
  });

  final int index;
  final int count;
  final ValueChanged<_RoundAction> onSelected;

  @override
  Widget build(BuildContext context) {
    PopupMenuItem<_RoundAction> item(
      _RoundAction value,
      IconData icon,
      String text, {
      bool enabled = true,
      bool danger = false,
    }) {
      final color = danger ? AppColors.danger : context.colors.text;
      return PopupMenuItem(
        value: value,
        enabled: enabled,
        child: Row(
          children: [
            Icon(icon, size: 20, color: enabled ? color : context.colors.hint),
            const SizedBox(width: 10),
            Text(
              text,
              style: TextStyle(color: enabled ? color : context.colors.hint),
            ),
          ],
        ),
      );
    }

    return PopupMenuButton<_RoundAction>(
      tooltip: '${index + 1}차 메뉴',
      color: context.colors.card,
      icon: Icon(Icons.more_vert_rounded, color: context.colors.subText),
      onSelected: onSelected,
      itemBuilder: (_) => [
        item(_RoundAction.up, Icons.arrow_upward_rounded, '위로 이동',
            enabled: index > 0),
        item(_RoundAction.down, Icons.arrow_downward_rounded, '아래로 이동',
            enabled: index < count - 1),
        item(_RoundAction.duplicate, Icons.copy_rounded, '참석자 그대로 복제'),
        item(_RoundAction.delete, Icons.delete_outline_rounded, '삭제',
            danger: true),
      ],
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
  static const cardTitle =
      TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.3);
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
      padding: const EdgeInsets.fromLTRB(18, 16, 10, 8),
      decoration: BoxDecoration(
        color: context.colors.primaryLight,
        borderRadius: BorderRadius.circular(AppDecor.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '예시 회식으로 채워 두었어요',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: context.colors.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '금액이나 참석 인원을 바꿔 보세요. 1인당 금액이 바로 계산돼요.',
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: context.colors.subText,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: onStartBlank,
                style: TextButton.styleFrom(
                  foregroundColor: context.colors.subText,
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

/// 상단 고정 요약 (총 지출 + 참여 인원)
class _SummaryBanner extends StatelessWidget {
  const _SummaryBanner({required this.total, required this.people});

  final int total;
  final int people;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: AppDecor.card(context),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('총 지출', style: _Txt.caption(context)),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: _AnimatedWon(
                    total,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                      color: context.colors.text,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: context.colors.primaryLight,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$people명 참여',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
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
  const _QuickChip({
    required this.label,
    required this.onTap,
    this.muted = false,
    this.icon,
  });

  final String label;
  final VoidCallback onTap;
  final bool muted;
  final IconData? icon;

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
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: AppColors.primary),
                  const SizedBox(width: 4),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: muted ? context.colors.subText : context.colors.text,
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
        border: Border(top: BorderSide(color: context.colors.border)),
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
    this.suggestions = const [],
    this.hint = '이름 입력',
  });

  final String title;
  final String hint;
  final String initial;
  final bool showDelete;

  /// 지난 정산에서 함께한 멤버 이름 (누르면 바로 추가)
  final List<String> suggestions;

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
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _c,
              autofocus: widget.suggestions.isEmpty,
              maxLength: 10,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: AppDecor.boxInput(context, widget.hint)
                  .copyWith(counterText: ''),
            ),
            if (widget.suggestions.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text('지난 정산에서 함께한 멤버', style: _Txt.caption(context)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final n in widget.suggestions)
                    _SelectChip(
                      label: '+ $n',
                      dense: true,
                      selected: false,
                      onTap: () =>
                          Navigator.of(context).pop(_NameResult.save(n)),
                    ),
                ],
              ),
            ],
          ],
        ),
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

// ── 개별 추가 금액 다이얼로그 ──

class _ExtraResult {
  const _ExtraResult(this.memberId, this.amount);

  final String memberId;

  /// 0 이면 삭제
  final int amount;
}

class _ExtraDialog extends StatefulWidget {
  const _ExtraDialog({
    required this.members,
    this.initialMemberId,
    this.initialAmount = 0,
    this.title = '개별 추가 금액',
    this.editTitle = '추가 금액 수정',
    this.question = '누가 따로 시켰나요?',
    this.allowExternal = false,
  });

  final List<Member> members;
  final String? initialMemberId;
  final int initialAmount;
  final String title;
  final String editTitle;
  final String question;

  /// '회사·외부 지원' 선택지 표시 (찬조·지원용)
  final bool allowExternal;

  @override
  State<_ExtraDialog> createState() => _ExtraDialogState();
}

class _ExtraDialogState extends State<_ExtraDialog> {
  late String? _memberId = widget.initialMemberId ??
      (widget.members.isEmpty ? null : widget.members.first.id);
  late final TextEditingController _c = TextEditingController(
    text: widget.initialAmount > 0 ? Fmt.number(widget.initialAmount) : '',
  );

  bool get _editing => widget.initialMemberId != null;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _submit() {
    final id = _memberId;
    final v = int.tryParse(_c.text.replaceAll(',', '')) ?? 0;
    if (id == null || (v <= 0 && !_editing)) return;
    Navigator.of(context).pop(_ExtraResult(id, v));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.colors.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(
        _editing ? widget.editTitle : widget.title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.question, style: _Txt.caption(context)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (id, name) in [
                  for (final m in widget.members) (m.id, m.name),
                  if (widget.allowExternal) (kExternalSponsor, '회사·외부 지원'),
                ])
                  _SelectChip(
                    label: name,
                    dense: true,
                    selected: _memberId == id,
                    onTap:
                        _editing ? () {} : () => setState(() => _memberId = id),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _c,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [ThousandsFormatter()],
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: AppDecor.boxInput(context, '금액 (예: 12,000)')
                  .copyWith(suffixText: '원'),
            ),
          ],
        ),
      ),
      actions: [
        if (_editing)
          TextButton(
            onPressed: () => Navigator.of(context)
                .pop(_ExtraResult(widget.initialMemberId!, 0)),
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

// ── 늦게 온·먼저 간 사람 비율 ──

class _WeightSheet extends StatefulWidget {
  const _WeightSheet({required this.members, required this.initial});

  final List<Member> members;
  final Map<String, double> initial;

  @override
  State<_WeightSheet> createState() => _WeightSheetState();
}

class _WeightSheetState extends State<_WeightSheet> {
  late final Map<String, double> _w = {...widget.initial};

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('이 차수, 얼마나 있었나요?', style: _Txt.cardTitle),
            const SizedBox(height: 4),
            Text(
              '1배가 기본이에요. 잠깐 있다 간 사람은 0.5배, 더 많이 먹은 사람은 1.5배처럼 정해요.',
              style: _Txt.caption(context),
            ),
            const SizedBox(height: 14),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final m in widget.members)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              m.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _Txt.label,
                            ),
                          ),
                          for (final w in kWeightOptions)
                            Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: _SelectChip(
                                label: '${weightLabel(w)}배',
                                dense: true,
                                selected: (_w[m.id] ?? 1.0) == w,
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  setState(() => _w[m.id] = w);
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(_w),
                child: const Text('적용하기'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 금액 계산기 ──

class _CalcSheet extends StatefulWidget {
  const _CalcSheet({required this.initial});

  final int initial;

  @override
  State<_CalcSheet> createState() => _CalcSheetState();
}

class _CalcSheetState extends State<_CalcSheet> {
  static const _ops = ['+', '-', '×', '÷'];

  late String _expr = widget.initial > 0 ? '${widget.initial}' : '';

  bool get _endsWithOp =>
      _expr.isNotEmpty && _ops.contains(_expr[_expr.length - 1]);

  /// 끝에 연산자가 있으면 빼고 계산 (입력 중에도 결과 미리 보기)
  int? get _result =>
      evalAmount(_endsWithOp ? _expr.substring(0, _expr.length - 1) : _expr);

  /// '32000+15000' → '32,000 + 15,000'
  String get _display {
    if (_expr.isEmpty) return '0';
    return _expr.replaceAllMapped(RegExp(r'\d+|[+\-×÷]'), (m) {
      final t = m[0]!;
      final n = int.tryParse(t);
      if (n != null) return Fmt.number(n);
      return ' ${t == '-' ? '−' : t} ';
    });
  }

  void _press(String key) {
    HapticFeedback.selectionClick();
    setState(() {
      if (key == 'C') {
        _expr = '';
      } else if (key == '⌫') {
        if (_expr.isNotEmpty) _expr = _expr.substring(0, _expr.length - 1);
      } else if (_ops.contains(key)) {
        if (_expr.isEmpty) return;
        if (_endsWithOp) _expr = _expr.substring(0, _expr.length - 1);
        _expr += key;
      } else {
        // 숫자: 한 덩어리 최대 12자리
        final last = RegExp(r'\d*$').firstMatch(_expr)![0]!;
        if (last.length + key.length > 12) return;
        if (last == '0') {
          if (key.startsWith('0')) return; // '00' 같은 입력 막기
          _expr = _expr.substring(0, _expr.length - 1);
        }
        if (last.isEmpty && key == '00') key = '0';
        _expr += key;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final hasOp = isAmountExpr(_expr);
    Widget key(String label, {bool op = false, VoidCallback? onTap}) {
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Material(
            color: op ? context.colors.primaryLight : context.colors.background,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap ?? () => _press(label),
              child: SizedBox(
                height: 52,
                child: Center(
                  child: label == '⌫'
                      ? Icon(Icons.backspace_outlined,
                          size: 20, color: context.colors.text)
                      : Text(
                          label == '-' ? '−' : label,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: op ? AppColors.primary : context.colors.text,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('금액 계산기', style: _Txt.cardTitle),
            const SizedBox(height: 2),
            Text('영수증 여러 장을 더하거나 나눌 때 써 보세요', style: _Txt.caption(context)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: context.colors.background,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _display,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: hasOp ? 16 : 26,
                      fontWeight: hasOp ? FontWeight.w600 : FontWeight.w800,
                      color:
                          hasOp ? context.colors.subText : context.colors.text,
                    ),
                  ),
                  if (hasOp) ...[
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        result == null ? '계산할 수 없어요' : '= ${Fmt.won(result)}',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: result == null
                              ? AppColors.danger
                              : AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            for (final row in const [
              ['7', '8', '9', '÷'],
              ['4', '5', '6', '×'],
              ['1', '2', '3', '-'],
              ['00', '0', '⌫', '+'],
            ])
              Row(
                children: [
                  for (final k in row) key(k, op: _ops.contains(k)),
                ],
              ),
            Row(
              children: [
                key('C'),
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: SizedBox(
                      height: 52,
                      child: FilledButton(
                        onPressed: result == null
                            ? null
                            : () => Navigator.of(context).pop(result),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(
                          result == null ? '금액 입력' : '${Fmt.won(result)} 입력',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── 할인·쿠폰 다이얼로그 ──

class _SaleDialog extends StatefulWidget {
  const _SaleDialog({
    required this.amount,
    required this.percent,
    required this.coupon,
  });

  final int amount;
  final int percent;
  final int coupon;

  @override
  State<_SaleDialog> createState() => _SaleDialogState();
}

class _SaleDialogState extends State<_SaleDialog> {
  static const _presets = [5, 10, 15, 20, 30];

  late int _percent = widget.percent;
  late final TextEditingController _couponCtrl = TextEditingController(
    text: widget.coupon > 0 ? Fmt.number(widget.coupon) : '',
  );

  int get _coupon => int.tryParse(_couponCtrl.text.replaceAll(',', '')) ?? 0;

  @override
  void dispose() {
    _couponCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preview = RoundItem(id: '', amount: widget.amount)
      ..setSale(percent: _percent, coupon: _coupon);
    return AlertDialog(
      backgroundColor: context.colors.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text(
        '할인·쿠폰',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('전체 할인율', style: _Txt.caption(context)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _SelectChip(
                  label: '없음',
                  dense: true,
                  selected: _percent == 0,
                  onTap: () => setState(() => _percent = 0),
                ),
                for (final p in _presets)
                  _SelectChip(
                    label: '$p%',
                    dense: true,
                    selected: _percent == p,
                    onTap: () => setState(() => _percent = p),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('쿠폰·포인트 (할인율 적용 뒤에 빼요)', style: _Txt.caption(context)),
            const SizedBox(height: 8),
            TextField(
              controller: _couponCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [ThousandsFormatter()],
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {}),
              decoration: AppDecor.boxInput(context, '금액 (예: 5,000)')
                  .copyWith(suffixText: '원'),
            ),
            if (widget.amount > 0 && preview.hasSale) ...[
              const SizedBox(height: 12),
              Text(
                '${Fmt.won(widget.amount)} - ${Fmt.won(preview.saleTotal)}'
                ' = ${Fmt.won(preview.netAmount)}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (widget.percent > 0 || widget.coupon > 0)
          TextButton(
            onPressed: () => Navigator.of(context).pop((0, 0)),
            child: const Text('삭제', style: TextStyle(color: AppColors.danger)),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('취소', style: TextStyle(color: context.colors.subText)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop((_percent, _coupon)),
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

// ── 모임 그룹 시트 ──

sealed class _GroupAction {
  const _GroupAction();
}

class _GroupSave extends _GroupAction {
  const _GroupSave();
}

class _GroupLoad extends _GroupAction {
  const _GroupLoad(this.group);

  final MemberGroup group;
}

class _GroupDelete extends _GroupAction {
  const _GroupDelete(this.group);

  final MemberGroup group;
}

class _GroupSheet extends StatelessWidget {
  const _GroupSheet({required this.groups, required this.memberCount});

  final List<MemberGroup> groups;
  final int memberCount;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('모임 그룹', style: _Txt.cardTitle),
                  const SizedBox(height: 2),
                  Text('자주 모이는 멤버를 저장해 두고 한 번에 불러와요',
                      style: _Txt.caption(context)),
                ],
              ),
            ),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              leading:
                  const Icon(Icons.group_add_rounded, color: AppColors.primary),
              title: Text(
                '지금 멤버 $memberCount명을 그룹으로 저장',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
              onTap: () => Navigator.of(context).pop(const _GroupSave()),
            ),
            const Divider(height: 1),
            if (groups.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                child: Text(
                  '저장된 그룹이 없어요',
                  textAlign: TextAlign.center,
                  style: _Txt.caption(context),
                ),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final g in groups)
                      ListTile(
                        contentPadding:
                            const EdgeInsets.only(left: 20, right: 8),
                        leading: Icon(Icons.groups_rounded,
                            color: context.colors.subText),
                        title: Text(
                          '${g.name} · ${g.names.length}명',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: context.colors.text,
                          ),
                        ),
                        subtitle: Text(
                          g.names.join(', '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _Txt.caption(context),
                        ),
                        onTap: () => Navigator.of(context).pop(_GroupLoad(g)),
                        trailing: IconButton(
                          tooltip: '${g.name} 삭제',
                          icon: Icon(Icons.delete_outline_rounded,
                              color: context.colors.subText),
                          onPressed: () =>
                              Navigator.of(context).pop(_GroupDelete(g)),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
