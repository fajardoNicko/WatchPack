// WatchPack backend jobs. Runs with the Firebase Admin SDK (bypasses security rules).
//
//   node src/run.mjs quakes   — one pass: scrape PHIVOLCS, store events, alert nearby devices
//   node src/run.mjs loop     — same, every 5 minutes, forever
//
// Credentials: backend/serviceAccount.json (Firebase console → Project settings →
// Service accounts → Generate new private key). Git-ignored. Or set
// GOOGLE_APPLICATION_CREDENTIALS to its path.

import { readFileSync, existsSync } from "node:fs";
import { initializeApp, cert, applicationDefault } from "firebase-admin/app";
import { getFirestore, Timestamp, FieldValue } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { fetchQuakes } from "./phivolcs.mjs";

const keyPath = new URL("../serviceAccount.json", import.meta.url);
initializeApp({ credential: existsSync(keyPath) ? cert(JSON.parse(readFileSync(keyPath))) : applicationDefault() });
const db = getFirestore();
const fcm = getMessaging();

// ---------- alert policy ----------
const MIN_MAG = 4.0;                                   // below this nobody is woken up
const KEEP_HOURS = 48;                                 // how long events stay in `quakes`
/** How far away a quake of this magnitude is still worth an alert (km). */
const alertRadiusKm = (mag) => (mag >= 6.5 ? 400 : mag >= 6 ? 300 : mag >= 5 ? 200 : mag >= 4.5 ? 120 : 80);

const haversineKm = (a, b) => {
  const R = 6371, toR = (d) => (d * Math.PI) / 180;
  const dLat = toR(b.lat - a.lat), dLng = toR(b.lng - a.lng);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(toR(a.lat)) * Math.cos(toR(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
};

// ---------- jobs ----------
export async function quakesJob() {
  const events = await fetchQuakes();
  const cutoff = Date.now() - KEEP_HOURS * 3600e3;
  const recent = events.filter((e) => e.ts.getTime() >= cutoff);

  // 1. Store events (idempotent).
  const batch = db.batch();
  for (const e of recent) {
    batch.set(db.doc(`quakes/${e.id}`), { ...e, ts: Timestamp.fromDate(e.ts), seenAt: FieldValue.serverTimestamp() }, { merge: true });
  }
  await batch.commit();

  // 2. Drop stale events.
  const stale = await db.collection("quakes").where("ts", "<", Timestamp.fromMillis(cutoff)).get();
  if (!stale.empty) { const b = db.batch(); stale.docs.forEach((d) => b.delete(d.ref)); await b.commit(); }

  // 3. Alert devices near a significant quake (once per device per event).
  const strong = recent.filter((e) => e.mag >= MIN_MAG);
  let alerts = 0;
  if (strong.length) {
    const devices = await db.collection("devices").get();
    for (const dev of devices.docs) {
      const d = dev.data();
      if (d.lastLat == null || d.lastLng == null) continue;
      for (const e of strong) {
        const km = haversineKm({ lat: d.lastLat, lng: d.lastLng }, e);
        if (km > alertRadiusKm(e.mag)) continue;
        const alertRef = dev.ref.collection("alerts").doc(`quake_${e.id}`);
        if ((await alertRef.get()).exists) continue;
        const title = `M${e.mag.toFixed(1)} earthquake ${Math.round(km)} km from ${d.name ?? "the device"}`;
        const body = `${e.location} · depth ${e.depthKm} km · ${e.ts.toLocaleTimeString("en-PH", { timeZone: "Asia/Manila", hour: "2-digit", minute: "2-digit" })} PHT. Check on ${d.name ?? "your child"}.`;
        await alertRef.set({ type: "quake", title, body, ts: Timestamp.fromDate(e.ts), lat: e.lat, lng: e.lng, mag: e.mag, distanceKm: Math.round(km), quakeId: e.id });
        await pushToParents(dev.id, { title, body, data: { type: "quake", deviceId: dev.id, quakeId: e.id } });
        alerts++;
      }
    }
  }
  console.log(`[${new Date().toISOString()}] quakes: ${events.length} scraped, ${recent.length} kept, ${strong.length} ≥M${MIN_MAG}, ${alerts} new alerts`);
}

/** Sends a push to every parent linked to the device; prunes dead tokens. */
export async function pushToParents(deviceId, { title, body, data = {} }) {
  const parents = await db.collection("users").where("deviceIds", "array-contains", deviceId).get();
  for (const p of parents.docs) {
    const tokens = p.data().fcmTokens ?? [];
    if (!tokens.length) continue;
    const res = await fcm.sendEachForMulticast({
      tokens,
      notification: { title, body },
      data: { ...data, click_action: "FLUTTER_NOTIFICATION_CLICK" },
      android: { priority: "high", notification: { channelId: "alerts", sound: "default" } },
    });
    const dead = tokens.filter((_, i) => res.responses[i].error?.code?.includes("registration-token-not-registered"));
    if (dead.length) await p.ref.update({ fcmTokens: FieldValue.arrayRemove(...dead) });
    console.log(`  push → ${p.id}: ${res.successCount} ok, ${res.failureCount} failed${dead.length ? `, ${dead.length} tokens pruned` : ""}`);
  }
}

// ---------- CLI ----------
const mode = process.argv[2] ?? "quakes";
if (mode === "loop") {
  for (;;) {
    try { await quakesJob(); } catch (e) { console.error("quakes job failed:", e.message); }
    await new Promise((r) => setTimeout(r, 5 * 60e3));
  }
} else {
  await quakesJob();
}
