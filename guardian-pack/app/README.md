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
  backend/          Firebase Cloud Functions (milestone 3)
```

## Firebase
Project **watchpack-f9483**, Android app `ph.watchpack.app`. Firestore in `asia-southeast1`.
**Security rules are live** (`firestore.rules`, deployed 2026-10-08 18:51): a parent can only read
devices listed in `users/{uid}.deviceIds`; locations and alerts are read-only for the app.
Redeploy with `firebase deploy --only firestore:rules`.
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
- `npm run watch` — the same every 5 minutes.
Needs `backend/serviceAccount.json` (Firebase console → Project settings → Service accounts →
Generate new private key). Git-ignored. Run it on the laptop or as a scheduled task / GitHub Action.

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
