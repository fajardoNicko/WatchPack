import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/models.dart';
import '../../data/repo.dart';
import '../../data/unread.dart';
import '../../theme/tokens.dart';
import '../../util/format.dart';
import '../motion.dart';
import '../nav.dart';
import '../widgets.dart';
import 'alert_sheet.dart';
import 'zone_editor.dart';

/// Notification tab: safety zones + system triggers, and the alert feed.
class AlertsScreen extends ConsumerWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(alertsSegmentProvider);
    final unread = ref.watch(unreadAlertsProvider);
    return Scaffold(
      appBar: const WpHeader(title: 'Notifications', subtitle: 'Proactive protection'),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(WpSpace.l, WpSpace.m, WpSpace.l, 0),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<int>(
                segments: [
                  const ButtonSegment(value: 0, label: Text('Zones & triggers'), icon: Icon(Symbols.verified_user_rounded, size: 18)),
                  ButtonSegment(
                    value: 1,
                    label: Text(unread > 0 && tab != 1 ? 'Alert feed ($unread)' : 'Alert feed'),
                    icon: const Icon(Symbols.notifications_rounded, size: 18),
                  ),
                ],
                selected: {tab},
                showSelectedIcon: false,
                onSelectionChanged: (s) => ref.read(alertsSegmentProvider.notifier).set(s.first),
                style: SegmentedButton.styleFrom(
                  selectedBackgroundColor: WpColors.navy,
                  selectedForegroundColor: Colors.white,
                  side: BorderSide(color: context.wp.line),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(WpRadius.button)),
                ),
              ),
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: WpMotion.base,
              child: tab == 0 ? const _ZonesTab(key: ValueKey(0)) : const _FeedTab(key: ValueKey(1)),
            ),
          ),
        ],
      ),
    );
  }
}

class _ZonesTab extends ConsumerWidget {
  const _ZonesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zones = ref.watch(zonesProvider);
    final triggers = ref.watch(triggersProvider);
    final device = ref.watch(deviceProvider).value;
    final actions = ref.read(deviceActionsProvider);
    final t = context.text;

    return ListView(
      padding: const EdgeInsets.fromLTRB(WpSpace.l, WpSpace.l, WpSpace.l, WpSpace.xl),
      children: [
        FilledButton.icon(
          onPressed: () => ZoneEditorScreen.open(context),
          icon: const Icon(Symbols.add_circle_rounded),
          label: const Text('Create new safety zone'),
        ),
        const SectionTitle('Safety zones'),
        zones.when(
          loading: () => const Column(children: [Skeleton(height: 72), SizedBox(height: WpSpace.m), Skeleton(height: 72)]),
          error: (e, _) => Text('$e', style: t.bodySmall),
          data: (list) => list.isEmpty
              ? const EmptyState(icon: Symbols.map_rounded, title: 'No zones yet', body: 'Register home, school, a friend\'s or relative\'s house, the tutor… to get arrival and departure alerts.')
              : Column(children: [
                  for (final (i, z) in list.indexed) ...[
                    FadeSlideIn(
                      key: ValueKey(z.id),
                      index: i,
                      child: _ZoneCard(
                        z,
                        deviceName: device?.name,
                        onToggle: (v) => actions.setZoneEnabled(z.id, v),
                        onEdit: () => ZoneEditorScreen.open(context, existing: z),
                        onDelete: () => _confirmDelete(context, z, actions),
                      ),
                    ),
                    const SizedBox(height: WpSpace.m),
                  ]
                ]),
        ),
        const SectionTitle('System triggers'),
        triggers.when(
          loading: () => const Skeleton(height: 120),
          error: (e, _) => Text('$e', style: t.bodySmall),
          data: (tr) => WpCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              _TriggerRow(
                icon: Symbols.battery_1_bar_rounded,
                color: WpColors.amber,
                title: 'Low battery alert',
                detail: 'Trigger: ${tr.lowBatteryPct}%  ·  tap to change',
                value: tr.lowBatteryOn,
                onChanged: (v) => actions.updateTriggers({'lowBatteryOn': v}),
                onTap: () => _pickLevel(
                  context,
                  title: 'Low battery alert at',
                  options: const [10, 15, 20, 30, 40, 50],
                  label: (v) => '$v%',
                  current: tr.lowBatteryPct,
                  onPick: (v) => actions.updateTriggers({'lowBatteryPct': v, 'lowBatteryOn': true}),
                ),
              ),
              Divider(color: context.wp.line),
              _TriggerRow(
                icon: Symbols.signal_cellular_off_rounded,
                color: WpColors.amber,
                title: 'Signal loss notification',
                detail: 'Trigger: offline for ${tr.signalLossMin} min  ·  tap to change',
                value: tr.signalLossOn,
                onChanged: (v) => actions.updateTriggers({'signalLossOn': v}),
                onTap: () => _pickLevel(
                  context,
                  title: 'Signal loss alert after',
                  options: const [5, 10, 15, 30, 60],
                  label: (v) => '$v minutes offline',
                  current: tr.signalLossMin,
                  onPick: (v) => actions.updateTriggers({'signalLossMin': v, 'signalLossOn': true}),
                ),
              ),
              Divider(color: context.wp.line),
              _TriggerRow(
                icon: Symbols.warning_rounded,
                color: WpColors.red,
                title: 'Off-route alert',
                detail: 'Far from everywhere ${device?.name ?? 'your child'} usually goes. Learns over 3 days.',
                value: tr.offRouteOn,
                onChanged: (v) => actions.updateTriggers({'offRouteOn': v}),
              ),
              Divider(color: context.wp.line),
              _TriggerRow(
                icon: Symbols.thunderstorm_rounded,
                color: WpColors.amber,
                title: 'Severe weather',
                detail: 'Thunderstorm, heavy rain or strong wind where ${device?.name ?? 'your child'} is',
                value: tr.weatherOn,
                onChanged: (v) => actions.updateTriggers({'weatherOn': v}),
              ),
              Divider(color: context.wp.line),
              const _TriggerRow(
                icon: Symbols.earthquake_rounded,
                color: WpColors.red,
                title: 'Earthquakes',
                detail: 'Always on — PHIVOLCS quakes M4 and up nearby',
                value: true,
                onChanged: null,
              ),
              Divider(color: context.wp.line),
              const _TriggerRow(
                icon: Symbols.sos_rounded,
                color: WpColors.red,
                title: 'SOS button',
                detail: 'Always on — texts every family contact',
                value: true,
                onChanged: null,
              ),
            ]),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmDelete(BuildContext context, Zone z, DeviceActions actions) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Delete ${z.name}?'),
        content: const Text('You will stop getting arrival and departure alerts for this place.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: WpColors.red), onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) await actions.deleteZone(z.id);
  }

  Future<void> _pickLevel(
    BuildContext context, {
    required String title,
    required List<int> options,
    required String Function(int) label,
    required int current,
    required ValueChanged<int> onPick,
  }) async {
    final v = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.only(bottom: WpSpace.s),
            child: Text(title, style: c.text.titleSmall),
          ),
          for (final o in options)
            ListTile(
              title: Text(label(o)),
              trailing: o == current ? const Icon(Symbols.check_rounded, color: WpColors.cyan, size: 20) : null,
              onTap: () => Navigator.pop(c, o),
            ),
          const SizedBox(height: WpSpace.s),
        ]),
      ),
    );
    if (v != null && v != current) onPick(v);
  }
}

class _ZoneCard extends StatelessWidget {
  const _ZoneCard(this.z, {required this.deviceName, required this.onToggle, required this.onEdit, required this.onDelete});
  final Zone z;
  final String? deviceName;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit, onDelete;

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    return WpCard(
      padding: const EdgeInsets.fromLTRB(WpSpace.l, WpSpace.m, WpSpace.s, WpSpace.m),
      child: Row(children: [
        IconDisc(zoneIcon(z.type), color: z.enabled ? WpColors.navy : context.wp.muted, size: 44),
        const SizedBox(width: WpSpace.m),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(z.name, style: t.titleSmall),
            Text('${z.type.label}  ·  ${z.radiusM.round()} m${z.notify == ZoneNotify.both ? '' : '  ·  ${z.notify.label.toLowerCase()} only'}'
                '${deviceName != null ? '  ·  $deviceName' : ''}', style: t.bodySmall),
          ]),
        ),
        Switch(value: z.enabled, onChanged: onToggle),
        IconButton(
          tooltip: 'Edit',
          onPressed: onEdit,
          icon: Icon(Symbols.edit_rounded, color: context.wp.muted, size: 20),
        ),
        IconButton(
          tooltip: 'Delete',
          onPressed: onDelete,
          icon: Icon(Symbols.delete_rounded, color: context.wp.muted, size: 20),
        ),
      ]),
    );
  }
}

class _TriggerRow extends StatelessWidget {
  const _TriggerRow({required this.icon, required this.color, required this.title, required this.detail, required this.value, required this.onChanged, this.onTap});
  final IconData icon;
  final Color color;
  final String title, detail;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(WpSpace.l, WpSpace.s, WpSpace.s, WpSpace.s),
          child: Row(children: [
            IconDisc(icon, color: color, size: 40),
            const SizedBox(width: WpSpace.m),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: context.text.bodyMedium),
                Text(detail, style: context.text.bodySmall),
              ]),
            ),
            Switch(value: value, onChanged: onChanged),
          ]),
        ),
      );
}

class _FeedTab extends ConsumerWidget {
  const _FeedTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(alertsProvider);
    final t = context.text;
    // Open on screen = read. The badge clears once the feed has actually been shown.
    final id = ref.watch(deviceIdProvider);
    if (id != null && ref.watch(tabProvider) == 2 && ref.watch(unreadAlertsProvider) > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) ref.read(alertsSeenProvider.notifier).markSeen(id);
      });
    }
    return alerts.when(
      loading: () => const Padding(padding: EdgeInsets.all(WpSpace.l), child: Column(children: [Skeleton(height: 72), SizedBox(height: WpSpace.m), Skeleton(height: 72)])),
      error: (e, _) => Center(child: Text('$e', style: t.bodySmall)),
      data: (list) => list.isEmpty
          ? const EmptyState(icon: Symbols.notifications_off_rounded, title: 'All quiet', body: 'Zone, route, battery and SOS alerts will show up here.')
          : ListView.separated(
              padding: const EdgeInsets.all(WpSpace.l),
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(height: WpSpace.m),
              itemBuilder: (_, i) {
                final a = list[i];
                final showDay = i == 0 || !sameDay(a.ts, list[i - 1].ts);
                return FadeSlideIn(key: ValueKey(a.id), index: i, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (showDay) Padding(padding: const EdgeInsets.only(bottom: WpSpace.s, left: WpSpace.xs), child: Text(sameDay(a.ts, DateTime.now()) ? 'Today' : fmtDayShort(a.ts), style: t.labelSmall)),
                  WpCard(
                    padding: const EdgeInsets.all(WpSpace.m),
                    onTap: () => showAlertSheet(context, a),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      IconDisc(alertIcon(a.type), color: alertColor(a.type)),
                      const SizedBox(width: WpSpace.m),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(child: Text(a.title, style: t.titleSmall)),
                            Text(fmtTime(a.ts), style: t.bodySmall),
                          ]),
                          const SizedBox(height: 2),
                          Text(a.body, style: t.bodyMedium),
                        ]),
                      ),
                    ]),
                  ),
                ]));
              },
            ),
    );
  }
}
