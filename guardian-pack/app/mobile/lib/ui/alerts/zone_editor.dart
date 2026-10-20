import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/models.dart';
import '../../data/repo.dart';
import '../../theme/tokens.dart';
import '../map/map_layers.dart';
import '../widgets.dart';

/// Create or edit a safety zone. The map moves under a fixed centre pin — more
/// precise on a phone than dragging a marker — and the radius circle previews live.
class ZoneEditorScreen extends ConsumerStatefulWidget {
  const ZoneEditorScreen({super.key, this.existing});
  final Zone? existing;

  static Future<void> open(BuildContext context, {Zone? existing}) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ZoneEditorScreen(existing: existing), fullscreenDialog: true),
      );

  @override
  ConsumerState<ZoneEditorScreen> createState() => _ZoneEditorScreenState();
}

class _ZoneEditorScreenState extends ConsumerState<ZoneEditorScreen> {
  final _map = MapController();
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late ZoneType _type = widget.existing?.type ?? ZoneType.home;
  late double _radius = widget.existing?.radiusM ?? 200;
  LatLng? _center;
  bool _saving = false;
  bool _nameTouched = false;

  @override
  void initState() {
    super.initState();
    _nameTouched = widget.existing != null;
    _center = widget.existing?.center;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _setType(ZoneType t) => setState(() {
        _type = t;
        if (!_nameTouched) _name.text = t.defaultName;
      });

  Future<void> _save() async {
    final center = _center;
    if (center == null) return;
    final name = _name.text.trim().isEmpty ? _type.defaultName : _name.text.trim();
    setState(() => _saving = true);
    try {
      await ref.read(deviceActionsProvider).saveZone(
            id: widget.existing?.id,
            name: name,
            type: _type,
            center: center,
            radiusM: _radius,
            enabled: widget.existing?.enabled ?? true,
          );
      if (mounted) {
        Navigator.of(context).pop();
        showNote(context, widget.existing == null ? '$name created.' : '$name updated.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showNote(context, 'Could not save: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final device = ref.watch(deviceProvider).value;
    final t = context.text;
    final wp = context.wp;
    // First open on a new zone: start where the device is.
    final initial = _center ?? device?.position ?? const LatLng(14.65, 120.98);
    _center ??= device?.position;

    return Scaffold(
      appBar: WpHeader(
        title: widget.existing == null ? 'New safety zone' : 'Edit zone',
        subtitle: 'Move the map to place the centre',
        trailing: IconButton(
          tooltip: 'Close',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Symbols.close_rounded, color: Colors.white),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                FlutterMap(
                  mapController: _map,
                  options: MapOptions(
                    initialCenter: initial,
                    initialZoom: 16,
                    interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                    onPositionChanged: (pos, _) {
                      if (_center != pos.center) setState(() => _center = pos.center);
                    },
                  ),
                  children: [
                    baseTiles(context),
                    if (_center != null)
                      CircleLayer(circles: [
                        CircleMarker(
                          point: _center!,
                          radius: _radius,
                          useRadiusInMeter: true,
                          color: WpColors.cyan.withValues(alpha: 0.14),
                          borderColor: WpColors.cyan,
                          borderStrokeWidth: 2,
                        ),
                      ]),
                    attribution(),
                  ],
                ),
                // Fixed centre pin (tip sits on the map centre).
                IgnorePointer(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 36),
                    child: Icon(Symbols.location_on_rounded, fill: 1, size: 44, color: WpColors.navy,
                        shadows: const [Shadow(color: Color(0x55000000), blurRadius: 6, offset: Offset(0, 2))]),
                  ),
                ),
                if (device?.position != null)
                  Positioned(
                    right: WpSpace.l,
                    top: WpSpace.l,
                    child: Material(
                      color: wp.card,
                      shape: const CircleBorder(),
                      elevation: 2,
                      child: IconButton(
                        tooltip: 'Centre on ${device!.name}',
                        onPressed: () => _map.move(device.position!, 16),
                        icon: const Icon(Symbols.my_location_rounded),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Material(
            color: wp.card,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(WpSpace.l, WpSpace.m, WpSpace.l, WpSpace.m),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Two rows of five: home, school, friend's house, family, tutor, …
                    LayoutBuilder(builder: (_, box) {
                      final w = (box.maxWidth - 4 * WpSpace.s) / 5;
                      return Wrap(spacing: WpSpace.s, runSpacing: WpSpace.s, children: [
                        for (final z in ZoneType.values)
                          SizedBox(width: w, child: _TypeChip(type: z, selected: _type == z, onTap: () => _setType(z))),
                      ]);
                    }),
                    const SizedBox(height: WpSpace.m),
                    TextField(
                      controller: _name,
                      onChanged: (_) => _nameTouched = true,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        hintText: _type.example,
                        labelText: 'Name',
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(WpRadius.button)),
                      ),
                    ),
                    const SizedBox(height: WpSpace.s),
                    Row(children: [
                      Text('Radius', style: t.labelMedium),
                      const Spacer(),
                      Text('${_radius.round()} m', style: t.titleSmall),
                    ]),
                    Slider(
                      value: _radius,
                      min: 100,
                      max: 1000,
                      divisions: 18,
                      activeColor: WpColors.navy,
                      inactiveColor: wp.line,
                      onChanged: (v) => setState(() => _radius = v),
                    ),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _saving || _center == null ? null : _save,
                        child: Text(_saving ? 'Saving…' : (widget.existing == null ? 'Create zone' : 'Save changes')),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.type, required this.selected, required this.onTap});
  final ZoneType type;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: selected ? WpColors.navy : context.wp.bg,
        borderRadius: BorderRadius.circular(WpRadius.button),
        child: InkWell(
          borderRadius: BorderRadius.circular(WpRadius.button),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: WpSpace.s),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(zoneIcon(type), fill: 1, size: 20, color: selected ? Colors.white : context.wp.muted),
              const SizedBox(height: 2),
              Text(type.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.labelMedium!.copyWith(color: selected ? Colors.white : context.wp.ink)),
            ]),
          ),
        ),
      );
}
