# Guardian Pack — Firmware Plan (the code on the device)

> How the sketch is structured. We build each block **standalone first**, then combine.
> Language: Arduino C++ (`.ino` + helper `.cpp/.h`). Sketches live in
> [`../firmware/`](../firmware/).

---

## 1. Bring-up order (do NOT skip) — updated for the LilyGO board (2026-10-05)

Each is its own tiny sketch under `firmware/`. Get a green checkmark before moving on.
**Software first:** steps 0–3 need **no soldering**. The board's onboard **IO0 button** stands
in for the SOS button, and the serial monitor stands in for the buzzer, until Phase 2.
Pins: see the `config.h` block in [`lilygo-wiring.html`](lilygo-wiring.html).

| Step | Sketch | Proves | Needs |
|------|--------|--------|-------|
| 0 | `00_hello_board` | Toolchain, USB driver, upload, serial monitor; reads IO0 + battery voltage (IO35) | USB cable only |
| 1 | `01_modem_at` | Modem powers on (IO12 HIGH, PWRKEY pulse on IO4); `AT`, `AT+SIMCOMATI`, `AT+CPIN?`, `AT+CSQ`, `AT+CEREG?` | LTE antenna + SIM |
| 2 | `02_gps_l76k` | L76K NMEA on Serial2 @ 9600 (RX 22 / TX 21) → TinyGPS++ lat/lng | GPS antenna, sky view |
| 3 | `03_sms_send` | IO0 press → one SMS with a Google Maps link | Steps 1 + 2 |
| — | *Phase 2: solder 5 header pins, wire SOS button (IO32) + buzzer driver (IO18 → 1 kΩ → NPN, buzzer from V_BAT)* | | NPN transistor + 1 kΩ bought |
| 4 | `04_pins_test` | NC button reads idle LOW / pressed HIGH; buzzer beeps | Wiring done |
| 5 | `05_data_post` | HTTP POST of a fixed JSON to the backend over LTE | Backend endpoint |
| 6 | `06_buzz_command` | Device polls backend, buzzes when told | Step 5 |
| 10 | `10_guardian_main` | Integrated firmware (state machine below) | All of the above |

If a step fails, you know *exactly* which subsystem — that's the whole point of this order.

**Board-specific rules every sketch follows:**
- `digitalWrite(12, HIGH)` first thing in `setup()` — powers the modem/SD rail and stops resets on battery.
- GPS is the **L76K on its own UART**, not modem AT commands (the A7670G has no GNSS).
- SOS button is **normally closed**: `INPUT_PULLUP`, pressed = `HIGH`. Require a ~2 s hold so a bump
  in the backpack doesn't send an SOS. A wire that comes loose also reads HIGH — report a reading
  that stays HIGH for a long time as "button fault" in the app.
- IO32 is an RTC pin, so the SOS button can wake the ESP32 from deep sleep later (Phase 3).

---

## 2. Main firmware architecture

A simple **non-blocking loop** (no `delay()` for timing — use `millis()`), because the
device must watch the SOS button *and* stream GPS *and* listen for commands at once.

```
setup():
  init serial (debug), modem UART, GPS
  configure buzzer pin OUT, SOS button INPUT_PULLUP
  modem: power on, register to network, attach data

loop():                        // runs forever, nothing blocks
  ├─ readGPS()                 // keep parsing NMEA into latest fix
  ├─ if (millis - lastSend > SEND_INTERVAL):   sendLocation()
  ├─ if (SOS button pressed):  sendEmergencySMS()   // highest priority
  ├─ if (millis - lastPoll > POLL_INTERVAL):   checkCommands()  // buzz?
  └─ handleBuzzer()            // beep pattern if buzzFlag set
```

### Modules (files)

| File | Responsibility | Key functions |
|------|----------------|---------------|
| `gps.h/.cpp` | Read + parse GPS | `updateGPS()`, `getFix() → {lat,lng,valid}` |
| `modem.h/.cpp` | Cellular: data + SMS | `sendPost(json)`, `sendSMS(num,text)`, `httpGet(url)` |
| `buzzer.h/.cpp` | Non-blocking beeps | `startBuzz(pattern)`, `handleBuzzer()` |
| `config.h` | Pins, intervals, URLs, phone numbers | constants only |
| `guardian_main.ino` | Wires it together (state machine) | `setup()`, `loop()` |

### Suggested libraries
- **TinyGPS++** — NMEA parsing for the L76K (Serial2, 9600 baud).
- **TinyGSM** — AT-command wrapper for the A7670 (data + SMS). Use the copy bundled in LilyGO's
  `LilyGO-T-A76XX/lib` folder; LilyGO warns that updating it can break the build.
- **ArduinoHttpClient** — HTTP on top of TinyGSM.
- On ESP32 you also get native `WiFi`/`BLE` if you want a local "find device" path.

### Toolchain
VS Code + **PlatformIO**, mirroring LilyGO's official `[env:T-A7670X]`
(`platform = espressif32@6.12.0`, `board = esp32dev`, `-DBOARD_HAS_PSRAM
-mfix-esp32-psram-cache-issue`). USB driver: WCH **CH9102** (CH343SER). Arduino IDE also
works (board "ESP32 Dev Module", PSRAM enabled, partition "Huge APP") as a fallback.

---

## 3. What the device sends (uplink message)

Keep it tiny — cellular data is metered and RAM is limited.

```json
POST /api/location
{
  "id":  "guardianpack-01",     // device id
  "lat": 14.5995,
  "lng": 120.9842,
  "spd": 3.2,                    // km/h, optional
  "bat": 82,                     // battery %, optional
  "ts":  1719900000             // unix time (from GPS or modem)
}
```

Emergency SMS is separate and does **not** go through the backend:
```
SMS → each contact: "SOS from Guardian Pack. Last location:
                     https://maps.google.com/?q=14.5995,120.9842"
```

---

## 4. What the device receives (downlink — for the buzzer)

Device polls a lightweight endpoint (simplest) or holds an MQTT connection (fancier).
Start with **polling** every ~10 s:

```
GET /api/command?id=guardianpack-01   →   { "buzz": true }
```
When `buzz` is true, run a loud beep pattern for ~20 s, then the backend clears the flag.

> Later upgrade: **MQTT** (e.g. HiveMQ/EMQX) gives near-instant push to the device and
> uses less data than constant polling. Not needed for the MVP.

---

## 5. Power/battery behavior (Phase 3)

- Sleep the MCU between sends (ESP32 deep sleep) to stretch battery — but this fights
  the "always listening for a buzz command" goal, so it's a **later** tuning step.
- Report battery % (IO35 reads V_BAT through the board's built-in ½ divider) so the parent app can warn "low".
- Sensible intervals to start: **send location every 30 s**, **poll commands every 10 s**.
  Tune for battery vs freshness once it all works.
