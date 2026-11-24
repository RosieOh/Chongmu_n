import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/round_item.dart';
import '../theme/app_theme.dart';

/// ④ 지난 정산 기록 목록
///
/// 항목을 누르면 그 정산의 ID 를 돌려주고(Navigator.pop), 메인 화면이 불러옵니다.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.currentId});

  /// 지금 메인 화면에서 편집 중인 정산 ID
  final String currentId;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late final List<Settlement> _items = AppStorage.loadHistory();

  void _toast(String msg, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 3),
        action: action,
      ));
  }

  void _open(Settlement s) {
    HapticFeedback.lightImpact();
    if (s.id == widget.currentId) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pop(s.id);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('지난 정산')),
      body: _items.isEmpty ? const _EmptyHistory() : _buildList(),
    );
  }

  Widget _buildList() {
    // 월별로 묶어서 헤더 + 카드 목록 만들기 (최신순)
    final children = <Widget>[];
    String? currentMonth;
    for (final s in _items) {
      final month = DateFormat('yyyy년 M월').format(s.createdAt);
      if (month != currentMonth) {
        currentMonth = month;
        final monthTotal = _items
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
            ),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        Padding(
          padding: EdgeInsets.only(left: 4, bottom: 4),
          child: Text(
            '눌러서 불러오고, 왼쪽으로 밀어서 삭제해요',
            style: TextStyle(fontSize: 12, color: context.colors.subText),
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
  });

  final Settlement settlement;
  final bool isCurrent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = settlement;
    final results = s.buildResults();
    final paid = results.where((p) => s.isPaid(p.member.id)).length;
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
                    _paidTag(context, paid, results.length),
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
