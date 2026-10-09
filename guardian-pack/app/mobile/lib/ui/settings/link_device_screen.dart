import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../auth/auth.dart';
import '../../theme/tokens.dart';
import '../widgets.dart';

/// Shown instead of the tabs when the parent has no device on their profile.
class LinkDeviceScreen extends ConsumerWidget {
  const LinkDeviceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.text;
    return Scaffold(
      appBar: WpHeader(
        trailing: TextButton(
          onPressed: () => ref.read(authActionsProvider).signOut(),
          style: TextButton.styleFrom(foregroundColor: Colors.white70),
          child: const Text('Sign out'),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(WpSpace.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const IconDisc(Symbols.phone_android_rounded, size: 72),
              const SizedBox(height: WpSpace.l),
              Text('Link your child\'s WatchPack', style: t.titleLarge, textAlign: TextAlign.center),
              const SizedBox(height: WpSpace.s),
              Text('Enter the device ID printed on the WatchPack to start tracking.', style: t.bodySmall, textAlign: TextAlign.center),
              const SizedBox(height: WpSpace.xl),
              FilledButton.icon(
                onPressed: () => showLinkDeviceDialog(context, ref),
                icon: const Icon(Symbols.link_rounded),
                label: const Text('Link a device'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Asks for a device id and adds it to the profile. Shared by the link screen
/// and the Settings card.
Future<void> showLinkDeviceDialog(BuildContext context, WidgetRef ref) async {
  final ctl = TextEditingController();
  final id = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Link a device'),
      content: TextField(
        controller: ctl,
        autofocus: true,
        autocorrect: false,
        decoration: const InputDecoration(labelText: 'Device ID', hintText: 'e.g. wp-demo-ivy'),
        onSubmitted: (v) => Navigator.pop(c, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, ctl.text), child: const Text('Link')),
      ],
    ),
  );
  final clean = id?.trim() ?? '';
  if (clean.isEmpty) return;
  final uid = ref.read(authStateProvider).value?.uid;
  if (uid == null) return;
  try {
    await ref.read(authActionsProvider).linkDevice(uid, clean);
    if (context.mounted) showNote(context, 'Linked $clean.');
  } catch (e) {
    if (context.mounted) showNote(context, 'Could not link: $e');
  }
}
