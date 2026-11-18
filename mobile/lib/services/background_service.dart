import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:workmanager/workmanager.dart';

const String kBackgroundCheckTask = 'kivora_programme_periodic_check';
const String kBackgroundUniqueName = 'kivora_programme_bg_worker';
const String kPrefApiBaseUrl = 'api_base_url';
const String kPrefStudentId = 'student_id';

final FlutterLocalNotificationsPlugin _notificationsPlugin =
    FlutterLocalNotificationsPlugin();

const AndroidNotificationDetails _androidChannelDetails =
    AndroidNotificationDetails(
  'kivora_study_reminders',
  'Kivora Study Reminders',
  channelDescription:
      'Sunday weekly programme briefings and daily scheduled topic reminders.',
  importance: Importance.high,
  priority: Priority.high,
);

const NotificationDetails _defaultNotificationDetails = NotificationDetails(
  android: _androidChannelDetails,
  iOS: DarwinNotificationDetails(),
);

@pragma('vm:entry-point')
void studyBackgroundDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final baseUrl = prefs.getString(kPrefApiBaseUrl) ?? 'http://10.0.2.2:8000';
      final userId = prefs.getInt(kPrefStudentId) ?? 1;

      final cleanBase = baseUrl.endsWith('/')
          ? baseUrl.substring(0, baseUrl.length - 1)
          : baseUrl;
      final res = await http
          .get(Uri.parse('$cleanBase/curriculum/background-digest/$userId'))
          .timeout(const Duration(seconds: 12));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final isSunday = data['is_sunday'] as bool? ?? false;
        final title = isSunday
            ? (data['sunday_title'] as String? ?? 'Kivora Weekly Briefing')
            : (data['daily_title'] as String? ?? 'Today on Kivora');
        final body = isSunday
            ? (data['sunday_body'] as String? ??
                'Check your official weekly study programme.')
            : (data['daily_body'] as String? ??
                'Check what you should study today.');

        await BackgroundService.initNotificationsOnly();
        await _notificationsPlugin.show(
          id: isSunday ? 2002 : 2001,
          title: title,
          body: body,
          notificationDetails: _defaultNotificationDetails,
        );
      }
      return true;
    } catch (_) {
      return false;
    }
  });
}

class BackgroundService {
  static bool _initialized = false;

  static bool get isMobilePlatform =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static Future<void> initNotificationsOnly() async {
    tz.initializeTimeZones();
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinInit = DarwinInitializationSettings();
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: darwinInit,
    );
    await _notificationsPlugin.initialize(settings: initSettings);
  }

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    if (!isMobilePlatform) return;

    await initNotificationsOnly();

    if (Platform.isAndroid) {
      await _notificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } else if (Platform.isIOS) {
      await _notificationsPlugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }

    await Workmanager().initialize(studyBackgroundDispatcher);
  }

  static Future<void> showInstantNotification({
    required String title,
    required String body,
    int id = 1001,
  }) async {
    if (!isMobilePlatform) return;
    await _notificationsPlugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: _defaultNotificationDetails,
    );
  }

  static Future<void> scheduleDailyReminder({
    required int hour,
    required int minute,
    String? customBody,
  }) async {
    if (!isMobilePlatform) return;

    final now = DateTime.now();
    var target = DateTime(now.year, now.month, now.day, hour, minute);
    if (target.isBefore(now)) {
      target = target.add(const Duration(days: 1));
    }

    final scheduled = tz.TZDateTime.from(target.toUtc(), tz.UTC);
    await _notificationsPlugin.zonedSchedule(
      id: 1002,
      title: "Kivora • Today's Study Programme",
      body: customBody ??
          'Open Kivora to see your scheduled subjects and topics for today.',
      scheduledDate: scheduled,
      notificationDetails: _defaultNotificationDetails,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  static Future<void> scheduleSundayWeeklyReminder({
    String? customBody,
  }) async {
    if (!isMobilePlatform) return;

    final now = DateTime.now();
    var daysUntilSunday = (DateTime.sunday - now.weekday) % 7;
    var target = DateTime(
      now.year,
      now.month,
      now.day,
      18,
      0,
    ).add(Duration(days: daysUntilSunday));
    if (target.isBefore(now)) {
      target = target.add(const Duration(days: 7));
    }

    final scheduled = tz.TZDateTime.from(target.toUtc(), tz.UTC);
    await _notificationsPlugin.zonedSchedule(
      id: 1005,
      title: 'Kivora • This Week’s Official Programme',
      body: customBody ??
          'Sunday Briefing: Open Kivora to see all subjects & topics scheduled for this week.',
      scheduledDate: scheduled,
      notificationDetails: _defaultNotificationDetails,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
    );
  }

  static Future<void> cancelDailyReminder() async {
    if (!isMobilePlatform) return;
    await _notificationsPlugin.cancel(id: 1002);
  }

  static Future<void> enablePeriodicBackgroundSync({
    Duration frequency = const Duration(hours: 6),
  }) async {
    if (!isMobilePlatform) return;
    await Workmanager().registerPeriodicTask(
      kBackgroundUniqueName,
      kBackgroundCheckTask,
      frequency: frequency,
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
      constraints: Constraints(networkType: NetworkType.connected),
    );
  }

  static Future<void> disablePeriodicBackgroundSync() async {
    if (!isMobilePlatform) return;
    await Workmanager().cancelByUniqueName(kBackgroundUniqueName);
  }
}
