// Registers a real device: devices/<id> + its secret command mailbox cmdbox/<secret>,
// and links it (first) to a parent account so the app opens on it.
//   node src/provision.mjs [deviceId] [name] [parentEmail]
// Re-running keeps the existing secret. Prints the lines for firmware/include/secrets.h.
import { randomBytes } from "node:crypto";
import { readFileSync, existsSync } from "node:fs";
import { initializeApp, cert, applicationDefault } from "firebase-admin/app";
import { getFirestore, FieldValue } from "firebase-admin/firestore";

const keyPath = new URL("../serviceAccount.json", import.meta.url);
initializeApp({ credential: existsSync(keyPath) ? cert(JSON.parse(readFileSync(keyPath))) : applicationDefault() });
const db = getFirestore();

const [deviceId = "wp-001", name = "Ivy", email = "demo@watchpack.app"] = process.argv.slice(2);

const ref = db.doc(`devices/${deviceId}`);
const snap = await ref.get();
const secret = snap.get("cmdId") ?? randomBytes(16).toString("hex");

await ref.set(
  snap.exists
    ? { cmdId: secret }
    : { name, cmdId: secret, battery: 0, status: "idle", speedKmh: 0, buzz: false, contacts: [], lastSeen: null },
  { merge: true },
);
await db.doc(`cmdbox/${secret}`).set({ deviceId, buzz: false }, { merge: true });
const triggers = db.doc(`devices/${deviceId}/settings/triggers`);
if (!(await triggers.get()).exists) {
  await triggers.set({ lowBatteryPct: 20, lowBatteryOn: true, signalLossMin: 10, signalLossOn: true, offRouteOn: false });
}

const users = await db.collection("users").where("email", "==", email).get();
for (const u of users.docs) {
  const ids = (u.get("deviceIds") ?? []).filter((x) => x !== deviceId);
  await u.ref.update({ deviceIds: [deviceId, ...ids] });
  console.log(`linked ${deviceId} first on users/${u.id} (${email})`);
}
if (users.empty) console.log(`no profile with email ${email} — link it in the app: Settings → Link device → ${deviceId}`);

console.log(`\ndevice ${deviceId} ready. firmware/include/secrets.h:\n`);
console.log(`#define DEVICE_ID     "${deviceId}"`);
console.log(`#define DEVICE_SECRET "${secret}"`);
process.exit(0);
