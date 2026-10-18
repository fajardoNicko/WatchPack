import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth.dart';

/// Push notifications (FCM). The backend sends to every token stored on
/// users/{uid}.fcmTokens. Background/terminated messages are shown by the OS;
/// foreground ones we show ourselves through a local notification so they're
/// never silently dropped. Tapping either kind lands in [pushOpenProvider].

/// What a tapped notification asks the app to show: its device and alert type
/// (the `data` the backend sends — backend/src/run.mjs pushToParents).
class PushTarget {
  const PushTarget({this.deviceId, this.type = ''});
  final String? deviceId;
  final String type;

  /// SOS, zone and route alerts are about where the child is; the rest go to the feed.
  bool get showsMap => const {'sos', 'zone_enter', 'zone_exit', 'off_route', 'on_route'}.contains(type);
}

class PushOpen extends Notifier<PushTarget?> {
  @override
  PushTarget? build() => null;
  void open(Map<String, dynamic> data) =>
      state = PushTarget(deviceId: data['deviceId'] as String?, type: (data['type'] as String?) ?? '');
  void handled() => state = null;
}

final pushOpenProvider = NotifierProvider<PushOpen, PushTarget?>(PushOpen.new);

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

  // The plugin keeps this callback after sign-out; only act while this session lives.
  void open(Map<String, dynamic> data) {
    if (ref.mounted) ref.read(pushOpenProvider.notifier).open(data);
  }

  await _local.initialize(
    settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
    onDidReceiveNotificationResponse: (r) {
      if (r.payload != null) open(jsonDecode(r.payload!) as Map<String, dynamic>);
    },
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
      payload: jsonEncode(m.data),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(_channel.id, _channel.name,
            channelDescription: _channel.description, importance: Importance.high, priority: Priority.high),
      ),
    );
  });
  // Tapped while the app was in the background, or the tap that launched it.
  final tapped = FirebaseMessaging.onMessageOpenedApp.listen((m) => open(m.data));
  final launch = await fm.getInitialMessage();
  if (launch != null) open(launch.data);
  ref.onDispose(() { sub.cancel(); fg.cancel(); tapped.cancel(); });

  if (kDebugMode) debugPrint('push: allowed=$allowed');
  return allowed;
});
