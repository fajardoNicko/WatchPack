# WatchPack — App & Backend

Companion app (parent's phone) + backend logic. Plan: [`../docs/04-app-backend.md`](../docs/04-app-backend.md).
Design spec: [`../docs/06-app-design.md`](../docs/06-app-design.md).

```
app/
  mobile/           Flutter app (Android first)  — see mobile/README.md
    lib/theme/      tokens, ThemeData, theme-mode persistence
    lib/data/       Firestore models, Riverpod providers, trip maths
    lib/ui/         shell + Map Pin / Trip History / Notification / Settings
  tools/
    seed_demo.mjs   writes a realistic demo day for device `wp-demo-ivy` into Firestore
  backend/          Node + Admin SDK watcher on the laptop (alerts, push) — no Cloud Functions
```

## Firebase
Project **watchpack-f9483**, Android app `ph.watchpack.app`. Firestore in `asia-southeast1`.
**Security rules are live** (`firestore.rules`, last deployed 2026-10-18): a parent can only read
devices listed in `users/{uid}.deviceIds`, and that list only grows with a link code (below);
locations and alerts are read-only for the app. Redeploy with `firebase deploy --only firestore:rules`.

## Linking a device, second parents
- Every real device has a permanent **pairing code** (8 characters, `XXXX-XXXX`) made by
  `npm run provision` and printed for the sticker (re-running prints the same code). Keep it
  out of the repo — anyone with it can see the device.
- A linked parent can make a one-time **invite code** (Settings → Parental account → Invite a
  parent, valid 48 h) and share it. The other parent signs up and enters it under Settings →
  Device linking. Linking, the member entry and using up the invite are one batch write.
- The device id alone is no longer enough to link. The demo device `wp-demo-ivy` is the only
  exception (every new account starts on it; "Look around with the demo device").
- Security & privacy: change password, unlink a device, delete the account.
- Family contacts edited in the app are mirrored to the device's mailbox
  (`cmdbox/<secret>.contacts`); the `05_cloud` firmware texts those numbers on SOS and falls
  back to `SOS_CONTACTS` in `secrets.h` until the app has sent any.
`google-services.json` and `firebase_options.dart` are git-ignored; regenerate with
`flutterfire configure --project=watchpack-f9483` if missing.

> `tools/seed_demo.mjs` wrote unauthenticated and **no longer works** under the rules. Next time
> it's needed, run it with the Admin SDK (service-account key, git-ignored) or temporarily
> relax the rules.

## Demo account
`demo@watchpack.app` / `watchpack-demo-2026` — linked to device `wp-demo-ivy`. Recreate or re-link with
`node tools/create_demo_account.mjs`. Re-seed the demo day with `powershell -File tools/seed.ps1`
(opens the rules for ~1 min, then restores them).

## Backend (`backend/`)
Node + Firebase Admin SDK, no Cloud Functions needed (so no Blaze plan yet).
- `npm run scrape` — parse PHIVOLCS latest earthquakes (no credentials needed).
- `npm run quakes` — one pass: store quakes (48 h), alert devices near ≥M4.0 events, push to parents.
- `npm run watch` — the live watcher for real devices: SOS, zone enter/exit, **off-route**,
  low battery, signal loss / back online, quakes every 5 min and **severe weather** every 15 min.
  Must be running for push notifications.
  - Off-route (`src/routes.mjs`): learns ~220 m cells the device was in on 2+ different days in
    the last 14; alerts when it's 440 m+ from all of them for two fixes in a row, outside every
    zone. Needs 3 days of history first; today's detour never counts as "usual".
  - Weather (`src/weather.mjs`, Open-Meteo, no key): thunderstorm, ≥7.5 mm/h rain or ≥62 km/h
    gusts now or within the hour; once per kind per 3 h. Only a ~10 km rounded position is sent.
    `node src/weather.mjs 14.6 121.0` prints what it sees for a spot.
- `npm run provision -- <deviceId> <name> <parentEmail>` — registers a device, prints the
  `secrets.h` lines and the pairing code.
Needs `backend/serviceAccount.json` (Firebase console → Project settings → Service accounts →
Generate new private key). Git-ignored. Run it on the laptop or as a scheduled task / GitHub Action.

## Status (2026-10-18)
Feature-complete for the demo. Added: pairing / invite codes, Parental account (parents list,
invites), Security & privacy, editable battery and signal-loss thresholds, severe-weather and
off-route alerts, SOS card (red, *Call family*, *Directions*), share sheet, mobile-signal bars,
queued "Find device" that can be cancelled, family contacts synced to the device, push
notifications that open the right device and tab, unread badge on Notification, alert details
with a map. Still to field-test on the board: GPS fix, SMS to app-edited contacts.

## Status (2026-10-09)
Added: demo account, breathing splash + skeleton first load, app icon (placeholder W mark until the
real logo file arrives), entrance/tab animations, profile/contact/child photos (stored as 256 px
base64 JPEG in Firestore — no Cloud Storage needed), family-contact editor, PHIVOLCS quake layer on
the map, FCM push registration (`users/{uid}.fcmTokens`), backend quake watcher.

## Status (end of 2026-10-08)
Built and running on the phone: sign-in / create account (email + password), demo device auto-linked
on sign-up, Map Pin (live marker, trail, zones, status card, Find device, Share), Trip History
(day picker, route scrubber, timeline, summary), Notifications (zone list with toggle/edit/delete,
**zone editor**, system triggers, alert feed), Settings (contacts, device linking by ID, account,
appearance, sign out). Not built: push notifications (needs Blaze plan), contact editing,
second-parent invites, backend Cloud Functions. A full requirements pass is expected next session.

## Build & run
Flutter SDK is at `C:\dev\flutter`. Android SDK via Android Studio.

```
cd app/mobile
flutter run                 # phone plugged in with USB debugging, or an emulator
flutter build apk --debug   # APK at build/app/outputs/flutter-apk/app-debug.apk
node ../tools/seed_demo.mjs # refresh the demo data (needs test-mode rules)
```

## Milestones
See `docs/06-app-design.md` §4. M1 (map + demo device) built 2026-10-08.
