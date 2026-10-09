# Re-seeds the demo device. The live rules make locations/alerts read-only, so this
# opens the database for the ~1 minute the seed takes, then restores the real rules.
# Run from app/:  powershell -File tools/seed.ps1
$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)
try {
    Write-Host "opening rules (temporary)..."
    firebase deploy --only firestore:rules --config firebase.open.json --non-interactive | Select-String "released|Error"
    node tools/seed_demo.mjs
} finally {
    Write-Host "restoring real rules..."
    firebase deploy --only firestore:rules --config firebase.json --non-interactive | Select-String "released|Error"
}
