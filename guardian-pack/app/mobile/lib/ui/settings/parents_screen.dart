import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../auth/auth.dart';
import '../../data/linking.dart';
import '../../data/repo.dart';
import '../../theme/tokens.dart';
import '../motion.dart';
import '../widgets.dart';

/// Parental account: who can see the device, and invites for another parent.
class ParentsScreen extends ConsumerWidget {
  const ParentsScreen({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ParentsScreen()));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final device = ref.watch(deviceProvider).value;
    final deviceId = ref.watch(deviceIdProvider);
    final members = ref.watch(membersProvider);
    final invites = ref.watch(myInvitesProvider).value ?? const <Invite>[];
    final me = ref.watch(authStateProvider).value?.uid;
    final name = device?.name ?? 'your child';
    final demo = deviceId == demoDeviceId;
    final t = context.text;

    return Scaffold(
      appBar: WpHeader(
        title: 'Parental account',
        subtitle: 'Who can see $name',
        back: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(WpSpace.l, WpSpace.s, WpSpace.l, WpSpace.xl),
        children: [
          if (demo) ...[
            const SizedBox(height: WpSpace.l),
            const _Note(
              icon: Symbols.info_rounded,
              text: 'This is the shared demo device — every new account can see it, so there is no parent list. '
                  'Invites work on real WatchPacks.',
            ),
          ] else ...[
            const SectionTitle('Parents'),
            members.when(
              loading: () => const Skeleton(height: 72),
              error: (e, _) => Text('$e', style: t.bodySmall),
              data: (list) => WpCard(
                padding: EdgeInsets.zero,
                child: Column(children: [
                  for (final (i, m) in list.indexed) ...[
                    if (i > 0) Divider(color: context.wp.line),
                    FadeSlideIn(
                      index: i,
                      child: ListTile(
                        leading: Avatar(name: m.name, photo: m.photo, size: 40),
                        title: Text(m.name.isEmpty ? m.email : m.name, style: t.bodyMedium),
                        subtitle: Text(m.email, style: t.bodySmall),
                        trailing: m.uid == me
                            ? const _Chip('You')
                            : IconButton(
                                tooltip: 'Remove',
                                onPressed: () => _remove(context, ref, deviceId!, m, name),
                                icon: Icon(Symbols.person_remove_rounded, color: context.wp.muted, size: 20),
                              ),
                      ),
                    ),
                  ],
                  if (list.isEmpty) Padding(padding: const EdgeInsets.all(WpSpace.l), child: Text('Only you so far.', style: t.bodySmall)),
                ]),
              ),
            ),
            const SizedBox(height: WpSpace.s),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: WpSpace.xs),
              child: Text('Every parent here sees the live location, history and alerts, and gets the same push notifications. '
                  'Each parent can leave from Security & privacy on their own phone, or be removed here.', style: t.bodySmall),
            ),
            const SizedBox(height: WpSpace.xl),
            _InviteButton(onPressed: deviceId == null ? null : () => _invite(context, ref, deviceId, name)),
            if (invites.isNotEmpty) ...[
              const SectionTitle('Open invites'),
              WpCard(
                padding: EdgeInsets.zero,
                child: Column(children: [
                  for (final (i, inv) in invites.indexed) ...[
                    if (i > 0) Divider(color: context.wp.line),
                    ListTile(
                      onTap: inv.expired ? null : () => _showInvite(context, inv, name),
                      leading: IconDisc(Symbols.key_rounded, color: inv.expired ? context.wp.muted : WpColors.navy),
                      title: Text(fmtCode(inv.code), style: t.bodyMedium!.copyWith(fontFeatures: const [FontFeature.tabularFigures()], letterSpacing: 1)),
                      subtitle: Text(inv.expired ? 'Expired' : 'Until ${_until(inv.expiresAt)}', style: t.bodySmall),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (!inv.expired)
                          IconButton(tooltip: 'Share', onPressed: () => _share(inv, name), icon: Icon(Symbols.share_rounded, color: context.wp.muted, size: 20)),
                        IconButton(
                          tooltip: inv.expired ? 'Remove' : 'Cancel invite',
                          onPressed: () => ref.read(linkActionsProvider).cancelInvite(inv.code),
                          icon: Icon(Symbols.close_rounded, color: context.wp.muted, size: 20),
                        ),
                      ]),
                    ),
                  ],
                ]),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Future<void> _remove(BuildContext context, WidgetRef ref, String deviceId, Member m, String child) async {
    final who = m.name.isEmpty ? m.email : m.name;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Remove $who?'),
        content: Text('$who stops seeing $child\'s location, history and alerts right away. '
            'To come back they need a new invite, or the pairing code on the WatchPack\'s sticker.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: WpColors.red), onPressed: () => Navigator.pop(c, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(linkActionsProvider).removeParent(deviceId, m);
      if (context.mounted) showNote(context, '$who removed.');
    } catch (e) {
      if (context.mounted) showNote(context, 'Could not remove $who: $e');
    }
  }

  Future<void> _invite(BuildContext context, WidgetRef ref, String deviceId, String name) async {
    try {
      final inv = await ref.read(linkActionsProvider).createInvite(deviceId);
      if (context.mounted) _showInvite(context, inv, name);
    } catch (e) {
      if (context.mounted) showNote(context, 'Could not create an invite: $e');
    }
  }

  Future<void> _showInvite(BuildContext context, Invite inv, String name) => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (c) {
          final t = c.text;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(WpSpace.xl, 0, WpSpace.xl, WpSpace.l),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Invite code', style: t.titleMedium, textAlign: TextAlign.center),
                const SizedBox(height: WpSpace.l),
                // White in dark mode too: scanners want dark modules on a light ground.
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(WpSpace.m),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(WpRadius.card)),
                    child: QrImageView(
                      data: qrPayload(inv.code),
                      size: 160,
                      padding: EdgeInsets.zero,
                      eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: WpColors.navy),
                      dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: WpColors.navy),
                    ),
                  ),
                ),
                const SizedBox(height: WpSpace.m),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: WpSpace.l),
                  decoration: BoxDecoration(color: WpColors.cyanSoft, borderRadius: BorderRadius.circular(WpRadius.card)),
                  child: Text(fmtCode(inv.code),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontFamily: 'Inter', fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: 4, color: WpColors.navy)),
                ),
                const SizedBox(height: WpSpace.m),
                Text('The other parent signs up in WatchPack, then scans this or types the code under Settings → Device linking. '
                    'Works once, until ${_until(inv.expiresAt)}.', style: t.bodySmall, textAlign: TextAlign.center),
                const SizedBox(height: WpSpace.xl),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: fmtCode(inv.code)));
                        if (c.mounted) showNote(c, 'Code copied.');
                      },
                      icon: const Icon(Symbols.content_copy_rounded),
                      label: const Text('Copy'),
                    ),
                  ),
                  const SizedBox(width: WpSpace.m),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _share(inv, name),
                      icon: const Icon(Symbols.share_rounded),
                      label: const Text('Share'),
                    ),
                  ),
                ]),
              ]),
            ),
          );
        },
      );

  static Future<void> _share(Invite inv, String name) => SharePlus.instance.share(ShareParams(
        subject: 'WatchPack invite',
        text: 'Join me on WatchPack to look after $name. Install WatchPack, create an account, then go to '
            'Settings → Device linking and enter the code ${fmtCode(inv.code)} (valid until ${_until(inv.expiresAt)}).',
      ));

  static String _until(DateTime t) => DateFormat('MMM d, h:mm a').format(t);
}

/// "Invite a parent", greyed out with a "Creating…" label until the code is ready.
class _InviteButton extends StatefulWidget {
  const _InviteButton({required this.onPressed});
  final Future<void> Function()? onPressed;
  @override
  State<_InviteButton> createState() => _InviteButtonState();
}

class _InviteButtonState extends State<_InviteButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) => FilledButton.icon(
        onPressed: widget.onPressed == null || _busy
            ? null
            : () async {
                setState(() => _busy = true);
                try {
                  await widget.onPressed!();
                } finally {
                  if (mounted) setState(() => _busy = false);
                }
              },
        icon: const Icon(Symbols.person_add_rounded),
        label: Text(_busy ? 'Creating…' : 'Invite a parent'),
      );
}

class _Chip extends StatelessWidget {
  const _Chip(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: WpSpace.s, vertical: 2),
        decoration: BoxDecoration(color: WpColors.cyanSoft, borderRadius: BorderRadius.circular(WpRadius.chip)),
        child: Text(label, style: context.text.labelSmall!.copyWith(color: WpColors.navy)),
      );
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => WpCard(
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: WpColors.cyan, size: 20),
          const SizedBox(width: WpSpace.m),
          Expanded(child: Text(text, style: context.text.bodySmall)),
        ]),
      );
}
