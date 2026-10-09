// Creates (or signs into) the demo parent account and makes sure its profile is
// linked to the demo device. Uses the public Firebase Auth REST API with the
// project's Android API key, then writes the profile as that user (so the security
// rules allow it).  Run:  node tools/create_demo_account.mjs
import { readFileSync } from "node:fs";

const cfg = JSON.parse(readFileSync(new URL("../mobile/android/app/google-services.json", import.meta.url)));
const API_KEY = cfg.client[0].api_key[0].current_key;
const PROJECT = cfg.project_info.project_id;

const EMAIL = process.env.DEMO_EMAIL ?? "demo@watchpack.app";
const PASSWORD = process.env.DEMO_PASSWORD ?? "watchpack-demo-2026";
const NAME = "Nicko (demo)";
const DEVICE = "wp-demo-ivy";

const auth = (path, body) =>
  fetch(`https://identitytoolkit.googleapis.com/v1/accounts:${path}?key=${API_KEY}`, {
    method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body),
  }).then(async (r) => { const j = await r.json(); if (!r.ok) throw new Error(JSON.stringify(j.error)); return j; });

let user;
try {
  user = await auth("signUp", { email: EMAIL, password: PASSWORD, returnSecureToken: true });
  console.log("created", EMAIL);
} catch (e) {
  if (!String(e.message).includes("EMAIL_EXISTS")) throw e;
  user = await auth("signInWithPassword", { email: EMAIL, password: PASSWORD, returnSecureToken: true });
  console.log("exists, signed in", EMAIL);
}
await auth("update", { idToken: user.idToken, displayName: NAME, returnSecureToken: false });

const doc = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents/users/${user.localId}`;
const r = await fetch(`${doc}?updateMask.fieldPaths=email&updateMask.fieldPaths=displayName&updateMask.fieldPaths=deviceIds`, {
  method: "PATCH",
  headers: { "Content-Type": "application/json", Authorization: `Bearer ${user.idToken}` },
  body: JSON.stringify({ fields: {
    email: { stringValue: EMAIL },
    displayName: { stringValue: NAME },
    deviceIds: { arrayValue: { values: [{ stringValue: DEVICE }] } },
  } }),
});
if (!r.ok) throw new Error(`profile write failed: ${r.status} ${await r.text()}`);
console.log(`profile users/${user.localId} linked to ${DEVICE}`);
console.log(`\nSign in with:\n  email:    ${EMAIL}\n  password: ${PASSWORD}`);
