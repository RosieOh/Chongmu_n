import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/round_item.dart';
import '../theme/app_theme.dart';
import 'history_screen.dart';

/// 한 사람에게 보낼 미입금 안내 메시지 (카톡에 붙여넣기용)
String ledgerReminderText(
  LedgerEntry e, {
  String account = '',
  List<String> payLinks = const [],
}) {
  final b = StringBuffer()
    ..writeln('📢 ${e.name}님, 아직 입금 확인이 안 된 정산이 있어요 🙏')
    ..writeln();
  for (final item in e.items) {
    final s = item.settlement;
    final title = s.title.trim().isEmpty ? '모임' : s.title.trim();
    b.writeln('· $title (${DateFormat('M/d').format(s.createdAt)}) '
        '${Fmt.won(item.amount)}');
  }
  if (e.items.length > 1) b.writeln('= 합계 ${Fmt.won(e.total)}');

  // 다른 사람에게 보내야 하는 정산(송금 정리)이 섞여 있으면 총무 계좌는 안 붙여요
  final toTreasurer = e.items.every((i) => !i.settlement.usesTransfers);
  if (toTreasurer && account.isNotEmpty) {
    b
      ..writeln()
      ..writeln('🏦 입금 계좌')
      ..writeln(account);
  }
  if (toTreasurer && payLinks.isNotEmpty) {
    b
      ..writeln()
      ..writeln('👉 눌러서 바로 송금');
    payLinks.forEach(b.writeln);
  }
  return b.toString().trimRight();
}

/// ⑤ 미수금 장부 — 지난 정산 전체에서 아직 안 낸 돈을 사람별로
///
/// 정산을 누르면 [HistoryPick] 을 돌려줘요. 바뀐 게 있으면 지난 정산 화면이 다시 읽어요.
class LedgerScreen extends StatefulWidget {
  const LedgerScreen({super.key, required this.currentId});

  /// 지금 메인 화면에서 편집 중인 정산 ID (여기서는 입금 처리하지 않음)
  final String currentId;

  @override
  State<LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerScreenState extends State<LedgerScreen> {
  late List<LedgerEntry> _entries = _load();

  List<LedgerEntry> _load() => buildLedger(AppStorage.loadHistory());

  String get _account {
    final number = AppStorage.accountNumber.trim();
    if (number.isEmpty) return '';
    final head = [AppStorage.bankName.trim(), number]
        .where((e) => e.isNotEmpty)
        .join(' ');
    final holder = AppStorage.accountHolder.trim();
    return holder.isEmpty ? head : '$head ($holder)';
  }

  List<String> get _payLinks => [
        if (AppStorage.tossLink.isNotEmpty) '· 토스 ${AppStorage.tossLink}',
        if (AppStorage.kakaoPayLink.isNotEmpty)
          '· 카카오페이 ${AppStorage.kakaoPayLink}',
      ];

  void _toast(String msg, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        duration: Duration(seconds: action == null ? 2 : 3),
        action: action,
      ));
  }

  Future<void> _setPaid(LedgerItem item, bool paid) async {
    await AppStorage.setHistoryPaid(item.settlement.id, item.member.id, paid);
    if (!mounted) return;
    setState(() => _entries = _load());
  }

  Future<void> _markPaid(LedgerItem item) async {
    HapticFeedback.lightImpact();
    await _setPaid(item, true);
    if (!mounted) return;
    _toast(
      '${item.member.name}님 ${Fmt.won(item.amount)} 입금 확인했어요',
      action: SnackBarAction(
        label: '되돌리기',
        onPressed: () => _setPaid(item, false),
      ),
    );
  }

  Future<void> _copy(LedgerEntry e) async {
    HapticFeedback.lightImpact();
    await Clipboard.setData(ClipboardData(
      text: ledgerReminderText(e, account: _account, payLinks: _payLinks),
    ));
    if (!mounted) return;
    _toast('${e.name}님에게 보낼 메시지를 복사했어요');
  }

  void _open(LedgerItem item) {
    HapticFeedback.lightImpact();
    Navigator.of(context).pop(HistoryPick(item.settlement.id));
  }

  @override
  Widget build(BuildContext context) {
    final total = _entries.fold<int>(0, (sum, e) => sum + e.total);
    final count = _entries.fold<int>(0, (sum, e) => sum + e.items.length);
    return Scaffold(
      appBar: AppBar(title: const Text('미수금 장부')),
      body: _entries.isEmpty
          ? const _AllPaid()
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              children: [
                _TotalCard(total: total, people: _entries.length, count: count),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
                  child: Text(
                    '체크를 누르면 입금 확인 · 정산을 누르면 불러와요',
                    style:
                        TextStyle(fontSize: 12, color: context.colors.subText),
                  ),
                ),
                for (final e in _entries) ...[
                  _EntryCard(
                    entry: e,
                    currentId: widget.currentId,
                    onPaid: _markPaid,
                    onOpen: _open,
                    onCopy: () => _copy(e),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ),
    );
  }
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({
    required this.total,
    required this.people,
    required this.count,
  });

  final int total;
  final int people;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppDecor.card(context),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: context.colors.primaryLight,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.account_balance_wallet_outlined,
                color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '아직 받지 못한 돈',
                  style: TextStyle(fontSize: 13, color: context.colors.subText),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    Fmt.won(total),
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: context.colors.text,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Text(
            '$people명 · $count건',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.entry,
    required this.currentId,
    required this.onPaid,
    required this.onOpen,
    required this.onCopy,
  });

  final LedgerEntry entry;
  final String currentId;
  final ValueChanged<LedgerItem> onPaid;
  final ValueChanged<LedgerItem> onOpen;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppDecor.card(context),
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    entry.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: context.colors.text,
                    ),
                  ),
                ),
                Text(
                  '${entry.items.length}건 ',
                  style: TextStyle(fontSize: 13, color: context.colors.subText),
                ),
                Text(
                  Fmt.won(entry.total),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: AppColors.danger,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          for (final item in entry.items) _itemRow(context, item),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onCopy,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text(
                '안내 메시지 복사',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _itemRow(BuildContext context, LedgerItem item) {
    final s = item.settlement;
    final current = s.id == currentId;
    final title = s.title.trim().isEmpty ? '이름 없는 모임' : s.title.trim();
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => onOpen(item),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: context.colors.text,
                    ),
                  ),
                  Text(
                    current
                        ? '${DateFormat('M월 d일').format(s.createdAt)} · 지금 정산 중'
                        : DateFormat('M월 d일').format(s.createdAt),
                    style:
                        TextStyle(fontSize: 12, color: context.colors.subText),
                  ),
                ],
              ),
            ),
            Text(
              Fmt.won(item.amount),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: context.colors.text,
              ),
            ),
            // 지금 편집 중인 정산은 영수증 화면에서 체크해요 (덮어쓰기 방지)
            current
                ? IconButton(
                    tooltip: '불러와서 입금 확인',
                    onPressed: () => onOpen(item),
                    icon: Icon(Icons.chevron_right_rounded,
                        color: context.colors.subText),
                  )
                : IconButton(
                    tooltip: '${item.member.name} 입금 확인',
                    onPressed: () => onPaid(item),
                    icon: Icon(Icons.check_circle_outline_rounded,
                        color: context.colors.hint),
                  ),
          ],
        ),
      ),
    );
  }
}

class _AllPaid extends StatelessWidget {
  const _AllPaid();

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
                Icons.task_alt_rounded,
                size: 36,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '받을 돈이 없어요',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: context.colors.text,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '지난 정산 모두 입금이 확인됐어요',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: context.colors.subText),
            ),
          ],
        ),
      ),
    );
  }
}
