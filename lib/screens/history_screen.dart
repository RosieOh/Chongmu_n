import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/round_item.dart';
import '../theme/app_theme.dart';
import 'ledger_screen.dart';

/// 지난 정산 화면에서 고른 결과
class HistoryPick {
  const HistoryPick(this.id, {this.asNew = false});

  final String id;

  /// true 면 그 정산의 멤버로 새 정산 시작 (원본은 그대로)
  final bool asNew;
}

/// 정산이 검색어와 맞는지 (모임 이름 / 멤버 이름 / 장소 이름)
bool matchesHistoryQuery(Settlement s, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  bool has(String v) => v.toLowerCase().contains(q);
  return has(s.title) ||
      s.members.any((m) => has(m.name)) ||
      s.rounds.any((r) => has(r.name));
}

/// 최근 [count]개월 월별 지출 합계 (오래된 달 → 이번 달 순)
List<(DateTime month, int total)> monthlyTotals(
  List<Settlement> items,
  DateTime now, {
  int count = 6,
}) {
  return [
    for (var i = count - 1; i >= 0; i--)
      () {
        final m = DateTime(now.year, now.month - i);
        final total = items
            .where((s) =>
                s.createdAt.year == m.year && s.createdAt.month == m.month)
            .fold<int>(0, (sum, s) => sum + s.totalSpent);
        return (m, total);
      }(),
  ];
}

/// 차트 라벨용 짧은 금액 (184,000 → 18.4만, 1,250,000 → 125만)
String shortWon(int v) {
  if (v <= 0) return '-';
  if (v < 10000) return Fmt.number(v);
  final man = v / 10000;
  final text = man >= 100 ? man.round().toString() : man.toStringAsFixed(1);
  return '${text.endsWith('.0') ? text.substring(0, text.length - 2) : text}만';
}

/// ④ 지난 정산 기록 목록
///
/// 항목을 누르면 [HistoryPick] 을 돌려주고(Navigator.pop), 메인 화면이 불러옵니다.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.currentId, this.onPick});

  /// 지금 메인 화면에서 편집 중인 정산 ID
  final String currentId;

  /// 하단 탭 안에 들어갈 때: 화면을 닫는 대신 이 콜백으로 알려요
  /// (null 을 넘기면 '지금 정산 열기')
  final ValueChanged<HistoryPick?>? onPick;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late final List<Settlement> _items = AppStorage.loadHistory();
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _toast(String msg, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 3),
        action: action,
      ));
  }

  /// 화면을 닫으며 결과 전달 (탭 안이면 콜백)
  void _finish(HistoryPick? pick) {
    final onPick = widget.onPick;
    if (onPick != null) {
      onPick(pick);
    } else {
      Navigator.of(context).pop(pick);
    }
  }

  void _open(Settlement s) {
    HapticFeedback.lightImpact();
    _finish(s.id == widget.currentId ? null : HistoryPick(s.id));
  }

  void _startNewFrom(Settlement s) {
    HapticFeedback.lightImpact();
    _finish(HistoryPick(s.id, asNew: true));
  }

  /// 길게 누르면 나오는 메뉴
  Future<void> _showActions(Settlement s) async {
    HapticFeedback.mediumImpact();
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.colors.card,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                _titleOf(s),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: context.colors.text,
                ),
              ),
            ),
            _SheetTile(
              icon: Icons.open_in_new_rounded,
              title: '불러오기',
              onTap: () => Navigator.of(ctx).pop('open'),
            ),
            _SheetTile(
              icon: Icons.group_add_rounded,
              title: '이 멤버로 새 정산 시작',
              subtitle: '정기 모임이면 멤버를 다시 입력할 필요 없어요',
              onTap: () => Navigator.of(ctx).pop('new'),
            ),
            if (s.id != widget.currentId)
              _SheetTile(
                icon: Icons.delete_outline_rounded,
                title: '삭제',
                danger: true,
                onTap: () => Navigator.of(ctx).pop('delete'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'open':
        _open(s);
      case 'new':
        _startNewFrom(s);
      case 'delete':
        _delete(s);
    }
  }

  Future<bool> _confirmDelete(Settlement s) async {
    if (s.id == widget.currentId) {
      _toast('지금 보고 있는 정산은 삭제할 수 없어요');
      return false;
    }
    return true;
  }

  void _delete(Settlement s) {
    HapticFeedback.lightImpact();
    final index = _items.indexOf(s);
    setState(() => _items.removeAt(index));
    AppStorage.deleteHistory(s.id);
    _toast(
      '"${_titleOf(s)}" 기록을 삭제했어요',
      action: SnackBarAction(
        label: '되돌리기',
        onPressed: () {
          if (!mounted) return;
          setState(
              () => _items.insert(index.clamp(0, _items.length).toInt(), s));
          AppStorage.restoreHistory(s);
        },
      ),
    );
  }

  Future<void> _openLedger() async {
    HapticFeedback.lightImpact();
    final pick = await Navigator.of(context).push<HistoryPick>(
      MaterialPageRoute(
        builder: (_) => LedgerScreen(currentId: widget.currentId),
      ),
    );
    if (!mounted) return;
    if (pick != null) {
      _finish(pick);
      return;
    }
    // 장부에서 입금 확인한 내용 반영
    setState(() {
      _items
        ..clear()
        ..addAll(AppStorage.loadHistory());
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('지난 정산'),
        actions: [
          if (_items.isNotEmpty)
            IconButton(
              tooltip: '미수금 장부',
              onPressed: _openLedger,
              icon: Icon(Icons.account_balance_wallet_outlined,
                  color: context.colors.text),
            ),
        ],
      ),
      body: _items.isEmpty ? const _EmptyHistory() : _buildList(),
    );
  }

  Widget _buildList() {
    // 월별로 묶어서 헤더 + 카드 목록 만들기 (최신순)
    final children = <Widget>[];
    final visible =
        _items.where((s) => matchesHistoryQuery(s, _query)).toList();
    String? currentMonth;
    for (final s in visible) {
      final month = DateFormat('yyyy년 M월').format(s.createdAt);
      if (month != currentMonth) {
        currentMonth = month;
        final monthTotal = visible
            .where((e) => DateFormat('yyyy년 M월').format(e.createdAt) == month)
            .fold<int>(0, (sum, e) => sum + e.totalSpent);
        children.add(_MonthHeader(month: month, total: monthTotal));
      }
      children.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Dismissible(
            key: ValueKey(s.id),
            direction: DismissDirection.endToStart,
            confirmDismiss: (_) => _confirmDelete(s),
            onDismissed: (_) => _delete(s),
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 24),
              decoration: BoxDecoration(
                color: AppColors.danger,
                borderRadius: BorderRadius.circular(AppDecor.radius),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.delete_outline_rounded, color: Colors.white),
                  SizedBox(width: 4),
                  Text(
                    '삭제',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            child: _HistoryCard(
              settlement: s,
              isCurrent: s.id == widget.currentId,
              onTap: () => _open(s),
              onLongPress: () => _showActions(s),
            ),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        _StatsCard(items: _items),
        const SizedBox(height: 12),
        _LedgerBanner(ledger: buildLedger(_items), onTap: _openLedger),
        TextField(
          controller: _searchCtrl,
          textInputAction: TextInputAction.search,
          onChanged: (v) => setState(() => _query = v),
          decoration: AppDecor.boxInput(context, '모임·멤버·장소 이름으로 검색').copyWith(
            prefixIcon: Icon(Icons.search_rounded, color: context.colors.hint),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    tooltip: '검색어 지우기',
                    icon: Icon(Icons.close_rounded,
                        color: context.colors.subText),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() => _query = '');
                    },
                  ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 4, top: 8, bottom: 4),
          child: Text(
            '눌러서 불러오고, 길게 눌러 새 정산 · 왼쪽으로 밀어서 삭제',
            style: TextStyle(fontSize: 12, color: context.colors.subText),
          ),
        ),
        if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Text(
              '"${_query.trim()}" 검색 결과가 없어요',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: context.colors.subText),
            ),
          ),
        ...children,
      ],
    );
  }
}

String _titleOf(Settlement s) =>
    s.title.trim().isEmpty ? '이름 없는 모임' : s.title.trim();

// ═════════════════════════════════════════════
// 작은 위젯들
// ═════════════════════════════════════════════

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({required this.month, required this.total});

  final String month;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Row(
        children: [
          Text(
            month,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: context.colors.text,
            ),
          ),
          const Spacer(),
          Text(
            '총 ${Fmt.won(total)}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: context.colors.subText,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.settlement,
    required this.isCurrent,
    required this.onTap,
    this.onLongPress,
  });

  final Settlement settlement;
  final bool isCurrent;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final s = settlement;
    final results = s.buildResults();
    final dues = s.buildDues(results);
    final paid = dues.where((d) => s.isPaid(d.member.id)).length;
    final roundCount = s.rounds.where((r) => r.amount > 0).length;
    final places = s.rounds
        .where((r) => r.amount > 0 && r.name.trim().isNotEmpty)
        .map((r) => r.name.trim())
        .join(' → ');

    return Container(
      decoration: isCurrent
          ? AppDecor.card(context).copyWith(
              border: Border.all(color: AppColors.primary, width: 1.5),
            )
          : AppDecor.card(context),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppDecor.radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppDecor.radius),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // ── 날짜 블록 ──
                Container(
                  width: 50,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: context.colors.primaryLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: [
                      Text(
                        DateFormat('d').format(s.createdAt),
                        style: const TextStyle(
                          fontSize: 20,
                          height: 1.1,
                          fontWeight: FontWeight.w900,
                          color: AppColors.primary,
                        ),
                      ),
                      Text(
                        '${DateFormat('M').format(s.createdAt)}월',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // ── 제목 / 상세 ──
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              _titleOf(s),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: context.colors.text,
                              ),
                            ),
                          ),
                          if (isCurrent) ...[
                            const SizedBox(width: 6),
                            const _Tag(
                              text: '지금 보는 정산',
                              color: AppColors.primary,
                              filled: true,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        places.isEmpty
                            ? '${results.length}명 · $roundCount차'
                            : '${results.length}명 · $places',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: context.colors.subText,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                // ── 금액 / 입금 상태 ──
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      Fmt.won(s.totalSpent),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: context.colors.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _paidTag(context, paid, dues.length),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _paidTag(BuildContext context, int paid, int total) {
    if (total > 0 && paid == total) {
      return const _Tag(
          text: '✓ 정산 완료', color: AppColors.primary, filled: true);
    }
    if (paid > 0) {
      return _Tag(text: '입금 $paid/$total', color: AppColors.primary);
    }
    return _Tag(text: '입금 대기', color: context.colors.subText);
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color, this.filled = false});

  final String text;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: filled ? Colors.white : color,
        ),
      ),
    );
  }
}

/// 상단 통계: 정산 횟수 · 누적 지출 · 가장 자주 함께한 멤버
class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.items});

  final List<Settlement> items;

  @override
  Widget build(BuildContext context) {
    final total = items.fold<int>(0, (sum, s) => sum + s.totalSpent);
    final now = DateTime.now();
    final thisMonth = items
        .where((s) =>
            s.createdAt.year == now.year && s.createdAt.month == now.month)
        .fold<int>(0, (sum, s) => sum + s.totalSpent);
    final best = AppStorage.recentMemberNames(limit: 1);

    Widget stat(String label, String value) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 12, color: context.colors.subText),
              ),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: context.colors.text,
                  ),
                ),
              ),
            ],
          ),
        );

    return Container(
      decoration: AppDecor.card(context),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              stat('정산 횟수', '${items.length}번'),
              stat('누적 지출', Fmt.won(total)),
              stat('이번 달', Fmt.won(thisMonth)),
            ],
          ),
          const SizedBox(height: 16),
          _MonthlyChart(data: monthlyTotals(items, now)),
          if (best.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: context.colors.primaryLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '가장 자주 함께한 멤버: ${best.first}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 최근 6개월 월별 지출 막대 차트 (단일 시리즈, 값은 막대 위에 직접 표시)
class _MonthlyChart extends StatelessWidget {
  const _MonthlyChart({required this.data});

  final List<(DateTime, int)> data;

  static const double _maxBar = 64;

  @override
  Widget build(BuildContext context) {
    final max = data.fold<int>(0, (m, e) => e.$2 > m ? e.$2 : m);
    final caption = TextStyle(fontSize: 11, color: context.colors.subText);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('최근 6개월 지출', style: caption),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final (i, (month, total)) in data.indexed)
              Expanded(
                child: Semantics(
                  label: '${month.month}월 ${Fmt.won(total)}',
                  excludeSemantics: true,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          shortWon(total),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: total > 0
                                ? context.colors.text
                                : context.colors.hint,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      TweenAnimationBuilder<double>(
                        tween: Tween<double>(
                          end: max == 0 ? 0 : total / max * _maxBar,
                        ),
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeOutCubic,
                        builder: (context, h, _) => Container(
                          width: 20,
                          height: total > 0 ? h.clamp(3, _maxBar) : 0,
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(4),
                            ),
                          ),
                        ),
                      ),
                      Container(height: 1, color: context.colors.border),
                      const SizedBox(height: 4),
                      Text(
                        '${month.month}월',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: i == data.length - 1
                              ? FontWeight.w800
                              : FontWeight.w500,
                          color: i == data.length - 1
                              ? context.colors.text
                              : context.colors.subText,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// 길게 누르기 메뉴 항목
class _SheetTile extends StatelessWidget {
  const _SheetTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.danger : context.colors.text;
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: danger ? AppColors.danger : AppColors.primary),
      title: Text(
        title,
        style: TextStyle(fontWeight: FontWeight.w700, color: color),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: TextStyle(fontSize: 12, color: context.colors.subText),
            ),
    );
  }
}

/// 아직 받지 못한 돈 요약 (누르면 미수금 장부)
class _LedgerBanner extends StatelessWidget {
  const _LedgerBanner({required this.ledger, required this.onTap});

  final List<LedgerEntry> ledger;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (ledger.isEmpty) return const SizedBox.shrink();
    final total = ledger.fold<int>(0, (sum, e) => sum + e.total);
    final names = ledger.take(3).map((e) => e.name).join(', ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: context.colors.primaryLight,
        borderRadius: BorderRadius.circular(AppDecor.radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppDecor.radius),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            child: Row(
              children: [
                const Icon(Icons.account_balance_wallet_outlined,
                    size: 20, color: AppColors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '받을 돈 ${Fmt.won(total)} · ${ledger.length}명',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
                      ),
                      Text(
                        ledger.length > 3 ? '$names 외' : names,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12, color: context.colors.subText),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    color: AppColors.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: context.colors.primaryLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.history_rounded,
                size: 36,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '아직 정산 기록이 없어요',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: context.colors.text,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '정산 금액을 입력하면 자동으로 여기에 저장돼요',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: context.colors.subText),
            ),
          ],
        ),
      ),
    );
  }
}
