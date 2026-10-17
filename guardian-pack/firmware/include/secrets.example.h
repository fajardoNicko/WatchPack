// Copy this file to include/secrets.h (git-ignored) and fill in real values.
// Never commit secrets.h.
#pragma once

// Phone numbers that receive the SOS text, international format.
#define SOS_CONTACTS { "+639XXXXXXXXX" }

// Name shown in the SOS text.
#define CHILD_NAME "Ivy"

// Cloud identity — printed by `node app/backend/src/provision.mjs <deviceId>`.
#define DEVICE_ID     "wp-001"
#define DEVICE_SECRET "00000000000000000000000000000000"
