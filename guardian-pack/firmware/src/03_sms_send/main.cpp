// Step 3 — sms_send
// Proves: modem + GPS together, and an SOS text reaches a real phone.
// Press the onboard IO0 button (hold ~1 s) → one SMS to every number in SOS_CONTACTS,
// with a Google Maps link if the GPS has a fix, or "no GPS fix yet" otherwise.
//
// Needs: include/secrets.h (copy secrets.example.h), LTE + GPS antennas, SIM with load,
// battery in, switch ON.

#include <Arduino.h>
#include <TinyGPS++.h>
#include "board.h"
#include "secrets.h"

#define SerialAT  Serial1
#define SerialGPS Serial2

TinyGPSPlus gps;
const char* const contacts[] = SOS_CONTACTS;
constexpr size_t contactCount = sizeof(contacts) / sizeof(contacts[0]);

// ---------- modem helpers ----------
static String at(const char* cmd, uint32_t timeoutMs = 2000, const char* until = "OK") {
    while (SerialAT.available()) SerialAT.read();
    SerialAT.println(cmd);
    String reply;
    uint32_t t0 = millis();
    while (millis() - t0 < timeoutMs) {
        while (SerialAT.available()) reply += (char)SerialAT.read();
        if (reply.indexOf(until) >= 0 || reply.indexOf("ERROR") >= 0) break;
        delay(5);
    }
    reply.trim();
    return reply;
}

static void modemPowerOn() {
    pinMode(MODEM_RESET_PIN, OUTPUT);
    digitalWrite(MODEM_RESET_PIN, LOW);  delay(100);
    digitalWrite(MODEM_RESET_PIN, HIGH); delay(2600);
    digitalWrite(MODEM_RESET_PIN, LOW);
    pinMode(MODEM_PWRKEY_PIN, OUTPUT);
    digitalWrite(MODEM_PWRKEY_PIN, LOW);  delay(100);
    digitalWrite(MODEM_PWRKEY_PIN, HIGH); delay(MODEM_PWRKEY_MS);
    digitalWrite(MODEM_PWRKEY_PIN, LOW);
}

static bool modemReady() {
    for (int i = 0; i < 60; i++) {
        if (at("AT", 1000).indexOf("OK") >= 0) return true;
        Serial.print('.');
    }
    return false;
}

static bool registered() {
    const String r = at("AT+CEREG?");
    return r.indexOf(",1") >= 0 || r.indexOf(",5") >= 0;
}

// Text mode SMS. Returns true on +CMGS.
static bool sendSms(const char* number, const String& text) {
    at("AT+CMGF=1");
    at("AT+CSCS=\"GSM\"");
    String cmd = "AT+CMGS=\"";
    cmd += number;
    cmd += '"';
    const String prompt = at(cmd.c_str(), 5000, ">");
    if (prompt.indexOf('>') < 0) { Serial.printf("  no prompt: %s\n", prompt.c_str()); return false; }
    SerialAT.print(text);
    SerialAT.write(0x1A);                      // Ctrl-Z ends the message
    String r;
    uint32_t t0 = millis();
    while (millis() - t0 < 30000) {            // the network can take a while to accept
        while (SerialAT.available()) r += (char)SerialAT.read();
        if (r.indexOf("+CMGS") >= 0 || r.indexOf("ERROR") >= 0) break;
        delay(10);
    }
    r.trim();
    Serial.printf("  reply: %s\n", r.c_str());
    return r.indexOf("+CMGS") >= 0;
}

static String sosText() {
    String t = "SOS from WatchPack - ";
    t += CHILD_NAME;
    t += " pressed the emergency button. ";
    if (gps.location.isValid()) {
        t += "Location: https://maps.google.com/?q=";
        t += String(gps.location.lat(), 5) + "," + String(gps.location.lng(), 5);
    } else {
        t += "No GPS fix yet (indoors?). Last signal strength ok.";
    }
    return t;
}

// ---------- sketch ----------
bool modemOk = false;
uint32_t pressedSince = 0;
bool sent = false;

void setup() {
    boardPowerOn();
    pinMode(BOOT_BUTTON_PIN, INPUT_PULLUP);
    pinMode(GPS_WAKEUP_PIN, OUTPUT);
    digitalWrite(GPS_WAKEUP_PIN, HIGH);

    Serial.begin(SERIAL_BAUD);
    delay(300);
    Serial.println("\nGuardian Pack — 03_sms_send");
    Serial.printf("contacts: %u | battery %.2f V\n", (unsigned)contactCount, readBatteryVolts());

    SerialGPS.begin(GPS_BAUD, SERIAL_8N1, GPS_RX_PIN, GPS_TX_PIN);
    SerialAT.begin(MODEM_BAUD, SERIAL_8N1, MODEM_RX_PIN, MODEM_TX_PIN);

    Serial.print("modem starting");
    modemPowerOn();
    modemOk = modemReady();
    Serial.println(modemOk ? " ready" : " NOT ANSWERING");
    if (!modemOk) return;
    at("ATE0");
    Serial.print("registering");
    for (int i = 0; i < 45 && !registered(); i++) { Serial.print('.'); delay(2000); }
    Serial.println(registered() ? " on network" : " NOT registered (will still try)");
    Serial.printf("signal: %s\n", at("AT+CSQ").c_str());
    Serial.println("READY. Hold the IO0 button for 1 s to send the SOS text.");
}

void loop() {
    while (SerialGPS.available()) gps.encode(SerialGPS.read());

    const bool pressed = digitalRead(BOOT_BUTTON_PIN) == LOW;
    if (pressed && pressedSince == 0) pressedSince = millis();
    if (!pressed) { pressedSince = 0; sent = false; }

    if (pressed && !sent && millis() - pressedSince >= SOS_HOLD_MS) {
        sent = true;
        Serial.printf("\nSOS! gps fix: %s\n", gps.location.isValid() ? "yes" : "no");
        const String text = sosText();
        Serial.printf("text: %s\n", text.c_str());
        for (size_t i = 0; i < contactCount; i++) {
            Serial.printf("sending to %s ...\n", contacts[i]);
            Serial.println(sendSms(contacts[i], text) ? "  SENT" : "  FAILED");
        }
        Serial.println("release the button; hold again to resend.");
    }

    static uint32_t lastStatus = 0;
    if (millis() - lastStatus >= 10000) {
        lastStatus = millis();
        Serial.printf("[%4lu s] gps sats %lu fix %s | modem %s\n", millis() / 1000,
                      (unsigned long)gps.satellites.value(), gps.location.isValid() ? "yes" : "no",
                      modemOk ? (registered() ? "registered" : "searching") : "off");
    }
    delay(5);
}
