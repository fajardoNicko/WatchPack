import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

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
    final fixes = ref.watch(fixesForDayProvider(dateOnly(DateTime.now())));
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
      alert: device.value?.status == DeviceStatus.sos,
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
                  Expanded(
                    child: Text(sos ? 'SOS — ${d.name} needs help' : 'Real-time tracking',
                        style: t.titleSmall!.copyWith(color: sos ? WpColors.red : null), overflow: TextOverflow.ellipsis),
                  ),
                  Text(sos && d.sosAt != null ? 'since ${fmtTime(d.sosAt!)}' : fmtRelative(d.lastSeen), style: t.bodySmall),
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
                          if (d.csq != null && d.status != DeviceStatus.offline) ...[
                            const SizedBox(width: WpSpace.m),
                            Tooltip(
                              message: 'Mobile signal',
                              child: Icon(_signalIcon(d.csq!), size: 16, color: context.wp.muted),
                            ),
                          ],
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
                children: sos
                    ? [
                        _Action(
                          icon: Symbols.directions_rounded,
                          label: 'Directions',
                          onTap: d.position == null ? null : () => _open(context, _directionsUrl(d.position!)),
                        ),
                        _Action(
                          icon: Symbols.call_rounded,
                          label: 'Call family',
                          primary: true,
                          danger: true,
                          onTap: () => _callFamily(context, d),
                        ),
                        _Action(icon: Symbols.share_rounded, label: 'Share', onTap: d.position == null ? null : () => _share(d)),
                      ]
                    : [
                        _Action(icon: Symbols.history_rounded, label: 'History', onTap: onHistory),
                        _Action(
                          icon: Symbols.notifications_active_rounded,
                          // Offline devices can't pick the buzz up: it waits, and can be withdrawn.
                          label: !d.buzz ? 'Find device' : (d.status == DeviceStatus.offline ? 'Queued · cancel' : 'Buzzing…'),
                          primary: true,
                          onTap: !d.buzz
                              ? () async {
                                  await ref.read(deviceActionsProvider).requestBuzz(d.cmdId);
                                  if (context.mounted) {
                                    showNote(context, d.status == DeviceStatus.offline
                                        ? '${d.name}\'s WatchPack is offline. It will beep as soon as it reconnects.'
                                        : 'Buzz sent. ${d.name}\'s WatchPack beeps within 10 seconds.');
                                  }
                                }
                              : d.status == DeviceStatus.offline
                                  ? () => ref.read(deviceActionsProvider).cancelBuzz(d.cmdId)
                                  : null,
                        ),
                        _Action(icon: Symbols.share_rounded, label: 'Share', onTap: d.position == null ? null : () => _share(d)),
                      ],
              ),
            ],
          );
        },
      ),
    );
  }

  static String _mapsUrl(LatLng p) => 'https://maps.google.com/?q=${p.latitude.toStringAsFixed(5)},${p.longitude.toStringAsFixed(5)}';

  static Uri _directionsUrl(LatLng p) =>
      Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${p.latitude.toStringAsFixed(5)},${p.longitude.toStringAsFixed(5)}');

  Future<void> _share(Device d) => SharePlus.instance.share(ShareParams(
        subject: '${d.name}\'s location',
        text: '${d.name}\'s location from WatchPack (${fmtTime(d.lastSeen ?? DateTime.now())}): ${_mapsUrl(d.position!)}',
      ));

  static Future<void> _open(BuildContext context, Uri uri) async {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && context.mounted) {
      showNote(context, 'No app on this phone can open that.');
    }
  }

  Future<void> _callFamily(BuildContext context, Device d) async {
    if (d.contacts.isEmpty) {
      showNote(context, 'No family contacts yet — add them in Settings.');
      return;
    }
    final phone = d.contacts.length == 1
        ? d.contacts.first.phone
        : await showModalBottomSheet<String>(
            context: context,
            showDragHandle: true,
            builder: (c) => SafeArea(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                for (final p in d.contacts)
                  ListTile(
                    leading: Avatar(name: p.name, photo: p.photo, size: 40),
                    title: Text(p.name),
                    subtitle: Text(p.phone),
                    trailing: const Icon(Symbols.call_rounded, color: WpColors.green),
                    onTap: () => Navigator.pop(c, p.phone),
                  ),
                const SizedBox(height: WpSpace.s),
              ]),
            ),
          );
    if (phone != null && context.mounted) await _open(context, Uri(scheme: 'tel', path: phone));
  }

  IconData _signalIcon(int csq) => csq == 99 || csq < 10
      ? Symbols.signal_cellular_alt_1_bar_rounded
      : csq < 18
          ? Symbols.signal_cellular_alt_2_bar_rounded
          : Symbols.signal_cellular_alt_rounded;

  IconData _batteryIcon(int pct) => pct > 80
      ? Symbols.battery_full_rounded
      : pct > 50
          ? Symbols.battery_5_bar_rounded
          : pct > 20
              ? Symbols.battery_3_bar_rounded
              : Symbols.battery_1_bar_rounded;
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, this.onTap, this.primary = false, this.danger = false});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool primary, danger;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final fg = !enabled ? context.wp.muted : (primary ? Colors.white : context.wp.ink);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: WpSpace.xs),
        child: Material(
          color: primary ? (enabled ? (danger ? WpColors.red : WpColors.navy) : context.wp.line) : Colors.transparent,
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
