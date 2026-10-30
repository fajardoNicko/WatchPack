import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/quakes.dart';
import '../../theme/tokens.dart';
import '../../util/format.dart';
import '../widgets.dart';

/// Recent earthquakes as tappable rings sized and coloured by magnitude.
MarkerLayer quakeLayer(BuildContext context, List<Quake> quakes) => MarkerLayer(markers: [
      for (final q in quakes)
        Marker(
          point: q.point,
          width: _size(q.mag),
          height: _size(q.mag),
          child: GestureDetector(onTap: () => _showQuake(context, q), child: _QuakeRing(q)),
        ),
    ]);

double _size(double mag) => (18 + (mag - 3) * 10).clamp(18, 60).toDouble();
Color quakeColor(double mag) => mag >= 5.5 ? WpColors.red : mag >= 4.5 ? const Color(0xFFE0671B) : WpColors.amber;

class _QuakeRing extends StatelessWidget {
  const _QuakeRing(this.q);
  final Quake q;
  @override
  Widget build(BuildContext context) {
    final c = quakeColor(q.mag);
    return Container(
      decoration: BoxDecoration(shape: BoxShape.circle, color: c.withValues(alpha: 0.18), border: Border.all(color: c, width: 2)),
      alignment: Alignment.center,
      child: Text(q.mag.toStringAsFixed(1),
          style: TextStyle(fontFamily: 'Inter', fontSize: _size(q.mag) * 0.3, fontWeight: FontWeight.w700, color: c)),
    );
  }
}

void _showQuake(BuildContext context, Quake q) {
  final t = context.text;
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(WpSpace.l, 0, WpSpace.l, WpSpace.l),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            IconMark(Symbols.earthquake, color: quakeColor(q.mag), size: 44),
            const SizedBox(width: WpSpace.m),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Magnitude ${q.mag.toStringAsFixed(1)} earthquake', style: t.titleMedium),
                Text('${fmtDayShort(q.ts)} · ${fmtTime(q.ts)} · depth ${q.depthKm.round()} km', style: t.bodySmall),
              ]),
            ),
          ]),
          const SizedBox(height: WpSpace.m),
          Text(q.location, style: t.bodyMedium),
          const SizedBox(height: WpSpace.xs),
          Text('Source: PHIVOLCS', style: t.labelSmall),
        ]),
      ),
    ),
  );
}
