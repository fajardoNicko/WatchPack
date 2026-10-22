// Firestore rules test for WatchPack linking / invites / members. Runs against the emulator.
import { initializeTestEnvironment, assertSucceeds, assertFails } from "@firebase/rules-unit-testing";
import {
  doc, getDoc, setDoc, updateDoc, deleteDoc, collection, query, where, getDocs,
  Timestamp, arrayUnion, arrayRemove, serverTimestamp, writeBatch,
} from "firebase/firestore";
import { readFileSync } from "node:fs";

const RULES = process.argv[2];
const env = await initializeTestEnvironment({
  projectId: "demo-watchpack",
  firestore: { rules: readFileSync(RULES, "utf8"), host: "127.0.0.1", port: 8080 },
});

const hours = (h) => Timestamp.fromMillis(Date.now() + h * 3600e3);

await env.withSecurityRulesDisabled(async (ctx) => {
  const db = ctx.firestore();
  await setDoc(doc(db, "devices/wp-001"), { name: "Ivy", cmdId: "SECRET" });
  await setDoc(doc(db, "devices/wp-002"), { name: "Other" });
  await setDoc(doc(db, "devices/wp-demo-ivy"), { name: "Ivy demo" });
  await setDoc(doc(db, "cmdbox/SECRET"), { deviceId: "wp-001", buzz: false });
  await setDoc(doc(db, "linkcodes/PAIRCODE"), { deviceId: "wp-001", kind: "device" });
  await setDoc(doc(db, "linkcodes/OLDINVIT"), { deviceId: "wp-001", kind: "invite", createdBy: "alice", expiresAt: hours(-1) });
  await setDoc(doc(db, "users/alice"), { email: "a@x", deviceIds: ["wp-001"] });
});

const as = (uid) => env.authenticatedContext(uid).firestore();
const alice = as("alice"), bob = as("bob"), eve = as("eve"), carol = as("carol");
const anon = env.unauthenticatedContext().firestore();

let pass = 0, fail = 0;
async function t(name, p) {
  try { await p; pass++; console.log("ok   ", name); }
  catch (e) { fail++; console.log("FAIL ", name, "-", e.message.split("\n")[0]); }
}

// --- sign-up and linking ---
await t("sign-up with demo device", assertSucceeds(setDoc(doc(bob, "users/bob"), { email: "b@x", deviceIds: ["wp-demo-ivy"], createdAt: serverTimestamp() })));
await t("sign-up with a real device, no code", assertFails(setDoc(doc(eve, "users/eve"), { email: "e@x", deviceIds: ["wp-001"] })));
await t("sign-up with demo", assertSucceeds(setDoc(doc(eve, "users/eve"), { email: "e@x", deviceIds: ["wp-demo-ivy"] })));
await t("link by device id alone", assertFails(setDoc(doc(eve, "users/eve"), { deviceIds: arrayUnion("wp-001") }, { merge: true })));
await t("link with a code for another device", assertFails(setDoc(doc(eve, "users/eve"), { deviceIds: arrayUnion("wp-002"), linkCode: "PAIRCODE" }, { merge: true })));
await t("link with a bogus code", assertFails(setDoc(doc(eve, "users/eve"), { deviceIds: arrayUnion("wp-001"), linkCode: "NOPENOPE" }, { merge: true })));
await t("link two devices with one code", assertFails(setDoc(doc(eve, "users/eve"), { deviceIds: arrayUnion("wp-001", "wp-002"), linkCode: "PAIRCODE" }, { merge: true })));
await t("link with the pairing code", assertSucceeds(setDoc(doc(eve, "users/eve"), { deviceIds: arrayUnion("wp-001"), linkCode: "PAIRCODE" }, { merge: true })));
await t("later profile writes (fcm token)", assertSucceeds(setDoc(doc(eve, "users/eve"), { fcmTokens: arrayUnion("tok") }, { merge: true })));
await t("read own profile", assertSucceeds(getDoc(doc(eve, "users/eve"))));
await t("read someone else's profile", assertFails(getDoc(doc(eve, "users/alice"))));
await t("write someone else's profile", assertFails(setDoc(doc(eve, "users/alice"), { displayName: "x" }, { merge: true })));

// --- invites ---
const invite = (expiresAt, by = "alice") => ({ deviceId: "wp-001", kind: "invite", createdBy: by, createdByName: "A", expiresAt });
await t("linked parent creates invite", assertSucceeds(setDoc(doc(alice, "linkcodes/INVITE01"), invite(hours(48)))));
await t("unlinked user creates invite", assertFails(setDoc(doc(bob, "linkcodes/INVITE02"), invite(hours(48), "bob"))));
await t("invite with a 10-day expiry", assertFails(setDoc(doc(alice, "linkcodes/INVITE03"), invite(hours(240)))));
await t("invite posing as another maker", assertFails(setDoc(doc(alice, "linkcodes/INVITE04"), invite(hours(48), "eve"))));
await t("invite of kind device", assertFails(setDoc(doc(alice, "linkcodes/INVITE05"), { ...invite(hours(48)), kind: "device" })));
await t("overwrite an existing code", assertFails(setDoc(doc(alice, "linkcodes/PAIRCODE"), invite(hours(48)))));
await t("anyone signed in can get a code", assertSucceeds(getDoc(doc(bob, "linkcodes/INVITE01"))));
await t("signed-out can't get a code", assertFails(getDoc(doc(anon, "linkcodes/INVITE01"))));
await t("list my invites", assertSucceeds(getDocs(query(collection(alice, "linkcodes"), where("createdBy", "==", "alice"), where("deviceId", "==", "wp-001")))));
await t("list someone else's invites", assertFails(getDocs(query(collection(bob, "linkcodes"), where("createdBy", "==", "alice")))));
await t("list all codes", assertFails(getDocs(collection(bob, "linkcodes"))));
await t("bob links with the invite", assertSucceeds(setDoc(doc(bob, "users/bob"), { deviceIds: arrayUnion("wp-001"), linkCode: "INVITE01" }, { merge: true })));
await t("bob retires the used invite", assertSucceeds(deleteDoc(doc(bob, "linkcodes/INVITE01"))));

// The app's real flow: profile + member entry + invite retired in one batch.
await t("dave links in one batch", (async () => {
  await assertSucceeds(setDoc(doc(as("dave"), "users/dave"), { email: "d@x", deviceIds: ["wp-demo-ivy"] }));
  await assertSucceeds(setDoc(doc(alice, "linkcodes/INVITE06"), invite(hours(48))));
  const dave = as("dave");
  const b = writeBatch(dave);
  b.set(doc(dave, "users/dave"), { deviceIds: arrayUnion("wp-001"), linkCode: "INVITE06" }, { merge: true });
  b.set(doc(dave, "devices/wp-001/members/dave"), { name: "D", email: "d@x", joinedAt: serverTimestamp() });
  b.delete(doc(dave, "linkcodes/INVITE06"));
  await assertSucceeds(b.commit());
})());
await t("member entry without linking in the batch", (async () => {
  const frank = as("frank");
  await assertSucceeds(setDoc(doc(frank, "users/frank"), { email: "f@x", deviceIds: ["wp-demo-ivy"] }));
  const b = writeBatch(frank);
  b.set(doc(frank, "users/frank"), { displayName: "F" }, { merge: true });
  b.set(doc(frank, "devices/wp-001/members/frank"), { name: "F", email: "f@x" });
  await assertFails(b.commit());
})());
await t("dave unlinks in one batch", (async () => {
  const dave = as("dave");
  const b = writeBatch(dave);
  b.update(doc(dave, "users/dave"), { deviceIds: arrayRemove("wp-001") });
  b.delete(doc(dave, "devices/wp-001/members/dave"));
  await assertSucceeds(b.commit());
})());
await t("expired invite", assertFails(setDoc(doc(carol, "users/carol"), { deviceIds: ["wp-001"], linkCode: "OLDINVIT" })));
await t("delete the pairing code", assertFails(deleteDoc(doc(alice, "linkcodes/PAIRCODE"))));
await t("stranger deletes an invite", assertFails(deleteDoc(doc(carol, "linkcodes/OLDINVIT"))));
await t("maker cancels an invite", assertSucceeds(deleteDoc(doc(alice, "linkcodes/OLDINVIT"))));

// --- members ---
await t("write my member entry", assertSucceeds(setDoc(doc(alice, "devices/wp-001/members/alice"), { name: "A", email: "a@x", joinedAt: serverTimestamp() })));
await t("write someone else's entry", assertFails(setDoc(doc(alice, "devices/wp-001/members/bob"), { name: "B", email: "b@x" })));
await t("unlinked writes an entry", assertFails(setDoc(doc(carol, "devices/wp-001/members/carol"), { name: "C", email: "c@x" })));
await t("entry on the demo device", assertFails(setDoc(doc(bob, "devices/wp-demo-ivy/members/bob"), { name: "B", email: "b@x" })));
await t("extra fields in an entry", assertFails(setDoc(doc(bob, "devices/wp-001/members/bob"), { name: "B", email: "b@x", admin: true })));
await t("linked reads members", assertSucceeds(getDocs(collection(bob, "devices/wp-001/members"))));
await t("unlinked reads members", assertFails(getDocs(collection(carol, "devices/wp-001/members"))));
await t("delete own entry", assertSucceeds(deleteDoc(doc(alice, "devices/wp-001/members/alice"))));

// --- unchanged behaviour ---
await t("linked parent reads device", assertSucceeds(getDoc(doc(alice, "devices/wp-001"))));
await t("unlinked reads device", assertFails(getDoc(doc(carol, "devices/wp-001"))));
await t("device writes telemetry with its secret", assertSucceeds(updateDoc(doc(anon, "devices/wp-001"), { status: "idle", battery: 80, auth: "SECRET:abc" })));
await t("telemetry with a wrong secret", assertFails(updateDoc(doc(anon, "devices/wp-001"), { status: "sos", auth: "WRONG:abc" })));
await t("app mirrors contacts to cmdbox", assertSucceeds(updateDoc(doc(alice, "cmdbox/SECRET"), { contacts: "+639171234567,+639181234567" })));
await t("cmdbox contacts as a list", assertFails(updateDoc(doc(alice, "cmdbox/SECRET"), { contacts: ["+639171234567"] })));
await t("cmdbox other field", assertFails(updateDoc(doc(alice, "cmdbox/SECRET"), { deviceId: "wp-002" })));
await t("device clears buzz", assertSucceeds(updateDoc(doc(anon, "cmdbox/SECRET"), { buzz: false })));
await t("parent renames device", assertSucceeds(updateDoc(doc(alice, "devices/wp-001"), { name: "Ivy B" })));
await t("delete own profile", assertSucceeds(deleteDoc(doc(alice, "users/alice"))));

// --- removing another parent ---
// grace and henry linked with the pairing code; ivan with an invite that is used up.
await env.withSecurityRulesDisabled(async (ctx) => {
  const db = ctx.firestore();
  for (const [uid, code] of [["grace", "PAIRCODE"], ["henry", "PAIRCODE"], ["ivan", "USEDINV1"], ["kate", "PAIRCODE"]]) {
    await setDoc(doc(db, `users/${uid}`), { email: `${uid}@x`, deviceIds: ["wp-001"], linkCode: code });
    await setDoc(doc(db, `devices/wp-001/members/${uid}`), { name: uid, email: `${uid}@x` });
  }
  await setDoc(doc(db, "devices/wp-001/locations/fix1"), { lat: 14.6, lng: 121, ts: Timestamp.now() });
});
const grace = as("grace"), henry = as("henry"), ivan = as("ivan");
const removal = (by) => ({ by, byName: by, at: serverTimestamp() });
const remove = (who, uid) => {
  const b = writeBatch(who);
  b.set(doc(who, `devices/wp-001/removed/${uid}`), removal(who === grace ? "grace" : "?"));
  b.delete(doc(who, `devices/wp-001/members/${uid}`));
  return b.commit();
};
// The app's flow when it finds itself removed, then links again with a code.
const relink = (who, uid, code, { invite = false } = {}) => {
  const b = writeBatch(who);
  b.set(doc(who, `users/${uid}`), { deviceIds: arrayUnion("wp-001"), linkCode: code }, { merge: true });
  b.set(doc(who, `devices/wp-001/members/${uid}`), { name: uid, email: `${uid}@x`, joinedAt: serverTimestamp() });
  b.delete(doc(who, `devices/wp-001/removed/${uid}`));
  if (invite) b.delete(doc(who, `linkcodes/${code}`));
  return b.commit();
};

await t("remove another parent", assertSucceeds(remove(grace, "henry")));
await t("removed parent can't read the device", assertFails(getDoc(doc(henry, "devices/wp-001"))));
await t("removed parent can't read locations", assertFails(getDocs(collection(henry, "devices/wp-001/locations"))));
await t("removed parent can't invite", assertFails(setDoc(doc(henry, "linkcodes/INVITE07"), invite(hours(48), "henry"))));
await t("removed parent can't re-add their entry", assertFails(setDoc(doc(henry, "devices/wp-001/members/henry"), { name: "H", email: "h@x" })));
await t("removed parent sees the removal", assertSucceeds(getDoc(doc(henry, "devices/wp-001/removed/henry"))));
await t("others can't read a removal", assertFails(getDoc(doc(grace, "devices/wp-001/removed/henry"))));
await t("removed parent can't just lift it", assertFails(deleteDoc(doc(henry, "devices/wp-001/removed/henry"))));
await t("remaining parent still reads", assertSucceeds(getDoc(doc(grace, "devices/wp-001"))));
await t("remove yourself this way", assertFails(setDoc(doc(grace, "devices/wp-001/removed/grace"), removal("grace"))));
await t("unlinked user removes a parent", assertFails(setDoc(doc(carol, "devices/wp-001/removed/grace"), removal("carol"))));
await t("removal signed as someone else", assertFails(setDoc(doc(grace, "devices/wp-001/removed/kate"), removal("henry"))));
await t("removal on the demo device", assertFails(setDoc(doc(bob, "devices/wp-demo-ivy/removed/eve"), removal("bob"))));
await t("delete another's entry without removing them", assertFails(deleteDoc(doc(grace, "devices/wp-001/members/kate"))));
await t("removed parent unlinks", assertSucceeds(updateDoc(doc(henry, "users/henry"), { deviceIds: arrayRemove("wp-001") })));
await t("back with the pairing code", assertSucceeds(relink(henry, "henry", "PAIRCODE")));
await t("reads again after re-linking", assertSucceeds(getDoc(doc(henry, "devices/wp-001"))));

await t("remove the invited parent", assertSucceeds(remove(grace, "ivan")));
await t("invited parent unlinks", assertSucceeds(updateDoc(doc(ivan, "users/ivan"), { deviceIds: arrayRemove("wp-001") })));
await t("back with the used-up invite", assertFails(relink(ivan, "ivan", "USEDINV1")));
await t("back with a fresh invite", (async () => {
  await assertSucceeds(setDoc(doc(grace, "linkcodes/INVITE08"), invite(hours(48), "grace")));
  await assertSucceeds(relink(ivan, "ivan", "INVITE08", { invite: true }));
  await assertSucceeds(getDoc(doc(ivan, "devices/wp-001")));
})());

console.log(`\n${pass} passed, ${fail} failed`);
await env.cleanup();
process.exit(fail ? 1 : 0);
