// Off-route detection without a map of "the route": learn the places a device usually
// goes — ~220 m grid cells it was in on at least 2 different days in the last 2 weeks —
// and flag a fix that is far from all of them. Today's fixes are added as they arrive
// but don't count as usual until another day, so a detour never teaches itself.
import { Timestamp } from "firebase-admin/firestore";

const CELL = 0.002;                     // degrees, ~220 m
const CELL_M = 220;
const HISTORY_DAYS = 14;
const MIN_DAYS = 3;                     // history needed before it judges anything
const MAX_RING = 10;                    // search out to ~2.2 km
const RELOAD_MS = 24 * 3600e3;

const dayOf = (ms) => new Date(ms + 8 * 3600e3).toISOString().slice(0, 10);      // Manila date
const cellOf = (lat, lng) => [Math.floor(lat / CELL), Math.floor(lng / CELL)];

export class RouteMemory {
  #devices = new Map();                 // deviceId → { cells: Map<key, Set<day>>, days: Set<day>, loadedAt }

  async #load(ref) {
    const since = Timestamp.fromMillis(Date.now() - HISTORY_DAYS * 86400e3);
    const q = await ref.collection("locations").where("ts", ">=", since).select("lat", "lng", "ts").get();
    const m = { cells: new Map(), days: new Set(), loadedAt: Date.now() };
    for (const doc of q.docs) {
      const { lat, lng, ts } = doc.data();
      if (typeof lat === "number" && typeof lng === "number" && ts instanceof Timestamp) this.#add(m, lat, lng, ts.toMillis());
    }
    this.#devices.set(ref.id, m);
    console.log(`  routes: ${ref.id} learned ${m.cells.size} cells over ${m.days.size} days`);
    return m;
  }

  #add(m, lat, lng, ms) {
    const day = dayOf(ms);
    m.days.add(day);
    const k = cellOf(lat, lng).join(":");
    if (!m.cells.has(k)) m.cells.set(k, new Set());
    m.cells.get(k).add(day);
  }

  /**
   * How far the fix is from the usual places: { learning: true } while there's too
   * little history, else { metres } (Infinity beyond ~2 km). Remembers the fix.
   */
  async check(ref, lat, lng) {
    let m = this.#devices.get(ref.id);
    if (!m || Date.now() - m.loadedAt > RELOAD_MS) m = await this.#load(ref);
    const today = dayOf(Date.now());
    const pastDays = (set) => set.size - (set.has(today) ? 1 : 0);
    let result = { learning: true };
    if (pastDays(m.days) >= MIN_DAYS) {
      const [i, j] = cellOf(lat, lng);
      const usual = (di, dj) => {
        const s = m.cells.get(`${i + di}:${j + dj}`);
        return s != null && pastDays(s) >= 2;
      };
      let ring = Infinity;
      for (let r = 0; r <= MAX_RING && ring === Infinity; r++) {
        for (let di = -r; di <= r && ring === Infinity; di++) {
          for (let dj = -r; dj <= r; dj++) {
            if (Math.max(Math.abs(di), Math.abs(dj)) === r && usual(di, dj)) { ring = r; break; }
          }
        }
      }
      result = { learning: false, metres: ring * CELL_M };
    }
    this.#add(m, lat, lng, Date.now());
    return result;
  }
}
