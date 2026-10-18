import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../auth/auth.dart';
import '../../data/linking.dart';
import '../../data/repo.dart';
import '../../theme/tokens.dart';
import '../widgets.dart';

/// Security & privacy: password, leaving a device, what's stored, deleting the account.
class SecurityScreen extends ConsumerWidget {
  const SecurityScreen({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SecurityScreen()));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider).value;
    final device = ref.watch(deviceProvider).value;
    final deviceId = ref.watch(deviceIdProvider);
    final t = context.text;

    return Scaffold(
      appBar: const WpHeader(title: 'Security & privacy', subtitle: 'Your account and your child\'s data', back: true),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(WpSpace.l, WpSpace.s, WpSpace.l, WpSpace.xl),
        children: [
          const SectionTitle('Sign-in'),
          WpCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              ListTile(
                leading: const Icon(Symbols.mail_rounded),
                title: Text(profile?.email ?? '', style: t.bodyMedium),
                subtitle: Text('Email and password', style: t.bodySmall),
              ),
              Divider(color: context.wp.line),
              ListTile(
                leading: const Icon(Symbols.password_rounded),
                title: Text('Change password', style: t.bodyMedium),
                trailing: Icon(Symbols.chevron_right_rounded, size: 18, color: context.wp.muted),
                onTap: () => _changePassword(context, ref),
              ),
            ]),
          ),
          if (deviceId != null) ...[
            SectionTitle(device?.name ?? deviceId),
            WpCard(
              padding: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Symbols.link_off_rounded, color: WpColors.red),
                title: Text('Unlink from my account', style: t.bodyMedium!.copyWith(color: WpColors.red)),
                subtitle: Text('You stop seeing ${device?.name ?? 'this device'}. Other parents keep access.', style: t.bodySmall),
                onTap: () => _unlink(context, ref, deviceId, device?.name ?? deviceId),
              ),
            ),
          ],
          const SectionTitle('What WatchPack keeps'),
          WpCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final (icon, text) in const [
                (Symbols.location_on_rounded, 'Location every 30 seconds while the WatchPack is on (every 10 s during SOS), with speed and battery. This is the trail in Trip History.'),
                (Symbols.group_rounded, 'Only parents linked with a pairing or invite code can see a device. Nobody can link with the device ID alone.'),
                (Symbols.key_rounded, 'The WatchPack signs every update with its own secret key, so nothing else can pretend to be it.'),
                (Symbols.sms_rounded, 'SOS texts go straight from the WatchPack\'s SIM to your family contacts — they work without the app or internet.'),
                (Symbols.photo_camera_rounded, 'Photos stay small (256 px) and are stored with your account, not shared outside the family.'),
              ]) ...[
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(icon, size: 18, color: WpColors.cyan),
                  const SizedBox(width: WpSpace.m),
                  Expanded(child: Text(text, style: t.bodySmall)),
                ]),
                const SizedBox(height: WpSpace.m),
              ],
            ]),
          ),
          const SizedBox(height: WpSpace.xl),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: WpColors.red, side: const BorderSide(color: WpColors.red)),
            onPressed: () => _deleteAccount(context, ref),
            icon: const Icon(Symbols.delete_forever_rounded),
            label: const Text('Delete my account'),
          ),
        ],
      ),
    );
  }

  Future<void> _changePassword(BuildContext context, WidgetRef ref) async {
    final cur = TextEditingController(), next = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Change password'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: cur, obscureText: true, autofocus: true, decoration: const InputDecoration(labelText: 'Current password')),
          const SizedBox(height: WpSpace.m),
          TextField(controller: next, obscureText: true, decoration: const InputDecoration(labelText: 'New password', helperText: 'At least 8 characters')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Change')),
        ],
      ),
    );
    if (ok != true) return;
    if (next.text.length < 8) {
      if (context.mounted) showNote(context, 'Use at least 8 characters for the new password.');
      return;
    }
    try {
      await ref.read(authActionsProvider).changePassword(cur.text, next.text);
      if (context.mounted) showNote(context, 'Password changed.');
    } catch (e) {
      if (context.mounted) showNote(context, authErrorMessage(e));
    }
  }

  Future<void> _unlink(BuildContext context, WidgetRef ref, String deviceId, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Unlink $name?'),
        content: const Text('You will stop seeing its location and getting its alerts. To see it again you need its pairing code or a new invite.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: WpColors.red), onPressed: () => Navigator.pop(c, true), child: const Text('Unlink')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final link = ref.read(linkActionsProvider);
    Navigator.of(context).popUntil((r) => r.isFirst);
    try {
      await link.unlink(deviceId);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not unlink $name: $e')));
    }
  }

  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    final pw = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete your account?'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('This removes your profile, your photo and your invites, and signs you out for good. '
              'Your child\'s WatchPack and the other parents are not affected.'),
          const SizedBox(height: WpSpace.l),
          TextField(controller: pw, obscureText: true, decoration: const InputDecoration(labelText: 'Password to confirm')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: WpColors.red), onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final nav = Navigator.of(context);
    final auth = ref.read(authActionsProvider);
    try {
      await auth.reauth(pw.text);
      await ref.read(linkActionsProvider).forgetMe();
      nav.popUntil((r) => r.isFirst);
      await auth.deleteAccount();
    } catch (e) {
      if (context.mounted) showNote(context, authErrorMessage(e));
    }
  }
}
