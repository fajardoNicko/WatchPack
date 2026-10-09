# Guardian Pack — App & Backend Plan (the phone / cloud side)

> Receives the device's location, runs the "smart" logic (geofence, weather, earthquake),
> and pushes notifications to the parent's app. Code lives in [`../app/`](../app/).

---

## 1. Platform decision

The app features (custom geofencing, weather API, **scraping PHIVOLCS**, push
notifications) need real backend logic — so a pure no-code tool will hit a wall.

| Option | Device↔App | Custom logic (scrape/weather/geofence) | Push notifications | Effort | Verdict |
|--------|-----------|----------------------------------------|--------------------|--------|---------|
| **Firebase + Flutter** | ✅ REST/Firestore | ✅ **Cloud Functions** (scheduled) | ✅ **FCM** built in | Medium | **Recommended** — free tier covers this, one app codebase (Android+iOS), push is first-class |
| **Blynk (low-code IoT)** | ✅ very easy | ⚠️ limited — hard to scrape/geofence custom | ✅ basic | Low | Fast for tracking + buzzer demo, but F4–F6 fight the platform |
| **Custom Node.js + React Native** | ✅ | ✅ full control | ✅ (via FCM) | High | Most flexible, most work — overkill for a first build |

**Recommendation: Firebase.** You get: Firestore (store locations + config), Cloud
Functions (run the weather/quake watchers on a schedule + geofence check), FCM (push to
the app), and Auth (parent login) — all on one free tier. The parent app is a **Flutter**
app talking to Firebase.

> Decision #3 in [`05-roadmap.md`](05-roadmap.md#open-decisions).

---

## 2. Data model (Firestore-style)

```
devices/{deviceId}
  ownerUid, name, lastSeen, battery
  school:   { lat, lng, radius_m, name }        // parent sets this
  contacts: [ "+639XXXXXXXXX", ... ]            // emergency SMS list (also on device)
  buzz:     false                               // app sets true → device reads → false
  insideSchool: false                           // geofence state (prevents repeat alerts)

devices/{deviceId}/locations/{autoId}
  lat, lng, spd, ts                             // the tracking history / live map

users/{uid}
  fcmToken, deviceIds[]                          // where to send push notifications
```

---

## 3. The backend jobs

### (a) Ingest location  — HTTP function
Device `POST /api/location` → validate → write to `locations` + update `lastSeen`,
`battery`. Then run the **geofence check** (below).

### (b) Geofence: school arrival — F6
On each new location, compute distance to `school`:
```
d = haversine(loc, school)
was_inside = device.insideSchool
now_inside = d <= school.radius_m
if now_inside && !was_inside:   → push "Arrived at school", set insideSchool=true
if !now_inside && was_inside:   → (optional) push "Left school", set insideSchool=false
```
The `insideSchool` flag is what stops it firing every 30 s while the kid sits in class.
Use a radius of ~100–150 m and optionally require 2 consecutive fixes inside to debounce.

### (c) Weather watcher — F4  (scheduled, e.g. every 30 min)
- Source: **OpenWeatherMap** free API (`/weather?lat=&lon=`), keyed to the device's last
  location. (PAGASA has no clean public API; OWM is the pragmatic choice.)
- If condition is severe (heavy rain / thunderstorm / high wind) → push to parent.
- Debounce: don't re-push the same active condition.

### (d) Earthquake watcher — F5  (scheduled, e.g. every 5 min)
- **Primary (reliable): USGS API** — `earthquake.usgs.gov/fdsnws/event/1/query?format=geojson&minmagnitude=4&latitude=&longitude=&maxradiuskm=300`
  → clean JSON, filter to events near the device, near-real-time.
- **Local authority: PHIVOLCS** — no official API, so **scrape** the latest-events table
  from `earthquake.phivolcs.dost.gov.ph`. HTML tables change format occasionally, so wrap
  it in a try/catch and treat USGS as the dependable source, PHIVOLCS as the "local name"
  overlay.
- Track the **last event id/time seen** so each quake pushes once.

### (e) Buzz relay — F3
App sets `devices/{id}.buzz = true`. Device's `GET /api/command` returns it; the ingest/
command function clears it after the device acknowledges.

---

## 4. The parent app (Flutter) — screens

| Screen | Shows | Talks to |
|--------|-------|----------|
| **Map** | Live marker + recent trail (Life360 feel) | `locations` stream |
| **Alerts** | SOS, weather, earthquake, "arrived at school" feed | FCM + `alerts` |
| **Device** | Battery, last seen, **"Find device"** (buzzer) button | `buzz` flag |
| **Settings** | Set school (pick on map + radius), emergency contacts | `devices/{id}` |
| **Login** | Parent account | Firebase Auth |

Push notifications arrive via **FCM** whether or not the app is open — that's the whole
point of using it over polling on the phone.

---

## 5. Notes / gotchas
- **PHIVOLCS scraping is fragile** — build it defensively and keep USGS as the backbone.
- **API keys** (OpenWeatherMap, Firebase) live in backend config / env, **never** in the
  device firmware or committed to git.
- **Privacy:** this tracks a child's live location. Lock Firestore rules so only the
  parent's account can read their device. Worth stating plainly in the project writeup.
- Emergency SMS is sent **by the device**, not the backend — so it still works if Firebase
  or the phone's internet is down. Keep it that way; it's the safety net.
