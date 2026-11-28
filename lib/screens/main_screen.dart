import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../models/round_item.dart';
import '../theme/app_theme.dart';
import '../widgets/illustrations.dart';
import 'history_screen.dart';
import 'home_screen.dart';
import 'ledger_screen.dart';
import 'settings_screen.dart';

/// 앱의 뼈대 — 하단 탭(홈 / 기록 / 장부 / 설정)
class MainScreen extends StatefulWidget {
  const MainScreen({super.key, this.now});

  /// 테스트용 현재 시각 (null 이면 실제 시각)
  final DateTime? now;

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _tab = 0;

  /// 탭을 다시 그릴 때마다 올려서 기록·장부가 최신 데이터를 읽게 해요
  int _rev = 0;

  late Settlement _current;
  late List<Settlement> _history;
  late List<LedgerEntry> _ledger;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _current = AppStorage.loadSettlement();
    _history = AppStorage.loadHistory();
    _ledger = buildLedger(_history);
    _rev++;
  }

  void _reload() {
    if (mounted) setState(_load);
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 2),
      ));
  }

  void _goTab(int i) {
    if (i == _tab) return;
    HapticFeedback.selectionClick();
    setState(() {
      _tab = i;
      _load();
    });
  }

  // ───────────────── 정산 열기 ─────────────────

  /// 정산 입력 화면 열기. [next] 를 주면 그 정산으로 바꿔서 열어요
  /// (지금 정산은 금액이 있으면 '지난 정산'에 이미 남아 있어요).
  Future<void> _openEditor({
    Settlement? next,
    String? toast,
    bool groups = false,
  }) async {
    HapticFeedback.lightImpact();
    if (next != null) await AppStorage.saveSettlement(next);
    if (!mounted) return;
    final route = Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => HomeScreen(openGroupsOnStart: groups),
    ));
    if (toast != null) _toast(toast);
    await route;
    _reload();
  }

  void _startNew() {
    final c = _current;
    _openEditor(
      next: c.isSample
          ? Settlement.blank()
          : Settlement.fresh(
              members: c.members,
              roundUnit: c.roundUnit,
              roundMode: c.roundMode,
              groupName: c.groupName,
            ),
      toast: '새 정산을 시작했어요',
    );
  }

  /// 가장 최근 정산의 멤버로 새 정산
  void _repeatLast() {
    if (_history.isEmpty) {
      _toast('아직 지난 정산이 없어요');
      return;
    }
    _openPick(HistoryPick(_history.first.id, asNew: true));
  }

  /// 지난 정산 / 장부에서 고른 정산 열기 (null = 지금 정산)
  void _openPick(HistoryPick? pick) {
    if (pick == null) {
      _openEditor();
      return;
    }
    final picked = AppStorage.historyById(pick.id);
    if (picked == null) return;
    final title = _titleOf(picked);
    if (pick.asNew) {
      _openEditor(
        next: Settlement.fresh(
          members: picked.members,
          roundUnit: picked.roundUnit,
          roundMode: picked.roundMode,
          title: picked.title,
          groupName: picked.groupName,
        ),
        toast: '"$title" 멤버로 새 정산을 시작했어요',
      );
    } else if (picked.id == _current.id) {
      _openEditor();
    } else {
      _openEditor(next: picked, toast: '"$title" 정산을 불러왔어요');
    }
  }

  void _onSettings(SettingsAction action) {
    switch (action) {
      case SettingsAction.newSettlement:
        _startNew();
      case SettingsAction.loadSample:
        _openEditor(next: Settlement.sample(), toast: '예시 데이터를 불러왔어요');
    }
  }

  void _showGuide() {
    HapticFeedback.lightImpact();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.colors.card,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const _GuideSheet(),
    );
  }

  // ───────────────── UI ─────────────────

  @override
  Widget build(BuildContext context) {
    final body = switch (_tab) {
      1 => HistoryScreen(
          key: ValueKey('history$_rev'),
          currentId: _current.id,
          onPick: _openPick,
        ),
      2 => LedgerScreen(
          key: ValueKey('ledger$_rev'),
          currentId: _current.id,
          onPick: _openPick,
        ),
      3 => SettingsScreen(
          key: ValueKey('settings$_rev'),
          current: _current,
          onAction: _onSettings,
        ),
      _ => _HomeTab(
          now: widget.now ?? DateTime.now(),
          current: _current,
          history: _history,
          ledger: _ledger,
          onStart: _startNew,
          onContinue: () => _openEditor(),
          onGroups: () => _openEditor(groups: true),
          onRepeat: _repeatLast,
          onSample: () => _openEditor(
            next: Settlement.sample(),
            toast: '예시 정산을 불러왔어요',
          ),
          onAccount: () => _goTab(3),
          onHistory: () => _goTab(1),
          onLedger: () => _goTab(2),
          onPick: _openPick,
          onGuide: _showGuide,
        ),
    };

    return Scaffold(
      body: body,
      bottomNavigationBar: _BottomTabs(
        index: _tab,
        unpaid: _ledger.length,
        onTap: _goTab,
      ),
    );
  }
}

String _titleOf(Settlement s) =>
    s.title.trim().isEmpty ? '이름 없는 모임' : s.title.trim();

// ═════════════════════════════════════════════
// 홈 탭
// ═════════════════════════════════════════════

class _HomeTab extends StatelessWidget {
  const _HomeTab({
    required this.now,
    required this.current,
    required this.history,
    required this.ledger,
    required this.onStart,
    required this.onContinue,
    required this.onGroups,
    required this.onRepeat,
    required this.onSample,
    required this.onAccount,
    required this.onHistory,
    required this.onLedger,
    required this.onPick,
    required this.onGuide,
  });

  final DateTime now;
  final Settlement current;
  final List<Settlement> history;
  final List<LedgerEntry> ledger;
  final VoidCallback onStart;
  final VoidCallback onContinue;
  final VoidCallback onGroups;
  final VoidCallback onRepeat;
  final VoidCallback onSample;
  final VoidCallback onAccount;
  final VoidCallback onHistory;
  final VoidCallback onLedger;
  final ValueChanged<HistoryPick> onPick;
  final VoidCallback onGuide;

  @override
  Widget build(BuildContext context) {
    final hasAccount = AppStorage.accountNumber.trim().isNotEmpty ||
        AppStorage.tossLink.isNotEmpty ||
        AppStorage.kakaoPayLink.isNotEmpty;

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _TopBar(onGuide: onGuide),
          _Banner(onTap: onGuide),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Bento(
                  current: current,
                  onStart: onStart,
                  onContinue: onContinue,
                  onGroups: onGroups,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _SmallTile(
                        icon: Icons.replay_rounded,
                        label: '지난 멤버로',
                        onTap: onRepeat,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _SmallTile(
                        icon: Icons.menu_book_rounded,
                        label: '예시 보기',
                        onTap: onSample,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _SmallTile(
                        icon: Icons.account_balance_rounded,
                        label: hasAccount ? '송금 정보' : '계좌 등록',
                        badge: hasAccount ? null : '필수',
                        onTap: onAccount,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                _SectionHeader(
                  '최근 정산',
                  action: history.isEmpty ? null : '전체보기',
                  onAction: onHistory,
                ),
                const SizedBox(height: 12),
                _RecentList(
                  items: history.take(3).toList(),
                  currentId: current.id,
                  onPick: onPick,
                ),
                if (ledger.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _UnpaidRow(ledger: ledger, onTap: onLedger),
                ],
                if (AppStorage.backupDue(now)) ...[
                  const SizedBox(height: 10),
                  _NoticeRow(
                    icon: Icons.save_alt_rounded,
                    text: AppStorage.lastBackupAt == null
                        ? '정산 기록을 백업해 두세요 (휴대폰에만 저장돼요)'
                        : '백업한 지 2주가 넘었어요',
                    onTap: onAccount,
                  ),
                ],
                const SizedBox(height: 28),
                _GuideRow(onTap: onGuide),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 누르면 살짝 눌리는 효과
class _Tap extends StatefulWidget {
  const _Tap({required this.child, required this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<_Tap> createState() => _TapState();
}

class _TapState extends State<_Tap> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapCancel: () => _set(false),
      onTapUp: (_) => _set(false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.97 : 1,
        duration: const Duration(milliseconds: 110),
        child: widget.child,
      ),
    );
  }
}

/// 그림자 없는 흰 카드 (레퍼런스처럼 납작하게)
BoxDecoration _flatCard(BuildContext context, {Color? color}) => BoxDecoration(
      color: color ?? context.colors.card,
      borderRadius: BorderRadius.circular(20),
    );

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onGuide});

  final VoidCallback onGuide;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            const AppLogo(size: 26),
            const SizedBox(width: 8),
            const AppWordmark(fontSize: 18),
            const Spacer(),
            OutlinedButton(
              onPressed: onGuide,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 30),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                backgroundColor: Colors.transparent,
                side: BorderSide(color: context.colors.text, width: 1.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                textStyle:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              child: const Text('사용법'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 상단 배너 (넘겨 보는 3장) ──

class _Banner extends StatefulWidget {
  const _Banner({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_Banner> createState() => _BannerState();
}

class _BannerState extends State<_Banner> {
  static const _slides = [
    (
      '술 안 마신 사람은 덜 내게',
      '차수마다 할인율을 따로 정해요',
      ArtKind.glass,
    ),
    (
      '한 명만 시킨 메뉴는 따로',
      '공통 금액만 나누고 추가금은 그 사람에게',
      ArtKind.receipt,
    ),
    (
      '여러 명이 나눠 결제했다면',
      '누가 누구에게 보낼지 정리해 드려요',
      ArtKind.transfer,
    ),
  ];

  int _page = 0;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 104,
      color: context.colors.primaryLight,
      child: Stack(
        children: [
          PageView.builder(
            itemCount: _slides.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (context, i) {
              final (title, sub, art) = _slides[i];
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onTap,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 18, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                                color: context.colors.text,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              sub,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                color: context.colors.subText,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Illustration(art, width: 72),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          Positioned(
            left: 20,
            bottom: 12,
            child: Row(
              children: [
                for (var i = 0; i < _slides.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(right: 5),
                    width: i == _page ? 14 : 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: i == _page
                          ? AppColors.primary
                          : context.colors.subText.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── 큰 카드 3개 (왼쪽 1 + 오른쪽 2) ──

class _Bento extends StatelessWidget {
  const _Bento({
    required this.current,
    required this.onStart,
    required this.onContinue,
    required this.onGroups,
  });

  final Settlement current;
  final VoidCallback onStart;
  final VoidCallback onContinue;
  final VoidCallback onGroups;

  @override
  Widget build(BuildContext context) {
    final total = current.totalSpent;
    final continueSub = current.isSample
        ? '예시 정산\n둘러보기'
        : total > 0
            ? '${_titleOf(current)}\n${Fmt.won(total)}'
            : '쓰던 정산\n마저 하기';

    return SizedBox(
      height: 316,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: _Tap(
                    onTap: onStart,
                    child: Container(
                      decoration: _flatCard(context, color: AppColors.primary),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 24, 12, 0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '새 정산',
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.6,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '차수별 금액과\n참석자만 넣기',
                                  style: TextStyle(
                                    fontSize: 15,
                                    height: 1.4,
                                    color: Colors.white.withValues(alpha: 0.85),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Positioned(
                            left: 10,
                            right: -6,
                            bottom: -4,
                            child: Illustration(
                              ArtKind.receipt,
                              width: 160,
                              height: 168,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const Positioned(
                  top: -9,
                  left: 0,
                  child: _Pill('1/N 말고 공평하게'),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _SideCard(
                    title: '이어서 하기',
                    sub: continueSub,
                    art: ArtKind.coins,
                    onTap: onContinue,
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: _SideCard(
                    title: '모임 그룹',
                    sub: '자주 보는 멤버\n바로 불러오기',
                    art: ArtKind.people,
                    onTap: onGroups,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SideCard extends StatelessWidget {
  const _SideCard({
    required this.title,
    required this.sub,
    required this.art,
    required this.onTap,
  });

  final String title;
  final String sub;
  final ArtKind art;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _Tap(
      onTap: onTap,
      child: Container(
        decoration: _flatCard(context),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 12, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      color: context.colors.text,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    sub,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.35,
                      color: context.colors.subText,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              right: 10,
              bottom: 8,
              child: Illustration(art, width: 62),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, {this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color ?? AppColors.charcoal,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _SmallTile extends StatelessWidget {
  const _SmallTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        _Tap(
          onTap: onTap,
          child: Container(
            height: 104,
            width: double.infinity,
            decoration: _flatCard(context),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: context.colors.primaryLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 22, color: AppColors.primary),
                ),
                const SizedBox(height: 10),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: context.colors.text,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (badge != null)
          Positioned(
            top: -9,
            left: 0,
            child: _Pill(badge!, color: AppColors.primary),
          ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text, {this.action, this.onAction});

  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: context.colors.text,
            ),
          ),
        ),
        if (action != null)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onAction,
            child: Row(
              children: [
                Text(
                  action!,
                  style: TextStyle(fontSize: 14, color: context.colors.hint),
                ),
                Icon(Icons.chevron_right_rounded,
                    size: 20, color: context.colors.hint),
              ],
            ),
          ),
      ],
    );
  }
}

class _RecentList extends StatelessWidget {
  const _RecentList({
    required this.items,
    required this.currentId,
    required this.onPick,
  });

  final List<Settlement> items;
  final String currentId;
  final ValueChanged<HistoryPick> onPick;

  static const _week = ['월', '화', '수', '목', '금', '토', '일'];

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        decoration: _flatCard(context),
        child: Text(
          '금액을 입력한 정산은 여기에 모여요',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: context.colors.subText),
        ),
      );
    }
    return Container(
      decoration: _flatCard(context),
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0)
                Divider(
                    indent: 76, endIndent: 18, color: context.colors.border),
              _row(context, items[i]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, Settlement s) {
    final d = s.createdAt;
    final dues = s.buildDues();
    final unpaid = dues.where((e) => !s.isPaid(e.member.id)).length;
    final isCurrent = s.id == currentId;
    final status = isCurrent
        ? ('작성 중', AppColors.primary)
        : unpaid == 0
            ? ('완료', context.colors.hint)
            : ('$unpaid명 미입금', AppColors.danger);

    return InkWell(
      onTap: () => onPick(HistoryPick(s.id)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              child: Column(
                children: [
                  Text(
                    '${d.month}.${d.day}',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: context.colors.text,
                    ),
                  ),
                  Text(
                    _week[d.weekday - 1],
                    style: TextStyle(fontSize: 12, color: context.colors.hint),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _titleOf(s),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: context.colors.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${s.rounds.length}차 · ${s.involvedCount}명',
                    style:
                        TextStyle(fontSize: 13, color: context.colors.subText),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  Fmt.won(s.totalSpent),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: context.colors.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  status.$1,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: status.$2,
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

class _UnpaidRow extends StatelessWidget {
  const _UnpaidRow({required this.ledger, required this.onTap});

  final List<LedgerEntry> ledger;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final total = ledger.fold<int>(0, (sum, e) => sum + e.total);
    return _Tap(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
        decoration: _flatCard(context),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 20, color: AppColors.danger),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '아직 못 받은 돈 ${Fmt.won(total)} (${ledger.length}명)',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: context.colors.text,
                ),
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: context.colors.hint),
          ],
        ),
      ),
    );
  }
}

class _NoticeRow extends StatelessWidget {
  const _NoticeRow({
    required this.icon,
    required this.text,
    required this.onTap,
  });

  final IconData icon;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _Tap(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
        decoration: _flatCard(context),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: context.colors.text,
                ),
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: context.colors.hint),
          ],
        ),
      ),
    );
  }
}

class _GuideRow extends StatelessWidget {
  const _GuideRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _Tap(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: context.colors.card,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.lightbulb_outline_rounded,
                  color: context.colors.subText),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '이용 가이드',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: context.colors.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '카카오페이 정산이랑 같이 쓰는 법',
                    style:
                        TextStyle(fontSize: 13, color: context.colors.subText),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: context.colors.hint),
          ],
        ),
      ),
    );
  }
}

/// 사용법 — 계산은 여기서, 송금은 카톡·토스에서
class _GuideSheet extends StatelessWidget {
  const _GuideSheet();

  static const _steps = [
    ('멤버를 넣어요', '모임 그룹에 저장해 두면 다음엔 한 번에 불러와요.'),
    ('차수별로 금액과 참석자를 골라요', '중간에 온 사람, 먼저 간 사람은 그 차수에서만 빼면 돼요.'),
    ('예외를 정해요', '술 안 마신 사람 할인, 면제, 한 사람만 시킨 메뉴 추가금까지.'),
    ('영수증을 카톡방에 공유해요', '송금은 늘 쓰던 카카오페이·토스로. 계좌와 송금 링크가 영수증에 같이 찍혀요.'),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '1/N이 안 맞는 회식, 이렇게 나눠요',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                color: context.colors.text,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '모두 똑같이 내면 카톡 정산으로 충분해요.\n'
              '술 안 마신 사람, 따로 시킨 메뉴, 여러 명이 나눠 낸 결제처럼 '
              '1/N이 안 맞을 때 여기서 계산하세요.',
              style: TextStyle(
                fontSize: 14,
                height: 1.45,
                color: context.colors.subText,
              ),
            ),
            const SizedBox(height: 20),
            for (var i = 0; i < _steps.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${i + 1}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _steps[i].$1,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: context.colors.text,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _steps[i].$2,
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.4,
                              color: context.colors.subText,
                            ),
                          ),
                        ],
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

// ═════════════════════════════════════════════
// 하단 탭
// ═════════════════════════════════════════════

class _BottomTabs extends StatelessWidget {
  const _BottomTabs({
    required this.index,
    required this.unpaid,
    required this.onTap,
  });

  final int index;
  final int unpaid;
  final ValueChanged<int> onTap;

  static const _items = [
    (Icons.home_rounded, Icons.home_outlined, '홈'),
    (Icons.receipt_long_rounded, Icons.receipt_long_outlined, '기록'),
    (
      Icons.account_balance_wallet_rounded,
      Icons.account_balance_wallet_outlined,
      '장부'
    ),
    (Icons.person_rounded, Icons.person_outline_rounded, '설정'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.card,
        border: Border(top: BorderSide(color: context.colors.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(
            children: [
              for (var i = 0; i < _items.length; i++)
                Expanded(
                  child: InkResponse(
                    onTap: () => onTap(i),
                    radius: 36,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Badge(
                          isLabelVisible: i == 2 && unpaid > 0,
                          backgroundColor: AppColors.danger,
                          smallSize: 7,
                          child: Icon(
                            i == index ? _items[i].$1 : _items[i].$2,
                            size: 26,
                            color: i == index
                                ? context.colors.text
                                : context.colors.hint,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _items[i].$3,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight:
                                i == index ? FontWeight.w700 : FontWeight.w500,
                            color: i == index
                                ? context.colors.text
                                : context.colors.hint,
                          ),
                        ),
                      ],
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
