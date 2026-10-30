import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../auth/auth.dart';
import '../../data/linking.dart';
import '../../data/models.dart';
import '../../data/repo.dart';
import '../../theme/theme_mode.dart';
import '../../theme/tokens.dart';
import '../../util/format.dart';
import '../widgets.dart';
import 'link_device_screen.dart';
import 'parents_screen.dart';
import 'security_screen.dart';

/// Settings & Controls tab.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final device = ref.watch(deviceProvider).value;
    final profile = ref.watch(userProfileProvider).value;
    final mode = ref.watch(themeModeProvider);
    final parents = ref.watch(membersProvider).value?.length ?? 0;
    ref.watch(memberSyncProvider);
    final t = context.text;

    return Scaffold(
      appBar: const WpHeader(title: 'Settings & controls', subtitle: 'Parental dashboard'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(WpSpace.l, WpSpace.s, WpSpace.l, WpSpace.xl),
        children: [
          const SectionTitle('Family contacts'),
          SizedBox(
            height: 96,
            child: device == null
                ? const Row(children: [Skeleton(height: 92, width: 72), SizedBox(width: WpSpace.m), Skeleton(height: 92, width: 72)])
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: device.contacts.length + 1,
                    separatorBuilder: (_, _) => const SizedBox(width: WpSpace.l),
                    itemBuilder: (_, i) => i == device.contacts.length
                        ? _AddContact(onTap: () => _editContact(context, ref, device, null))
                        : _ContactTile(
                            device.contacts[i],
                            onPhoto: () => _contactPhoto(context, ref, device, i),
                            onEdit: () => _editContact(context, ref, device, i),
                          ),
                  ),
          ),
          const SizedBox(height: WpSpace.m),
          Row(children: [
            Expanded(
              child: _BigCard(
                icon: Symbols.phone_android,
                title: 'Device linking',
                body: device == null ? 'Link a physical WatchPack device' : 'Showing ${device.name} (${device.id})',
                action: (profile?.deviceIds.length ?? 0) > 1 ? 'Switch' : 'Link another',
                onTap: () => showDevicePicker(context, ref),
              ),
            ),
            const SizedBox(width: WpSpace.m),
            Expanded(
              child: _BigCard(
                icon: Symbols.groups,
                title: 'Parental account',
                body: parents > 1 ? '$parents parents can see ${device?.name ?? 'this device'}' : 'Add another parent for shared monitoring',
                action: parents > 1 ? 'Manage' : 'Add parent',
                onTap: () => ParentsScreen.open(context),
              ),
            ),
          ]),
          if (device != null) ...[
            const SectionTitle('Child'),
            WpCard(
              padding: EdgeInsets.zero,
              child: ListTile(
                leading: Avatar(name: device.name, photo: device.photo, size: 44, onTap: () => _childPhoto(context, ref, device)),
                title: Text(device.name, style: t.bodyMedium),
                subtitle: Text('WatchPack ${device.id}', style: t.bodySmall),
                trailing: Icon(Symbols.edit, size: 18, color: context.wp.muted),
                onTap: () => _editChildName(context, ref, device),
              ),
            ),
          ],
          const SectionTitle('Account'),
          WpCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              ListTile(
                leading: Avatar(
                  name: profile?.displayName ?? '',
                  photo: profile?.photo,
                  size: 44,
                  onTap: profile == null ? null : () => _parentPhoto(context, ref, profile),
                ),
                title: Text(profile?.displayName.isNotEmpty == true ? profile!.displayName : 'Parent', style: t.bodyMedium),
                subtitle: Text(profile?.email ?? '', style: t.bodySmall),
                trailing: Icon(Symbols.edit, size: 18, color: context.wp.muted),
                onTap: profile == null ? null : () => _editName(context, ref, profile),
              ),
              Divider(color: context.wp.line),
              _Row(icon: Symbols.lock, title: 'Security & privacy', onTap: () => SecurityScreen.open(context)),
              Divider(color: context.wp.line),
              _Row(
                icon: Symbols.palette,
                title: 'Appearance',
                trailing: Text(switch (mode) { ThemeMode.system => 'System', ThemeMode.light => 'Light', ThemeMode.dark => 'Dark' }, style: t.bodySmall),
                onTap: () => _pickTheme(context, ref, mode),
              ),
              Divider(color: context.wp.line),
              _Row(icon: Symbols.logout, title: 'Sign out', onTap: () => _confirmSignOut(context, ref)),
            ]),
          ),
          const SizedBox(height: WpSpace.xl),
          Center(child: Text('WatchPack 1.1  ·  device ${device?.id ?? '—'}', style: t.labelSmall)),
        ],
      ),
    );
  }

  // ---- photos ----
  Future<void> _parentPhoto(BuildContext context, WidgetRef ref, UserProfile p) async {
    final r = await pickAvatarSheet(context, hasPhoto: p.photo != null);
    if (r == null) return;
    await ref.read(authActionsProvider).setPhoto(p.uid, r.isEmpty ? null : r);
  }

  Future<void> _contactPhoto(BuildContext context, WidgetRef ref, Device d, int i) async {
    final c = d.contacts[i];
    final r = await pickAvatarSheet(context, hasPhoto: c.photo != null);
    if (r == null) return;
    final list = [...d.contacts];
    list[i] = r.isEmpty ? c.copyWith(clearPhoto: true) : c.copyWith(photo: r);
    await ref.read(deviceActionsProvider).updateContacts(list, cmdId: d.cmdId);
  }

  // ---- contacts ----
  Future<void> _editContact(BuildContext context, WidgetRef ref, Device d, int? index) async {
    final existing = index == null ? null : d.contacts[index];
    final name = TextEditingController(text: existing?.name ?? '');
    final phone = TextEditingController(text: existing?.phone ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(existing == null ? 'Add family contact' : 'Edit contact'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, autofocus: existing == null, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Name')),
          const SizedBox(height: WpSpace.m),
          TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Mobile number', hintText: '+639XXXXXXXXX')),
          const SizedBox(height: WpSpace.s),
          Text('Gets the SOS text from the device.', style: context.text.bodySmall),
        ]),
        actions: [
          if (existing != null)
            TextButton(style: TextButton.styleFrom(foregroundColor: WpColors.red), onPressed: () => Navigator.pop(c, 'delete'), child: const Text('Remove')),
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, 'save'), child: const Text('Save')),
        ],
      ),
    );
    if (result == null) return;
    final list = [...d.contacts];
    if (result == 'delete') {
      list.removeAt(index!);
    } else {
      final n = name.text.trim(), p = normalizePhPhone(phone.text);
      if (n.isEmpty || p == null) {
        if (context.mounted) showNote(context, 'Enter a name and a valid PH mobile number (+639…).');
        return;
      }
      final c = Contact(name: n, phone: p, photo: existing?.photo);
      if (index == null) {
        list.add(c);
      } else {
        list[index] = c;
      }
    }
    await ref.read(deviceActionsProvider).updateContacts(list, cmdId: d.cmdId);
    if (d.cmdId != null && context.mounted) {
      showNote(context, '${d.name}\'s WatchPack picks up the new numbers within a minute.');
    }
  }

  Future<void> _editChildName(BuildContext context, WidgetRef ref, Device d) async {
    if (d.id == demoDeviceId) {
      showNote(context, 'Every new account shares the demo device, so it keeps its name.');
      return;
    }
    final ctl = TextEditingController(text: d.name);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Child\'s name'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          maxLength: 24,
          decoration: const InputDecoration(helperText: 'Shown on the map and in every alert'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
        ],
      ),
    );
    final name = ctl.text.trim();
    if (ok == true && name.isNotEmpty && name != d.name) await ref.read(deviceActionsProvider).rename(name);
  }

  Future<void> _childPhoto(BuildContext context, WidgetRef ref, Device d) async {
    final r = await pickAvatarSheet(context, hasPhoto: d.photo != null);
    if (r == null) return;
    await ref.read(deviceActionsProvider).setChildPhoto(r.isEmpty ? null : r);
  }

  Future<void> _editName(BuildContext context, WidgetRef ref, UserProfile p) async {
    final ctl = TextEditingController(text: p.displayName);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Your name'),
        content: TextField(controller: ctl, autofocus: true, textCapitalization: TextCapitalization.words),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok == true && ctl.text.trim().isNotEmpty) await ref.read(authActionsProvider).setDisplayName(p.uid, ctl.text);
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You will stop receiving alerts on this phone until you sign in again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Sign out')),
        ],
      ),
    );
    if (ok == true) await ref.read(authActionsProvider).signOut();
  }

  Future<void> _pickTheme(BuildContext context, WidgetRef ref, ThemeMode current) async {
    final m = await showModalBottomSheet<ThemeMode>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final (mode, label) in const [(ThemeMode.system, 'Match system'), (ThemeMode.light, 'Light'), (ThemeMode.dark, 'Dark')])
            ListTile(
              title: Text(label),
              trailing: mode == current ? Icon(Symbols.check, color: c.wp.accent, size: 20) : null,
              onTap: () => Navigator.pop(c, mode),
            ),
          const SizedBox(height: WpSpace.s),
        ]),
      ),
    );
    if (m != null) ref.read(themeModeProvider.notifier).set(m);
  }
}

class _ContactTile extends StatelessWidget {
  const _ContactTile(this.c, {required this.onPhoto, required this.onEdit});
  final Contact c;
  final VoidCallback onPhoto, onEdit;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 72,
        child: Column(children: [
          Avatar(name: c.name, photo: c.photo, size: 60, onTap: onPhoto),
          const SizedBox(height: WpSpace.xs),
          GestureDetector(
            onTap: onEdit,
            behavior: HitTestBehavior.opaque,
            child: Text(c.name, style: context.text.labelMedium, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
          ),
        ]),
      );
}

class _AddContact extends StatelessWidget {
  const _AddContact({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 72,
          child: Column(children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: context.wp.line, width: 1.5)),
              child: Icon(Symbols.add, color: context.wp.muted),
            ),
            const SizedBox(height: WpSpace.xs),
            Text('Add', style: context.text.labelMedium),
          ]),
        ),
      );
}

class _BigCard extends StatelessWidget {
  const _BigCard({required this.icon, required this.title, required this.body, required this.action, required this.onTap});
  final IconData icon;
  final String title, body, action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => WpCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          IconDisc(icon, size: 44),
          const SizedBox(height: WpSpace.m),
          Text(title, style: context.text.titleSmall),
          const SizedBox(height: 2),
          Text(body, style: context.text.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: WpSpace.m),
          SizedBox(width: double.infinity, child: OutlinedButton(onPressed: onTap, child: Text(action))),
        ]),
      );
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.title, required this.onTap, this.trailing});
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon),
        title: Text(title, style: context.text.bodyMedium),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          ?trailing,
          const SizedBox(width: WpSpace.s),
          Icon(Symbols.chevron_right, size: 18, color: context.wp.muted),
        ]),
        onTap: onTap,
      );
}
