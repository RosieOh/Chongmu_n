import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../models/round_item.dart';

/// [days]일 뒤 저녁 8시 (미입금 리마인드 시각)
DateTime reminderTimeAfter(DateTime now, int days) =>
    DateTime(now.year, now.month, now.day + days, 20);

/// '11월 27일 (목) 오후 8시' (기기 언어와 상관없이 한국어)
String reminderLabel(DateTime at) {
  const week = ['월', '화', '수', '목', '금', '토', '일'];
  final h = at.hour;
  final ampm = h < 12 ? '오전' : '오후';
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '${at.month}월 ${at.day}일 (${week[at.weekday - 1]}) $ampm $h12시';
}

/// 정산 ID → 알림 ID (앱을 다시 켜도 같은 값이 나오도록 FNV-1a 해시)
int reminderIdFor(String settlementId) {
  var h = 0x811c9dc5;
  for (final c in settlementId.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h & 0x7fffffff;
}

/// 미입금 리마인드 알림 (기기 안에서만 예약, 서버 없음)
class ReminderService {
  ReminderService._();

  static final ReminderService instance = ReminderService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'unpaid_reminder',
      '미입금 리마인드',
      channelDescription: '정산 후 아직 입금하지 않은 사람이 있을 때 알려드려요',
      importance: Importance.defaultImportance,
    ),
    iOS: DarwinNotificationDetails(),
  );

  Future<bool> _init() async {
    if (_ready) return true;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          // 권한은 처음 알림을 예약할 때 물어봐요
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestSoundPermission: false,
            requestBadgePermission: false,
          ),
        ),
      );
      _ready = true;
    } catch (e) {
      debugPrint('알림 초기화 실패: $e');
    }
    return _ready;
  }

  Future<bool> _requestPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      return await ios.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }
    return false;
  }

  /// [at] 에 미입금 알림 예약. 권한이 없거나 실패하면 false.
  Future<bool> schedule(Settlement s, DateTime at,
      {required int unpaid}) async {
    if (!await _init()) return false;
    try {
      if (!await _requestPermission()) return false;
      final title = s.title.trim().isEmpty ? '정산' : s.title.trim();
      await _plugin.zonedSchedule(
        id: reminderIdFor(s.id),
        // 절대 시각으로 한 번만 울리므로 UTC 기준으로 넘겨도 정확해요
        scheduledDate: tz.TZDateTime.from(at, tz.UTC),
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: '💸 [$title] 입금 확인할 시간이에요',
        body: '아직 $unpaid명이 입금 전이에요. 독촉 메시지를 보내 볼까요?',
      );
      return true;
    } catch (e) {
      debugPrint('알림 예약 실패: $e');
      return false;
    }
  }

  Future<void> cancel(String settlementId) async {
    if (!await _init()) return;
    try {
      await _plugin.cancel(id: reminderIdFor(settlementId));
    } catch (e) {
      debugPrint('알림 취소 실패: $e');
    }
  }
}
