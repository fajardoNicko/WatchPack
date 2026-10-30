# WatchPack — App Design Spec

> Source: the "WatchPack Interface" PDF (received 2026-10-08). This file turns those mockups
> into a build spec and records the design decisions we're making on top of them.
> **The product is now called WatchPack** ("Guardian Pack" was the working title; folder
> names stay for now).

Brief from Nicko: *follow their design but improve it. Premium, flat (no gradients), fast,
no visible delays, must not look auto-generated.*

---

## 1. Design system (what makes it look finished)

| Element | Decision |
|---------|----------|
| **Palette** | Navy `#0B2A55` (headers, nav), cyan `#3FB9D0` (accent, logo), red `#E24B4B` (alerts, route), near-white `#F4F6F9` (surfaces), ink `#14181F`, muted `#5B6472`. **Flat fills only, no gradients, no glow.** The mockup's cyan→blue gradients become solid navy headers with a thin cyan accent line. |
| **Type** | One family: **Inter** (bundled). Sizes: 28/22/17/15/13. Weight 600 for titles, 400 body. Tabular numbers for times/speeds. |
| **Shape** | Cards radius 16, buttons 12, chips 999. One shadow level (y2 blur8 at 6 %), nothing heavier. |
| **Spacing** | 8-pt grid. Screen gutter 16, card padding 16, list gap 12. |
| **Icons** | Google's **Material Symbols (outlined)** via `material_symbols_icons`, drawn at weight 300 — thin line icons, no fills, no tinted discs behind them (since 1.2; the rounded, filled icons on soft circles looked auto-generated). (Phosphor was the first pick but its Flutter package is abandoned and no longer compiles.) Zone icons (home/school/park) come from the same set. |
| **Map style** | Light grey base like the mockup (CartoDB Positron tiles). Route in red 4 px. Live marker = the child's photo (or initials) in a white pin, "Last seen 5 min ago" under it; it pulses while moving, turns red in SOS and fades when offline. |
| **Motion** | Only colour changes animate (an SOS card turning red). Tabs, cards and lists appear without fades or slides (removed in 1.2 — they felt jittery). The pin glides between fixes and keeps moving at the reported speed until the next one (`data/estimate.dart`). |
| **Loading** | Never a spinner on first paint: cached last state renders instantly, then updates. Skeleton rows for lists. |
| **Dark mode** | Same tokens re-mapped; ship it from day one (cheap in Flutter, expensive later). The accent (buttons, selected states, brand-coloured icons) is navy in light mode and cyan in dark mode — `context.wp.accent`, never `WpColors.navy` on a surface. |

## 2. Screens (from the PDF, with improvements)

### Splash
Navy background, logo centred, ~600 ms max, then straight to Map. No animation beyond a fade.

### Map Pin (home tab)
- Full-bleed map, header overlay with logo + "WatchPack".
- Live marker + today's trail, school/home zone circles drawn on the map.
- Bottom card (draggable sheet): **Ivy · Moving 4 km/h · Battery 99 % · Updated just now**, with status dot (moving / idle / offline / SOS).
- Actions row: **History** (jumps to Trip History for today), **Find device** (buzzer — the mockup's centre logo button becomes this, since it's a core feature), **Share** (share a maps link).
- Improvement: SOS state takes over the card in red with the last location and a "Call Ivy's contacts" button.

### Trip History
- Date strip with ‹ › and a date picker. Default today.
- Map with the day's route; scrubber under it moves a "selected point" marker along the trip (the mockup's slider).
- Timeline: segments auto-derived from the fixes — *moving* (start→stop, duration, distance) and *idle* (stopped ≥ 3 min). Names like "Home to Terminal" come from zone entry/exit; otherwise "Unknown stop".
- Trip Summary: total distance, duration, average speed.

### Notifications
Two parts, like the mockup:
1. **Safety zones** — list of zones (name, icon, radius, which device), each with enable toggle, edit, delete. **Create new safety zone** → pick on map + radius slider (100–1000 m) + name + icon.
2. **System triggers** — Low battery (threshold %), Signal loss (minutes offline), plus two the mockup implies: **SOS** (always on, not toggleable) and **Off-route** (deviation from the usual path; Phase 2).
- Improvement: add an **Alert feed** tab at the top (chronological list of everything that fired), since the mockup has nowhere to see past alerts in the app except SMS.

### Settings & Controls
- Family contacts carousel (avatars) → these are the **emergency SMS contacts** stored on the device too.
- Device linking (scan the device's QR / enter its ID), Parental account (invite another parent by email).
- Manage: Account profile, Security & privacy, Customization (theme, units).

### "WatchPack Updates" (page 1 of the PDF)
This is an **SMS thread**, not an app screen: the device's SIM texts the parent directly
(departure, off-route, recovery, arrived home). It works with no internet and no app.
The app shows the same events in the Alert feed; the SMS text format follows the mockup:
`[3:05 PM, 12 Oct] WatchPack - Ivy: (Departure) Ivy has exited the School Zone and is heading Home.`

## 3. Build decisions

| Decision | Choice | Why |
|----------|--------|-----|
| Framework | **Flutter**, Android first | Locked earlier; true native feel, dark mode and animations are cheap |
| State | **Riverpod** + Firestore streams | Live updates with no manual refresh; small, testable |
| Map | **flutter_map** + CartoDB Positron tiles | No Google Maps API key / billing; matches the light map in the design; fast. Switch to Google Maps later only if needed |
| Data | Firestore (device doc + `locations` subcollection + `zones` + `alerts`) | Per `04-app-backend.md` |
| Push | FCM via Cloud Functions | Alerts arrive with the app closed |
| Offline | Firestore persistence on; last map state cached | Instant first paint, works on a bad connection |
| Perf rules | Location list paginated by day; trail simplified (Douglas-Peucker) before drawing; marker updates via `AnimatedPositioned`, never full rebuilds | "Does not delay" |

## 4. Milestones

1. **M1 — Map with a fake device.** Firebase project, Flutter app skeleton (4 tabs, design system), Map Pin showing a location I write into Firestore by hand. *No hardware needed.*
2. **M2 — Trip History** from fake fixes (I'll generate a realistic school-run day).
3. **M3 — Zones + alert feed + push.** Cloud Function geofence, FCM to the phone.
4. **M4 — Settings:** contacts, device linking, second parent.
5. **M5 — Real device.** Firmware `05_data_post` sends real fixes; everything above lights up.

## 5. Assets needed from the design team
- Logo as **SVG** (or PNG ≥ 1024 px, transparent): the "W" mark and the wordmark separately.
- Zone icons if they have specific ones (otherwise I use the icon set).
- The PDF itself, saved to `docs/design/WatchPack-Interface.pdf`.
