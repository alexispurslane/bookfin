# Corrected ordinary Android acceptance

The result is in `docs/evidence/reader/android-corrected-formats-20261103.md`.
This directory applies to exact source
`44d53afbe491f28cec0205584ba7f023ec8a10b6`, not the earlier rejection build or a
future OCR build. It contains ordinary Jellyfin responses, exact installed APK
readbacks, scoped Android database captures and audited screenshots.

`check_evidence.py` reads only committed evidence and writes
`evidence-checks.json`. Run it through `nix develop --command python3`.
It is an evidence consistency check, not coverage or mutation testing.
It deliberately records the KF8 navigation and explicit sync retry failures
instead of treating retained record hashes as visible-text success.

Private fixture files and database copies are removed after audit. No password
or token belongs here. `cleanup.json` records the audit before the final Device
panel release; the release result is reported separately by the acceptance lane.
