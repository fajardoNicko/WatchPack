// Step 5 — cloud. The demo firmware: everything the app needs from the device.
//   every 30 s (10 s in SOS) → position, battery, signal to Firestore over LTE/HTTPS
//   every 10 s               → reads its command mailbox: "Find device" → buzzer 15 s,
//                              and the family contacts edited in the app
//   SOS button held 2 s      → SMS to every contact first, then the app goes red (10 min)
//   short press while buzzing → stops the buzzer
// Talks to Firestore's REST API directly, no Cloud Functions. Each write carries
// DEVICE_SECRET, which the security rules check — app/firestore.rules, provision.mjs.
// IO0 works as a second SOS button. The SOS input is ignored until it has read idle once,
// so the sketch is safe to run before the button is wired.
// SOS numbers: the app's family contacts once it has sent them (kept in flash, so SOS
// still works offline after a reboot), else SOS_CONTACTS from secrets.h.

#include <Arduino.h>
#include <Preferences.h>
#include <TinyGPS++.h>
#include <vector>
#include "board.h"
#include "secrets.h"

#define SerialAT  Serial1
#define SerialGPS Serial2

constexpr uint32_t POST_MS = 30000, POST_SOS_MS = 10000, POLL_MS = 10000;
constexpr uint32_t SOS_ACTIVE_MS = 10UL * 60 * 1000;
constexpr uint32_t BUZZ_MS = 15000;
#define DOCS "projects/" FIREBASE_PROJECT "/databases/(default)/documents"
const char* const BASE = "https://firestore.googleapis.com/v1/" DOCS;
const char* const FW = "05_cloud";

TinyGPSPlus gps;
const char* const builtinContacts[] = SOS_CONTACTS;
Preferences prefs;
String appContacts;                     // "+639…,+639…" as last received from the app

static bool validPhone(const String& p) {
    if (p.length() != 13 || !p.startsWith("+639")) return false;
    for (int i = 1; i < 13; i++) if (!isDigit(p[i])) return false;
    return true;
}

static std::vector<String> sosNumbers() {
    std::vector<String> out;
    for (int start = 0; start < (int)appContacts.length();) {
        int comma = appContacts.indexOf(',', start);
        if (comma < 0) comma = appContacts.length();
        String p = appContacts.substring(start, comma);
        p.trim();
        if (validPhone(p)) out.push_back(p);
        start = comma + 1;
    }
    if (out.empty()) for (const char* c : builtinContacts) out.push_back(c);
    return out;
}

// ---------- background work: GPS, button, buzzer (runs inside every wait) ----------
bool sosWired = false, btnDown = false, sosFiredThisPress = false, sosRequested = false;
uint32_t btnSince = 0, buzzUntil = 0, toneUntil = 0;

static void service() {
    while (SerialGPS.available()) gps.encode(SerialGPS.read());

    const bool sosPin = digitalRead(SOS_BUTTON_PIN) == SOS_PRESSED_LEVEL;
    if (!sosPin) sosWired = true;
    const bool down = (sosWired && sosPin) || digitalRead(BOOT_BUTTON_PIN) == LOW;
    if (down && !btnDown) { btnDown = true; btnSince = millis(); }
    if (!down && btnDown) {
        btnDown = false;
        if (!sosFiredThisPress && buzzUntil) buzzUntil = 0;     // short press = "found it"
        sosFiredThisPress = false;
    }
    if (btnDown && !sosFiredThisPress && millis() - btnSince >= SOS_HOLD_MS) {
        sosFiredThisPress = true;
        sosRequested = true;
    }

    bool on = (int32_t)(toneUntil - millis()) > 0;
    if (buzzUntil) {
        if ((int32_t)(buzzUntil - millis()) > 0) on = on || (millis() / 300) % 2 == 0;
        else buzzUntil = 0;
    }
    digitalWrite(BUZZER_PIN, on ? HIGH : LOW);
}

static void wait(uint32_t ms) {
    const uint32_t t0 = millis();
    while (millis() - t0 < ms) { service(); delay(2); }
}

// ---------- modem ----------
static String waitFor(const char* a, const char* b, uint32_t timeoutMs, String r = "") {
    const uint32_t t0 = millis();
    while (millis() - t0 < timeoutMs) {
        while (SerialAT.available()) r += (char)SerialAT.read();
        if (r.indexOf(a) >= 0 || (b && r.indexOf(b) >= 0)) break;
        service();
        delay(2);
    }
    return r;
}

static String at(const String& cmd, uint32_t timeoutMs = 3000, const char* until = "OK") {
    while (SerialAT.available()) SerialAT.read();
    SerialAT.println(cmd);
    String r = waitFor(until, "ERROR", timeoutMs);
    r.trim();
    return r;
}

static bool modemAnswers(int tries) {
    for (int i = 0; i < tries; i++) {
        if (at("AT", 1000).indexOf("OK") >= 0) return true;
    }
    return false;
}

static void modemPowerOn() {                    // same sequence as 03_sms_send (proven)
    pinMode(MODEM_RESET_PIN, OUTPUT);
    digitalWrite(MODEM_RESET_PIN, LOW);  wait(100);
    digitalWrite(MODEM_RESET_PIN, HIGH); wait(2600);
    digitalWrite(MODEM_RESET_PIN, LOW);
    pinMode(MODEM_PWRKEY_PIN, OUTPUT);
    digitalWrite(MODEM_PWRKEY_PIN, LOW);  wait(100);
    digitalWrite(MODEM_PWRKEY_PIN, HIGH); wait(MODEM_PWRKEY_MS);
    digitalWrite(MODEM_PWRKEY_PIN, LOW);
}

static bool registered() {
    const String r = at("AT+CEREG?");
    return r.indexOf(",1") >= 0 || r.indexOf(",5") >= 0;
}

int csq = 0;
static void readCsq() {
    const String r = at("AT+CSQ");
    const int p = r.indexOf("+CSQ: ");
    if (p >= 0) csq = r.substring(p + 6).toInt();
}

static bool dataUp() {
    auto hasIp = [] {
        const String r = at("AT+CGPADDR=1");
        const int p = r.indexOf("+CGPADDR: 1,");
        if (p < 0) return false;
        String ip = r.substring(p + 12);
        ip = ip.substring(0, ip.indexOf('\n'));
        ip.trim();
        ip.replace("\"", "");
        return ip.length() >= 7 && ip != "0.0.0.0";
    };
    if (hasIp()) return true;
    at(String("AT+CGDCONT=1,\"IP\",\"") + APN + "\"");
    at("AT+CGACT=1,1", 30000);
    return hasIp();
}

static void sslSetup() {
    at("AT+CSSLCFG=\"sslversion\",0,4");     // any TLS version
    at("AT+CSSLCFG=\"authmode\",0,0");       // no server cert check (no CA store on the modem)
    at("AT+CSSLCFG=\"enableSNI\",0,1");      // Google's front ends need SNI
}

// Text-mode SMS. True on +CMGS.
static bool sendSms(const char* number, const String& text) {
    at("AT+CMGF=1");
    at("AT+CSCS=\"GSM\"");
    const String prompt = at(String("AT+CMGS=\"") + number + "\"", 5000, ">");
    if (prompt.indexOf('>') < 0) return false;
    SerialAT.print(text);
    SerialAT.write(0x1A);
    const String r = waitFor("+CMGS", "ERROR", 30000);
    return r.indexOf("+CMGS") >= 0;
}

// HTTP(S) with the modem's own stack. method 0 = GET, 1 = POST. Returns the HTTP status,
// a 7xx modem error, or < 0 if the AT exchange broke. `out` gets the body (GET only).
static int http(int method, const String& url, const String& body, String* out = nullptr) {
    at("AT+HTTPTERM", 2000);
    if (at("AT+HTTPINIT", 5000).indexOf("OK") < 0) return -1;
    at("AT+HTTPPARA=\"URL\",\"" + url + "\"");
    at("AT+HTTPPARA=\"SSLCFG\",0");
    if (method == 1) {
        at("AT+HTTPPARA=\"CONTENT\",\"application/json\"");
        const String r = at("AT+HTTPDATA=" + String(body.length()) + ",10000", 5000, "DOWNLOAD");
        if (r.indexOf("DOWNLOAD") < 0) { at("AT+HTTPTERM"); return -2; }
        SerialAT.print(body);
        waitFor("OK", "ERROR", 10000);
    }
    String r = at("AT+HTTPACTION=" + String(method), 3000);
    r = waitFor("+HTTPACTION:", nullptr, 60000, r);
    const int p = r.indexOf("+HTTPACTION:");
    if (p < 0) { at("AT+HTTPTERM"); return -3; }
    r = waitFor("\n", nullptr, 2000, r.substring(p));      // make sure the line is complete
    int m = 0, status = -4, len = 0;
    sscanf(r.c_str(), "+HTTPACTION: %d,%d,%d", &m, &status, &len);
    if (len > 0 && (out || status != 200)) {
        const int n = len > 1500 ? 1500 : len;
        String b = at("AT+HTTPREAD=0," + String(n), 10000, "+HTTPREAD: 0");
        const int s = b.indexOf("+HTTPREAD: ");
        if (s >= 0) b = b.substring(b.indexOf('\n', s) + 1, b.lastIndexOf("+HTTPREAD: 0"));
        if (out) *out = b;
        else Serial.printf("  http %d: %s\n", status, b.substring(0, 300).c_str());
    }
    at("AT+HTTPTERM");
    return status;
}

// ---------- Firestore REST encoding ----------
static String dbl(double v, int digits) { return "{\"doubleValue\":" + String(v, digits) + "}"; }
static String integer(long v) { return "{\"integerValue\":\"" + String(v) + "\"}"; }
static String str(const String& v) { return "{\"stringValue\":\"" + v + "\"}"; }
static String boolv(bool v) { return String("{\"booleanValue\":") + (v ? "true" : "false") + "}"; }
static String hex32() { char b[9]; snprintf(b, sizeof b, "%08x", (unsigned)esp_random()); return b; }

static int batteryPct() {
    const int p = (int)((readBatteryVolts() - 3.3f) / (4.15f - 3.3f) * 100.0f);
    return constrain(p, 0, 100);
}

// ---------- device state ----------
uint32_t sosSince = 0;
bool sosStampPending = false, clearDeviceBuzz = false, buzzWasOn = false;
double lastLat = 0, lastLng = 0;
uint32_t lastFixPost = 0, lastGoodFixAt = 0;
int failures = 0;

static bool sosActive() { return sosSince && millis() - sosSince < SOS_ACTIVE_MS; }
static bool freshFix() { return gps.location.isValid() && gps.location.age() < 5000; }

static bool postTelemetry() {
    readCsq();
    const bool fix = freshFix();
    const double lat = gps.location.lat(), lng = gps.location.lng();
    const double spd = fix && gps.speed.isValid() ? gps.speed.kmph() : 0;
    const int bat = batteryPct();
    const char* status = sosActive() ? "sos" : (fix && spd > 3 ? "moving" : "idle");
    const String auth = String(DEVICE_SECRET) + ":" + hex32();

    // A new trail point only when it moved 15 m, every 2 min while still, or in SOS.
    const bool newPoint = fix && (lastFixPost == 0 || sosActive() || millis() - lastFixPost > 120000 ||
                                  TinyGPSPlus::distanceBetween(lat, lng, lastLat, lastLng) > 15);

    String w = "{\"writes\":[";
    if (newPoint) {
        w += "{\"update\":{\"name\":\"" DOCS "/devices/" DEVICE_ID "/locations/" + hex32() + hex32() + "\",\"fields\":{";
        w += "\"lat\":" + dbl(lat, 6) + ",\"lng\":" + dbl(lng, 6) + ",\"spd\":" + dbl(spd, 1);
        w += ",\"bat\":" + integer(bat) + ",\"auth\":" + str(auth) + "}},";
        w += "\"updateTransforms\":[{\"fieldPath\":\"ts\",\"setToServerValue\":\"REQUEST_TIME\"}],";
        w += "\"currentDocument\":{\"exists\":false}},";
    }
    String fields = "\"battery\":" + integer(bat) + ",\"status\":" + str(status) + ",\"gpsFix\":" + boolv(fix) +
                    ",\"csq\":" + integer(csq) + ",\"fw\":" + str(FW) + ",\"speedKmh\":" + dbl(spd, 1) +
                    ",\"auth\":" + str(auth);
    String mask = "\"battery\",\"status\",\"gpsFix\",\"csq\",\"fw\",\"speedKmh\",\"auth\"";
    if (fix) {
        fields += ",\"lastLat\":" + dbl(lat, 6) + ",\"lastLng\":" + dbl(lng, 6);
        mask += ",\"lastLat\",\"lastLng\"";
    }
    const bool clearing = clearDeviceBuzz;
    if (clearing) { fields += ",\"buzz\":" + boolv(false); mask += ",\"buzz\""; }
    const bool stamping = sosStampPending;
    String transforms = "{\"fieldPath\":\"lastSeen\",\"setToServerValue\":\"REQUEST_TIME\"}";
    if (stamping) transforms += ",{\"fieldPath\":\"sosAt\",\"setToServerValue\":\"REQUEST_TIME\"}";
    w += "{\"update\":{\"name\":\"" DOCS "/devices/" DEVICE_ID "\",\"fields\":{" + fields + "}},";
    w += "\"updateMask\":{\"fieldPaths\":[" + mask + "]},\"updateTransforms\":[" + transforms + "]}]}";

    const uint32_t t0 = millis();
    const int st = http(1, String(BASE) + ":commit", w);
    Serial.printf("[%4lu s] post %d in %lu ms | %s | fix %s %.5f,%.5f | %d km/h | bat %d%% | csq %d%s\n",
                  millis() / 1000, st, millis() - t0, status, fix ? "yes" : "no", lat, lng, (int)spd, bat, csq,
                  newPoint ? " | +trail" : "");
    if (st != 200) return false;
    if (newPoint) { lastFixPost = millis(); lastLat = lat; lastLng = lng; }
    if (clearing) clearDeviceBuzz = false;
    if (stamping) sosStampPending = false;
    return true;
}

// One field of a Firestore REST document: `"name": { "booleanValue": true }` → the
// text from the name up to its closing brace, or "" if it isn't there.
static String field(const String& body, const char* name) {
    const int k = body.indexOf(String("\"") + name + "\"");
    if (k < 0) return "";
    const int end = body.indexOf('}', k);
    return end < 0 ? "" : body.substring(k, end);
}

// Reads cmdbox/<secret>. New contacts from the app → flash. On buzz: start the buzzer
// and clear the mailbox.
static bool pollCommands() {
    String body;
    const int st = http(0, String(BASE) + "/cmdbox/" DEVICE_SECRET "?mask.fieldPaths=buzz&mask.fieldPaths=contacts", "", &body);
    if (st != 200) { Serial.printf("[%4lu s] poll %d\n", millis() / 1000, st); return false; }

    const String c = field(body, "contacts");
    const int sv = c.indexOf("stringValue");
    if (sv >= 0) {
        const int q1 = c.indexOf('"', c.indexOf(':', sv) + 1), q2 = c.indexOf('"', q1 + 1);
        const String list = q1 >= 0 && q2 > q1 ? c.substring(q1 + 1, q2) : "";
        if (list != appContacts) {
            appContacts = list;
            prefs.putString("contacts", appContacts);
            Serial.printf("[%4lu s] contacts from the app: %u SOS numbers\n", millis() / 1000, (unsigned)sosNumbers().size());
        }
    }

    if (field(body, "buzz").indexOf("true") < 0) return true;
    Serial.printf("[%4lu s] FIND DEVICE → buzzing %lu s\n", millis() / 1000, BUZZ_MS / 1000);
    buzzUntil = millis() + BUZZ_MS;
    buzzWasOn = true;
    const String w = "{\"writes\":[{\"update\":{\"name\":\"" DOCS "/cmdbox/" DEVICE_SECRET "\",\"fields\":{\"buzz\":" +
                     boolv(false) + "}},\"updateMask\":{\"fieldPaths\":[\"buzz\"]}}]}";
    http(1, String(BASE) + ":commit", w);
    return true;
}

static void fireSos() {
    Serial.printf("\n[%4lu s] SOS!\n", millis() / 1000);
    sosSince = millis();
    sosStampPending = true;
    toneUntil = millis() + 800;                         // "it's sent" confirmation beep

    String t = "SOS from WatchPack - ";
    t += CHILD_NAME;
    t += " pressed the emergency button. ";
    if (freshFix()) {
        t += "Location: https://maps.google.com/?q=" + String(gps.location.lat(), 5) + "," + String(gps.location.lng(), 5);
    } else if (lastGoodFixAt) {
        t += "Last known location (" + String((millis() - lastGoodFixAt) / 60000) + " min ago): https://maps.google.com/?q=";
        t += String(gps.location.lat(), 5) + "," + String(gps.location.lng(), 5);
    } else {
        t += "No GPS fix yet.";
    }
    for (const String& n : sosNumbers()) {              // SMS first: it works without internet
        const bool ok = sendSms(n.c_str(), t);
        Serial.printf("  sms %s %s\n", n.c_str(), ok ? "SENT" : "FAILED");
    }
    postTelemetry();
}

// ---------- sketch ----------
bool modemOk = false;
uint32_t lastPost = 0, lastPoll = 0;

void setup() {
    boardPowerOn();
    pinMode(BUZZER_PIN, OUTPUT);
    digitalWrite(BUZZER_PIN, LOW);
    pinMode(SOS_BUTTON_PIN, INPUT_PULLUP);
    pinMode(BOOT_BUTTON_PIN, INPUT_PULLUP);
    pinMode(GPS_WAKEUP_PIN, OUTPUT);
    digitalWrite(GPS_WAKEUP_PIN, HIGH);

    Serial.begin(SERIAL_BAUD);
    delay(300);
    Serial.printf("\nWatchPack — %s | device %s | battery %.2f V\n", FW, DEVICE_ID, readBatteryVolts());
    prefs.begin("watchpack", false);
    appContacts = prefs.getString("contacts", "");
    Serial.printf("sos numbers: %u (%s)\n", (unsigned)sosNumbers().size(), appContacts.length() ? "from the app" : "secrets.h");
    SerialGPS.begin(GPS_BAUD, SERIAL_8N1, GPS_RX_PIN, GPS_TX_PIN);
    SerialAT.begin(MODEM_BAUD, SERIAL_8N1, MODEM_RX_PIN, MODEM_TX_PIN);

    Serial.print("modem ");
    if (!modemAnswers(2)) { modemPowerOn(); modemOk = modemAnswers(60); }
    else modemOk = true;
    Serial.println(modemOk ? "ready" : "NOT ANSWERING");
    if (!modemOk) return;
    at("ATE0");
    auto line = [](String s) { s.replace("\r", ""); s.replace("\n", " "); s.replace("OK", ""); s.trim(); return s; };
    Serial.printf("sim: %s\n", line(at("AT+CPIN?")).c_str());
    for (int i = 0; i < 45 && !registered(); i++) {
        if (i % 5 == 0) Serial.printf("  [%3lu s] %s | %s\n", millis() / 1000, line(at("AT+CEREG?")).c_str(), line(at("AT+CSQ")).c_str());
        wait(2000);
    }
    Serial.printf("network %s\n", registered() ? "registered" : "NOT registered");
    if (!registered()) {
        Serial.printf("  creg: %s\n", line(at("AT+CREG?")).c_str());
        Serial.printf("  cops: %s\n", line(at("AT+COPS?", 10000)).c_str());
        Serial.printf("  cpsi: %s\n", line(at("AT+CPSI?")).c_str());
        Serial.printf("  cfun: %s\n", line(at("AT+CFUN?")).c_str());
    }
    Serial.printf("data %s\n", dataUp() ? "up" : "DOWN");
    sslSetup();
    toneUntil = millis() + 150;                         // one short chirp = online
}

void loop() {
    service();
    if (gps.location.isValid() && gps.location.isUpdated()) lastGoodFixAt = millis();

    if (sosRequested) { sosRequested = false; if (modemOk) fireSos(); }
    if (!modemOk) return;

    if (buzzWasOn && !buzzUntil) { buzzWasOn = false; clearDeviceBuzz = true; lastPost = 0; }

    const uint32_t every = sosActive() ? POST_SOS_MS : POST_MS;
    if (lastPost == 0 || millis() - lastPost >= every) {
        lastPost = millis();
        failures = postTelemetry() ? 0 : failures + 1;
    }
    if (millis() - lastPoll >= POLL_MS) {
        lastPoll = millis();
        failures = pollCommands() ? 0 : failures + 1;
    }
    if (failures >= 3) {
        Serial.println("3 failures in a row — reconnecting data");
        failures = 0;
        if (!modemAnswers(3)) { modemPowerOn(); modemAnswers(60); at("ATE0"); }
        for (int i = 0; i < 15 && !registered(); i++) wait(2000);
        dataUp();
        sslSetup();
    }
}
