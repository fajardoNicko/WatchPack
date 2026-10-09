# Guardian Pack — Wiring

> ✅ **Hardware arrived (2026-10-05): LilyGO T-A7670G + L76K GPS, PCB V1.4.** It's an
> all-in-one board — ESP32, modem, GPS, charger, regulators and the 18650 holder are already
> wired on the PCB. **Wire from [`lilygo-wiring.html`](lilygo-wiring.html)** (verified against
> LilyGO's V1.4 schematic and your photos). The only external wiring is the SOS button
> (IO32 + GND) and the buzzer. The buzzer is 5 V, so it runs through an NPN transistor:
> IO18 → 1 kΩ → base, emitter → GND, buzzer between V_BAT and the collector.
>
> ⛔ **§A and §B below are for builds you did not buy.** §B (ESP32 DevKit + separate modem on
> GPIO16/17, PWRKEY on GPIO4, buzzer GPIO25, button GPIO26) is **wrong for the LilyGO board** —
> on its ESP32-WROVER, GPIO16/17 belong to the PSRAM, and 4/25/26 are wired to the modem. Same for
> [`wiring-corrected.html`](wiring-corrected.html). Kept for reference only.
>
> Also outdated below: the A7670**G** has **no GPS inside**. GPS comes from the separate L76K
> module on its own UART (ESP32 RX = IO22, TX = IO21, 9600 baud), not from modem AT commands.

⚠️ **Before wiring anything, read the power rules in
[`01-hardware.md` §4](01-hardware.md#4-power--the-1-cause-of-it-randomly-resets).**
The cellular module gets its own regulated power from the battery — **never** straight
off the MCU pin.

---

## A. Arduino Uno version (REFERENCE ONLY — not the chosen build)

Uses **SIM800L** (2G, SMS + GPRS data) + **NEO-6M** (GPS) + buzzer + SOS button.
Because the Uno has only one hardware UART (pins 0/1, tied to USB), GPS and the modem
both run on **SoftwareSerial**. This *works for a demo* but is the Uno's weak spot — see
the note at the bottom.

```
                         USB                    DC power jack
                       ┌──┴──┐                  ┌──┴──┐
        ┌──────────────┴─────┴──────────────────┴─────┴──────────────┐
        │  ┌─┐                                                        │
        │  └─┘  ARDUINO UNO                                           │
        │                                                            │
   ┌────┤ [ ] AREF                                          IOREF [ ] │
   │    │ [ ] GND                                           RESET [ ] │
   │    │ [ ] 13                                             3V3  [ ]─┼──► NEO-6M  VCC (3.3V)
   │    │ [ ] 12                                             5V   [ ]─┼──► (do NOT power SIM800L here)
   │    │ [~] 11                                             GND  [ ]─┼──► common ground rail ◄─┐
   │    │ [~] 10                                             GND  [ ] │                         │
   │    │ [ ]  9  ──────────────► BUZZER (+)                 VIN  [ ] │                         │
   │    │ [ ]  8  ──────────────► SOS BUTTON ─► GND                  │                         │
   │    │ [~]  7  ──► SIM800L RXD  (via divider, see below)          │       ┌──────────────┐  │
   │    │ [~]  6  ◄── SIM800L TXD                              A0 [ ] │       │ common GND   │  │
   │    │ [~]  5                                               A1 [ ] │       │ rail: MCU +  │  │
   │    │ [ ]  4  ◄── NEO-6M TXD  (GPS → Uno)                  A2 [ ] │       │ NEO-6M +     │  │
   │    │ [~]  3  ──► NEO-6M RXD  (Uno → GPS, opt.)            A3 [ ] │       │ SIM800L +    ├──┘
   │    │ [ ]  2                                          SDA/A4 [ ] │       │ buzzer +     │
   │    │ [ ]  1  TX ─ (USB serial — leave free)          SCL/A5 [ ] │       │ battery(-)   │
   │    │ [ ]  0  RX ─ (USB serial — leave free)                     │       └──────────────┘
   │    └────────────────────────────────────────────────────────────┘
   │
   └── AREF/GND block unused here

  SIM800L POWER (separate!):   Li-ion 3.7V ──► [1000µF cap] ──► SIM800L VCC/GND
                               (NOT from the Uno 5V pin — it can't supply 2A)

  LEVEL SHIFT (Uno 5V TX  →  SIM800L 3.3V RX):
     Uno pin 7 ──[1kΩ]──┬── SIM800L RXD
                        │
                     [2kΩ]
                        │
                       GND        (voltage divider drops 5V → ~3.3V)
```

### Uno connection table

| From (Uno) | To (component) | Notes |
|------------|----------------|-------|
| D4 | NEO-6M **TXD** | GPS data into Uno (SoftwareSerial RX) |
| D3 | NEO-6M **RXD** | optional (config GPS); GPS works read-only |
| 3V3 | NEO-6M **VCC** | NEO-6M runs at 3.3 V |
| D6 | SIM800L **TXD** | modem → Uno (SoftwareSerial RX) |
| D7 | SIM800L **RXD** | Uno → modem, **through 1k/2k divider** |
| Battery 3.7 V | SIM800L **VCC** | separate supply + 1000 µF cap |
| D9 | Buzzer (+) | drive directly if small; use a transistor if loud |
| D8 | SOS button | other side of button → GND, use `INPUT_PULLUP` |
| GND | **all** GND | one common ground rail — mandatory |

> **Uno reality check:** two `SoftwareSerial` ports can't both listen simultaneously,
> so you'll poll GPS, then switch to the modem, etc. For a science-fair demo that's fine.
> For reliable always-on tracking, the ESP32 below (real second UART) is the safer build,
> or a single **4G module with built-in GPS** removes the second serial device entirely.

---

## B. ESP32 version — ✅ THE BUILD

Uses a **4G module with built-in GPS (SIM7600/A7670)** — so **no separate GPS module**,
one UART for the modem, and 3.3 V logic that matches the ESP32 (no dividers needed).

> **One extra wire to know about:** most SIM7600/A7670 boards have a **PWRKEY** pin that
> must be pulsed LOW for ~1 s to turn the modem on at boot. Wire it to a spare GPIO (e.g.
> **GPIO4**) so the firmware can power the modem up. Some boards auto-power — check yours;
> we'll confirm the exact pinout against your specific board when it arrives.

```
        ┌──────────────────── ESP32 DevKit ─────────────────────┐
        │  [EN]                                          [GPIO23]│
        │  [VP/36]                                        [22]   │
        │  [VN/39]                                        [TX0]──┼── USB debug (leave free)
        │  [34]                                           [RX0]──┼── USB debug (leave free)
        │  [35]                                           [21]   │
        │  [32]                                           [19]   │
        │  [33]                                           [18]   │
        │  [25]  ──────► BUZZER (+)                        [ 5]   │
        │  [26]  ◄────── SOS BUTTON ─► GND                 [17]──┼──► MODEM RX  (ESP32 TX2)
        │  [27]                                            [16]──┼──◄ MODEM TX  (ESP32 RX2)
        │  [14]                                            [ 4]──┼──► MODEM PWRKEY (power-on pulse)
        │  [12]                                            [ 2]   │
        │  [13]                                            [15]   │
        │  [GND] ──── common ground rail                  [GND]   │
        │  [VIN/5V]                                        [3V3]   │
        └───────────────────────────────────────────────────────┘

   MODEM POWER:   Li-ion 3.7V ─► buck/boost (set per module) ─► [1000µF] ─► MODEM VCC
                  MODEM GND ──────────────────────────────────────► common ground
```

### ESP32 connection table

| From (ESP32) | To (component) | Notes |
|--------------|----------------|-------|
| GPIO17 (TX2) | Modem **RX** | UART2 to modem — no divider (both 3.3 V) |
| GPIO16 (RX2) | Modem **TX** | UART2 from modem |
| GPIO4 | Modem **PWRKEY** | pulse LOW ~1 s at boot to power the modem on (if board needs it) |
| GPIO25 | Buzzer (+) | direct for small buzzer, transistor for loud |
| GPIO26 | SOS button | other leg → GND, `INPUT_PULLUP` |
| GND | **all** GND | common ground rail |
| Battery via regulator | Modem **VCC** | own supply + 1000 µF cap |

GPS comes over the **same modem UART** (AT commands turn GPS on and read a fix) — that's
the big simplification of the combined 4G+GPS module.

---

## C. Things that will bite you (checklist)

- [ ] **Common ground** across every module + battery. Missing this = flaky everything.
- [ ] Modem powered from **battery + regulator**, not the MCU pin. Add the **1000 µF cap**.
- [ ] On Uno: **level-shift** the 5 V TX line into the 3.3 V modem/GPS RX.
- [ ] Keep **antennas** clear of metal / battery; GPS needs sky view for first fix.
- [ ] SIM card **PIN lock disabled**, has **load/data**, and is **activated** (send one
      SMS from a phone first).
- [ ] First GPS fix outdoors can take **1–2 minutes** — normal, not a bug.
