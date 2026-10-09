// Step 1 — modem_at
// Proves: the A7670G powers on, answers AT commands, sees the SIM, has signal,
// and registers on the LTE network. Then it becomes a serial bridge so you can
// type AT commands yourself in the monitor.
//
// Needs: LTE antenna on "RF", nano-SIM inserted (PIN off, with load), 18650 in,
// switch ON (the modem's transmit spikes are too much for USB alone on some ports).
//
// Power sequence follows LilyGO's ATdebug example for the T-A7670 (reset level HIGH,
// PWRKEY pulse HIGH ~100 ms).

#include <Arduino.h>
#include "board.h"

#define SerialAT Serial1

// Send one AT command, print the raw reply, return the reply text.
static String at(const char* cmd, uint32_t timeoutMs = 2000) {
    while (SerialAT.available()) SerialAT.read();   // drop stale bytes
    Serial.printf(">> %s\n", cmd);
    SerialAT.println(cmd);
    String reply;
    uint32_t t0 = millis();
    while (millis() - t0 < timeoutMs) {
        while (SerialAT.available()) reply += (char)SerialAT.read();
        if (reply.endsWith("OK\r\n") || reply.indexOf("ERROR") >= 0) break;
        delay(5);
    }
    reply.trim();
    Serial.println(reply.length() ? reply : "(no reply)");
    return reply;
}

static void modemPowerOn() {
    pinMode(MODEM_RESET_PIN, OUTPUT);
    digitalWrite(MODEM_RESET_PIN, LOW);
    delay(100);
    digitalWrite(MODEM_RESET_PIN, HIGH);   // reset is active HIGH on this board
    delay(2600);
    digitalWrite(MODEM_RESET_PIN, LOW);

    pinMode(MODEM_PWRKEY_PIN, OUTPUT);
    digitalWrite(MODEM_PWRKEY_PIN, LOW);
    delay(100);
    digitalWrite(MODEM_PWRKEY_PIN, HIGH);  // power-key pulse (length: see config.h)
    delay(MODEM_PWRKEY_MS);
    digitalWrite(MODEM_PWRKEY_PIN, LOW);
    Serial.printf("IO12 (modem rail) reads %d, PWRKEY pulsed %d ms\n", digitalRead(BOARD_POWERON_PIN), MODEM_PWRKEY_MS);
}

void setup() {
    boardPowerOn();                         // IO12 HIGH — modem rail
    Serial.begin(SERIAL_BAUD);
    delay(300);
    Serial.println("\nGuardian Pack — 01_modem_at");
    Serial.printf("battery %.2f V\n", readBatteryVolts());

    SerialAT.begin(MODEM_BAUD, SERIAL_8N1, MODEM_RX_PIN, MODEM_TX_PIN);
    Serial.println("powering modem on...");
    modemPowerOn();

    // Wait for the modem to boot (typically 5–15 s, allow 60). Print anything it
    // sends so a wrong baud rate shows up as garbage instead of silence.
    bool alive = false;
    for (int i = 0; i < 60 && !alive; i++) {
        SerialAT.println("AT");
        delay(1000);
        String r;
        while (SerialAT.available()) r += (char)SerialAT.read();
        alive = r.indexOf("OK") >= 0;
        if (r.length()) Serial.printf("[rx %d bytes] %s\n", r.length(), r.c_str());
        Serial.print(alive ? "modem answered\n" : ".");
    }
    if (!alive) {
        // Try the other common rates in case this unit isn't at 115200.
        for (const uint32_t baud : {9600u, 57600u, 460800u, 921600u}) {
            Serial.printf("\ntrying %lu baud", (unsigned long)baud);
            SerialAT.updateBaudRate(baud);
            for (int i = 0; i < 5 && !alive; i++) {
                SerialAT.println("AT");
                delay(500);
                String r;
                while (SerialAT.available()) r += (char)SerialAT.read();
                alive = r.indexOf("OK") >= 0;
                if (r.length()) Serial.printf(" [rx %d bytes]", r.length());
            }
            if (alive) { Serial.printf("\nmodem answered at %lu baud\n", (unsigned long)baud); break; }
        }
    }
    if (!alive) {
        SerialAT.updateBaudRate(MODEM_BAUD);
        Serial.println("\nMODEM NOT ANSWERING. Check: battery in + switch ON, red modem LED lit, LTE antenna on RF.");
        Serial.println("Dropping to bridge mode anyway — type AT and press Enter.");
        return;
    }

    at("ATE0");                 // echo off
    at("AT+SIMCOMATI", 3000);   // modem model + firmware
    at("AT+CPIN?");             // expect +CPIN: READY
    at("AT+CSQ");               // signal: first number 0–31, 99 = none. 10+ is usable
    at("AT+CNUM");              // SIM's own number (not all SIMs report it)
    at("AT+COPS?", 5000);       // operator currently used

    // Registration can take a while after power-on; poll up to 60 s.
    Serial.println("waiting for network registration (up to 60 s)...");
    bool reg = false;
    for (int i = 0; i < 30 && !reg; i++) {
        String r = at("AT+CEREG?");          // LTE registration
        // +CEREG: <n>,<stat>  — stat 1 = home, 5 = roaming
        reg = r.indexOf(",1") >= 0 || r.indexOf(",5") >= 0;
        if (!reg) delay(2000);
    }
    Serial.println(reg ? "REGISTERED on LTE" : "NOT registered yet (stat 2 = still searching, 0/3 = no SIM/denied)");
    at("AT+CSQ");
    at("AT+COPS?", 5000);

    Serial.println("\n--- bridge mode: type AT commands here, replies come back ---");
}

void loop() {
    while (SerialAT.available()) Serial.write(SerialAT.read());
    while (Serial.available())   SerialAT.write(Serial.read());
}
