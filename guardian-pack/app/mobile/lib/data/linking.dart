import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth.dart';
import 'repo.dart';

/// Linking a parent to a device, and who else can see it.
///
/// linkcodes/{code}: { deviceId, kind, createdBy?, createdByName?, expiresAt? }
///   kind 'device' — the permanent pairing code on the WatchPack's sticker (provision.mjs)
///   kind 'invite' — one-time code a linked parent shares with another parent, 48 h
/// A profile can only gain a device id together with a code for it (firestore.rules).
///
/// devices/{id}/members/{uid}: { name, email, photo?, joinedAt } — each parent writes
/// their own entry, so the others can see who has access.

const demoDeviceId = 'wp-demo-ivy';
const inviteLifetime = Duration(hours: 48);
const _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';     // no 0/O or 1/I to misread

String newCode([Random? rng]) {
  final r = rng ?? Random.secure();
  return List.generate(8, (_) => _alphabet[r.nextInt(_alphabet.length)]).join();
}

/// "abcd efgh", "ABCD-EFGH" → "ABCDEFGH"; null if it can't be a code.
String? normalizeCode(String raw) {
  final s = raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  return RegExp('^[$_alphabet]{8}\$').hasMatch(s) ? s : null;
}

String fmtCode(String code) => code.length == 8 ? '${code.substring(0, 4)}-${code.substring(4)}' : code;

class LinkError implements Exception {
  const LinkError(this.message);
  final String message;
  @override
  String toString() => message;
}

class Member {
  const Member({required this.uid, required this.name, required this.email, this.photo, this.joinedAt});
  final String uid, name, email;
  final String? photo;
  final DateTime? joinedAt;

  factory Member.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const {};
    return Member(
      uid: d.id,
      name: (m['name'] as String?) ?? '',
      email: (m['email'] as String?) ?? '',
      photo: m['photo'] as String?,
      joinedAt: (m['joinedAt'] as Timestamp?)?.toDate(),
    );
  }
}

class Invite {
  const Invite({required this.code, required this.deviceId, required this.expiresAt});
  final String code, deviceId;
  final DateTime expiresAt;
  bool get expired => expiresAt.isBefore(DateTime.now());
}

final _db = FirebaseFirestore.instance;

/// Parents who can see the selected device, earliest first.
final membersProvider = StreamProvider<List<Member>>((ref) {
  final id = ref.watch(deviceIdProvider);
  if (id == null) return Stream.value(const []);
  return _db.collection('devices').doc(id).collection('members').snapshots().map((q) {
    final list = q.docs.map(Member.fromDoc).toList();
    list.sort((a, b) => (a.joinedAt ?? DateTime(2100)).compareTo(b.joinedAt ?? DateTime(2100)));
    return list;
  });
});

/// Invites I made for the selected device that nobody has used yet.
final myInvitesProvider = StreamProvider<List<Invite>>((ref) {
  final uid = ref.watch(authStateProvider).value?.uid;
  final id = ref.watch(deviceIdProvider);
  if (uid == null || id == null) return Stream.value(const []);
  return _db
      .collection('linkcodes')
      .where('createdBy', isEqualTo: uid)
      .where('deviceId', isEqualTo: id)
      .snapshots()
      .map((q) => [
            for (final d in q.docs)
              if (d.data()['expiresAt'] is Timestamp)
                Invite(code: d.id, deviceId: id, expiresAt: (d.data()['expiresAt'] as Timestamp).toDate()),
          ]..sort((a, b) => b.expiresAt.compareTo(a.expiresAt)));
});

/// Keeps my members entry on the selected device current (name, photo). Watched by
/// Settings, so parents who linked before members existed show up too.
final memberSyncProvider = FutureProvider<void>((ref) async {
  final profile = ref.watch(userProfileProvider).value;
  final id = ref.watch(deviceIdProvider);
  if (profile == null || id == null) return;
  await ref.read(linkActionsProvider).ensureMember(id, profile);
});

class LinkActions {
  LinkActions(this._ref);
  final Ref _ref;

  UserProfile get _me {
    final p = _ref.read(userProfileProvider).value;
    if (p == null) throw const LinkError('Still loading your account. Try again in a moment.');
    return p;
  }

  DocumentReference<Map<String, dynamic>> _member(String deviceId, String uid) =>
      _db.collection('devices').doc(deviceId).collection('members').doc(uid);

  /// Links the device behind a pairing or invite code and switches the app to it.
  /// Returns the device id.
  Future<String> linkWithCode(String raw) async {
    final me = _me;
    if (raw.trim().toLowerCase() == demoDeviceId) return _link(me, demoDeviceId, null);

    final code = normalizeCode(raw);
    if (code == null) throw const LinkError('Codes are 8 letters and numbers, like K7QM-2XPA.');
    final snap = await _db.collection('linkcodes').doc(code).get();
    final m = snap.data();
    if (m == null) throw const LinkError('No WatchPack uses that code. Check it and try again.');
    final expires = (m['expiresAt'] as Timestamp?)?.toDate();
    if (expires != null && expires.isBefore(DateTime.now())) {
      throw const LinkError('This invite has expired. Ask for a new one.');
    }
    final deviceId = m['deviceId'] as String;
    return _link(me, deviceId, code, retireInvite: m['kind'] == 'invite' ? snap.reference : null);
  }

  /// One atomic write: the device on my profile, me on its member list, and the
  /// invite used up (the rules check each against the batch's result).
  Future<String> _link(UserProfile me, String deviceId, String? code, {DocumentReference? retireInvite}) async {
    if (!me.deviceIds.contains(deviceId)) {
      final batch = _db.batch()
        ..set(_db.collection('users').doc(me.uid), {
          'deviceIds': FieldValue.arrayUnion([deviceId]),
          'linkCode': ?code,
        }, SetOptions(merge: true));
      if (deviceId != demoDeviceId) batch.set(_member(deviceId, me.uid), _memberFields(me, joined: true));
      if (retireInvite != null) batch.delete(retireInvite);
      await batch.commit();
    }
    _ref.read(selectedDeviceProvider.notifier).select(deviceId);
    return deviceId;
  }

  /// Removes the device from my account. The others keep their access. Not awaited
  /// by the UI past the local write: the cache updates at once, the server follows.
  Future<void> unlink(String deviceId) {
    final me = _me;
    if (_ref.read(selectedDeviceProvider) == deviceId) _ref.read(selectedDeviceProvider.notifier).clear();
    final batch = _db.batch()..update(_db.collection('users').doc(me.uid), {'deviceIds': FieldValue.arrayRemove([deviceId])});
    if (deviceId != demoDeviceId) batch.delete(_member(deviceId, me.uid));
    return batch.commit();
  }

  Map<String, Object> _memberFields(UserProfile me, {bool joined = false}) => {
        'name': me.displayName,
        'email': me.email,
        'photo': ?me.photo,
        if (joined) 'joinedAt': FieldValue.serverTimestamp(),
      };

  /// The demo device is shared by every new account, so nobody is listed on it.
  Future<void> ensureMember(String deviceId, UserProfile me) async {
    if (deviceId == demoDeviceId) return;
    final ref = _member(deviceId, me.uid);
    final cur = (await ref.get()).data();
    if (cur == null) {
      await ref.set(_memberFields(me, joined: true));
    } else if (cur['name'] != me.displayName || cur['email'] != me.email || cur['photo'] != me.photo) {
      await ref.update({'name': me.displayName, 'email': me.email, 'photo': me.photo ?? FieldValue.delete()});
    }
  }

  /// Makes a one-time invite for [deviceId]. Waits a few seconds for the server, then
  /// trusts the local write (it syncs when the network catches up) so the code shows
  /// without a long pause. A random 8-character code clashing is not a real risk.
  Future<Invite> createInvite(String deviceId) async {
    final me = _me;
    final expires = DateTime.now().add(inviteLifetime);
    final code = newCode();
    await _db.collection('linkcodes').doc(code).set({
      'deviceId': deviceId,
      'kind': 'invite',
      'createdBy': me.uid,
      'createdByName': me.displayName,
      'expiresAt': Timestamp.fromDate(expires),
    }).timeout(const Duration(seconds: 4), onTimeout: () {});
    return Invite(code: code, deviceId: deviceId, expiresAt: expires);
  }

  Future<void> cancelInvite(String code) => _db.collection('linkcodes').doc(code).delete();

  /// Everything of mine outside my profile: member entries and open invites.
  Future<void> forgetMe() async {
    final me = _me;
    for (final id in me.deviceIds) {
      await _member(id, me.uid).delete().catchError((_) {});
    }
    final invites = await _db.collection('linkcodes').where('createdBy', isEqualTo: me.uid).get();
    for (final d in invites.docs) {
      await d.reference.delete();
    }
  }
}

final linkActionsProvider = Provider<LinkActions>(LinkActions.new);
