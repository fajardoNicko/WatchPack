// Seeds Firestore with a realistic demo device ("Ivy") so the app can be built and
// tested before the hardware sends anything. Safe to re-run: it overwrites the same ids.
//
// Uses the Firestore REST API unauthenticated — this only works while the database is
// in "test mode" (rules allow everyone). Run:  node tools/seed_demo.mjs
//
// Demo day (Valenzuela): home → jeep → school 6:10–6:35 am, idle at school, school → home
// 3:05–3:51 pm with an off-route detour. Last fix is "now", at home.

const PROJECT = "watchpack-f9483";
const BASE = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;
const DEVICE_ID = "wp-demo-ivy";

const HOME   = { lat: 14.7008, lng: 120.9830 };   // Valenzuela (approx.)
const TERM   = { lat: 14.6965, lng: 120.9880 };   // jeepney terminal
const SCHOOL = { lat: 14.6905, lng: 120.9950 };
const DETOUR = { lat: 14.6930, lng: 120.9790 };   // off-route point on the way home

// ---------- Firestore value encoding ----------
const v = (x) => {
  if (x === null) return { nullValue: null };
  if (typeof x === "boolean") return { booleanValue: x };
  if (typeof x === "number") return Number.isInteger(x) ? { integerValue: String(x) } : { doubleValue: x };
  if (typeof x === "string") return { stringValue: x };
  if (x instanceof Date) return { timestampValue: x.toISOString() };
  if (Array.isArray(x)) return { arrayValue: { values: x.map(v) } };
  if (typeof x === "object") return { mapValue: { fields: enc(x) } };
  throw new Error("unsupported " + typeof x);
};
const enc = (o) => Object.fromEntries(Object.entries(o).map(([k, x]) => [k, v(x)]));

async function put(path, data) {
  const r = await fetch(`${BASE}/${path}`, {
    method: "PATCH",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ fields: enc(data) }),
  });
  if (!r.ok) throw new Error(`${path}: ${r.status} ${await r.text()}`);
}

async function deleteCollection(path) {
  const r = await fetch(`${BASE}/${path}?pageSize=300`);
  if (!r.ok) return;
  const { documents = [] } = await r.json();
  await Promise.all(documents.map((d) => fetch(`https://firestore.googleapis.com/v1/${d.name}`, { method: "DELETE" })));
  if (documents.length === 300) await deleteCollection(path);
}

// ---------- route generation ----------
const lerp = (a, b, t) => ({ lat: a.lat + (b.lat - a.lat) * t, lng: a.lng + (b.lng - a.lng) * t });
const jitter = (p, m = 0.00004) => ({ lat: p.lat + (Math.random() - 0.5) * m, lng: p.lng + (Math.random() - 0.5) * m });
const haversineKm = (a, b) => {
  const R = 6371, toR = (d) => (d * Math.PI) / 180;
  const dLat = toR(b.lat - a.lat), dLng = toR(b.lng - a.lng);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(toR(a.lat)) * Math.cos(toR(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
};

// Walk a polyline between `start` and `end` times, one fix every `stepS` seconds.
function leg(points, start, end, stepS = 15) {
  const fixes = [];
  const total = (end - start) / 1000;
  const segs = points.length - 1;
  for (let s = 0; s <= total; s += stepS) {
    const t = s / total, seg = Math.min(segs - 1, Math.floor(t * segs)), lt = t * segs - seg;
    const p = jitter(lerp(points[seg], points[seg + 1], lt));
    fixes.push({ ...p, ts: new Date(start.getTime() + s * 1000) });
  }
  return fixes;
}
function idle(at, start, end, stepS = 60) {
  const fixes = [];
  for (let t = start.getTime(); t <= end.getTime(); t += stepS * 1000) fixes.push({ ...jitter(at, 0.00002), ts: new Date(t) });
  return fixes;
}
// Speed from neighbouring fixes (km/h).
function withSpeed(fixes) {
  return fixes.map((f, i) => {
    if (i === 0) return { ...f, spd: 0 };
    const p = fixes[i - 1], dt = (f.ts - p.ts) / 3600000;
    return { ...f, spd: dt > 0 ? +(haversineKm(p, f) / dt).toFixed(1) : 0 };
  });
}

const today = new Date();
const at = (h, m) => new Date(today.getFullYear(), today.getMonth(), today.getDate(), h, m);
const now = new Date();

let fixes = [
  ...idle(HOME, at(5, 30), at(6, 9)),
  ...leg([HOME, TERM], at(6, 10), at(6, 20), 15),          // walk to terminal
  ...idle(TERM, at(6, 20), at(6, 24), 30),                 // waiting for a jeep
  ...leg([TERM, SCHOOL], at(6, 24), at(6, 35), 10),        // jeep to school
  ...idle(SCHOOL, at(6, 35), at(15, 4), 300),              // in class
  ...leg([SCHOOL, DETOUR, HOME], at(15, 5), at(15, 51), 15), // home with a detour
  ...idle(HOME, at(15, 51), now, 120),
];
fixes = withSpeed(fixes).filter((f) => f.ts <= now);
const last = fixes[fixes.length - 1];

const alerts = [
  { type: "zone_exit",  title: "Departure",     body: "Ivy has exited the School Zone and is heading Home.", ts: at(15, 5),  lat: SCHOOL.lat, lng: SCHOOL.lng },
  { type: "off_route",  title: "Off-route alert", body: `Ivy has deviated from the established direct path home. Current location: ${DETOUR.lat.toFixed(4)}° N, ${DETOUR.lng.toFixed(4)}° E`, ts: at(15, 15), lat: DETOUR.lat, lng: DETOUR.lng },
  { type: "on_route",   title: "Route recovery", body: "Ivy has returned to the expected path home.", ts: at(15, 25), lat: 14.6960, lng: 120.9810 },
  { type: "zone_enter", title: "Home Zone reached", body: "Ivy has arrived at the Home Zone.", ts: at(15, 51), lat: HOME.lat, lng: HOME.lng },
].filter((a) => a.ts <= now);

console.log(`seeding ${fixes.length} fixes, ${alerts.length} alerts for ${DEVICE_ID} …`);
await deleteCollection(`devices/${DEVICE_ID}/locations`);
await deleteCollection(`devices/${DEVICE_ID}/alerts`);

await put(`devices/${DEVICE_ID}`, {
  name: "Ivy",
  ownerUid: "demo",
  battery: 99,
  lastSeen: last.ts,
  lastLat: last.lat,
  lastLng: last.lng,
  speedKmh: last.spd,
  status: "idle",
  buzz: false,
  insideZoneId: "home",
  contacts: [{ name: "Dad", phone: "+639000000001" }, { name: "Mom", phone: "+639000000002" }, { name: "Angel", phone: "+639000000003" }],
});
await put(`devices/${DEVICE_ID}/zones/home`,   { name: "Home Zone",   type: "home",   lat: HOME.lat,   lng: HOME.lng,   radiusM: 200, enabled: true });
await put(`devices/${DEVICE_ID}/zones/school`, { name: "School Zone", type: "school", lat: SCHOOL.lat, lng: SCHOOL.lng, radiusM: 500, enabled: true });
await put(`devices/${DEVICE_ID}/settings/triggers`, { lowBatteryPct: 10, lowBatteryOn: true, signalLossMin: 15, signalLossOn: true, offRouteOn: true });

// Write fixes in parallel batches of 25 (REST has no bulk write without auth).
for (let i = 0; i < fixes.length; i += 25) {
  await Promise.all(fixes.slice(i, i + 25).map((f, j) =>
    put(`devices/${DEVICE_ID}/locations/${String(i + j).padStart(5, "0")}`, { lat: f.lat, lng: f.lng, spd: f.spd, ts: f.ts })));
  process.stdout.write(`  fixes ${Math.min(i + 25, fixes.length)}/${fixes.length}\r`);
}
console.log();
for (const [i, a] of alerts.entries()) await put(`devices/${DEVICE_ID}/alerts/${String(i).padStart(3, "0")}`, a);
console.log("done. last fix:", last.ts.toLocaleString(), `${last.lat.toFixed(5)}, ${last.lng.toFixed(5)}`);
