# Probe

Probe is a client-side diagnostic script for **Roblox experiences you own or are explicitly authorized to test**. It surfaces local observations for debugging an experience's defensive behavior; it is not a server-side security test, a bypass, or proof that a system is present or absent.

## Important limitations and safety

- Use it only in an isolated test place or other environment where you have permission. Do not run state-changing probes in public experiences or against other players.
- Most scans are observational, but the optional **Live** mode temporarily installs a `game.__namecall` observer. This changes the local client's call path. Live is off by default; pausing it attempts to restore the previous metatable entry. If safe restoration fails, the UI reports that and offers a separate **Close anyway** action; the observer is inactive, the load guard remains set, and reloading the client is the safest cleanup.
- **Probe** temporarily changes the local character's WalkSpeed, JumpPower, and HipHeight for short observation windows. It does not perform an automatic position/teleport test. Probe requires two clicks within five seconds. Each property is restored only if the same character is still active and the value still equals the test value. If something else changes it during the window, Probe preserves that newer value rather than overwriting it. Close cancels the sequence and waits for cleanup.
- Calls observed during a probe or near a monitored remote are temporal observations only. Probe does not establish that a call caused a state change or that the server accepted/rejected anything.
- Fingerprints and keyword matches are heuristics. A match is a lead to inspect, not identification. No client observation can establish server-side enforcement.

## Runtime

`main.lua` is a standalone Luau script that depends on Roblox client APIs and optional executor-provided APIs such as file I/O, metatable inspection, and script decompilation. It is not a normal Roblox Studio plugin and some views/features will be unavailable when those APIs are missing.

On startup, Probe runs compatibility checks and a read-only scan. Compatibility checks may briefly connect/disconnect a local signal, change the read-only state of a metatable before relocking it, and test hook support only on temporary local functions/tables. The file-I/O check reserves a unique temporary filename before writing; when deletion is supported, it removes the temporary file.

### Controls

- **Run All**: re-runs the local scans. It does not deliberately fire remotes.
- **Live: Off / Live: On**: enables/disables remote-call and local-state observation. This installs the observer only after explicit opt-in and attempts to detach it when paused.
- **Probe**: click once to arm, then click again within five seconds to confirm the temporary local character changes. Only use in an authorized test environment.
- **JSON**: copies the current snapshot to the clipboard when clipboard support is available.
- **Wipe**: stops Live, clears in-memory history and pending outcome monitors, and attempts to delete the saved file. If file deletion is unavailable, the UI says that only memory was cleared.
- **Close**: stops active work, waits for a probe to clean up, attempts to detach Live, saves the snapshot, then removes the UI.

## Data and privacy

When file I/O is available, Probe stores a local JSON snapshot under `ACProbeV7/<placeId>.json` (or a flat-file fallback). It may contain the Roblox account name and user ID, place ID, local script/instance paths, observations, and session history. Probe does not upload data or make HTTP requests. The JSON clipboard action is explicit; inspect the snapshot before sharing it.

Saved schema 7 snapshots are accepted and merged into schema 8 data. Invalid, oversized, mismatched-place, or unsupported-schema files are ignored rather than merged. Outcome history is restored from a valid saved snapshot.

## Development checks

Run the dependency-free source-contract regression checks with:

```sh
python3 -m unittest discover -s tests -v
```

These checks guard important source-level safety invariants. They do not emulate Roblox or replace runtime testing in an authorized test place. A full runtime test still needs Roblox/Luau APIs and a controlled experience.