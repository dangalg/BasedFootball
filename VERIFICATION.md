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

## Close control update — 2026-10-11

Small stick movements now scale dribble touches with requested and actual player
speed. Reach-limited impulses guide the ball around the player on turns and settle
a nearby ground ball when input is released. Sprint pushes remain longer. Fast
relative motion, height and reach limits preserve loose balls and physical tackles.
The shared controller applies these rules to humans and AI. Player rigid bodies
now have `can_sleep = false`, so movement forces respond after standing still.

The first approved dribble session failed because the player stayed stationary;
its report, trace, log and six images are preserved in
`evidence/dribble-attempt-1/`. After explicit approval, the only additional gameplay
change was keeping player bodies awake. The same test with unchanged criteria was
run once after a clean rebuild and **passed all 11 assertions**:

- Walking and left/right turns physically moved the player.
- Close-control ball gap peaked at **0.8405 m**, with mean **0.7959 m**.
- Stopping left a **0.7978 m** gap and **0.0046 m/s** horizontal ball speed.
- Sprint touches reached a **1.2616 m** gap.
- The opponent's production tackle broke possession, reaching a **4.0169 m** gap.
- Out-of-reach and airborne balls received no control touches.
- All six rendered evidence frames were saved and inspected.

The sequence uses production rigid bodies and actions with direct player intents;
match input and opponent AI decisions are disabled during this isolated test.
It injects no gamepad events and cannot overlap human match controls. Career data
is not saved by the sequence. Results are in `evidence/dribble-acceptance.json`,
`dribble-trace.json`, `dribble-acceptance.log`, and `dribble_*.png`. The passing
runtime log contained no errors. Hardware controller feel, full-match AI behavior
with the new touches, and subjective fun remain unverified.

Build output was excluded from Godot scanning/export to prevent bundling generated
runtime files. The user subsequently requested tests stay off the screen used for
FIFA. Test launch now requests a hidden window at an off-screen position; that
launcher-only change received a PowerShell structural check, without another
gameplay run. Normal play stays visible and has no automated test inputs.

Delivery remains a local commit on `main`; no remote push is performed. No gameplay
tuning or further behavioral test was performed after the passing revised session.

## Tight turns update — 2026-10-11

Recent ground-ball touches now briefly reduce requested carrier speed on sharp
non-sprint turns. Faster bounded sideways impulses guide the ball around the body.
Movement still uses capped forces; the ball remains a free rigid body. Humans and
AI share the same handling code.

Godot import and Windows game-pack export completed cleanly. Exactly one focused
rendered sequence ran against the rebuilt executable and passed all 13 checks:

- Full-stick carrying, two 90-degree turns and a 180-degree reversal moved the
  carrier in the requested directions while keeping the ball within kicking reach.
- Maximum carrying/turning gap was **0.9429 m**, with mean **0.7603 m**.
- Stopping left a **0.7606 m** gap and **0.0009 m/s** horizontal ball speed.
- Sprinting could separate the ball; the sequence reached a **9.5894 m** gap.
- An opponent tackle took possession away, reaching a **4.0069 m** gap.
- Airborne and out-of-reach balls received no control touches.
- Seven rendered frames were saved; reversal and stopping frames were inspected.

Results are preserved in `evidence/tight-turn-acceptance.json`,
`tight-turn-trace.json`, `tight_turn_*.png`, and `dribble-acceptance.log`.
The earlier passing dribble log is preserved as `dribble-passing-session.log`.
The runtime log contained no errors. Match hardware input and AI decisions were
disabled during the sequence, and no gamepad events were injected. Hardware feel,
full-match AI behavior and subjective handling remain for user evaluation.

The launcher requested a hidden window at `(30000, 30000)`, but Godot reported
`(3414, 766)`. Completely off-screen rendering is therefore unverified; this run
does not establish that the test could not appear over another application.
No further test or gameplay tuning was performed. Delivery is local on `main`,
with no remote push; the rebuilt game is available through the desktop shortcut.

## Desktop icon — 2026-10-11

Created a dark rounded-square icon with a turquoise pitch and a high-contrast
football. `tools/make_icon.py` builds SVG, PNG and ICO artwork; no game build is
needed because only the desktop shortcut's icon reference changes. One focused
setup check parsed the SVG and decoded the PNG and all seven ICO sizes
(16, 24, 32, 48, 64, 128, 256). The PNG preview was inspected. Shortcut readback
confirmed the new ICO path, unchanged playable target and empty arguments.
The game was not launched. Windows desktop icon-cache refresh remains unverified.
The intended source/artwork files are committed locally on `main`, without push.

## Physical touches, athletes and running direction - 2026-10-11

The current build supersedes the historical handling results above. It uses a
22 cm, 430 g free ball, roughly 1.8 m procedural athletes, PlayStation Classic
contextual controls, contact-timed dribble/kick impulses and three challenges.
Running faces actual horizontal velocity; action facing and jockeying remain
separate. Backpedalling reverses the gait. A kickoff clears the old possession
marker so opponents can control their own restart.

Earlier failures were preserved and corrected through the approved revised work:

- `run_1791744221882_b1e4dd20084a418baf823f26d10f29da`: 70/73;
  turn/stop control and an overly strict shoulder separation check failed.
- `run_1791745729047_e6645e5428af48799a8e03275f3360a4`: 79/82;
  the first timed-touch version lost control on turns and snapped the leg pose.
  Earlier trap scheduling, foot tracking before contact and angular limits fixed these.
- `run_1791745962625_a730d0a40ac741f89ca15958435dace9`: 8/9;
  live decisions exposed the stale kickoff ownership marker.
- `run_1791746273937_9830d1280c09416cba75d1a91ed0d264`: 9/10;
  facing passed, but a home-dominated, goalless opening had no orange dribble
  contacts. The scenario now starts with an orange kickoff to exercise their
  possession path directly; subsequent play uses normal match rules.

Final rebuilt-pack results:

| Scenario | Result | Evidence run |
| --- | --- | --- |
| Handling and tackles | 82/82 | `run_1791746335614_047cdc70929d4cdc84005ea09eea12b6` |
| Reactive decisions against normal AI | 10/10 | `run_1791746381889_bc42aad549fd44f399b070812f5c6bb8` |

Handling gaps peaked at 0.782 m during ordinary turns, 0.624 m during sustained
sprint and 0.678 m during a fast turn. Stopping left a 0.599 m gap and 0.0136 m/s
ball speed. All contact, miss, slide recovery, physical shoulder, flight and leg
blend checks passed. Thirty-six rendered frames include walk/sprint sequences;
selected close-up frames were inspected.

The live session made 171 reactive decisions and seven completed kicks; blue and
orange made 29 and 10 dribble contacts. Ordinary running faced away from velocity
in 11/7,832 blue and 21/7,793 orange samples, within brief turning transitions
under the 3 percent test limit. This is not a zero-transition or subjective
animation-quality claim. Normal AI, goals and ball physics were active. Both final
runs exited successfully without runtime errors; game-dev capture verification
confirmed the closed artifact rosters and hashes.

Evidence lives beneath `evidence/game-dev/.game-dev/runs/` and is Git-ignored.
Tests disable hardware input and do not overwrite normal career data. These are
rendered production-physics checks plus a short reactive decision session, not
hardware-controller validation, balance testing, subjective feel or a GPU benchmark.
The rebuilt local executable is available through the desktop shortcut. No push.

## Forward elbow bend and documentation captures - 2026-10-11

The user identified backwards forearms in the athlete screenshots. The elbow
flexion sign was incorrect for the model's local -Z forward direction. Both elbow
angles now bend the forearms forward; shoulder gait and physical contact code are
unchanged.

The rebuilt pack passed all 82 handling checks in
`run_1791746745699_777ac48b1807407c9d064c36f445d129`, saving 36 rendered frames.
Idle athlete and sprint frames were inspected for the corrected bend. Capture
verification passed with closed artifact hashes; no runtime errors were reported.
The earlier 10/10 live decision result remains historical; that scenario was not
repeated for this isolated elbow change.

The README uses two unedited frames from this corrected run. Documentation images
are excluded from Godot import with `docs/.gdignore`. GitHub source publication
was subsequently authorized by the user; earlier local-only delivery notes above
describe their historical milestones. Generated playable builds and raw evidence
remain local.

## Local physical falls, timed hops and varied AI - 2026-10-11

The user approved slide-induced ragdolls, R1 hops and bounded AI decision randomness.
The upright controller is retained. Swept slide-boot/lower-leg contact measures
closing speed and direction; movement, balance, energy and jockey stance determine
whether the hit produces a stumble or loses upright balance. Impact classification
does not sample randomness. A fall transfers the visible athlete and momentum to
11 joined rigid bodies, with the normal capsule disabled. Once the body settles,
clearance is checked and a get-up animation blends back to upright play. Get-up
uses an authored blend, not a fully physical muscular recovery controller.

R1 / E schedules an 80 ms preparation followed by an upward impulse. The real
collision body rises and lands under gravity, with reduced air steering, a cooldown
and a small stamina cost. Airborne/fallen players cannot supply close-control
touches or other actions. AI timing, positioning, sprint/challenge choices, pass
receivers and kick execution vary within bounds; tests seed the individual RNGs.

Development failures were preserved: the initial impact harness had an untyped
capture filename parse error; a subsequent run exposed renamed duplicate limbs
and an incomplete ragdoll. Explicit node names fixed the handoff, and spreading
the physical impact across pelvis, torso and struck shin avoids excessive torque.
A later run passed gameplay checks but failed the capture schema because AI frame
labels contained uppercase characters; the wrapper now normalizes labels.

Final recorded runs:

| Scenario | Checks | Evidence run |
| --- | --- | --- |
| Physical impacts and hops | 22/22 | `run_1791748133679_34046d063d8d4d8f8e00b2147fcc6f27` |
| Existing handling and challenges | 82/82 | `run_1791748014473_37e6cafbf06d498fb704674dbfd9cb00` |
| Reactive decisions against varied AI | 11/11 | `run_1791748195933_b17a248cd96f4898bfd9f8d69580e582` |

Impact coverage includes light stumbles, actual slide trips, early clearance and
late-hop trips, the same marginal impact at low/high balance, an AI-requested hop,
pause/resume, board recovery, restart cleanup and blocked actions while fallen.
The skill-threshold cases apply the same impulse directly to the production
response; real slide-to-leg detection is exercised separately. The AI hop case
samples 24 seeded choices in the same threat state, then physically runs one
successful choice; those probes are not 24 separate played collisions.
Fifty-one frames were saved. Fall, hop, recovery and restored-standing frames were
inspected. Maximum ragdoll-part speed was 8.202 m/s and all positions stayed finite.

The 30-second live session ended 1-1, with 21 blue and 18 orange dribble contacts,
five completed kicks, 17 AI actions and 37 distinct sampled AI reaction intervals.
An opponent physically fell at 2.13 seconds and got up at 4.33 seconds. The session
kept normal AI, rules and physics active with isolated career data and no hardware
input. All final processes exited successfully without runtime errors. Sealed
capture verification checked the final artifact rosters and hashes.

Physical controller feel, longer match balance and recovery in every possible
crowd arrangement remain human-playtest work. The rebuilt desktop executable is
ready. This update is committed locally; it has not been pushed to GitHub.

## Athlete models and animation - 2026-10-12

Approved correction, build clean. One `athlete-animation` rendered sequence passed
all 50 checks and saved 37 frames in
`run_1791817083312_075d89a8b6a445c7befeba232bbdcf09`. Closed capture roster and
hashes verified. Reviewed model, running, dribble, fall and recovered-model frames:
limb surfaces are solid after correcting winding, outward normals and end caps.
Both teams show ground-height stance samples and elevated swing samples; physical
boot dribble/kick contact, hop landing and ragdoll recovery passed. The fall case
uses the production impact receiver with a supplied impulse, not a complete
player-to-player tackle. Full-match regression and hardware controller feel were
not tested in this pass. Procedural geometry and gait remain stylized.

The earlier run `run_1791814374134_ab849da72bb24a1dab41cb7f4f6784a3` failed its
dribble check and showed open/inverted limb surfaces. Evidence was preserved and
work stopped for user approval. Its fixture called `dribble()` without selecting
the eligible controller; the corrected fixture calls production `_control_ball()`.
No ball-contact thresholds or gameplay impulses were relaxed to obtain a pass.

## First skinned athlete and contact-first shots - 2026-10-12

Build clean. One approved `skinned-shot` behavioral sequence passed in
`run_1791820187843_ca0cad511fd54d9ab2ff3d7dcc51e30e`: 253 checks, including
188 successful capture writes. All 24 reachable shots connected across standing,
walking, sprinting and turning, two powers and three ball offsets; four late
physical deflections missed. This is a bounded contact matrix, not a claim of
100 percent success in ordinary matches. Other checks covered dribble contact,
normalized skin weights, blended joints, hop landing and ragdoll recovery.

Weak and strong shots measured 12.2905 and 24.0147 m/s after the next physics
step. The maximum completed-frame skinned boot vertex error relative to its
contact bone was 0.000000964 m. Reviewed sprint/turn contact, strong-shot
follow-through, fall and recovery frames. Capture contract, closed artifact
roster and hashes verified. No contact-radius tolerance was expanded.

Ari alone uses the new original runtime-generated weighted mesh and 13-bone rig.
Shot poses and physical rules apply equally to both teams. This is procedural
skinning with connected limb rings and existing head/kit detail, not a scanned
human or imported animation library. Full-match balance, every opponent-contact
arrangement, airborne shots, controller feel and subjective shot quality remain
unverified in this pass. The supporting foot can exceed anatomical reach in
unusual cross-direction shots; the rendered output is retained for evaluation.

Previous evidence is preserved: `run_1791818472612_97310ddca48a4d6e8d6096cf35e27019`
failed before the fixture loaded due to a type declaration (no intended behavior
exercised). `run_1791818522292_b79cdba699c54adb8f3fc36f6334913a` exercised shots
but failed immediate impulse-speed and same-tick baked-boot checks. Work stopped
for an approved revised plan. User play also reported frequent kick misses.
Preparation now updates its ball intercept, the final swing commits in world
space and physical run-up momentum is retained until the strike. Measurements
now use the following physics step and completed render frame.
