// Guardian Pack — board pin map and settings.
// LilyGO T-A7670G + L76K GPS, PCB V1.4 ("XY--A7670(GPS+ADC) 2024-4-26").
// Verified against LilyGO schematic T-A7670X-V1.4 and the A7670G-GPS pin table.
// Full wiring + figures: docs/lilygo-wiring.html
#pragma once

// ---- Board-owned pins (wired on the PCB — never connect anything to these) ----
#define BOARD_POWERON_PIN    12   // modem/SD power rail. Set HIGH first thing in setup()
#define MODEM_PWRKEY_PIN      4   // pulse HIGH to switch the modem on — see MODEM_PWRKEY_MS
#define MODEM_PWRKEY_MS    1000   // LilyGO's examples use 100 ms; THIS unit stays dark at 100 ms
                                  // and powers up at 1000 ms (verified 2026-10-08). Keep 1000.
#define MODEM_RESET_PIN       5   // active HIGH
#define MODEM_TX_PIN         26   // ESP32 -> modem RX   (Serial1)
#define MODEM_RX_PIN         27   // modem TX -> ESP32   (Serial1)
#define MODEM_DTR_PIN        25
#define MODEM_RI_PIN         33
#define MODEM_BAUD       115200

#define GPS_RX_PIN           22   // L76K TXD -> ESP32   (Serial2)
#define GPS_TX_PIN           21   // ESP32 -> L76K RXD   (Serial2)
#define GPS_PPS_PIN          23
#define GPS_WAKEUP_PIN       19   // HIGH = running, LOW = standby
#define GPS_BAUD           9600

#define BATTERY_ADC_PIN      35   // reads V_BAT through the board's 100k/100k divider
#define SOLAR_ADC_PIN        36

#define BOOT_BUTTON_PIN       0   // onboard IO0 button; stand-in SOS until Phase 2 wiring

// ---- Our parts (Phase 2 wiring) ----
#define SOS_BUTTON_PIN       32   // normally-CLOSED button to GND, INPUT_PULLUP
#define SOS_PRESSED_LEVEL  HIGH   // NC: idle LOW, pressed (contact opens) HIGH
#define BUZZER_PIN           18   // NPN base via 1 kΩ: HIGH = beep

// ---- Behaviour ----
#define SOS_DOUBLE_MS       600   // SOS = two presses, the 2nd starting within this of the 1st
#define BUTTON_DEBOUNCE_MS   40   // a press, and the gap between presses, must last this long
#define SOS_HOLD_MS        2000   // 03_sms_send's IO0 test only (hold to send)
#define SERIAL_BAUD      115200

// ---- Cloud ----
#define FIREBASE_PROJECT "watchpack-f9483"
#define APN              "internet"   // Smart; only used if LTE didn't bring up data by itself
