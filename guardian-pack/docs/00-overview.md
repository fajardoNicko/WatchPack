# Guardian Pack — Project Overview

> A backpack (or belt/bag) attachment that lets a parent track a child in real time,
> get an SMS if there's an emergency, find the bag with a buzzer, and receive weather
> + earthquake safety alerts — plus an automatic "arrived at school" notification.

**Project name:** *Guardian Pack* (working title — rename freely; just update this file
and the folder slug).

---

## 1. What it does (features → who triggers them)

| # | Feature | Lives on | Triggered by | Notes |
|---|---------|----------|--------------|-------|
| F1 | **Live GPS tracking** (Life360-style map) | Device → Backend → App | Continuous | Device streams lat/lng on an interval |
| F2 | **Emergency SMS** to contacts | Device (cellular) | Button press on device *(or backend command)* | Works even with no internet — pure SMS |
| F3 | **"Find my device" buzzer** | Device | Parent taps in app → Backend → Device | Device needs to receive a command |
| F4 | **Weather alerts** | Backend → App | Weather API (scheduled) | e.g. heavy rain / storm near child |
| F5 | **Earthquake alerts** | Backend → App | PHIVOLCS / USGS (scheduled) | Local seismic events |
| F6 | **School-arrival notification** | Backend → App | Geofence: device enters school radius | Parent sets school location + radius |

Two of these (F2 emergency SMS, F3 buzzer) are **safety-critical** and should degrade
gracefully — F2 must work even if the internet/app is down.

---

## 2. System architecture

```
                   ┌────────────────────────────────────────────┐
                   │              WEARABLE DEVICE                 │
                   │            (backpack attachment)             │
                   │                                              │
                   │   ┌──────┐    ┌────────────┐    ┌────────┐   │
                   │   │ GPS  │    │  Cellular  │    │ Buzzer │   │
                   │   │module│    │ SMS + data │    │        │   │
                   │   └──┬───┘    └─────┬──────┘    └───┬────┘   │
                   │      │              │               │        │
                   │      └───── MCU (microcontroller) ──┘        │
                   │              │      │      ┌─────────┐       │
                   │      [SOS button]   │      │ battery │       │
                   └─────────────────────┼──────┴─────────┴───────┘
                                         │
                (a) EMERGENCY SMS  ──────┼──────►  Emergency contacts' phones
                    (no internet needed) │
                                         │
                (b) mobile DATA (HTTP or MQTT over the cellular link)
                                         │
                                         ▼
                     ┌───────────────────────────────────┐
                     │              BACKEND               │
                     │  • store & serve location history  │◄── Weather API
                     │  • geofence check (school arrival)  │◄── PHIVOLCS / USGS
                     │  • earthquake + weather watcher     │
                     │  • send push notifications (FCM)    │
                     │  • relay "buzz" command to device   │
                     └──────────────────┬─────────────────┘
                                        │  push notification
                                        ▼
                     ┌───────────────────────────────────┐
                     │           PARENT'S APP             │
                     │  • live map (Life360 style)         │
                     │  • alerts: SOS / weather / quake    │
                     │  • "Find device" button (buzzer)    │
                     │  • set child's school + radius      │
                     └───────────────────────────────────┘
```

**The one thing to internalize:** the device fundamentally needs a **cellular data
connection** for live tracking (WiFi only works near home — useless on the road). The
same cellular module also sends the emergency SMS. So the cellular module is the heart
of the device.

---

## 3. Scope — MVP first, then extend

**Phase 1 (MVP): prove the device can be tracked.**
- Device reads GPS, sends location to backend over cellular, backend shows it on a map.
- SOS button sends an SMS.
- Buzzer beeps on command.

**Phase 2: the "smart" app features.**
- School geofence → arrival push notification.
- Weather + earthquake watchers → push notifications.

**Phase 3: polish.**
- Battery optimization, enclosure, charging, config from the app (set school, contacts).

Don't build Phase 2 until Phase 1's device→backend→map loop is rock solid.

---

## 4. Success criteria (how we know it works)

- [ ] Parent opens app, sees the bag's location update within ~30 s of it moving.
- [ ] Pressing SOS delivers an SMS to at least one contact within ~15 s.
- [ ] Tapping "Find device" makes the buzzer sound within ~10 s.
- [ ] Walking into the school radius fires a push notification once (not repeatedly).
- [ ] A real PHIVOLCS/USGS quake near the device produces a push within a few minutes.

---

## 5. Core decisions — ✅ locked (2026-07-02)

The three big forks are decided (details in [`05-roadmap.md`](05-roadmap.md#open-decisions)):

- **Microcontroller:** ESP32 (3 hardware UARTs, 3.3 V, WiFi+BLE).
- **Cellular module:** 4G with **built-in GPS** (SIM7600 / A7670) — one module for
  GPS + data + SMS, so no separate GPS part.
- **App/backend:** Firebase + Flutter (Firestore, Cloud Functions, FCM push, Auth).

**As built (parts arrived 2026-10-05):** one **LilyGO T-A7670G + L76K GPS** board (V1.4).
The A7670G modem has **no GPS inside** — GPS comes from the board's separate L76K module.
Wiring: [`lilygo-wiring.html`](lilygo-wiring.html).

Next up: software bring-up in [`03-firmware.md`](03-firmware.md#1-bring-up-order-do-not-skip)
(`00_hello_board` first — no soldering needed until Phase 2).
