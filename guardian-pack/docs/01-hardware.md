# Guardian Pack — Hardware & Bill of Materials

> ✅ **Decisions locked (2026-07-02):** **ESP32** microcontroller + **4G module with
> built-in GPS (SIM7600 / A7670)**. The comparison tables below are kept for the record;
> the **finalized BOM is in §3**.
>
> 📦 **What actually arrived is in §0** — it replaces §3. Wiring: [`lilygo-wiring.html`](lilygo-wiring.html).

---

## 0. What actually arrived (checked from photos, 2026-10-05)

| Part | Notes |
|------|-------|
| **LilyGO T-A7670G + L76K GPS** (product Q425), PCB `XY--A7670(GPS+ADC) V1.4 2024-4-26` | ESP32-WROVER-E (4 MB flash, 8 MB PSRAM) + SIMCom A7670G + CN3065 charger (500 mA) + DW06D protection + 18650 holder + nano-SIM slot + microSD slot, all on one PCB |
| L76K GPS daughter-board (upright, on the back) | This is what makes it the **"with GPS" version**. The A7670G modem chip has no GPS of its own, so LilyGO adds this dedicated GPS receiver (GPS + BeiDou + GLONASS). It uses IO19/21/22/23 |
| Active GPS patch antenna (u.FL) | Goes on the L76K board's u.FL (back) |
| Full-band LTE antenna, 698–960 / 1710–2690 MHz (u.FL) | Goes on the front u.FL marked `RF` |
| 18650 Li-ion cell (blue, unbranded) | Unknown capacity. Check it reads 3.0–4.2 V before first use |
| 2 × male pin headers | For the PX / PY edges. Solder only the pins you use (see wiring page) |
| Red/black lead with small white 2-pin plug | Most likely the solar-panel lead for the board's white JST socket. Not needed |
| Female–female jumper wires (40 + 10) | Fine for prototyping |
| Momentary push button, 6 mm panel mount (MLE02963) | ⚠️ **Normally CLOSED** — firmware treats HIGH as pressed. Works fine; no need to swap |
| Active buzzer, MakerLab **MLE08216** (10 pcs) | Listing: **rated 5 V, operating 4–8 V, 30 mA max**, 85 dB @ 10 cm. Too much current and too high a voltage for a 3.3 V pin → driven by an NPN transistor from V_BAT (see wiring page, Figure 3) |

**Still to buy (buzzer driver):** 1 × NPN transistor, TO-92 (S8050 or 2N2222A), 1 × 1 kΩ resistor
(¼ W), heat-shrink tubing. Buy a few of each — they cost a few pesos. Transistor and resistor at
e-Gizmo (checked 2026-10-05, in stock):
[3 pcs S8050 TO-92, ₱9](https://e-gizmo.net/gizmoshop/index.php?route=product/product&product_id=49318) ·
[1K 5% ¼ W resistor, ₱0.50 each](https://e-gizmo.net/gizmoshop/index.php?route=product/product&product_id=49096) ·
heat-shrink is out of stock there → [MakerLab heat-shrink kit, 164 pcs, ₱59](https://makerlab.ph/products/164-328-530-pcs-polyolefin-heat-shrink-tube-wrap-heatshrink-tubing-kit-2-1-electric-insulation)
(in stock). Stopgap: PVC electrical tape, one wrap per joint.
MakerLab has the resistor and heat-shrink but **no S8050/2N2222**; its 2N7000 is a MOSFET, which needs a different circuit.
The S8050 listing doesn't state the pin order — confirm it from the marking on the part before soldering.

**No longer needed from §3:** separate ESP32 DevKit, separate SIM7600/A7670 breakout, TP4056,
MP1584/MT3608, 1000 µF capacitor, protoboard power wiring. The LilyGO board has all of it.

**Tools still worth getting:** soldering iron + solder, and a basic multimeter (continuity +
DC volts). The multimeter is what lets you check the battery, the NC button and your joints
before anything is powered.

---

## 1. The microcontroller decision (most important)

You mentioned an **Arduino Uno**. I'll give you the Uno wiring you asked for, but as
your engineer I have to flag: the Uno is a rough fit for *this specific* project, and
here's the honest tradeoff.

| | **Arduino Uno** | **ESP32** (my recommendation) | **Arduino Mega 2560** |
|---|---|---|---|
| Hardware serial ports (UART) | **1** (shared with USB) | **3** | **4** |
| Why that matters | GPS *and* cellular each need a UART. With one, you're forced into `SoftwareSerial`, and two soft-serial ports can't reliably listen at once → dropped GPS bytes / missed modem replies | GPS on UART1, modem on UART2, USB debug on UART0 — all real hardware ports | Enough ports, but big & power-hungry |
| Logic voltage | 5 V (modules are 3.3 V → need level shifting) | **3.3 V — matches the modules** | 5 V |
| RAM | 2 KB (tight for parsing HTTP/JSON) | ~520 KB | 8 KB |
| Internet by itself | No | **WiFi + BLE built in** | No |
| Secure HTTPS/TLS to backend | Very hard | Supported | Very hard |
| BLE (phone can find/buzz device up close, no cellular) | No | **Yes** | No |
| Cost | ~₱250 / clone | ~₱250–400 | ~₱500+ |

**Bottom line:** the ESP32 is *cheaper-or-equal*, has the ports and RAM this project
needs, matches the 3.3 V modules, and its BLE gives you a free "find my device up close"
path. The Uno will work for a demo but you'll fight it. **If you have a reason to stay on
Uno (already own one, class requirement), say so and we design around it — I'll use the
Mega-style approach or a single combined GPS+cellular module to dodge the UART problem.**

> This is decision #1 in [`05-roadmap.md`](05-roadmap.md#open-decisions).

---

## 2. The cellular module decision

This module does **two jobs**: send emergency SMS **and** carry the live-tracking data.

| Module | Network | GPS built in? | SMS | Data | Notes |
|--------|---------|---------------|-----|------|-------|
| **SIM800L** | 2G / GSM | ❌ (needs separate GPS) | ✅ | GPRS (slow) | Cheapest (~₱200). ⚠️ **2G is being phased out** by Globe/Smart — check coverage in your area before committing |
| **SIM7600 / A7670** | **4G LTE** | ✅ **yes** | ✅ | LTE (fast) | ~₱900–1500. **Combines GPS + data + SMS in one module** → fewer parts, one UART, no separate GPS. My pick if budget allows |
| NEO-6M **+** LTE modem | — | (NEO-6M does GPS) | via modem | via modem | Classic split; more wiring |

**Recommendation:** a **4G module with built-in GPS (SIM7600/A7670)** simplifies the whole
device — one UART, one antenna set, future-proof network. If cost is the hard constraint,
**SIM800L + NEO-6M** is the budget path *if* 2G still works where the child goes.

> This is decision #2 in [`05-roadmap.md`](05-roadmap.md#open-decisions).

---

## 3. Bill of Materials — **FINALIZED** (ESP32 + 4G/GPS module)

| Part | Purpose | Qty | Est. cost (₱) |
|------|---------|-----|---------------|
| **ESP32 dev board** (DevKit v1 / WROOM-32) | Brain — 3 UARTs, 3.3 V, WiFi+BLE | 1 | 250–400 |
| **SIM7600 or A7670 module** (4G, built-in GPS) | SMS + LTE data + GPS in one | 1 | 900–1500 |
| ~~Separate GPS module~~ | **Not needed** — GPS is in the 4G module | 0 | 0 |
| Active buzzer (or piezo + NPN transistor for loud) | Find-my-device | 1 | 30–80 |
| Push button (momentary) | SOS trigger | 1 | 10 |
| Li-ion 18650 cell + holder **or** LiPo 3.7 V ≥2000 mAh | Power (4G draws more than 2G) | 1 | 150–300 |
| TP4056 charging board (USB-C) | Safe charging | 1 | 40 |
| MP1584 / MT3608 buck-boost (set to module's Vin) | Stable power for the modem's current bursts | 1 | 50 |
| GPS + LTE antennas | Signal (usually bundled with the module) | — | incl. |
| 1000 µF capacitor + wires + protoboard | Power smoothing + glue | — | 100 |
| SIM card (prepaid, **with a data plan**) | Cellular service | 1 | 40 + load |
| **Total (rough)** | | | **~₱1,600–2,500** |

> No 5 V→3.3 V level-shifting dividers on this build — the ESP32 and the 4G module are
> both 3.3 V logic, so their UART lines connect directly. One fewer thing to get wrong.

---

## 4. Power — the #1 cause of "it randomly resets"

Cellular modules draw **short 2 A current spikes** when transmitting. If they share a weak
supply (like the MCU's onboard regulator), the voltage sags and the board **brown-out
resets**. This kills more IoT projects than any code bug.

Rules we follow:
- **Power the cellular module from the battery through its own buck/boost regulator**, not
  from the MCU's 5 V/3.3 V pin.
- Add a **big capacitor (≥1000 µF)** across the modem's power pins to absorb spikes.
- **Common ground**: every module's GND ties together with the MCU's GND.
- SIM800L specifically wants **3.7–4.2 V** (not 5 V) — a single Li-ion cell is ideal.

Details and the exact hookup are in [`02-wiring.md`](02-wiring.md).
