# Probe review follow-up

## Completed

- [x] Require a two-click confirmation before running character probes; cancel them on Close and wait for cleanup.
- [x] Restore WalkSpeed, JumpPower, and HipHeight only when the same character is still active and the value still matches the probe's change. Removed automatic position and noclip probes to avoid disruptive movement/collision changes.
- [x] Report remote traffic during probe windows as observation only; do not score or attribute temporal coincidences as causes.
- [x] Install the Live observer only after explicit opt-in, detach it on pause/close, and report failed cleanup without silently stacking another hook.
- [x] Use a checked, unique temporary filename for the file-I/O compatibility test and only remove the file Probe created.
- [x] Protect executor identity detection, recover a stale legacy guard when its UI is absent, and clear the new guard after startup failure or successful shutdown.
- [x] Validate persisted schema, place, size, and field shapes; preserve raw finding state and restore valid saved outcomes.
- [x] Make baseline toggling and reputation cycling functional, persisted, and consistent with the score and severity display.
- [x] Make Wipe clear the current-session index and invalidate pending outcome monitors; report when disk deletion is unavailable.
- [x] Align fingerprint confidence labels with equal-weight marker thresholds and describe matches as heuristic candidates.
- [x] Expand the README with usage boundaries, side effects, data handling, limitations, and local development checks.
- [x] Add dependency-free source-contract regression tests for the reviewed invariants.
- [x] Fix `safe()` so successful `false` return values are preserved rather than converted to `nil`.

## Runtime validation still needed

- [ ] In an authorized Roblox test place, verify Live attaches only after clicking, pauses by detaching, and handles a changed `__namecall` entry without overwriting it.
- [ ] In an authorized test place, confirm each temporary character property is restored when unchanged, left untouched if independently changed, and cleaned up when Close is clicked mid-probe.
- [ ] Verify save/load, schema-7 migration, Wipe behavior, and clipboard export using an executor that supports those APIs.
