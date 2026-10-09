import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth.dart';

/// Push notifications (FCM). The backend sends to every token stored on
/// users/{uid}.fcmTokens. Background/terminated messages are shown by the OS;
/// foreground ones we show ourselves through a local notification so they're
/// never silently dropped.

const _channel = AndroidNotificationChannel(
  'alerts',
  'WatchPack alerts',
  description: 'SOS, safety zones, earthquakes and device alerts',
  importance: Importance.high,
);

final _local = FlutterLocalNotificationsPlugin();

@pragma('vm:entry-point')
Future<void> _onBackgroundMessage(RemoteMessage m) async {
  // Nothing to do: FCM shows notification messages itself while the app is closed.
}

/// Runs once per signed-in session (watched by the Shell). Registers the token and
/// wires up foreground display. Returns true when notifications are allowed.
final pushSetupProvider = FutureProvider<bool>((ref) async {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return false;

  final fm = FirebaseMessaging.instance;
  FirebaseMessaging.onBackgroundMessage(_onBackgroundMessage);

  await _local.initialize(
    settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
  );
  await _local
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(_channel);

  final perm = await fm.requestPermission(alert: true, badge: true, sound: true);
  final allowed = perm.authorizationStatus == AuthorizationStatus.authorized ||
      perm.authorizationStatus == AuthorizationStatus.provisional;

  Future<void> save(String? token) async {
    if (token == null) return;
    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'fcmTokens': FieldValue.arrayUnion([token]),
    }, SetOptions(merge: true));
  }

  await save(await fm.getToken());
  final sub = fm.onTokenRefresh.listen(save);
  final fg = FirebaseMessaging.onMessage.listen((m) {
    final n = m.notification;
    if (n == null) return;
    _local.show(
      id: m.hashCode,
      title: n.title,
      body: n.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(_channel.id, _channel.name,
            channelDescription: _channel.description, importance: Importance.high, priority: Priority.high),
      ),
    );
  });
  ref.onDispose(() { sub.cancel(); fg.cancel(); });

  if (kDebugMode) debugPrint('push: allowed=$allowed');
  return allowed;
});
