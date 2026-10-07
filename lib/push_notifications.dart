import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:webview_flutter/webview_flutter.dart';

// Harus sama dengan CHANNEL_ID di app/Services/FcmService.php (Laravel)
// dan meta-data default_notification_channel_id di AndroidManifest.xml.
const String _kChannelId = 'tugas_baru';
const String _kChannelName = 'Tugas Baru';
const String _kChannelDesc = 'Notifikasi saat admin meng-assign tugas baru';

// Ikon kecil notifikasi: android/app/src/main/res/drawable/ic_stat_oregonet.xml
const String _kNotifIcon = 'ic_stat_oregonet';

const AndroidNotificationChannel _kTaskChannel = AndroidNotificationChannel(
  _kChannelId,
  _kChannelName,
  description: _kChannelDesc,
  importance: Importance.high,
  playSound: true,
);

/// Mengurus izin notifikasi, token FCM, dan notifikasi yang diketuk.
///
/// Saat app tertutup atau di background, notifikasi ditampilkan sistem Android
/// langsung dari pesan FCM (tanpa kode Dart). Kode di sini menangani sisanya:
/// notifikasi saat app sedang terbuka, dan membuka halaman saat notifikasi diketuk.
class PushNotifications {
  PushNotifications({required this.onToken, required this.onOpenPath});

  /// Dipanggil saat token FCM tersedia atau berubah.
  final void Function(String token) onToken;

  /// Dipanggil saat notifikasi diketuk. [path] contoh: /worker/tasks/12
  final void Function(String path) onOpenPath;

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    try {
      await Firebase.initializeApp();
      final messaging = FirebaseMessaging.instance;

      await _local.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings(_kNotifIcon),
        ),
        onDidReceiveNotificationResponse: (response) {
          final path = response.payload;
          if (path != null && path.isNotEmpty) onOpenPath(path);
        },
      );

      // Channel dengan prioritas tinggi supaya berbunyi dan muncul di layar.
      await _local
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_kTaskChannel);

      // Android 13+: minta izin menampilkan notifikasi.
      await messaging.requestPermission();

      // App sedang terbuka: FCM tidak menampilkan notifikasi sendiri.
      FirebaseMessaging.onMessage.listen(_showInForeground);

      // Notifikasi diketuk saat app di background.
      FirebaseMessaging.onMessageOpenedApp.listen(_openFromMessage);

      // Notifikasi diketuk saat app benar-benar tertutup.
      final initial = await messaging.getInitialMessage();
      if (initial != null) _openFromMessage(initial);

      final token = await messaging.getToken();
      debugPrint('FCM token diterima (${token?.length ?? 0} chars)');
      if (token != null) onToken(token);
      messaging.onTokenRefresh.listen(onToken);
    } catch (e, st) {
      debugPrint('Push notification init gagal: $e\n$st');
    }
  }

  Future<void> _showInForeground(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    await _local.show(
      id: message.hashCode,
      title: notification.title,
      body: notification.body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _kChannelId,
          _kChannelName,
          channelDescription: _kChannelDesc,
          importance: Importance.high,
          priority: Priority.high,
          icon: _kNotifIcon,
        ),
      ),
      payload: message.data['path']?.toString(),
    );
  }

  void _openFromMessage(RemoteMessage message) {
    final path = message.data['path']?.toString();
    if (path != null && path.isNotEmpty) onOpenPath(path);
  }
}

/// Titipkan token FCM ke halaman web yang sedang terbuka. Halaman pekerja
/// akan mengirimkannya ke server (resources/views/layouts/partials/push-token.blade.php).
Future<void> injectFcmToken(WebViewController controller, String token) async {
  final safe = jsonEncode(token);
  try {
    await controller.runJavaScript(
      'window.OREGONET_FCM_TOKEN = $safe;'
      "window.dispatchEvent(new CustomEvent('oregonet-fcm-token', { detail: $safe }));",
    );
  } catch (e) {
    debugPrint('Gagal menitipkan token FCM ke halaman: $e');
  }
}

/// Ubah path dari notifikasi (mis. /worker/tasks/12) jadi URL lengkap.
/// Hanya menerima path di host yang sama dengan [home], selain itu null.
Uri? resolveAppPath(String path, Uri home) {
  if (!path.startsWith('/') || path.startsWith('//')) return null;
  final uri = home.resolve(path);
  return uri.host == home.host ? uri : null;
}
