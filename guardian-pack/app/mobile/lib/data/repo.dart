import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../auth/auth.dart';
import 'models.dart';

/// The device the parent picked in Settings, if they have more than one.
class SelectedDevice extends Notifier<String?> {
  @override
  String? build() => null;
  void select(String id) => state = id;
}

final selectedDeviceProvider = NotifierProvider<SelectedDevice, String?>(SelectedDevice.new);

/// Which device the app is looking at: the picked one, else the first on the profile.
/// Null while the profile loads or when nothing is linked — the Shell shows the
/// link screen in that case, so the data providers below never run with null.
final deviceIdProvider = Provider<String?>((ref) {
  final ids = ref.watch(userProfileProvider).value?.deviceIds;
  if (ids == null || ids.isEmpty) return null;
  final picked = ref.watch(selectedDeviceProvider);
  return picked != null && ids.contains(picked) ? picked : ids.first;
});

String _requireDevice(Ref ref) {
  final id = ref.watch(deviceIdProvider);
  if (id == null) throw StateError('No device linked');
  return id;
}

final _db = FirebaseFirestore.instance;

DocumentReference<Map<String, dynamic>> _deviceRef(String id) => _db.collection('devices').doc(id);

/// Live device document (status, battery, last position).
final deviceProvider = StreamProvider<Device>((ref) {
  final id = _requireDevice(ref);
  return _deviceRef(id).snapshots().map(Device.fromDoc);
});

/// Fixes for one calendar day, oldest first. Used by the map trail and trip history.
final fixesForDayProvider = StreamProvider.family<List<Fix>, DateTime>((ref, day) {
  final id = _requireDevice(ref);
  final start = DateTime(day.year, day.month, day.day);
  final end = start.add(const Duration(days: 1));
  return _deviceRef(id)
      .collection('locations')
      .where('ts', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
      .where('ts', isLessThan: Timestamp.fromDate(end))
      .orderBy('ts')
      .snapshots()
      .map((q) => q.docs.map(Fix.fromDoc).toList(growable: false));
});

final zonesProvider = StreamProvider<List<Zone>>((ref) {
  final id = _requireDevice(ref);
  return _deviceRef(id).collection('zones').snapshots().map((q) => q.docs.map(Zone.fromDoc).toList(growable: false));
});

final alertsProvider = StreamProvider<List<Alert>>((ref) {
  final id = _requireDevice(ref);
  return _deviceRef(id)
      .collection('alerts')
      .orderBy('ts', descending: true)
      .limit(100)
      .snapshots()
      .map((q) => q.docs.map(Alert.fromDoc).toList(growable: false));
});

final triggersProvider = StreamProvider<Triggers>((ref) {
  final id = _requireDevice(ref);
  return _deviceRef(id).collection('settings').doc('triggers').snapshots().map(Triggers.fromDoc);
});

/// Writes. Kept together so every mutation is visible in one place.
class DeviceActions {
  DeviceActions(this._id);
  final String _id;

  /// Real devices read their mailbox (cmdbox/{cmdId}); the device doc flag drives
  /// the "Buzzing…" label until the device clears it.
  Future<void> requestBuzz(String? cmdId) {
    final batch = _db.batch()..update(_deviceRef(_id), {'buzz': true});
    if (cmdId != null) batch.update(_db.collection('cmdbox').doc(cmdId), {'buzz': true});
    return batch.commit();
  }

  Future<void> setZoneEnabled(String zoneId, bool enabled) =>
      _deviceRef(_id).collection('zones').doc(zoneId).update({'enabled': enabled});

  Future<void> deleteZone(String zoneId) => _deviceRef(_id).collection('zones').doc(zoneId).delete();

  /// Creates (id == null) or overwrites a zone.
  Future<void> saveZone({
    String? id,
    required String name,
    required ZoneType type,
    required LatLng center,
    required double radiusM,
    required bool enabled,
  }) {
    final zones = _deviceRef(_id).collection('zones');
    final doc = id == null ? zones.doc() : zones.doc(id);
    return doc.set({
      'name': name,
      'type': type.name,
      'lat': center.latitude,
      'lng': center.longitude,
      'radiusM': radiusM.round(),
      'enabled': enabled,
    });
  }

  Future<void> updateTriggers(Map<String, Object> patch) =>
      _deviceRef(_id).collection('settings').doc('triggers').set(patch, SetOptions(merge: true));

  /// Replaces the whole family-contacts list (it's one array on the device doc).
  Future<void> updateContacts(List<Contact> contacts) =>
      _deviceRef(_id).update({'contacts': [for (final c in contacts) c.toMap()]});

  /// Child's photo (data URI) or null to remove it.
  Future<void> setChildPhoto(String? dataUri) =>
      _deviceRef(_id).update({'photo': dataUri ?? FieldValue.delete()});
}

final deviceActionsProvider = Provider<DeviceActions>((ref) => DeviceActions(_requireDevice(ref)));
