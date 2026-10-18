// Severe-weather watcher: thunderstorms, heavy rain and strong wind where the child is,
// now or in the next hour. Open-Meteo (free, no key). Only a rounded position (~10 km)
// leaves the backend.
//   node src/weather.mjs 14.6 121.0   — print what it sees for a spot, no alerts
import { fileURLToPath } from "node:url";

const HEAVY_RAIN_MM_H = 7.5;            // PAGASA yellow rainfall warning starts here
const STRONG_GUST_KMH = 62;             // tropical-storm-force gusts
const THUNDER = new Set([95, 96, 99]);  // WMO weather codes
const CACHE_MS = 15 * 60e3;

const cache = new Map();                // "14.6,121.0" → { at, data }

async function forecast(lat, lng) {
  const key = `${lat.toFixed(1)},${lng.toFixed(1)}`;
  const hit = cache.get(key);
  if (hit && Date.now() - hit.at < CACHE_MS) return hit.data;
  const [la, lo] = key.split(",");
  const url = `https://api.open-meteo.com/v1/forecast?latitude=${la}&longitude=${lo}` +
    "&current=weather_code,precipitation,wind_gusts_10m" +
    "&hourly=weather_code,precipitation,wind_gusts_10m&forecast_hours=2&timezone=Asia%2FManila";
  const res = await fetch(url, { signal: AbortSignal.timeout(15000) });
  if (!res.ok) throw new Error(`open-meteo ${res.status}`);
  const data = await res.json();
  cache.set(key, { at: Date.now(), data });
  return data;
}

/** The worst thing happening now or within the hour, or null. */
export async function severeWeather(lat, lng) {
  const { current: c, hourly: h } = await forecast(lat, lng);
  const codes = [c.weather_code, ...h.weather_code];
  const rain = Math.max(c.precipitation * 4, ...h.precipitation);      // current is a 15-min sum
  const gust = Math.max(c.wind_gusts_10m, ...h.wind_gusts_10m);
  if (codes.some((x) => THUNDER.has(x))) return { kind: "thunder", rain, gust };
  if (rain >= HEAVY_RAIN_MM_H || codes.some((x) => x === 65 || x === 82)) return { kind: "rain", rain, gust };
  if (gust >= STRONG_GUST_KMH) return { kind: "wind", rain, gust };
  return null;
}

export function weatherText(w, name) {
  switch (w.kind) {
    case "thunder":
      return { title: `Thunderstorm near ${name}`, body: `A thunderstorm is over or close to ${name}'s area this hour. Make sure ${name} is indoors.` };
    case "rain": {
      const amount = w.rain >= HEAVY_RAIN_MM_H ? `About ${Math.round(w.rain)} mm/h` : "Heavy showers";
      return { title: `Heavy rain where ${name} is`, body: `${amount} this hour around ${name}'s area — watch for flooding on the way home.` };
    }
    default:
      return { title: `Strong wind near ${name}`, body: `Gusts up to ${Math.round(w.gust)} km/h this hour around ${name}'s area.` };
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const [lat = "14.6", lng = "121.0"] = process.argv.slice(2);
  const f = await forecast(+lat, +lng);
  console.log(JSON.stringify({ current: f.current, hourly: f.hourly }, null, 1));
  console.log("severe:", (await severeWeather(+lat, +lng)) ?? "none");
}
