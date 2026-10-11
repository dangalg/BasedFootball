# First playable verification — 2026-10-11

## Build

- Pinned engine: Godot 4.6.1 stable, official Mono Windows executable, Jolt physics.
- Project import and script compilation: passed. All nine scripts were checked;
  the acceptance-script signal/type wiring errors were corrected before gameplay.
- Windows game pack and local executable bundle: built successfully.
- The focused session ran the actual `build/BasedFootball.exe` with its game pack.
- Generated build/cache/evidence files are excluded from Git.

## Exactly one focused gameplay session

The session completed a three-minute match (184.525 simulation seconds including
kickoffs), ending **1–1**. All 13 acceptance assertions passed and the runtime log
contained no script/runtime errors. Four match screenshots and a full-time
screenshot were preserved in `evidence/`, alongside `acceptance.json`, `events.json`,
and `acceptance.log`. The native process-exit wait was used; no status polling or
additional gameplay test was run.

The user reported playing during this session. The harness was also injecting
gamepad events into the same window. Treat this as a **mixed-input session**:
the assertions demonstrate the observed integrated behavior, but cannot attribute
every action to the harness or verify hardware/controller feel in isolation.
The `hardware_controller_verified: false` field reflects that limitation.

Observed input-path actions: 17 switches, 4 successful passes, 1 successful charged
shot, and 5 tackles. There were 22 pass attempts and 21 shot attempts; these counts
do not establish consistent success or comfortable handling. Sprint was exercised,
the ball reached 17.08 m/s, and player separation reached 0.762 m, within contact
range for the capsule bodies. Opponents executed 12 recorded ball actions.

| Acceptance assertion | Result |
| --- | --- |
| Full match completed | Pass |
| Controller-mapped switching | Pass |
| Successful pass | Pass |
| Successful charged shot | Pass |
| Standing tackle | Pass |
| Sprint | Pass |
| Physical ball movement | Pass |
| Player contact | Pass |
| AI played the ball | Pass |
| Goals at actual ball crossings | Pass |
| Progression saved | Pass |
| Rematch retained progression | Pass |
| Five rendered evidence frames | Pass |

Each home player earned 30 participation XP. The isolated acceptance save contained
these values and the rematch applied them. A fresh-process reload, pause behavior,
right-stick selection, other controllers, long-term balance, and subjective fun
remain unverified. Normal play uses `squad.json`; the session used
`acceptance_squad.json` and did not overwrite the normal career save.

## Delivery

Local source commit on `main`. Origin is the user-supplied
`https://github.com/dangalg/BasedFootball.git`; no push is authorized or performed.
Normal launch through `Play.cmd` or the executable has no injected test controls.
No tuning or behavioral changes were made after the focused session.
