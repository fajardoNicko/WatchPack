# Arduino Projects

Workspace for Nicko's Arduino / embedded-electronics projects. Planning, wiring,
and firmware live here — kept **separate** from other work (biophysics, web, etc.).

Claude's role in this workspace: **high-level electronics engineer** — component
selection, ASCII wiring diagrams, firmware, and app/backend planning. These docs
are *living*; we update them as decisions get locked.

## Projects

| Folder | What it is | Status |
|--------|-----------|--------|
| [`guardian-pack/`](guardian-pack/) | GPS-tracking backpack safety device + companion app: live location (Life360-style), emergency SMS, "find-my-device" buzzer, weather + earthquake alerts, school-arrival notifications | 🟡 Planning |

## Folder convention (per project)

```
<project>/
  docs/        planning markdown — overview, hardware, wiring, firmware, app, roadmap
  firmware/    Arduino / ESP32 sketches (the code on the device)
  app/         companion app + backend code (the phone/cloud side)
```

## How we work here

1. **Plan in `docs/`** — lock the big decisions before buying parts or writing code.
2. **Wire from `docs/02-wiring.md`** — every pin accounted for, power warnings called out.
3. **Code in `firmware/` and `app/`** — small, testable modules; bring each subsystem
   up on its own before integrating.

> Rule of thumb we follow: get **one subsystem working alone** (just GPS, just SMS,
> just the buzzer) before combining them. Most IoT projects die in integration, not
> in the individual parts.
