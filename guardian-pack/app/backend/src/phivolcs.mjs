// Scrapes PHIVOLCS "Latest Earthquake Information" into clean event objects.
// Source: https://earthquake.phivolcs.dost.gov.ph/ — a plain HTML table:
//   Date - Time (PHT) | Latitude (ºN) | Longitude (ºE) | Depth (km) | Mag | Location
// PHIVOLCS has no API and the markup changes now and then, so parsing is defensive:
// rows that don't look like an event are skipped, never fatal.

import * as cheerio from "cheerio";

export const PHIVOLCS_URL = "https://earthquake.phivolcs.dost.gov.ph/";

const MONTHS = { january: 0, february: 1, march: 2, april: 3, may: 4, june: 5, july: 6, august: 7, september: 8, october: 9, november: 10, december: 11 };

/** "09 October 2026 - 07:24 PM" (Philippine time, UTC+8) → Date (UTC). */
export function parsePhtDate(s) {
  const m = s.replace(/\s+/g, " ").trim().match(/^(\d{1,2}) ([A-Za-z]+) (\d{4}) - (\d{1,2}):(\d{2}) (AM|PM)$/i);
  if (!m) return null;
  const [, d, mon, y, hh, mm, ap] = m;
  const month = MONTHS[mon.toLowerCase()];
  if (month === undefined) return null;
  let h = Number(hh) % 12;
  if (ap.toUpperCase() === "PM") h += 12;
  return new Date(Date.UTC(Number(y), month, Number(d), h - 8, Number(mm)));   // PHT = UTC+8
}

/** Stable id from the fields PHIVOLCS never changes for an event. */
export function eventId(ts, lat, lng) {
  return `${ts.toISOString().slice(0, 16).replace(/[-:T]/g, "")}_${lat.toFixed(2)}_${lng.toFixed(2)}`;
}

export function parseTable(html) {
  const $ = cheerio.load(html);
  const events = [];
  $("tr").each((_, tr) => {
    const cells = $(tr).find("td").map((_, td) => $(td).text().replace(/\s+/g, " ").trim()).get();
    if (cells.length < 6) return;
    const ts = parsePhtDate(cells[0]);
    const lat = Number(cells[1]), lng = Number(cells[2]), depthKm = Number(cells[3]), mag = Number(cells[4]);
    if (!ts || [lat, lng, depthKm, mag].some(Number.isNaN)) return;
    if (lat < 3 || lat > 22 || lng < 115 || lng > 130) return;     // sanity: Philippine region
    const href = $(tr).find("a[href]").first().attr("href") ?? null;
    events.push({
      id: eventId(ts, lat, lng),
      ts, lat, lng, depthKm, mag,
      location: cells[5],
      source: "PHIVOLCS",
      url: href ? new URL(href.replace(/\\/g, "/"), PHIVOLCS_URL).href : PHIVOLCS_URL,
    });
  });
  // newest first, de-duplicated (the page sometimes repeats an event after an update)
  const seen = new Set();
  return events.filter((e) => (seen.has(e.id) ? false : seen.add(e.id))).sort((a, b) => b.ts - a.ts);
}

export async function fetchQuakes() {
  const r = await fetch(PHIVOLCS_URL, { headers: { "User-Agent": "WatchPack/0.1 (+earthquake alerts for parents)" } });
  if (!r.ok) throw new Error(`PHIVOLCS ${r.status}`);
  return parseTable(await r.text());
}

// CLI: node src/phivolcs.mjs  → prints the latest events
if (process.argv[1] && import.meta.url.endsWith(process.argv[1].replace(/\\/g, "/").split("/").pop())) {
  const q = await fetchQuakes();
  console.log(`${q.length} events`);
  for (const e of q.slice(0, 8)) console.log(`${e.ts.toISOString()}  M${e.mag.toFixed(1)}  ${e.depthKm} km  ${e.lat},${e.lng}  ${e.location}`);
}
