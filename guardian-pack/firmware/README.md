# Guardian Pack — Firmware

Arduino / ESP32 sketches for the device. Plan & architecture:
[`../docs/03-firmware.md`](../docs/03-firmware.md).

## Build order (each is a standalone sketch — get it working before the next)

| Folder | Proves | Status |
|--------|--------|--------|
| `00_hello_board/` | Toolchain, upload, serial, IO0 button, battery ADC | ✅ 2026-10-06 |
| `01_modem_at/` | Modem power-on, SIM, LTE registration | ⬜ |
| `02_gps_l76k/` | L76K GPS on Serial2 @ 9600 + TinyGPS++ | ⬜ |
| `03_sms_send/` | IO0 press → SMS | ⬜ |
| `04_pins_test/` | NC SOS button (IO32) + buzzer (IO18) — after Phase 2 wiring | ⬜ |
| `05_data_post/` | HTTP POST to backend | ⬜ |
| `06_buzz_command/` | Downlink (device reads a command) | ⬜ |
| `10_guardian_main/` | Integrated firmware (state machine) | ⬜ |

## Setup
- Board: **LilyGO T-A7670G + L76K, V1.4** — pins in [`../docs/lilygo-wiring.html`](../docs/lilygo-wiring.html)
  and [`include/config.h`](include/config.h).
- VS Code + **PlatformIO** (matches LilyGO's `[env:T-A7670X]`); USB driver: WCH CH9102.
- Libraries: **TinyGPS++**, LilyGO's bundled **TinyGSM**, **ArduinoHttpClient** (see docs/03).
- Keep secrets (API URLs, phone numbers) in `include/secrets.h` (git-ignored) — **do not commit real numbers**.

## Layout
This folder is **one PlatformIO project**. Each bring-up step is an environment in
[`platformio.ini`](platformio.ini) that compiles `src/common/` + its own `src/NN_name/` folder.

```
pio run -e hello_board              # build step 0
pio run -e hello_board -t upload    # flash it (remove any microSD card first)
pio device monitor                  # serial monitor, 115200 baud
```
Or in VS Code: PlatformIO sidebar → pick the env → Build / Upload / Monitor.

> Sketches get created here as we reach each build step. Ask me for any one and I'll
> write it.
