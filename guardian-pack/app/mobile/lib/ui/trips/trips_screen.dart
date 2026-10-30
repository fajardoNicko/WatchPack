import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/models.dart';
import '../../data/repo.dart';
import '../../data/trips.dart';
import '../../theme/tokens.dart';
import '../../util/format.dart';
import '../map/map_layers.dart';
import '../widgets.dart';

/// Trip History tab: pick a day, scrub along the route, read the timeline.
class TripsScreen extends ConsumerStatefulWidget {
  const TripsScreen({super.key});
  @override
  ConsumerState<TripsScreen> createState() => _TripsScreenState();
}

class _TripsScreenState extends ConsumerState<TripsScreen> {
  DateTime _day = dateOnly(DateTime.now());
  double _scrub = 1.0;          // 0..1 along the day's fixes
  final _map = MapController();
  List<LatLng> _fitted = const [];

  void _shift(int days) => setState(() {
        _day = DateTime(_day.year, _day.month, _day.day + days);
        _scrub = 1.0;
      });

  Future<void> _pick() async {
    final d = await showDatePicker(context: context, initialDate: _day, firstDate: DateTime(2026), lastDate: DateTime.now());
    if (d != null) setState(() { _day = dateOnly(d); _scrub = 1.0; });
  }

  void _fit(List<LatLng> pts) {
    if (pts.length < 2 || identical(pts, _fitted)) return;
    _fitted = pts;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _map.fitCamera(CameraFit.coordinates(coordinates: pts, padding: const EdgeInsets.all(28)));
    });
  }

  @override
  Widget build(BuildContext context) {
    final fixes = ref.watch(fixesForDayProvider(_day));
    final zones = ref.watch(zonesProvider);
    final isToday = sameDay(_day, DateTime.now());
    final t = context.text;

    return Scaffold(
      appBar: WpHeader(title: 'Trip history', subtitle: fmtDayLong(_day)),
      body: fixes.when(
        loading: () => const _TripsSkeleton(),
        error: (e, _) => Center(child: Text('$e', style: t.bodySmall)),
        data: (list) {
          final summary = TripSummary.compute(list);
          final pts = [for (final f in list) f.point];
          final trail = simplify(pts);
          _fit(trail);
          final idx = list.isEmpty ? -1 : ((list.length - 1) * _scrub).round();
          final sel = idx >= 0 ? list[idx] : null;

          return Column(
            children: [
              _DayStrip(day: _day, isToday: isToday, onPrev: () => _shift(-1), onNext: isToday ? null : () => _shift(1), onPick: _pick),
              Expanded(
                child: list.isEmpty
                    ? const EmptyState(
                        icon: Symbols.route,
                        title: 'No trips recorded',
                        body: 'Nothing was logged on this day. Pick another date.',
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(WpSpace.l, 0, WpSpace.l, WpSpace.xl),
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(WpRadius.card),
                            child: SizedBox(
                              height: 260,
                              child: FlutterMap(
                                mapController: _map,
                                options: MapOptions(
                                  initialCenter: pts.last,
                                  initialZoom: 14,
                                  interactionOptions: const InteractionOptions(flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag),
                                ),
                                children: [
                                  baseTiles(context),
                                  zoneLayer(zones.value ?? const []),
                                  if (trail.length > 1) trailLayer(trail),
                                  zonePins(zones.value ?? const []),
                                  if (sel != null)
                                    MarkerLayer(markers: [
                                      Marker(point: sel.point, width: 20, height: 20, child: const _ScrubDot()),
                                    ]),
                                  attribution(),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: WpSpace.m),
                          WpCard(
                            padding: const EdgeInsets.fromLTRB(WpSpace.l, WpSpace.m, WpSpace.l, WpSpace.s),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Text('Selected point', style: t.labelMedium),
                                  const Spacer(),
                                  if (sel != null) Text('${fmtTime(sel.ts)}  ·  ${fmtSpeed(sel.speedKmh)}', style: t.bodySmall),
                                ]),
                                Slider(
                                  value: _scrub,
                                  activeColor: context.wp.accent,
                                  inactiveColor: context.wp.line,
                                  onChanged: (v) => setState(() => _scrub = v),
                                ),
                              ],
                            ),
                          ),
                          const SectionTitle('Timeline'),
                          WpCard(
                            padding: const EdgeInsets.symmetric(vertical: WpSpace.s),
                            child: Column(children: [
                              for (final (i, s) in summary.segments.indexed)
                                _SegmentRow(s, zones: zones.value ?? const [], last: i == summary.segments.length - 1),
                            ]),
                          ),
                          const SectionTitle('Trip summary'),
                          WpCard(
                            child: Row(children: [
                              _Stat('Distance', fmtKm(summary.meters)),
                              _Stat('Moving time', fmtDuration(summary.moving)),
                              _Stat('Avg. speed', fmtSpeed(summary.avgKmh)),
                            ]),
                          ),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DayStrip extends StatelessWidget {
  const _DayStrip({required this.day, required this.isToday, required this.onPrev, required this.onNext, required this.onPick});
  final DateTime day;
  final bool isToday;
  final VoidCallback onPrev, onPick;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(WpSpace.s, WpSpace.s, WpSpace.s, WpSpace.m),
        child: Row(children: [
          IconButton(onPressed: onPrev, icon: const Icon(Symbols.chevron_left)),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onPick,
              icon: const Icon(Symbols.calendar_today, size: 18),
              label: Text(isToday ? 'Today' : fmtDayShort(day)),
            ),
          ),
          IconButton(onPressed: onNext, icon: const Icon(Symbols.chevron_right)),
        ]),
      );
}

class _SegmentRow extends StatelessWidget {
  const _SegmentRow(this.s, {required this.zones, required this.last});
  final Segment s;
  final List<Zone> zones;
  final bool last;

  String _place(LatLng p) {
    const d = Distance();
    for (final z in zones) {
      if (d.as(LengthUnit.Meter, z.center, p) <= z.radiusM) return z.name.replaceAll(' Zone', '');
    }
    return 'Unknown stop';
  }

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    final moving = s.kind == SegmentKind.moving;
    final title = moving
        ? '${_place(s.fixes.first.point)} to ${_place(s.fixes.last.point)}'
        : 'Idle at ${_place(s.fixes.first.point)}';
    final detail = moving ? '${fmtDuration(s.duration)}  ·  ${fmtKm(s.meters)}' : fmtDuration(s.duration);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: WpSpace.l),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: 64, child: Padding(padding: const EdgeInsets.only(top: 10), child: Text(fmtTime(s.start), style: t.bodySmall))),
            Column(children: [
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: moving ? WpColors.cyan : context.wp.card,
                    border: Border.all(color: moving ? WpColors.cyan : context.wp.accent, width: 2),
                  ),
                ),
              ),
              if (!last) Expanded(child: Container(width: 2, color: context.wp.line)),
            ]),
            const SizedBox(width: WpSpace.m),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: WpSpace.s),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: t.bodyMedium),
                  Text(detail, style: t.bodySmall),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(children: [
          Text(value, style: context.text.titleMedium),
          const SizedBox(height: 2),
          Text(label, style: context.text.bodySmall),
        ]),
      );
}

class _ScrubDot extends StatelessWidget {
  const _ScrubDot();
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: context.wp.accent,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 2))],
        ),
      );
}

class _TripsSkeleton extends StatelessWidget {
  const _TripsSkeleton();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.all(WpSpace.l),
        child: Column(children: [
          Skeleton(height: 44),
          SizedBox(height: WpSpace.m),
          Skeleton(height: 260),
          SizedBox(height: WpSpace.m),
          Skeleton(height: 80),
        ]),
      );
}
