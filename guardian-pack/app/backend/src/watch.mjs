// Live watcher for real devices (the ones provision.mjs registered — they have a cmdId).
// Turns what the device writes into alerts + push notifications:
//   SOS · zone enter/exit · off-route / back on route · low battery · signal loss / back online
// and runs the PHIVOLCS quake job every 5 minutes and the severe-weather check every 15.
// Keep it running during the demo:
//   npm run watch
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { db, pushToParents, quakesJob } from "./run.mjs";
import { RouteMemory } from "./routes.mjs";
import { severeWeather, weatherText } from "./weather.mjs";

const EXIT_MARGIN_M = 25;            // hysteresis so GPS jitter at the edge doesn't flap
const BATTERY_RESET_MARGIN = 5;
const OFF_ROUTE_M = 440;             // this far from every usual place, two fixes in a row
const WEATHER_REPEAT_MS = 3 * 3600e3;

const routes = new RouteMemory();
const offStreak = new Map();         // deviceId → { seen, count } — fixes in a row off the usual places

const distM = (a, b) => {
  const R = 6371e3, toR = (d) => (d * Math.PI) / 180;
  const dLat = toR(b.lat - a.lat), dLng = toR(b.lng - a.lng);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(toR(a.lat)) * Math.cos(toR(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
};
const clock = (d = new Date()) =>
  d.toLocaleTimeString("en-PH", { timeZone: "Asia/Manila", hour: "numeric", minute: "2-digit" });

async function raise(ref, d, type, title, body) {
  const at = d.lastLat != null ? { lat: d.lastLat, lng: d.lastLng } : {};
  await ref.collection("alerts").add({ type, title, body, ts: FieldValue.serverTimestamp(), ...at });
  console.log(`[${clock()}] ${ref.id} ${type}: ${title}`);
  await pushToParents(ref.id, { title, body, data: { type, deviceId: ref.id } });
}

async function triggersOf(ref) {
  const t = (await ref.collection("settings").doc("triggers").get()).data() ?? {};
  return {
    lowBatteryOn: t.lowBatteryOn !== false, lowBatteryPct: t.lowBatteryPct ?? 20,
    signalLossOn: t.signalLossOn !== false, signalLossMin: t.signalLossMin ?? 10,
    offRouteOn: t.offRouteOn !== false, weatherOn: t.weatherOn !== false,
  };
}

const fmtM = (m) => (m === Infinity ? "more than 2 km" : m < 1000 ? `about ${Math.round(m / 10) * 10} m` : `about ${(m / 1000).toFixed(1)} km`);
const fmtMin = (ms) => {
  const min = Math.max(1, Math.round(ms / 60e3));
  return min < 60 ? `${min} min` : `${Math.floor(min / 60)} h${min % 60 ? ` ${min % 60} min` : ""}`;
};

// Zone names are free text. The app's defaults end in "Zone" ("Home Zone", "School
// Zone"), which reads badly in a sentence: "arrived home", "left School".
const place = (z) => {
  const n = (z.name ?? "").replace(/\s+zone$/i, "").trim() || "a safe zone";
  return n.toLowerCase() === "home" ? "home" : n;
};

async function evaluate(ref) {
  const snap = await ref.get();                    // fresh: an earlier pass may have patched watch.*
  const d = snap.data(), name = d.name ?? "Your child";
  const watch = d.watch ?? {};
  const patch = {};

  // SOS — once per press (the device stamps sosAt on every new press).
  const sosAt = d.sosAt instanceof Timestamp ? d.sosAt.toMillis() : null;
  if (d.status === "sos" && sosAt && watch.sosAt !== sosAt) {
    patch["watch.sosAt"] = sosAt;
    await raise(ref, d, "sos", `SOS — ${name} needs help`,
      `${name} pressed the emergency button at ${clock(new Date(sosAt))}. Open WatchPack for the live location.`);
  }

  // Zones — only with a current GPS fix.
  if (d.gpsFix && d.lastLat != null) {
    const here = { lat: d.lastLat, lng: d.lastLng };
    const zones = (await ref.collection("zones").get()).docs
      .map((z) => ({ id: z.id, ...z.data() }))
      .filter((z) => z.enabled !== false);
    const current = zones.find((z) => z.id === d.insideZoneId);
    const stillInside = current && distM(here, current) <= (current.radiusM ?? 200) + EXIT_MARGIN_M;
    if (!stillInside) {
      const entered = zones
        .filter((z) => distM(here, z) <= (z.radiusM ?? 200))
        .sort((a, b) => (a.radiusM ?? 200) - (b.radiusM ?? 200))[0];
      // Each zone picks which crossings alert (notify: both | arrive | leave).
      let left = watch.left;                       // last departure, for "25 min after leaving School"
      if (current) {
        if (current.notify !== "arrive") {
          await raise(ref, d, "zone_exit", `${name} left ${place(current)}`, `Left at ${clock()}.`);
        }
        left = { id: current.id, name: place(current), at: Date.now() };
        patch["watch.left"] = left;
      }
      if (entered && entered.notify !== "leave") {
        const home = place(entered) === "home";
        const ago = left && Date.now() - left.at < 3 * 3600e3 ? fmtMin(Date.now() - left.at) : null;
        const body = !ago ? `Arrived at ${clock()}.`
          : left.id === entered.id ? `Back at ${clock()}, ${ago} after leaving.`
          : `Arrived at ${clock()}, ${ago} after leaving ${left.name}.`;
        await raise(ref, d, "zone_enter", home ? `${name} arrived home` : `${name} arrived at ${place(entered)}`, body);
      }
      const next = entered?.id ?? null;
      if (next !== (d.insideZoneId ?? null)) patch.insideZoneId = next;
    }
  }

  const t = await triggersOf(ref);

  // Off-route — outside every zone and far from everywhere the child usually goes,
  // for two fixes in a row. Counted once per device update (lastSeen), not per snapshot.
  const seen = d.lastSeen instanceof Timestamp ? d.lastSeen.toMillis() : null;
  const streak = offStreak.get(ref.id) ?? { seen: null, count: 0 };
  if (t.offRouteOn && d.gpsFix && d.lastLat != null && seen && streak.seen !== seen) {
    streak.seen = seen;
    const inZone = (patch.insideZoneId !== undefined ? patch.insideZoneId : d.insideZoneId) != null;
    const r = await routes.check(ref, d.lastLat, d.lastLng);
    const off = !inZone && !r.learning && r.metres >= OFF_ROUTE_M;
    streak.count = off ? streak.count + 1 : 0;
    if (off && streak.count >= 2 && !watch.offRoute) {
      patch["watch.offRoute"] = true;
      await raise(ref, d, "off_route", `${name} is off the usual route`,
        `${name} is ${fmtM(r.metres)} from anywhere ${name} usually goes (${clock()}). Open WatchPack to see where.`);
    } else if (!off && watch.offRoute && (inZone || (!r.learning && r.metres < OFF_ROUTE_M / 2))) {
      patch["watch.offRoute"] = false;
      await raise(ref, d, "on_route", `${name} is back on a usual route`, `Back somewhere familiar at ${clock()}.`);
    }
    offStreak.set(ref.id, streak);
  }

  // Low battery — once per dip below the threshold.
  if (d.lastSeen && t.lowBatteryOn && typeof d.battery === "number") {
    if (d.battery <= t.lowBatteryPct && !watch.lowBattery) {
      patch["watch.lowBattery"] = true;
      await raise(ref, d, "low_battery", `${name}'s WatchPack battery is low`, `Battery at ${d.battery}%. Charge it soon.`);
    } else if (d.battery > t.lowBatteryPct + BATTERY_RESET_MARGIN && watch.lowBattery) {
      patch["watch.lowBattery"] = false;
    }
  }

  // Back online after a signal-loss alert.
  if (watch.offline && seen && Date.now() - seen < 2 * 60e3) {
    patch["watch.offline"] = false;
    await raise(ref, d, "other", `${name}'s WatchPack is back online`, `Reconnected at ${clock()}.`);
  }

  if (Object.keys(patch).length) await ref.update(patch);
}

// Signal loss needs a clock, not a change, so it's checked every minute.
async function signalLossSweep() {
  const devices = await db.collection("devices").get();
  for (const snap of devices.docs) {
    const d = snap.data();
    if (!d.cmdId || !(d.lastSeen instanceof Timestamp) || d.watch?.offline) continue;
    const t = await triggersOf(snap.ref);
    const minutes = (Date.now() - d.lastSeen.toMillis()) / 60e3;
    if (!t.signalLossOn || minutes < t.signalLossMin) continue;
    await snap.ref.update({ "watch.offline": true });
    await raise(snap.ref, d, "signal_loss", `Lost contact with ${d.name ?? "your child"}'s WatchPack`,
      `No update for ${Math.round(minutes)} min. Last seen at ${clock(d.lastSeen.toDate())}.`);
  }
}

// Severe weather where a device is (and has been heard from in the last hour).
// Each kind (thunder / rain / wind) alerts at most once every 3 hours per device.
async function weatherSweep() {
  const devices = await db.collection("devices").get();
  for (const snap of devices.docs) {
    const d = snap.data();
    if (!d.cmdId || d.lastLat == null || !(d.lastSeen instanceof Timestamp)) continue;
    if (Date.now() - d.lastSeen.toMillis() > 60 * 60e3) continue;
    if (!(await triggersOf(snap.ref)).weatherOn) continue;
    const w = await severeWeather(d.lastLat, d.lastLng);
    if (!w || Date.now() - (d.watch?.weather?.[w.kind] ?? 0) < WEATHER_REPEAT_MS) continue;
    await snap.ref.update({ [`watch.weather.${w.kind}`]: Date.now() });
    const { title, body } = weatherText(w, d.name ?? "your child");
    await raise(snap.ref, d, "weather", title, body);
  }
}

// Serialise per device so overlapping snapshots don't raise the same alert twice.
const queue = new Map();
const enqueue = (ref) => {
  const prev = queue.get(ref.id) ?? Promise.resolve();
  const next = prev.then(() => evaluate(ref)).catch((e) => console.error(`${ref.id}:`, e.message));
  queue.set(ref.id, next);
};

console.log(`[${clock()}] watching devices…`);
db.collection("devices").onSnapshot((q) => {
  for (const ch of q.docChanges()) {
    if (ch.type !== "removed" && ch.doc.get("cmdId")) enqueue(ch.doc.ref);
  }
}, (e) => console.error("snapshot error:", e.message));

setInterval(() => signalLossSweep().catch((e) => console.error("sweep:", e.message)), 60e3);
const quakes = () => quakesJob().catch((e) => console.error("quakes job failed:", e.message));
quakes();
setInterval(quakes, 5 * 60e3);
const weather = () => weatherSweep().catch((e) => console.error("weather:", e.message));
weather();
setInterval(weather, 15 * 60e3);
