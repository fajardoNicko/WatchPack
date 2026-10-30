import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../data/models.dart';
import '../data/photos.dart';
import '../theme/tokens.dart';

/// Navy header with the two-tone wordmark. Replace the text with the SVG logo
/// once the design team sends it (assets/images/logo.svg).
class WpHeader extends StatelessWidget implements PreferredSizeWidget {
  const WpHeader({super.key, this.title, this.subtitle, this.trailing, this.back = false});
  final String? title, subtitle;
  final Widget? trailing;
  final bool back;                        // pushed screens: back arrow before the title

  @override
  Size get preferredSize => Size.fromHeight(subtitle == null ? 56 : 76);

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    return Material(
      color: context.wp.header,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: preferredSize.height,
          child: Padding(
            padding: EdgeInsets.only(left: back ? WpSpace.xs : WpSpace.l, right: WpSpace.l),
            child: Row(
              children: [
                if (back) const BackButton(color: Colors.white),
                Expanded(
                  child: title == null
                      ? const Wordmark()
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title!, style: t.titleMedium!.copyWith(color: Colors.white)),
                            if (subtitle != null)
                              Text(subtitle!, style: t.bodySmall!.copyWith(color: Colors.white70)),
                          ],
                        ),
                ),
                ?trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.size = 22, this.light = true});
  final double size;
  final bool light;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: TextStyle(fontFamily: 'Inter', fontSize: size, fontWeight: FontWeight.w700, letterSpacing: -0.5, height: 1),
        children: [
          TextSpan(text: 'Watch', style: TextStyle(color: light ? Colors.white : WpColors.navy)),
          const TextSpan(text: 'Pack', style: TextStyle(color: WpColors.cyan)),
        ],
      ),
    );
  }
}

class WpCard extends StatelessWidget {
  const WpCard({super.key, required this.child, this.padding = const EdgeInsets.all(WpSpace.l), this.onTap, this.alert = false});
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final bool alert;                       // SOS: red outline on a red tint

  @override
  Widget build(BuildContext context) {
    final card = AnimatedContainer(
      duration: WpMotion.base,
      decoration: BoxDecoration(
        color: alert ? Color.alphaBlend(WpColors.red.withValues(alpha: 0.08), context.wp.card) : context.wp.card,
        borderRadius: BorderRadius.circular(WpRadius.card),
        border: Border.all(color: alert ? WpColors.red : context.wp.line, width: alert ? 1.5 : 1),
      ),
      padding: padding,
      child: child,
    );
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(borderRadius: BorderRadius.circular(WpRadius.card), onTap: onTap, child: card),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.action});
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(WpSpace.xs, WpSpace.xl, WpSpace.xs, WpSpace.m),
      child: Row(
        children: [
          Expanded(child: Text(text.toUpperCase(), style: context.text.labelSmall!.copyWith(letterSpacing: 0.8))),
          ?action,
        ],
      ),
    );
  }
}

Color statusColor(DeviceStatus s) => switch (s) {
      DeviceStatus.moving => WpColors.cyan,
      DeviceStatus.idle => WpColors.green,
      DeviceStatus.offline => WpColors.muted,
      DeviceStatus.sos => WpColors.red,
    };

String statusLabel(DeviceStatus s) => switch (s) {
      DeviceStatus.moving => 'Moving',
      DeviceStatus.idle => 'Idle',
      DeviceStatus.offline => 'Offline',
      DeviceStatus.sos => 'SOS',
    };

class StatusDot extends StatelessWidget {
  const StatusDot(this.status, {super.key, this.size = 10});
  final DeviceStatus status;
  final double size;
  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: WpMotion.base,
        width: size,
        height: size,
        decoration: BoxDecoration(color: statusColor(status), shape: BoxShape.circle),
      );
}

IconData zoneIcon(ZoneType t) => switch (t) {
      ZoneType.home => Symbols.home,
      ZoneType.school => Symbols.school,
      ZoneType.friend => Symbols.diversity_3,
      ZoneType.family => Symbols.family_restroom,
      ZoneType.tutor => Symbols.menu_book,
      ZoneType.sports => Symbols.sports_soccer,
      ZoneType.church => Symbols.church,
      ZoneType.park => Symbols.park,
      ZoneType.terminal => Symbols.directions_bus,
      ZoneType.other => Symbols.location_on,
    };

IconData alertIcon(AlertType t) => switch (t) {
      AlertType.sos => Symbols.sos,
      AlertType.zoneEnter => Symbols.login,
      AlertType.zoneExit => Symbols.logout,
      AlertType.offRoute => Symbols.warning,
      AlertType.onRoute => Symbols.check_circle,
      AlertType.lowBattery => Symbols.battery_1_bar,
      AlertType.signalLoss => Symbols.signal_cellular_off,
      AlertType.weather => Symbols.rainy,
      AlertType.quake => Symbols.earthquake,
      AlertType.other => Symbols.notifications,
    };

Color alertColor(BuildContext context, AlertType t) => switch (t) {
      AlertType.sos || AlertType.offRoute || AlertType.quake => WpColors.red,
      AlertType.lowBattery || AlertType.signalLoss || AlertType.weather => WpColors.amber,
      AlertType.onRoute || AlertType.zoneEnter => WpColors.green,
      _ => context.wp.accent,
    };

/// A line icon in a [size] square — no disc or tint behind it, the one icon
/// treatment used everywhere. [color] defaults to the theme's accent.
class IconMark extends StatelessWidget {
  const IconMark(this.icon, {super.key, this.color, this.size = 40});
  final IconData icon;
  final Color? color;
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: Icon(icon, color: color ?? context.wp.accent, size: size * 0.6),
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title, body;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(WpSpace.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconMark(icon, color: context.wp.muted, size: 56),
              const SizedBox(height: WpSpace.l),
              Text(title, style: context.text.titleSmall, textAlign: TextAlign.center),
              const SizedBox(height: WpSpace.xs),
              Text(body, style: context.text.bodySmall, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
}

/// Grey bars while a stream delivers its first value. No spinners.
class Skeleton extends StatelessWidget {
  const Skeleton({super.key, this.height = 14, this.width});
  final double height;
  final double? width;
  @override
  Widget build(BuildContext context) => Container(
        height: height,
        width: width,
        decoration: BoxDecoration(color: context.wp.line, borderRadius: BorderRadius.circular(6)),
      );
}

/// Round photo, or initials on a tinted disc when there's no photo yet.
/// [onTap] (optional) shows a small camera badge to signal it's editable.
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.name, this.photo, this.size = 60, this.onTap});
  final String name;
  final String? photo;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bytes = avatarBytes(photo);
    final initials = name.trim().split(RegExp(r'\s+')).take(2).map((w) => w.isEmpty ? '' : w[0].toUpperCase()).join();
    // A photo is clipped to the full circle with no ring. A border on the clipping box
    // insets the photo, so its corners poked out past the ring and the ring only
    // showed on the four sides — the avatar read as a square.
    final disc = bytes != null
        ? ClipOval(child: Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true, width: size, height: size))
        : Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: WpColors.cyanSoft,
              border: Border.all(color: WpColors.cyan, width: 2),
            ),
            alignment: Alignment.center,
            child: Text(initials.isEmpty ? '?' : initials,
                style: TextStyle(fontFamily: 'Inter', fontSize: size * 0.32, fontWeight: FontWeight.w600, color: WpColors.navy)),
          );
    if (onTap == null) return disc;
    return GestureDetector(
      onTap: onTap,
      child: Stack(clipBehavior: Clip.none, children: [
        disc,
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            width: size * 0.36,
            height: size * 0.36,
            decoration: BoxDecoration(color: context.wp.accent, shape: BoxShape.circle, border: Border.all(color: context.wp.card, width: 2)),
            child: Icon(Symbols.photo_camera, size: size * 0.18, color: context.wp.onAccent, weight: 500),
          ),
        ),
      ]),
    );
  }
}

/// Bottom sheet: Gallery / Camera / Remove. Returns the new data URI, '' to
/// remove, or null if cancelled.
Future<String?> pickAvatarSheet(BuildContext context, {bool hasPhoto = false}) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Symbols.photo_library), title: const Text('Choose from gallery'), onTap: () => Navigator.pop(c, 'gallery')),
        ListTile(leading: const Icon(Symbols.photo_camera), title: const Text('Take a photo'), onTap: () => Navigator.pop(c, 'camera')),
        if (hasPhoto)
          ListTile(leading: const Icon(Symbols.delete, color: WpColors.red), title: const Text('Remove photo', style: TextStyle(color: WpColors.red)), onTap: () => Navigator.pop(c, 'remove')),
        const SizedBox(height: WpSpace.s),
      ]),
    ),
  );
  if (choice == null) return null;
  if (choice == 'remove') return '';
  return pickAvatarDataUri(camera: choice == 'camera');
}

void showNote(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(text),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(WpRadius.button)),
    ));
}
