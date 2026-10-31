import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../data/models.dart';
import '../../theme/tokens.dart';
import '../widgets.dart';

/// Shared map pieces so the Map Pin and Trip History maps look identical.

/// OpenStreetMap raster tiles (no API key), recoloured on-device: desaturated and
/// lifted for the light theme so it reads like the grey map in the mockup, inverted
/// and dimmed for dark mode. Tiles are cached by flutter_map in memory.
Widget baseTiles(BuildContext context) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  // One colour filter over the whole layer (a single offscreen pass per frame),
  // not one per tile — hundreds of per-tile filters made panning stutter.
  return ColorFiltered(
    colorFilter: ColorFilter.matrix(dark ? _darkMatrix : _lightMatrix),
    child: TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'ph.watchpack.app',
      maxNativeZoom: 19,
      maxZoom: 20,
      keepBuffer: 3,
      panBuffer: 1,
    ),
  );
}

// Luma weights (0.2126, 0.7152, 0.0722) → greyscale, then scale 0.55 + offset 0.45·255
// to lift the midtones toward white without blowing out roads.
const _lightMatrix = <double>[
  0.2126 * 0.55, 0.7152 * 0.55, 0.0722 * 0.55, 0, 115,
  0.2126 * 0.55, 0.7152 * 0.55, 0.0722 * 0.55, 0, 115,
  0.2126 * 0.55, 0.7152 * 0.55, 0.0722 * 0.55, 0, 115,
  0, 0, 0, 1, 0,
];

// Greyscale, inverted, then dimmed: roads become dark-grey lines on near-black.
const _darkMatrix = <double>[
  -0.2126 * 0.7, -0.7152 * 0.7, -0.0722 * 0.7, 0, 200,
  -0.2126 * 0.7, -0.7152 * 0.7, -0.0722 * 0.7, 0, 200,
  -0.2126 * 0.7, -0.7152 * 0.7, -0.0722 * 0.7, 0, 200,
  0, 0, 0, 1, 0,
];

Widget attribution() => const RichAttributionWidget(
      showFlutterMapAttribution: false,
      attributions: [TextSourceAttribution('© OpenStreetMap contributors')],
    );

CircleLayer zoneLayer(List<Zone> zones) => CircleLayer(circles: [
      for (final z in zones.where((z) => z.enabled))
        CircleMarker(
          point: z.center,
          radius: z.radiusM,
          useRadiusInMeter: true,
          color: WpColors.cyan.withValues(alpha: 0.12),
          borderColor: WpColors.cyan.withValues(alpha: 0.7),
          borderStrokeWidth: 1.5,
        ),
    ]);

/// The place's icon at each zone centre, so home, school, a friend's house… read at a glance.
MarkerLayer zonePins(List<Zone> zones) => MarkerLayer(markers: [
      for (final z in zones.where((z) => z.enabled))
        Marker(point: z.center, width: 30, height: 30, child: _ZonePin(z)),
    ]);

class _ZonePin extends StatelessWidget {
  const _ZonePin(this.z);
  final Zone z;
  @override
  Widget build(BuildContext context) => Tooltip(
        message: z.name,
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: context.wp.card,
            border: Border.all(color: WpColors.cyan, width: 2),
          ),
          child: Icon(zoneIcon(z.type), size: 16, fill: 1, color: WpColors.navy),
        ),
      );
}

PolylineLayer trailLayer(List<LatLng> points, {Color color = WpColors.red}) => PolylineLayer(polylines: [
      Polyline(points: points, color: color, strokeWidth: 4, strokeCap: StrokeCap.round, strokeJoin: StrokeJoin.round),
    ]);

/// Cyan dot, navy ring, soft pulse. Red when in SOS.
class LiveMarker extends StatefulWidget {
  const LiveMarker({super.key, required this.status});
  final DeviceStatus status;

  @override
  State<LiveMarker> createState() => _LiveMarkerState();
}

class _LiveMarkerState extends State<LiveMarker> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.status == DeviceStatus.sos ? WpColors.red : WpColors.cyan;
    final pulsing = widget.status != DeviceStatus.offline;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) {
        final t = Curves.easeOut.transform(_c.value);
        return Stack(
          alignment: Alignment.center,
          children: [
            if (pulsing)
              Container(
                width: 14 + 30 * t,
                height: 14 + 30 * t,
                decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.35 * (1 - t))),
              ),
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: pulsing ? color : WpColors.muted,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 2))],
              ),
            ),
          ],
        );
      },
    );
  }
}
