// Step 2 — gps_l76k
// Proves: the L76K GPS board talks to the ESP32 (NMEA on Serial2 @ 9600) and gets a fix.
// Needs: GPS antenna on the L76K's u.FL; sky view for a fix (cold start 1–2 min outdoors,
// may never fix deep indoors — NMEA sentences still prove the wiring).
// The modem stays off in this test.

#include <Arduino.h>
#include <TinyGPS++.h>
#include "board.h"

#define SerialGPS Serial2

TinyGPSPlus gps;
// Satellites IN VIEW (before any fix) and the strongest signal, from the GSV sentences.
// Tells "antenna hears nothing" apart from "still searching".
TinyGPSCustom gpsInView(gps, "GPGSV", 3);
TinyGPSCustom bdInView(gps, "GBGSV", 3);     // L76K labels BeiDou "GB", not "BD"
TinyGPSCustom glInView(gps, "GLGSV", 3);
// Every satellite's SNR from the GSV sentences (4 per sentence). A fix needs ≥4 sats
// above ~25 dB; one strong one and three weak ones never locks.
TinyGPSCustom gSnr[4] = {{gps, "GPGSV", 7}, {gps, "GPGSV", 11}, {gps, "GPGSV", 15}, {gps, "GPGSV", 19}};
TinyGPSCustom bSnr[4] = {{gps, "GBGSV", 7}, {gps, "GBGSV", 11}, {gps, "GBGSV", 15}, {gps, "GBGSV", 19}};
int usable = 0, bestSnr = 0;
static void tally(TinyGPSCustom* arr) {
    for (int i = 0; i < 4; i++) {
        if (!arr[i].isUpdated()) continue;
        const int v = atoi(arr[i].value());
        if (v >= 25) usable++;
        if (v > bestSnr) bestSnr = v;
    }
}
uint32_t rawUntil;          // echo raw NMEA for the first seconds
uint32_t lastReport = 0;
uint32_t bytesSeen = 0;

void setup() {
    boardPowerOn();
    pinMode(GPS_WAKEUP_PIN, OUTPUT);
    digitalWrite(GPS_WAKEUP_PIN, HIGH);      // L76K: HIGH = run, LOW = standby

    Serial.begin(SERIAL_BAUD);
    delay(300);
    Serial.println("\nGuardian Pack — 02_gps_l76k");
    SerialGPS.begin(GPS_BAUD, SERIAL_8N1, GPS_RX_PIN, GPS_TX_PIN);
    Serial.printf("listening on RX=%d TX=%d @ %d baud. Raw NMEA for 15 s, then a summary each second.\n",
                  GPS_RX_PIN, GPS_TX_PIN, GPS_BAUD);
    rawUntil = millis() + 15000;
}

void loop() {
    while (SerialGPS.available()) {
        const char c = SerialGPS.read();
        bytesSeen++;
        if (millis() < rawUntil) Serial.write(c);
        if (gps.encode(c)) { tally(gSnr); tally(bSnr); }   // a sentence just completed
    }

    if (millis() - lastReport >= 1000 && millis() >= rawUntil) {
        lastReport = millis();
        if (bytesSeen == 0) {
            Serial.printf("[%4lu s] NO DATA from GPS — check the L76K board is seated and IO12 is HIGH\n", millis() / 1000);
            return;
        }
        Serial.printf("[%4lu s] sentences %lu (bad %lu) | in view GPS %s BeiDou %s GLONASS %s | usable(>=25dB) %d best %d dB | used %lu | ",
                      millis() / 1000,
                      (unsigned long)gps.passedChecksum(), (unsigned long)gps.failedChecksum(),
                      gpsInView.value(), bdInView.value(), glInView.value(), usable, bestSnr,
                      (unsigned long)gps.satellites.value());
        usable = 0; bestSnr = 0;
        if (gps.location.isValid()) {
            Serial.printf("FIX %.6f, %.6f | hdop %.1f | %.1f km/h | %02d:%02d:%02d UTC\n",
                          gps.location.lat(), gps.location.lng(), gps.hdop.hdop(), gps.speed.kmph(),
                          gps.time.hour(), gps.time.minute(), gps.time.second());
        } else {
            Serial.println(gps.time.isValid() ? "no fix yet (time ok — searching)" : "no fix yet");
        }
    }
}
