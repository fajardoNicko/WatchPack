import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../auth/auth.dart';
import '../../data/linking.dart';
import '../../data/repo.dart';
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
              Text('Enter the pairing code on the WatchPack\'s sticker, or an invite code from another parent.',
                  style: t.bodySmall, textAlign: TextAlign.center),
              const SizedBox(height: WpSpace.xl),
              FilledButton.icon(
                onPressed: () => showLinkDeviceDialog(context, ref),
                icon: const Icon(Symbols.link_rounded),
                label: const Text('Enter a code'),
              ),
              const SizedBox(height: WpSpace.s),
              TextButton(
                onPressed: () => _link(context, ref, demoDeviceId),
                child: const Text('Look around with the demo device'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Asks for a pairing / invite code and links the device behind it. Shared by the
/// link screen and the Settings device picker.
Future<void> showLinkDeviceDialog(BuildContext context, WidgetRef ref) async {
  final code = await showDialog<String>(context: context, builder: (_) => const _CodeDialog());
  if (code == null || !context.mounted) return;
  await _link(context, ref, code);
}

Future<void> _link(BuildContext context, WidgetRef ref, String code) async {
  showNote(context, 'Linking…');
  try {
    final id = await ref.read(linkActionsProvider).linkWithCode(code);
    final name = (await FirebaseFirestore.instance.collection('devices').doc(id).get()).data()?['name'] as String?;
    if (context.mounted) showNote(context, 'Linked ${name ?? id}.');
  } on LinkError catch (e) {
    if (context.mounted) showNote(context, e.message);
  } on FirebaseException catch (e) {
    if (context.mounted) {
      showNote(context, e.code == 'permission-denied' ? 'That code no longer works. Ask for a new one.' : 'Could not link: ${e.message}');
    }
  }
}

class _CodeDialog extends StatefulWidget {
  const _CodeDialog();
  @override
  State<_CodeDialog> createState() => _CodeDialogState();
}

class _CodeDialogState extends State<_CodeDialog> {
  final _ctl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _submit() {
    final raw = _ctl.text.trim();
    if (raw.toLowerCase() == demoDeviceId || normalizeCode(raw) != null) {
      Navigator.pop(context, raw);
    } else {
      setState(() => _error = '8 letters and numbers, like K7QM-2XPA');
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Link a WatchPack'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            controller: _ctl,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\- ]')),
              LengthLimitingTextInputFormatter(11),
              // Codes are upper case; "wp-demo-ivy" stays as typed.
              TextInputFormatter.withFunction((_, v) => v.text.startsWith(RegExp('wp', caseSensitive: false)) ? v : v.copyWith(text: v.text.toUpperCase())),
            ],
            style: const TextStyle(fontFamily: 'Inter', fontSize: 22, fontWeight: FontWeight.w600, letterSpacing: 2),
            decoration: InputDecoration(labelText: 'Pairing or invite code', hintText: 'XXXX-XXXX', errorText: _error),
            onChanged: (_) { if (_error != null) setState(() => _error = null); },
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: WpSpace.s),
          Text('The pairing code is on the sticker inside the WatchPack. Invite codes last 48 hours.',
              style: context.text.bodySmall),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: _submit, child: const Text('Link')),
        ],
      );
}

/// Lists the linked devices to switch between, plus "Link another device".
Future<void> showDevicePicker(BuildContext context, WidgetRef ref) async {
  final ids = ref.read(userProfileProvider).value?.deviceIds ?? const <String>[];
  final current = ref.read(deviceIdProvider);
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        for (final id in ids)
          ListTile(
            leading: const Icon(Symbols.phone_android_rounded),
            title: FutureBuilder(
              future: FirebaseFirestore.instance.collection('devices').doc(id).get(),
              builder: (_, s) => Text((s.data?.data()?['name'] as String?) ?? id),
            ),
            subtitle: Text(id == demoDeviceId ? '$id  ·  demo' : id),
            trailing: id == current ? const Icon(Symbols.check_rounded, color: WpColors.cyan) : null,
            onTap: () => Navigator.pop(c, id),
          ),
        ListTile(
          leading: const Icon(Symbols.link_rounded),
          title: const Text('Link another device'),
          onTap: () => Navigator.pop(c, '+link'),
        ),
        const SizedBox(height: WpSpace.s),
      ]),
    ),
  );
  if (choice == null || !context.mounted) return;
  if (choice == '+link') return showLinkDeviceDialog(context, ref);
  ref.read(selectedDeviceProvider.notifier).select(choice);
}
