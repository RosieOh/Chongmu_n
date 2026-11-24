import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../models/round_item.dart';
import '../theme/app_theme.dart';

/// 설정 화면에서 메인 화면으로 돌려보내는 요청
enum SettingsAction { newSettlement, loadSample }

// ═════════════════════════════════════════════
// 화면 모드 (시스템 설정 / 라이트 / 다크)
// ═════════════════════════════════════════════

class ThemeModeController {
  ThemeModeController._();

  static final ThemeModeController instance = ThemeModeController._();

  /// 앱 전체가 구독하는 현재 화면 모드
  final ValueNotifier<ThemeMode> mode =
      ValueNotifier<ThemeMode>(ThemeMode.system);

  void load() {
    mode.value = switch (AppStorage.themeMode) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> set(ThemeMode value) async {
    mode.value = value;
    await AppStorage.setThemeMode(value.name); // system / light / dark
  }
}

// ═════════════════════════════════════════════
// PRO 상태 관리 (추후 RevenueCat 연동 지점)
// ═════════════════════════════════════════════

class ProManager {
  ProManager._();

  static final ProManager instance = ProManager._();

  /// 앱 전체에서 구독하는 PRO 여부 (true 면 광고·워터마크 숨김)
  final ValueNotifier<bool> isPro = ValueNotifier<bool>(false);

  static const String productId = 'chongmu_pro_lifetime';
  static const String entitlementId = 'pro';

  void load() => isPro.value = AppStorage.isPro;

  Future<void> _setPro(bool value) async {
    await AppStorage.setPro(value);
    isPro.value = value;
  }

  /// 3,300원 평생 소장 구매
  Future<bool> purchase() async {
    // TODO(RevenueCat 3단계): purchases_flutter 연동
    // final offerings = await Purchases.getOfferings();
    // final package = offerings.current?.lifetime;
    // final result = await Purchases.purchasePackage(package!);
    // final active = result.customerInfo.entitlements.active.containsKey(entitlementId);
    // await _setPro(active);
    // return active;

    // 개발(디버그) 중에는 버튼을 누르면 PRO 가 바로 켜져 화면을 확인할 수 있어요.
    // ⚠️ 출시(release) 빌드에서는 결제 연동 전까지 아무것도 열리지 않습니다.
    if (kDebugMode) {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      await _setPro(true);
      return true;
    }
    return false;
  }

  /// 구매 내역 복원 (애플 심사 필수)
  Future<bool> restore() async {
    // TODO(RevenueCat 3단계):
    // final info = await Purchases.restorePurchases();
    // final active = info.entitlements.active.containsKey(entitlementId);
    // await _setPro(active);
    // return active;
    await Future<void>.delayed(const Duration(milliseconds: 600));
    return AppStorage.isPro;
  }

  /// 디버그 전용 토글
  Future<void> debugSetPro(bool value) => _setPro(value);
}

// ═════════════════════════════════════════════
// ③ 설정 및 Pro 업그레이드 화면
// ═════════════════════════════════════════════

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.current});

  /// 지금 메인 화면의 정산 (백업에 함께 담아요)
  final Settlement? current;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _buying = false;
  bool _restoring = false;

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 2),
      ));
  }

  Future<void> _purchase() async {
    HapticFeedback.lightImpact();
    setState(() => _buying = true);
    final ok = await ProManager.instance.purchase();
    if (!mounted) return;
    setState(() => _buying = false);
    _toast(ok ? 'PRO 가 적용되었어요. 감사합니다! 🎉' : '결제 기능을 준비 중이에요. 조금만 기다려 주세요!');
  }

  Future<void> _restore() async {
    HapticFeedback.lightImpact();
    setState(() => _restoring = true);
    final ok = await ProManager.instance.restore();
    if (!mounted) return;
    setState(() => _restoring = false);
    _toast(ok ? '구매 내역을 복원했어요' : '복원할 구매 내역이 없어요');
  }

  Future<void> _copyBackup() async {
    HapticFeedback.lightImpact();
    final current = widget.current ?? AppStorage.loadSettlement();
    await Clipboard.setData(
        ClipboardData(text: AppStorage.exportBackup(current)));
    if (!mounted) return;
    final count = AppStorage.loadHistory().length;
    _toast('정산 $count건을 복사했어요. 메모장이나 나에게 보내기로 보관하세요');
  }

  Future<void> _restoreBackup() async {
    HapticFeedback.lightImpact();
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final raw = data?.text?.trim() ?? '';
    if (!mounted) return;
    if (raw.isEmpty) {
      _toast('먼저 백업 내용을 복사한 뒤 눌러 주세요');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.colors.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          '복사한 백업으로 복원할까요?',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        content: const Text(
          '백업 속 정산을 \'지난 정산\'에 합쳐요.\n지금 있는 기록은 지워지지 않아요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('취소', style: TextStyle(color: context.colors.subText)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              '복원하기',
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final count = await AppStorage.importBackup(raw);
      if (!mounted) return;
      _toast('정산 $count건을 복원했어요. \'지난 정산\'에서 확인하세요');
    } on FormatException catch (e) {
      if (mounted) _toast('복원하지 못했어요: ${e.message}');
    }
  }

  Future<void> _confirmNewSettlement() async {
    HapticFeedback.lightImpact();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.colors.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          '새 정산을 시작할까요?',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        content: const Text(
          '멤버 목록은 그대로 두고, 차수와 금액만 비워요.\n지금 정산은 \'지난 정산\'에 저장돼요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('취소', style: TextStyle(color: context.colors.subText)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              '시작하기',
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      Navigator.of(context).pop(SettingsAction.newSettlement);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ProManager.instance.isPro,
      builder: (context, isPro, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('설정')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              _ProCard(isPro: isPro, busy: _buying, onBuy: _purchase),
              const SizedBox(height: 12),
              SizedBox(
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: _restoring ? null : _restore,
                  icon: _restoring
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.restore_rounded, size: 20),
                  label: const Text('구매 내역 복원'),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '휴대폰을 바꾸거나 앱을 다시 설치했다면 눌러주세요',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: context.colors.subText),
              ),
              const SizedBox(height: 28),
              const _SectionTitle('화면 모드'),
              const _ThemeModeSelector(),
              const SizedBox(height: 28),
              const _SectionTitle('정산 관리'),
              Container(
                decoration: AppDecor.card(context),
                child: Column(
                  children: [
                    _Tile(
                      icon: Icons.add_circle_outline_rounded,
                      title: '새 정산 시작하기',
                      subtitle: '멤버는 그대로, 차수와 금액만 비워요',
                      onTap: _confirmNewSettlement,
                    ),
                    const Divider(indent: 56),
                    _Tile(
                      icon: Icons.auto_awesome_rounded,
                      title: '예시 데이터 불러오기',
                      subtitle: '삼겹살·호프집 예시로 다시 채워요',
                      onTap: () {
                        HapticFeedback.lightImpact();
                        Navigator.of(context).pop(SettingsAction.loadSample);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              const _SectionTitle('데이터 백업'),
              Container(
                decoration: AppDecor.card(context),
                child: Column(
                  children: [
                    _Tile(
                      icon: Icons.copy_all_rounded,
                      title: '백업 복사하기',
                      subtitle: '휴대폰을 바꾸기 전에 복사해서 보관하세요',
                      onTap: _copyBackup,
                    ),
                    const Divider(indent: 56),
                    _Tile(
                      icon: Icons.content_paste_go_rounded,
                      title: '복사한 백업으로 복원',
                      subtitle: '백업 내용을 복사한 뒤 눌러 주세요',
                      onTap: _restoreBackup,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              const _SectionTitle('앱 정보'),
              Container(
                decoration: AppDecor.card(context),
                child: Column(
                  children: [
                    _Tile(
                      icon: Icons.info_outline_rounded,
                      title: '버전',
                      trailing: Text(
                        '1.1.0',
                        style: TextStyle(color: context.colors.subText),
                      ),
                    ),
                    Divider(indent: 56),
                    _Tile(
                      icon: Icons.lock_outline_rounded,
                      title: '개인정보 보호',
                      subtitle: '모든 데이터는 내 휴대폰에만 저장돼요 (서버 전송 없음)',
                    ),
                  ],
                ),
              ),
              if (kDebugMode) ...[
                const SizedBox(height: 28),
                const _SectionTitle('개발자 테스트 (디버그 빌드에서만 보여요)'),
                Container(
                  decoration: AppDecor.card(context),
                  padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'PRO 상태 강제 전환',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Switch.adaptive(
                        value: isPro,
                        activeTrackColor: AppColors.primary,
                        onChanged: (v) => ProManager.instance.debugSetPro(v),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ═════════════════════════════════════════════
// 작은 위젯들
// ═════════════════════════════════════════════

class _ProCard extends StatelessWidget {
  const _ProCard(
      {required this.isPro, required this.busy, required this.onBuy});

  final bool isPro;
  final bool busy;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary,
            Color.lerp(AppColors.primary, AppColors.charcoal, 0.35)!,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'PRO',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const Spacer(),
              if (isPro)
                const Icon(Icons.verified_rounded, color: Colors.white),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            '광고 제거 + 영수증 워터마크 제거',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '커피 한 잔 값으로 평생 깔끔하게',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 16),
          const _Benefit('모든 광고 완전 제거'),
          const _Benefit('영수증 하단 워터마크 제거'),
          const _Benefit('한 번 결제로 평생 소장 (구독 아님)'),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.primary,
                disabledBackgroundColor: Colors.white.withValues(alpha: 0.85),
                disabledForegroundColor: AppColors.primary,
              ),
              onPressed: isPro || busy ? null : onBuy,
              child: busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: AppColors.primary,
                      ),
                    )
                  : Text(
                      isPro ? 'PRO 이용 중이에요 🎉' : '3,300원 · 평생 소장하기',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Benefit extends StatelessWidget {
  const _Benefit(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: context.colors.subText,
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // 카드(Container) 위에서도 눌림 효과가 보이도록 투명 Material 로 감쌈
    return Material(
      type: MaterialType.transparency,
      child: ListTile(
        onTap: onTap,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDecor.radius)),
        leading: Icon(icon, color: AppColors.primary),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: context.colors.text,
          ),
        ),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle!,
                style: TextStyle(fontSize: 12, color: context.colors.subText),
              ),
        trailing: trailing ??
            (onTap == null
                ? null
                : Icon(Icons.chevron_right_rounded,
                    color: context.colors.hint)),
      ),
    );
  }
}

/// 시스템 설정 / 라이트 / 다크 선택 (세그먼트 버튼 스타일)
class _ThemeModeSelector extends StatelessWidget {
  const _ThemeModeSelector();

  static const _options = [
    (ThemeMode.system, Icons.brightness_auto_rounded, '시스템 설정'),
    (ThemeMode.light, Icons.light_mode_rounded, '라이트'),
    (ThemeMode.dark, Icons.dark_mode_rounded, '다크'),
  ];

  @override
  Widget build(BuildContext context) {
    final controller = ThemeModeController.instance;
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: controller.mode,
      builder: (context, current, _) {
        return Container(
          decoration: AppDecor.card(context),
          padding: const EdgeInsets.all(6),
          child: Row(
            children: [
              for (final (mode, icon, label) in _options)
                Expanded(
                  child: _ModeButton(
                    icon: icon,
                    label: label,
                    selected: current == mode,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      controller.set(mode);
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AppColors.primary : context.colors.subText;
    return Semantics(
      button: true,
      selected: selected,
      label: '화면 모드 $label',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? context.colors.primaryLight : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              Icon(icon, size: 22, color: fg),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
