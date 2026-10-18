// Step 4 — pins_test
// Proves: the Phase 2 wiring. SOS button on IO32 (normally closed to GND) and the
// buzzer driver on IO18 (1 kΩ → BC337 base, buzzer from V_BAT).
// Modem and GPS stay off.
//
// What you should see/hear:
//   boot          → 3 short beeps
//   button idle   → "button: idle (LOW)"
//   button held   → "button: PRESSED (HIGH)" and the buzzer sounds while you hold it
//   IO0 pressed   → one 1 s beep (tests the buzzer without the SOS button)
// If the button reads PRESSED without touching it, a wire is loose (NC opens = HIGH).

#include <Arduino.h>
#include "board.h"

static void beep(uint32_t ms) {
    digitalWrite(BUZZER_PIN, HIGH);
    delay(ms);
    digitalWrite(BUZZER_PIN, LOW);
}

bool lastPressed = false;
uint32_t pressedSince = 0;
uint32_t presses = 0;
bool faultReported = false;

void setup() {
    boardPowerOn();
    pinMode(BUZZER_PIN, OUTPUT);
    digitalWrite(BUZZER_PIN, LOW);
    pinMode(SOS_BUTTON_PIN, INPUT_PULLUP);
    pinMode(BOOT_BUTTON_PIN, INPUT_PULLUP);

    Serial.begin(SERIAL_BAUD);
    delay(300);
    Serial.println("\nGuardian Pack — 04_pins_test");
    Serial.printf("SOS button IO%d (NC, idle LOW) | buzzer IO%d | battery %.2f V\n",
                  SOS_BUTTON_PIN, BUZZER_PIN, readBatteryVolts());
    for (int i = 0; i < 3; i++) { beep(120); delay(120); }
    Serial.println("beeped 3 times. Hold the SOS button: the buzzer sounds while it's held.");
}

void loop() {
    const bool pressed = digitalRead(SOS_BUTTON_PIN) == SOS_PRESSED_LEVEL;
    if (pressed != lastPressed) {
        lastPressed = pressed;
        if (pressed) { presses++; pressedSince = millis(); }
        else if (faultReported) { faultReported = false; Serial.println("button back to idle — wiring ok again"); }
        Serial.printf("[%4lu s] button: %s | presses %lu\n", millis() / 1000,
                      pressed ? "PRESSED (HIGH)" : "idle (LOW)", (unsigned long)presses);
    }
    digitalWrite(BUZZER_PIN, pressed ? HIGH : LOW);

    if (pressed && !faultReported && millis() - pressedSince > 10000) {
        faultReported = true;
        Serial.println("button has read PRESSED for 10 s — if you're not holding it, a wire is loose");
    }

    if (digitalRead(BOOT_BUTTON_PIN) == LOW) {
        Serial.println("IO0 → 1 s beep");
        beep(1000);
        while (digitalRead(BOOT_BUTTON_PIN) == LOW) delay(10);
    }

    static uint32_t lastStatus = 0;
    if (millis() - lastStatus >= 5000) {
        lastStatus = millis();
        Serial.printf("[%4lu s] button %s | battery %.2f V\n", millis() / 1000,
                      pressed ? "PRESSED" : "idle", readBatteryVolts());
    }
    delay(10);
}
