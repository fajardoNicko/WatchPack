// Sends a test push to every parent linked to a device.
//   node src/testpush.mjs [deviceId]
import { pushToParents } from "./run.mjs";

const deviceId = process.argv[2] ?? "wp-demo-ivy";
await pushToParents(deviceId, {
  title: "WatchPack test",
  body: "Push notifications are working. Ivy says hi 👋",
  data: { type: "test", deviceId },
});
console.log("done");
process.exit(0);
