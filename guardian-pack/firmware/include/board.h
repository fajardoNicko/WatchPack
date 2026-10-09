// Shared board helpers used by every bring-up sketch.
#pragma once
#include <Arduino.h>
#include "config.h"

// Powers the peripheral rail. On battery the board resets without this.
inline void boardPowerOn() {
    pinMode(BOARD_POWERON_PIN, OUTPUT);
    digitalWrite(BOARD_POWERON_PIN, HIGH);
}

// Battery voltage in volts. V_BAT reaches IO35 through a 100k/100k divider.
inline float readBatteryVolts() {
    uint32_t sum = 0;
    for (int i = 0; i < 16; i++) sum += analogReadMilliVolts(BATTERY_ADC_PIN);
    return (sum / 16) * 2.0f / 1000.0f;
}
