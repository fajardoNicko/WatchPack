# Guardian Pack — Roadmap, Open Decisions & Risks

---

## Open decisions (lock these first — everything downstream depends on them)

| # | Decision | Chosen | Status |
|---|----------|--------|--------|
| D1 | **Microcontroller** | **ESP32** (3 UARTs, 3.3 V, WiFi+BLE, TLS) | ✅ **locked** |
| D2 | **Cellular module** | **4G with built-in GPS (SIM7600 / A7670)** — no separate GPS. *As bought: LilyGO T-A7670G — the A7670G has no GPS inside, so GPS is the board's L76K module on its own UART.* | ✅ **locked** |
| D3 | **App/backend platform** | **Firebase + Flutter** (Firestore + Functions + FCM + Auth) | ✅ **locked** |
| D4 | Earthquake source | Both — USGS reliable backbone, PHIVOLCS local overlay | ✅ resolved |
| D5 | Device downlink (buzz) | Polling for MVP, MQTT later | ✅ resolved |

**All core decisions locked (2026-07-02).** The build is: **ESP32 + SIM7600/A7670 (4G+GPS)
+ Firebase/Flutter.** BOM ([`01-hardware.md`](01-hardware.md)) and wiring
([`02-wiring.md §B`](02-wiring.md#b-esp32-version-recommended)) are finalized to this stack.

---

## Milestones

### Phase 1 — Device can be tracked (MVP)
- [x] D1–D3 locked (ESP32 + 4G/GPS module + Firebase/Flutter)
- [x] Parts arrived (2026-10-05): LilyGO T-A7670G + L76K V1.4, antennas, 18650, NC button, active buzzer, jumpers
- [x] Buzzer rated voltage confirmed: **5 V** (MakerLab MLE08216) → needs NPN driver from V_BAT
- [ ] Buy: NPN transistor (S8050 / 2N2222A, TO-92) + 1 kΩ resistor + heat-shrink
- [x] Wiring verified against the LilyGO V1.4 schematic → [`lilygo-wiring.html`](lilygo-wiring.html)
- [x] Toolchain: CH9102 driver + VS Code PlatformIO (2026-10-06, board on COM9)
- [x] `00_hello_board` — upload works, serial monitor, IO0 + battery voltage (2026-10-06)
- [x] `01_modem_at` — modem on, SIM ready, registered on LTE (2026-10-08: Smart, CSQ 24/31; needs a 1000 ms PWRKEY pulse, not LilyGO's 100 ms)
- [x] `02_gps_l76k` — L76K talks (NMEA @ 9600, ~1000 valid sentences/100 s, 2026-10-08); antenna proven (4 GPS sats, 30 dB, outdoors 2026-10-09 evening) — **no fix yet**: needs a daytime try in truly open sky, antenna ≥30 cm from the board/battery
- [x] `03_sms_send` — IO0 press → SMS accepted by the network (`+CMGS`, 2026-10-08 20:33, Smart); contacts live in git-ignored `include/secrets.h`
- [x] Phase 2 wiring: header pins, SOS button (IO32) + buzzer driver (IO18, V_BAT) → `04_pins_test` passes (2026-10-18)
- [ ] `05_cloud` — device writes location/battery/signal to Firestore, Find device, SOS (built; field test with a GPS fix + SMS pending)
- [x] Backend stores location; app map shows the marker moving
- [x] Find device — app → `cmdbox` mailbox → device buzzes (folded into `05_cloud`)

### App (WatchPack) — started early, 2026-10-08
- [x] Flutter toolchain + Firebase project `watchpack-f9483` (see `app/README.md`)
- [x] M1 Map Pin with demo device · M2 Trip History · zone editor · alert feed · settings
- [x] Sign-in / create account; Firestore security rules deployed
- [x] Push notifications — FCM from the laptop watcher (`npm run watch`), no Blaze plan needed
- [x] Contact editing (synced to the device's SOS list), second-parent invites, pairing codes (2026-10-18)
- [x] Security & privacy, unlink, delete account (2026-10-18)

### Phase 2 — Smart features
- [x] Zones (home, school, …) → arrive/leave push, once per crossing
- [x] Weather watcher → severe-weather push (Open-Meteo)
- [x] Earthquake watcher (PHIVOLCS) → quake push
- [x] Off-route alert (learned usual places)
- [x] Parent app screens: Map / Trip History / Notifications / Settings / Login

### Phase 3 — Make it real
- [x] Battery reporting + low-battery alert (threshold editable in the app)
- [ ] Power tuning (intervals, sleep)
- [ ] Enclosure + secure mount to backpack; charging (TP4056/USB-C)
- [x] Firestore security rules (only linked parents read a device; linking needs a code)

---

## Risks & mitigations

| Risk | Impact | Mitigation |
|------|--------|-----------|
| **2G shutdown** kills SIM800L | Device goes dark | Prefer 4G module; verify local 2G coverage before buying |
| **Modem power spikes** → resets | Flaky/unreliable | Separate regulated supply + 1000 µF cap + common ground |
| **Uno UART limits** (2 soft-serials) | Dropped GPS/modem data | ESP32 (hardware UART) or combined GPS+cellular module |
| **PHIVOLCS scrape breaks** | No local quake data | USGS API as reliable backbone; wrap scrape in try/catch |
| **Battery life too short** | Impractical | Tune intervals; deep sleep in Phase 3; size the cell right |
| **Privacy** (tracks a child) | Serious | Auth + strict Firestore rules; document data handling |
| **First GPS fix slow indoors** | "It doesn't work" panic | Test outdoors; expect 1–2 min cold fix |

---

## Parking lot (ideas for later)
- BLE proximity "find device" when phone is near (ESP32) — no cellular needed.
- Fall/impact detection (add an accelerometer) → auto-alert.
- Geofence multiple places (home, school, tutor) with per-place notifications.
- Speed/route history + "left an unexpected area" alert.
