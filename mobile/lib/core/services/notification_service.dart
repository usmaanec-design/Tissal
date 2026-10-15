import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../../main.dart';
import '../../ui/theme/app_theme.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized || kIsWeb) return;

    try {
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _localNotifications.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: (response) {
          // Handle tap on system notification
        },
      );

      // Request notification permissions for Android 13+
      final androidPlatform = _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlatform != null) {
        await androidPlatform.requestNotificationsPermission();
      }

      _initialized = true;
    } catch (e) {
      debugPrint('[NotificationService] Initialization error: $e');
    }
  }

  /// Show high-priority system notification for incoming call (rings and vibrates)
  static Future<void> showCallNotification({
    required String callerName,
    required String callType,
  }) async {
    if (kIsWeb) return;
    await init();

    try {
      const androidDetails = AndroidNotificationDetails(
        'tisaal_calls_channel',
        'Incoming Calls',
        channelDescription: 'Notifications for incoming audio and video calls',
        importance: Importance.max,
        priority: Priority.high,
        category: AndroidNotificationCategory.call,
        fullScreenIntent: true,
        autoCancel: false,
        ongoing: true,
        enableVibration: true,
        playSound: true,
      );

      const notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      );

      await _localNotifications.show(
        id: 9999, // Static ID for incoming call
        title: 'Incoming $callType Call',
        body: '@$callerName is calling you on Tisaal...',
        notificationDetails: notificationDetails,
      );
    } catch (e) {
      debugPrint('[NotificationService] Call notification error: $e');
    }
  }

  /// Cancel incoming call notification when answered, rejected, or ended
  static Future<void> cancelCallNotification() async {
    if (kIsWeb) return;
    try {
      await _localNotifications.cancel(id: 9999);
    } catch (_) {}
  }

  /// Show system notification for a new message
  static Future<void> showMessageNotification({
    required String senderName,
    required String message,
  }) async {
    if (kIsWeb) return;
    await init();

    try {
      const androidDetails = AndroidNotificationDetails(
        'tisaal_messages_channel',
        'Direct Messages',
        channelDescription: 'Notifications for incoming encrypted messages',
        importance: Importance.high,
        priority: Priority.high,
        enableVibration: true,
        playSound: true,
      );

      const notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      );

      final notificationId = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await _localNotifications.show(
        id: notificationId,
        title: '@$senderName',
        body: message,
        notificationDetails: notificationDetails,
      );
    } catch (e) {
      debugPrint('[NotificationService] Message notification error: $e');
    }
  }

  /// Show system notification for a new contact request
  static Future<void> showContactRequestNotification({
    required String senderUsername,
  }) async {
    if (kIsWeb) return;
    await init();

    try {
      const androidDetails = AndroidNotificationDetails(
        'tisaal_contacts_channel',
        'Contact Requests',
        channelDescription: 'Notifications for new friend and contact requests',
        importance: Importance.high,
        priority: Priority.high,
        enableVibration: true,
        playSound: true,
      );

      const notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      );

      final notificationId = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await _localNotifications.show(
        id: notificationId,
        title: 'New Connection Request',
        body: '@$senderUsername sent you a connection request on Tisaal',
        notificationDetails: notificationDetails,
      );
    } catch (e) {
      debugPrint('[NotificationService] Contact request notification error: $e');
    }
  }

  /// In-app floating pill banner when app is actively in foreground
  static void showInApp({
    required String title,
    required String message,
    IconData icon = Icons.notifications_active_rounded,
    Color iconColor = AppTheme.primaryLight,
    VoidCallback? onTap,
    Duration duration = const Duration(seconds: 4),
  }) {
    final messenger = scaffoldMessengerKey.currentState;
    if (messenger == null) return;

    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        duration: duration,
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF1E293B),
        elevation: 8,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xFF334155), width: 1),
        ),
        content: InkWell(
          onTap: () {
            messenger.hideCurrentSnackBar();
            onTap?.call();
          },
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
