// Pairing sticker for a WatchPack, 40 × 50 mm SVG: the QR the app scans
// ("WATCHPACK:<code>", mobile/lib/data/linking.dart codeFromScan) and the code in text.
//   npm run sticker -- <CODE> [deviceId]     → stickers/<deviceId>.svg
// provision.mjs makes one as well. stickers/ is git-ignored: the code is the key to the device.
import { mkdirSync, writeFileSync } from "node:fs";
import { pathToFileURL } from "node:url";
import QRCode from "qrcode";

export async function writeSticker(code, deviceId) {
  const clean = code.toUpperCase().replace(/[^A-Z0-9]/g, "");
  if (clean.length !== 8) throw new Error(`"${code}" is not an 8-character pairing code`);
  const qr = await QRCode.toString(`WATCHPACK:${clean}`, {
    type: "svg", margin: 0, errorCorrectionLevel: "M", color: { dark: "#0B2A55", light: "#FFFFFF" },
  });
  const inner = qr.replace(/^<\?xml[^>]*>\s*/, "").replace("<svg ", '<svg x="7" y="9" width="26" height="26" ');
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="40mm" height="50mm" viewBox="0 0 40 50">
  <rect x="0.15" y="0.15" width="39.7" height="49.7" rx="2" fill="#fff" stroke="#0B2A55" stroke-width="0.3"/>
  <text x="20" y="5.2" text-anchor="middle" font-family="Arial, sans-serif" font-size="3.6" font-weight="700" fill="#0B2A55">Watch<tspan fill="#3FB9D0">Pack</tspan></text>
  ${inner.trim()}
  <text x="20" y="43" text-anchor="middle" font-family="Consolas, monospace" font-size="4.4" font-weight="700" fill="#0B2A55">${clean.slice(0, 4)}-${clean.slice(4)}</text>
  <text x="20" y="47.5" text-anchor="middle" font-family="Arial, sans-serif" font-size="2.1" fill="#5B6472">Pairing code - keep it private</text>
</svg>
`;
  const dir = new URL("../stickers/", import.meta.url);
  mkdirSync(dir, { recursive: true });
  const file = new URL(`${deviceId ?? clean}.svg`, dir);
  writeFileSync(file, svg);
  return file;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const [code, deviceId] = process.argv.slice(2);
  if (!code) {
    console.error("usage: npm run sticker -- <CODE> [deviceId]");
    process.exit(1);
  }
  console.log(`sticker: ${(await writeSticker(code, deviceId)).pathname}`);
}
