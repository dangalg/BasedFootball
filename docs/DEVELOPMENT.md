# Development guide

[← Back to the README](../README.md)

## Engine and build

The project targets **Godot 4.6.1 Mono on Windows**, with GDScript gameplay,
built-in Jolt physics at **120 Hz**, physics interpolation and the OpenGL
Compatibility renderer. No external asset download is needed to load the game.

`Launch.ps1` defaults to the original development machine's Godot installation.
Set `GODOT_EXE` to your installed **console executable** on another machine:

```powershell
$env:GODOT_EXE = 'C:\path\to\Godot_v4.6.1-stable_mono_win64_console.exe'
powershell -NoProfile -ExecutionPolicy Bypass -File .\Launch.ps1 -Build
```

The script imports the project, checks import/export logs, exports the Windows
game pack, and copies the matching graphical engine and `GodotSharp` runtime
into `build/`. It creates a local playable bundle rather than a compact
export-template distribution. Keep the bundle together when moving it.

Open the editor with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Launch.ps1 -Editor
```

Double-click `Play.cmd` to launch. Without a built executable it opens the project
using the configured engine. Generated builds, Godot caches and raw test evidence
are excluded from Git. `docs/.gdignore` keeps documentation screenshots out of the
Godot resource import and exported game pack.

## Project map

| Path | Responsibility |
| --- | --- |
| `scenes/match.tscn` | Main scene |
| `scripts/match.gd` | Match rules, court, camera, input, switching and restarts |
| `scripts/player.gd` | Player forces, control touches, kicks and challenges |
| `scripts/player_visual.gd` | Procedural athlete, gait and contact poses |
| `scripts/player_ragdoll.gd` | Jointed physical falls, clearance and get-up handoff |
| `scripts/ball.gd` | Free rigid ball, touches, rolling resistance and spin force |
| `scripts/team_ai.gd` | Delayed teammate/opponent decisions |
| `scripts/squad.gd` | Player definitions, bounded progression and career saves |
| `scripts/hud.gd`, `scripts/art.gd`, `scripts/sound.gd` | HUD, original visual helpers and procedural sound |
| `data/squad.json` | Starting player identities and attributes |
| `tests/` | Scene, handling and reactive decision fixtures |
| `.game-dev/adapter.json` | Local game-dev scenario definitions |

## Current verification scenarios

Build first. With the separately installed `game-dev` CLI available, run from the
repository root:

```powershell
game-dev scenario run visual-scene-check --project . --output-dir evidence/game-dev --confirm --jsonl
game-dev scenario run handling-and-tackles --project . --output-dir evidence/game-dev --confirm --allow-gpu --jsonl
game-dev scenario run decision-match --project . --output-dir evidence/game-dev --confirm --allow-gpu --jsonl
game-dev scenario run impacts-and-hops --project . --output-dir evidence/game-dev --confirm --allow-gpu --jsonl
```

| Scenario | Coverage | Rendering |
| --- | --- | --- |
| `visual-scene-check` | Scene loading, assets, HUD bounds and collision configuration | Headless, CPU-only; no pixel evidence |
| `handling-and-tackles` | 82 checks: turns, stops, sprinting, carrying cost, contact timing, challenges, misses and flight | 36 frames including walk/sprint sequences |
| `decision-match` | 30 seconds of reactive decisions, normal match AI, an orange kickoff, physical actions and facing telemetry | Seven match frames |
| `impacts-and-hops` | Light/hard hits, skill thresholds, early/late hops, seeded AI hop choices, pause, board recovery and restart cleanup | Fall, jump and recovery sequences |

Rendered scenarios open a muted 960×600 window. Complete off-screen isolation is
not guaranteed. Hardware input is disabled, and tests use isolated career data.
The decision fixture chooses actions from current state through production
controller actions; it does not validate a physical PlayStation controller.

Inspect the report and logs inside the emitted run directory. Verify the sealed
artifact roster with:

```powershell
game-dev capture verify 'PATH_TO_RUN_DIRECTORY' --json
```

Game-dev proves process status, decoded raster bytes and sealed artifact hashes.
It does not independently prove GPU completion, hardware performance or subjective
quality. Read [VERIFICATION.md](../VERIFICATION.md) for recorded results and limits.

The adapter wrapper currently pins the original developer's Godot path and restores
Windows user-data paths. On another machine, update the engine path in
`tools/visual_scene_check.mjs` to match your installation. The regular build and
play launcher uses `GODOT_EXE` instead.

`-Acceptance` and `-DribbleAcceptance` remain historical launch modes. Their old
thresholds have not been revalidated for the current 22 cm ball and timed contacts;
use the game-dev scenarios for current verification.

## Original asset tools

The checked-in textures and branding are ready to use. Regeneration is optional
and needs Python with Pillow:

```powershell
python tools/make_court_textures.py
python tools/make_icon.py
```

Court textures live in `assets/court/`. Branding includes SVG, PNG and a seven-size
Windows ICO in `assets/branding/`. Athlete meshes and game sounds are generated
by project code. Documentation images are actual recorded prototype captures.

## Athlete animation review

The `athlete-animation` scenario runs one rendered sequence covering both teams
running, turns, control touches, a kick, slide, hop and physical fall/recovery.
It saves match-camera and close-up frames. Automated checks establish contact,
finite transforms, ground-height steps and recovery; inspect the frames for
artistic quality. It is not a complete match or hardware controller test.

## Skinned shot evaluation

`scripts/skinned_athlete.gd` constructs original weighted mesh surfaces locally;
no provider jobs, licenses, Blender export or network assets are needed.
`skinned-shot` runs one finite rendered sequence covering model pose, locomotion,
dribble contact, weak/strong/moving/missed shots and ragdoll recovery. It checks
normalized weights, blended joints, the baked boot against its contact anchor,
contact timing and charged-shot power. Saved frames supply visual review;
hardware controller feel and full-match balance remain human evaluation.

The contact-first matrix adds 24 reachable shots (standing, walking, sprinting and
turning; two powers and three offsets) plus four physically deflected misses.
Acceptance is at least 95 percent reachable contacts with all deflections missing.
Ball speeds are sampled after the following physics step. Baked boot vertices are
compared to their expected bone transforms after the completed render frame.

`shots-team` runs one finite rendered sequence covering modifier selection,
opposite curl, standard/high lob head clearance, side/backward actions, support
and defensive fixtures, then 30 seconds of normal match physics and team AI.
The fixture drives the controlled player through current-state AI actions; it
uses no hardware input. Artistic quality and hardware controller feel still
require human play. Historical impact tests expect R1 hop; use this new R3 mapping
when revising those fixtures rather than interpreting that old mapping as current.

`human-motion` executes one finite sequence for all six athletes: walk, sprint,
turn, stop, slide, hop, dribble and shot. It records low slide/recovery, jump
preparation/tuck/extension/landing, foot clearance, bounded joint steps, physical
ball contacts and unchanged AI random state/base pace. Captured frames support
visual review for the skinned Ari and the remaining articulated models.

The combined `human-motion` sequence also checks left/right-foot contacts for
each athlete, turning/stopping control and absence of remote ball touches.
The previous failed below-ground-foot evidence is retained separately.

Verified local movement checkpoint: run_1791827288363_1191765ce15640dda94a0015edff488b passed 429/429 checks and saved 192 frames. Build clean; sealed capture hashes verified. Preparation uses planted ankle geometry, retaining the 80 ms physical launch. Controller feel remains human evaluation.

The teamplay scenario checks side/end/corner recovery, goal-side switching, ground and lofted physical reception, missed pass assignment, pressure response and a bounded autonomous sequence. Rendered runs request an off-screen window.

Verified teamplay checkpoint: run_1791827595948_0fb7c13f7c8742f5a4d2531c63cf4d09 passed all 34 checks; clean build and verified sealed hashes. Wall/corner recovery and physical ground/lob receiving succeeded in the bounded fixtures. Full-match balance and controller feel remain unverified.
