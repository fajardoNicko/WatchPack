import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

/// Earthquakes scraped from PHIVOLCS by the backend (`backend/src/run.mjs`) into
/// the top-level `quakes` collection. The app only reads them.
class Quake {
  const Quake({required this.id, required this.ts, required this.point, required this.depthKm, required this.mag, required this.location, required this.url});
  final String id, location, url;
  final DateTime ts;
  final LatLng point;
  final double depthKm, mag;

  factory Quake.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data()!;
    return Quake(
      id: d.id,
      ts: (m['ts'] as Timestamp).toDate(),
      point: LatLng((m['lat'] as num).toDouble(), (m['lng'] as num).toDouble()),
      depthKm: (m['depthKm'] as num?)?.toDouble() ?? 0,
      mag: (m['mag'] as num?)?.toDouble() ?? 0,
      location: (m['location'] as String?) ?? '',
      url: (m['url'] as String?) ?? '',
    );
  }
}

/// Quakes from the last 24 h at magnitude ≥ 3.0 — what's worth drawing on the map.
final quakesProvider = StreamProvider<List<Quake>>((ref) {
  final since = DateTime.now().subtract(const Duration(hours: 24));
  return FirebaseFirestore.instance
      .collection('quakes')
      .where('ts', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
      .where('mag', isGreaterThanOrEqualTo: 3.0)
      .orderBy('mag', descending: true)
      .limit(60)
      .snapshots()
      .map((q) => q.docs.map(Quake.fromDoc).toList(growable: false));
});
