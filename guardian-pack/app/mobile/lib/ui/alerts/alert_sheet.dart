import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models.dart';
import '../../theme/tokens.dart';
import '../../util/format.dart';
import '../map/map_layers.dart';
import '../widgets.dart';

/// An alert from the feed: what happened, when, and where on a small map.
void showAlertSheet(BuildContext context, Alert a) {
  final t = context.text;
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(WpSpace.l, 0, WpSpace.l, WpSpace.l),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            IconMark(alertIcon(a.type), color: alertColor(context, a.type), size: 44),
            const SizedBox(width: WpSpace.m),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(a.title, style: t.titleMedium),
                Text('${fmtDayShort(a.ts)} · ${fmtTime(a.ts)}', style: t.bodySmall),
              ]),
            ),
          ]),
          const SizedBox(height: WpSpace.m),
          Text(a.body, style: t.bodyMedium),
          if (a.point != null) ...[
            const SizedBox(height: WpSpace.l),
            ClipRRect(
              borderRadius: BorderRadius.circular(WpRadius.card),
              child: SizedBox(
                height: 220,
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: a.point!,
                    initialZoom: a.type == AlertType.quake ? 8 : 16,
                    interactionOptions: const InteractionOptions(flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag),
                  ),
                  children: [
                    baseTiles(c),
                    MarkerLayer(markers: [
                      Marker(
                        point: a.point!,
                        width: 36,
                        height: 36,
                        child: Icon(Symbols.location_on, fill: 1, size: 36, color: alertColor(context, a.type)),
                        alignment: Alignment.topCenter,
                      ),
                    ]),
                    attribution(),
                  ],
                ),
              ),
            ),
            const SizedBox(height: WpSpace.m),
            OutlinedButton.icon(
              onPressed: () => launchUrl(
                Uri.parse('https://maps.google.com/?q=${a.point!.latitude.toStringAsFixed(5)},${a.point!.longitude.toStringAsFixed(5)}'),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Symbols.map),
              label: const Text('Open in Google Maps'),
            ),
          ],
        ]),
      ),
    ),
  );
}
