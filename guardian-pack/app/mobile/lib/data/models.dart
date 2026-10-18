import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

/// Firestore shapes — see docs/04-app-backend.md §2 and tools/seed_demo.mjs.

enum DeviceStatus { moving, idle, offline, sos }

class Contact {
  const Contact({required this.name, required this.phone, this.photo});
  final String name, phone;
  final String? photo;                    // base64 data URI, see data/photos.dart

  Contact copyWith({String? name, String? phone, String? photo, bool clearPhoto = false}) =>
      Contact(name: name ?? this.name, phone: phone ?? this.phone, photo: clearPhoto ? null : (photo ?? this.photo));

  Map<String, Object?> toMap() => {'name': name, 'phone': phone, if (photo != null) 'photo': photo};
}

class Device {
  const Device({
    required this.id,
    required this.name,
    required this.battery,
    required this.lastSeen,
    required this.position,
    required this.speedKmh,
    required this.status,
    required this.buzz,
    required this.insideZoneId,
    required this.contacts,
    this.photo,
    this.cmdId,
    this.gpsFix = true,
    this.sosAt,
    this.csq,
  });

  final String id, name;
  final String? photo;                    // child's photo, base64 data URI
  final String? cmdId;                    // real devices: their command mailbox, cmdbox/{cmdId}
  final bool gpsFix;                      // false = position is the last known one
  final DateTime? sosAt;                  // when the SOS button was last held
  final int? csq;                         // modem signal quality 0–31 (99 = unknown); real devices only
  final int battery;
  final DateTime? lastSeen;
  final LatLng? position;
  final double speedKmh;
  final DeviceStatus status;
  final bool buzz;
  final String? insideZoneId;
  final List<Contact> contacts;

  factory Device.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const {};
    final lat = (m['lastLat'] as num?)?.toDouble();
    final lng = (m['lastLng'] as num?)?.toDouble();
    final seen = (m['lastSeen'] as Timestamp?)?.toDate();
    var status = DeviceStatus.values.firstWhere(
      (s) => s.name == m['status'],
      orElse: () => DeviceStatus.idle,
    );
    // Not heard from in 15 min → offline, whatever the stored status says.
    if (status != DeviceStatus.sos &&
        (seen == null || DateTime.now().difference(seen) > const Duration(minutes: 15))) {
      status = DeviceStatus.offline;
    }
    return Device(
      id: d.id,
      name: (m['name'] as String?) ?? 'Device',
      battery: (m['battery'] as num?)?.toInt() ?? 0,
      lastSeen: seen,
      position: lat != null && lng != null ? LatLng(lat, lng) : null,
      speedKmh: (m['speedKmh'] as num?)?.toDouble() ?? 0,
      status: status,
      buzz: m['buzz'] == true,
      insideZoneId: m['insideZoneId'] as String?,
      photo: m['photo'] as String?,
      cmdId: m['cmdId'] as String?,
      gpsFix: m['gpsFix'] != false,
      sosAt: (m['sosAt'] as Timestamp?)?.toDate(),
      csq: (m['csq'] as num?)?.toInt(),
      contacts: [
        for (final c in (m['contacts'] as List?) ?? const [])
          if (c is Map) Contact(name: '${c['name'] ?? ''}', phone: '${c['phone'] ?? ''}', photo: c['photo'] as String?),
      ],
    );
  }
}

class Fix {
  const Fix({required this.point, required this.speedKmh, required this.ts});
  final LatLng point;
  final double speedKmh;
  final DateTime ts;

  factory Fix.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data()!;
    return Fix(
      point: LatLng((m['lat'] as num).toDouble(), (m['lng'] as num).toDouble()),
      speedKmh: (m['spd'] as num?)?.toDouble() ?? 0,
      ts: (m['ts'] as Timestamp).toDate(),
    );
  }
}

enum ZoneType { home, school, park, other }

class Zone {
  const Zone({
    required this.id,
    required this.name,
    required this.type,
    required this.center,
    required this.radiusM,
    required this.enabled,
  });
  final String id, name;
  final ZoneType type;
  final LatLng center;
  final double radiusM;
  final bool enabled;

  factory Zone.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data()!;
    return Zone(
      id: d.id,
      name: (m['name'] as String?) ?? 'Zone',
      type: ZoneType.values.firstWhere((t) => t.name == m['type'], orElse: () => ZoneType.other),
      center: LatLng((m['lat'] as num).toDouble(), (m['lng'] as num).toDouble()),
      radiusM: (m['radiusM'] as num?)?.toDouble() ?? 200,
      enabled: m['enabled'] != false,
    );
  }
}

enum AlertType { sos, zoneEnter, zoneExit, offRoute, onRoute, lowBattery, signalLoss, weather, quake, other }

class Alert {
  const Alert({required this.id, required this.type, required this.title, required this.body, required this.ts, this.point});
  final String id, title, body;
  final AlertType type;
  final DateTime ts;
  final LatLng? point;

  factory Alert.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data()!;
    const map = {
      'sos': AlertType.sos,
      'zone_enter': AlertType.zoneEnter,
      'zone_exit': AlertType.zoneExit,
      'off_route': AlertType.offRoute,
      'on_route': AlertType.onRoute,
      'low_battery': AlertType.lowBattery,
      'signal_loss': AlertType.signalLoss,
      'weather': AlertType.weather,
      'quake': AlertType.quake,
    };
    final lat = (m['lat'] as num?)?.toDouble(), lng = (m['lng'] as num?)?.toDouble();
    return Alert(
      id: d.id,
      type: map[m['type']] ?? AlertType.other,
      title: (m['title'] as String?) ?? '',
      body: (m['body'] as String?) ?? '',
      ts: (m['ts'] as Timestamp).toDate(),
      point: lat != null && lng != null ? LatLng(lat, lng) : null,
    );
  }
}

/// devices/{id}/settings/triggers. Defaults match backend/src/watch.mjs.
class Triggers {
  const Triggers({
    this.lowBatteryPct = 20,
    this.lowBatteryOn = true,
    this.signalLossMin = 10,
    this.signalLossOn = true,
    this.offRouteOn = true,
    this.weatherOn = true,
  });
  final int lowBatteryPct, signalLossMin;
  final bool lowBatteryOn, signalLossOn, offRouteOn, weatherOn;

  factory Triggers.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const {};
    return Triggers(
      lowBatteryPct: (m['lowBatteryPct'] as num?)?.toInt() ?? 20,
      lowBatteryOn: m['lowBatteryOn'] != false,
      signalLossMin: (m['signalLossMin'] as num?)?.toInt() ?? 10,
      signalLossOn: m['signalLossOn'] != false,
      offRouteOn: m['offRouteOn'] != false,
      weatherOn: m['weatherOn'] != false,
    );
  }
}
