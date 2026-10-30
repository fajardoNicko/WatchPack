import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../data/estimate.dart';
import '../../data/models.dart';
import 'map_layers.dart';

/// The live pin, moving smoothly instead of jumping every report: on a new report it
/// glides from where it is shown to the report, then keeps going along the estimate
/// (data/estimate.dart) until the next one. [child] is the pin (a LiveMarker).
class GlidingMarker extends StatefulWidget {
  const GlidingMarker({super.key, required this.device, required this.trail, required this.child});
  final Device device;                     // must have a position
  final List<LatLng> trail;                // today's fixes, oldest first
  final Widget child;

  @override
  State<GlidingMarker> createState() => _GlidingMarkerState();
}

class _GlidingMarkerState extends State<GlidingMarker> with SingleTickerProviderStateMixin {
  static const _glide = Duration(milliseconds: 1200);
  static const _d = DistanceHaversine(roundResult: false);

  late final Ticker _ticker = createTicker((_) => _tick());
  late Estimate _est;
  late LatLng _from, _shown;
  late DateTime _glideStart;

  @override
  void initState() {
    super.initState();
    final p = widget.device.position!;
    _est = _estimate(Estimate.cameFrom(widget.trail, p));
    _from = _shown = p;
    _glideStart = DateTime.now().subtract(_glide);   // nothing to glide from yet
    _run();
  }

  @override
  void didUpdateWidget(GlidingMarker old) {
    super.didUpdateWidget(old);
    final d = widget.device, o = old.device;
    if (d.position == o.position && d.lastSeen == o.lastSeen && d.speedKmh == o.speedKmh && d.status == o.status) return;
    final p = d.position!;
    // Heading: from the last report, or from the trail if the child hadn't moved.
    final from = _d.distance(_est.fix, p) >= Estimate.minStepM ? _est.fix : Estimate.cameFrom(widget.trail, p);
    _est = _estimate(from);
    _from = _shown;
    _glideStart = DateTime.now();
    _run();
  }

  Estimate _estimate(LatLng? from) {
    final d = widget.device;
    return Estimate.from(
      fix: d.position!,
      speedKmh: d.status == DeviceStatus.offline ? 0 : d.speedKmh,
      seenAt: d.lastSeen,
      from: from,
    );
  }

  LatLng _at(DateTime now) {
    final target = _est.positionAt(now);
    final t = now.difference(_glideStart).inMilliseconds / _glide.inMilliseconds;
    if (t >= 1) return target;
    final e = Curves.easeInOut.transform(t.clamp(0.0, 1.0));
    return LatLng(
      _from.latitude + (target.latitude - _from.latitude) * e,
      _from.longitude + (target.longitude - _from.longitude) * e,
    );
  }

  void _run() {
    if (!_ticker.isActive) _ticker.start();
  }

  void _tick() {
    final now = DateTime.now();
    final p = _at(now);
    final gliding = now.difference(_glideStart) < _glide;
    // While gliding every frame; after that only once it has moved a visible bit.
    if (gliding || _d.distance(p, _shown) > 0.3) setState(() => _shown = p);
    if (!gliding && !_est.movingAt(now)) _ticker.stop();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  // Own repaint layer: the moving, pulsing pin doesn't make the map tiles repaint.
  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: MarkerLayer(markers: [
          Marker(
            point: _shown,
            width: LiveMarker.width,
            height: LiveMarker.height,
            alignment: LiveMarker.alignment,
            child: widget.child,
          ),
        ]),
      );
}
