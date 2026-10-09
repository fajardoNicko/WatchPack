// Step 0 — hello_board
// Proves: PlatformIO builds, the CH9102 USB bridge uploads, the serial monitor
// works, the onboard IO0 button reads, and the battery ADC reads.
// No external wiring. Modem and GPS stay off.
//
// Expected output once a second:
//   [  12 s] battery 4.05 V | IO0 button: released | presses: 0
// Press the IO0 button (the one next to RST) → "presses" goes up.

#include <Arduino.h>
#include "board.h"

static uint32_t presses = 0;
static bool     wasPressed = false;

void setup() {
    boardPowerOn();                      // first thing, always
    pinMode(BOOT_BUTTON_PIN, INPUT_PULLUP);  // IO0: board has a 100k pull-up, pressed = LOW

    Serial.begin(SERIAL_BAUD);
    delay(300);
    Serial.println();
    Serial.println("Guardian Pack — 00_hello_board");
    Serial.printf("chip: %s rev %d, %d cores, %u MB flash, PSRAM %s\n",
                  ESP.getChipModel(), ESP.getChipRevision(), ESP.getChipCores(),
                  ESP.getFlashChipSize() / (1024 * 1024),
                  psramFound() ? "found" : "NOT found");
}

void loop() {
    bool pressed = digitalRead(BOOT_BUTTON_PIN) == LOW;
    if (pressed && !wasPressed) presses++;
    wasPressed = pressed;

    static uint32_t lastPrint = 0;
    if (millis() - lastPrint >= 1000) {
        lastPrint = millis();
        Serial.printf("[%4lu s] battery %.2f V | IO0 button: %s | presses: %lu\n",
                      millis() / 1000, readBatteryVolts(),
                      pressed ? "PRESSED " : "released",
                      presses);
    }
    delay(10);
}
