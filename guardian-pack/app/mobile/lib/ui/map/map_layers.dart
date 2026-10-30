import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;

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
          child: Icon(zoneIcon(z.type), size: 16, color: context.wp.accent),
        ),
      );
}

PolylineLayer trailLayer(List<LatLng> points, {Color color = WpColors.red}) => PolylineLayer(polylines: [
      Polyline(points: points, color: color, strokeWidth: 4, strokeCap: StrokeCap.round, strokeJoin: StrokeJoin.round),
    ]);

/// The child's photo (or initials) in a map pin whose tip sits on the position, with
/// [label] ("Last seen 5 min ago") under it. Pulses while the child is moving, red
/// in SOS, faded when the device is offline.
class LiveMarker extends StatefulWidget {
  const LiveMarker({super.key, required this.name, this.photo, required this.status, this.label});
  final String name;
  final String? photo;
  final DeviceStatus status;
  final String? label;

  /// The box the pin is drawn in, and where its tip is inside that box — use them
  /// for the Marker so the tip, not the box centre, lands on the position.
  static const width = 160.0, height = 112.0;
  static const _tip = Offset(80, 78);
  static final alignment = Marker.computePixelAlignment(width: width, height: height, left: _tip.dx, top: _tip.dy);

  static const _head = 48.0;               // photo + white ring
  static const _headTop = 20.0;

  @override
  State<LiveMarker> createState() => _LiveMarkerState();
}

class _LiveMarkerState extends State<LiveMarker> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  bool get _pulsing => widget.status == DeviceStatus.moving || widget.status == DeviceStatus.sos;

  @override
  void initState() {
    super.initState();
    if (_pulsing) _c.repeat();
  }

  @override
  void didUpdateWidget(LiveMarker old) {
    super.didUpdateWidget(old);
    if (_pulsing && !_c.isAnimating) {
      _c.repeat();
    } else if (!_pulsing && _c.isAnimating) {
      _c.reset();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sos = widget.status == DeviceStatus.sos;
    final ring = sos ? WpColors.red : (widget.status == DeviceStatus.offline ? WpColors.muted : Colors.white);
    const head = LiveMarker._head, top = LiveMarker._headTop, cx = LiveMarker.width / 2;
    final pin = Stack(clipBehavior: Clip.none, children: [
      // Tail first so the round head overlaps its base.
      Positioned(
        left: cx - 9,
        top: top + head - 8,
        child: CustomPaint(size: Size(18, LiveMarker._tip.dy - (top + head - 8)), painter: _PinTail(ring)),
      ),
      Positioned(
        left: cx - head / 2,
        top: top,
        child: Container(
          width: head,
          height: head,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: ring,
            boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 6, offset: Offset(0, 2))],
          ),
          child: Avatar(name: widget.name, photo: widget.photo, size: head - 6),
        ),
      ),
    ]);

    return SizedBox(
      width: LiveMarker.width,
      height: LiveMarker.height,
      child: Stack(clipBehavior: Clip.none, children: [
        if (_pulsing)
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _c,
              builder: (_, _) {
                final t = Curves.easeOut.transform(_c.value);
                final d = head + 40 * t;
                return Stack(clipBehavior: Clip.none, children: [
                  Positioned(
                    left: cx - d / 2,
                    top: top + head / 2 - d / 2,
                    child: Container(
                      width: d,
                      height: d,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: (sos ? WpColors.red : WpColors.cyan).withValues(alpha: 0.35 * (1 - t)),
                      ),
                    ),
                  ),
                ]);
              },
            ),
          ),
        Positioned.fill(child: widget.status == DeviceStatus.offline ? Opacity(opacity: 0.6, child: pin) : pin),
        if (widget.label != null)
          Positioned(
            left: 0,
            right: 0,
            top: LiveMarker._tip.dy + 6,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: WpSpace.s, vertical: 3),
                decoration: BoxDecoration(
                  color: context.wp.card,
                  borderRadius: BorderRadius.circular(WpRadius.chip),
                  border: Border.all(color: context.wp.line),
                  boxShadow: const [BoxShadow(color: Color(0x26000000), blurRadius: 4, offset: Offset(0, 1))],
                ),
                child: Text(widget.label!, maxLines: 1, style: context.text.labelSmall!.copyWith(color: context.wp.ink)),
              ),
            ),
          ),
      ]),
    );
  }
}

/// The pin's pointer: a short triangle from under the head down to the tip.
class _PinTail extends CustomPainter {
  const _PinTail(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawShadow(path, Colors.black, 2, false);
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_PinTail old) => old.color != color;
}
