import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/models.dart';
import '../../data/quakes.dart';
import '../../data/repo.dart';
import '../../data/trips.dart';
import '../../theme/tokens.dart';
import '../../util/format.dart';
import '../motion.dart';
import '../widgets.dart';
import 'map_layers.dart';
import 'quake_layer.dart';

/// Map Pin tab: live position, today's trail, zones, status card.
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key, required this.onOpenHistory});
  final VoidCallback onOpenHistory;

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final _map = MapController();
  bool _follow = true;      // re-centre on every fix until the user pans
  LatLng? _lastCentered;

  void _recenter(LatLng p) {
    if (_lastCentered == p) return;
    _lastCentered = p;
    _map.move(p, _map.camera.zoom < 14 ? 15.5 : _map.camera.zoom);
  }

  @override
  Widget build(BuildContext context) {
    final device = ref.watch(deviceProvider);
    final fixes = ref.watch(fixesForDayProvider(DateTime.now()));
    final zones = ref.watch(zonesProvider);
    final quakes = ref.watch(quakesProvider);
    final pos = device.value?.position;

    if (_follow && pos != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _recenter(pos));
    }

    final trail = simplify([for (final f in fixes.value ?? const <Fix>[]) f.point]);

    return Scaffold(
      appBar: WpHeader(
        trailing: IconButton(
          tooltip: 'Centre on device',
          onPressed: pos == null
              ? null
              : () {
                  setState(() => _follow = true);
                  _lastCentered = null;
                  _recenter(pos);
                },
          icon: Icon(Symbols.my_location_rounded, color: _follow ? WpColors.cyan : Colors.white70),
        ),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: pos ?? const LatLng(14.65, 120.98),
              initialZoom: pos == null ? 11 : 15.5,
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
              onPositionChanged: (_, hasGesture) {
                if (hasGesture && _follow) setState(() => _follow = false);
              },
            ),
            children: [
              baseTiles(context),
              zoneLayer(zones.value ?? const []),
              if (trail.length > 1) trailLayer(trail),
              quakeLayer(context, quakes.value ?? const []),
              if (pos != null)
                MarkerLayer(markers: [
                  Marker(
                    point: pos,
                    width: 44,
                    height: 44,
                    child: LiveMarker(status: device.value?.status ?? DeviceStatus.offline),
                  ),
                ]),
              attribution(),
            ],
          ),
          Positioned(
            left: WpSpace.l,
            right: WpSpace.l,
            bottom: WpSpace.l,
            child: FadeSlideIn(
              child: _StatusCard(
                device: device,
                onHistory: widget.onOpenHistory,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends ConsumerWidget {
  const _StatusCard({required this.device, required this.onHistory});
  final AsyncValue<Device> device;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.text;
    return WpCard(
      padding: const EdgeInsets.fromLTRB(WpSpace.l, WpSpace.m, WpSpace.l, WpSpace.m),
      child: device.when(
        loading: () => const _CardSkeleton(),
        error: (e, _) => Text('Could not load device: $e', style: t.bodySmall),
        data: (d) {
          final sos = d.status == DeviceStatus.sos;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  StatusDot(d.status, size: 12),
                  const SizedBox(width: WpSpace.s),
                  Text(sos ? 'SOS — ${d.name} needs help' : 'Real-time tracking',
                      style: t.titleSmall!.copyWith(color: sos ? WpColors.red : null)),
                  const Spacer(),
                  Text(fmtRelative(d.lastSeen), style: t.bodySmall),
                ],
              ),
              const SizedBox(height: WpSpace.s),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Avatar(
                    name: d.name,
                    photo: d.photo,
                    size: 44,
                    onTap: () async {
                      final r = await pickAvatarSheet(context, hasPhoto: d.photo != null);
                      if (r == null) return;
                      await ref.read(deviceActionsProvider).setChildPhoto(r.isEmpty ? null : r);
                    },
                  ),
                  const SizedBox(width: WpSpace.m),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text.rich(TextSpan(children: [
                        TextSpan(text: d.name, style: t.titleMedium),
                        TextSpan(text: '  ·  ${statusLabel(d.status)}', style: t.bodyMedium),
                        if (d.status == DeviceStatus.moving)
                          TextSpan(text: '  ${fmtSpeed(d.speedKmh)}', style: t.bodyMedium!.copyWith(color: context.wp.muted)),
                      ])),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(_batteryIcon(d.battery), size: 16, color: d.battery <= 15 ? WpColors.red : context.wp.muted),
                          const SizedBox(width: WpSpace.xs),
                          Text('${d.battery}%', style: t.bodySmall),
                          if (d.insideZoneId != null) ...[
                            const SizedBox(width: WpSpace.m),
                            Icon(Symbols.verified_user_rounded, size: 16, color: WpColors.green),
                            const SizedBox(width: WpSpace.xs),
                            Text('In a safe zone', style: t.bodySmall),
                          ] else if (!d.gpsFix && d.status != DeviceStatus.offline) ...[
                            const SizedBox(width: WpSpace.m),
                            Icon(Symbols.location_searching_rounded, size: 16, color: context.wp.muted),
                            const SizedBox(width: WpSpace.xs),
                            Flexible(
                              child: Text(d.position == null ? 'Waiting for GPS' : 'No GPS · last known spot',
                                  style: t.bodySmall, overflow: TextOverflow.ellipsis),
                            ),
                          ],
                        ],
                      ),
                    ]),
                  ),
                ],
              ),
              const SizedBox(height: WpSpace.m),
              Divider(color: context.wp.line),
              const SizedBox(height: WpSpace.s),
              Row(
                children: [
                  _Action(icon: Symbols.history_rounded, label: 'History', onTap: onHistory),
                  _Action(
                    icon: Symbols.notifications_active_rounded,
                    label: d.buzz ? 'Buzzing…' : 'Find device',
                    primary: true,
                    onTap: d.buzz
                        ? null
                        : () async {
                            await ref.read(deviceActionsProvider).requestBuzz(d.cmdId);
                            if (context.mounted) showNote(context, 'Buzz sent. ${d.name}\'s WatchPack beeps within 10 seconds.');
                          },
                  ),
                  _Action(
                    icon: Symbols.share_rounded,
                    label: 'Share',
                    onTap: d.position == null
                        ? null
                        : () async {
                            final p = d.position!;
                            await Clipboard.setData(ClipboardData(
                                text: 'https://maps.google.com/?q=${p.latitude.toStringAsFixed(5)},${p.longitude.toStringAsFixed(5)}'));
                            if (context.mounted) showNote(context, 'Map link copied.');
                          },
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  IconData _batteryIcon(int pct) => pct > 80
      ? Symbols.battery_full_rounded
      : pct > 50
          ? Symbols.battery_5_bar_rounded
          : pct > 20
              ? Symbols.battery_3_bar_rounded
              : Symbols.battery_1_bar_rounded;
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, this.onTap, this.primary = false});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final fg = !enabled ? context.wp.muted : (primary ? Colors.white : context.wp.ink);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: WpSpace.xs),
        child: Material(
          color: primary ? (enabled ? WpColors.navy : context.wp.line) : Colors.transparent,
          borderRadius: BorderRadius.circular(WpRadius.button),
          child: InkWell(
            borderRadius: BorderRadius.circular(WpRadius.button),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: WpSpace.s),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 22, color: primary ? fg : (enabled ? WpColors.navy : fg)),
                  const SizedBox(height: WpSpace.xs),
                  Text(label, style: context.text.labelMedium!.copyWith(color: fg)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CardSkeleton extends StatelessWidget {
  const _CardSkeleton();
  @override
  Widget build(BuildContext context) => const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Skeleton(width: 160),
          SizedBox(height: WpSpace.m),
          Skeleton(width: 220, height: 20),
          SizedBox(height: WpSpace.s),
          Skeleton(width: 120),
          SizedBox(height: WpSpace.xl),
          Skeleton(height: 44),
        ],
      );
}
