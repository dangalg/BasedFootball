# Based Football

Desktop artwork is in `assets/branding/based-football.ico` (seven Windows icon
sizes), with PNG preview and SVG source alongside it. `tools/make_icon.py`
rebuilds these files with Python and Pillow. The desktop shortcut uses this ICO
while continuing to launch `build/BasedFootball.exe` without test arguments.

Local 3v3 football, an angled camera, a physical ball, responsive weighted players,
small goals and rebound boards. Built for Godot **4.6.1**, using built-in Jolt.

## Play

Double-click **Play.cmd** or **build/BasedFootball.exe**. Connect a controller before
or during play. Blue attacks right; orange attacks left. Matches last three minutes.
Pause with Options/Escape. At full time, press Cross/Enter for a rematch, Q to exit.

| Action | Controller | Keyboard |
| --- | --- | --- |
| Move and aim | Left stick | WASD |
| Ground pass into space | Cross | Space |
| Charge and release shot (attack) | Circle | J |
| Standing tackle / side-contact shoulder (defence) | Circle | K / H |
| Lofted pass (attack) / sliding tackle (defence) | Square | U / L |
| Through pass into a teammate's path | Triangle | I |
| Shield / jockey | L2 | Ctrl |
| Sprint | R2 | Shift |
| Switch teammate | L1 | Tab |
| Directional teammate selection | Right stick flick | — |

Normal running faces actual movement, so a changed AI target does not make the
athlete run backwards while braking. Jockeying keeps its aim-facing stance and
reverses the gait when backpedalling.

Your last movement direction is your aim; the gold line shows it. Ground and lofted
passes follow that aim. Through passes select a teammate ahead and aim into their
path once; the ball never homes toward them after contact. Circle and Square use
attack actions only when a friendly/neutral ball is within foot reach. Side-contact
shoulder challenges require a nearby opponent; otherwise Circle extends a foot.
Sprint means longer touches and stamina use. Missed tackles have a recovery period.
Small stick movements produce small dribble touches. A foot approaches the ball,
strikes it once, follows through, then blends back into the running gait. The ball
travels freely between contacts; there is no continuous position-correction force.
Touch planning accounts for acceleration and the time until the next touch, so
sprinting from rest does not immediately punt the ball out of reach. Sharp turns
request an earlier trap touch, with physical braking before the next stride. Release the stick
to settle a nearby ground ball. Fast challenges, balls outside foot reach and
airborne balls remain free; sprinting still pushes the ball farther ahead.
Taking a touch briefly shortens the player's stride, while turning around the ball
also requires braking. Base running pace stays unchanged. Short bounded impulses
guide the ball around the body at a visible touch cadence. The visible boot's swept
contact window gates every dribble impulse. Joint rotations blend and have bounded
angular speed during dribbling, and resting beside a settled ball stops the touch
animation. Full-stick turns and reversals still
require braking and acceleration; there is no ball attachment or teleporting.
One eligible nearby player supplies control touches per physics tick, with a small
continuity preference for the last toucher. This applies to both teams. Standing
and sliding tackles use finite contact windows along the animated boot's swept path. Shoulder challenges
require a side contact with an opposing rigid body, exchange equal and opposite
impulses and briefly stagger the challenged player. Challenges suspend nearby
control assistance briefly; misses cannot kick a remote ball. Slides lower the
body collider temporarily, extend one leg with the torso leaning back, and have a
longer recovery. Shoulder contact exchanges equal/opposite impulses and can free
a ball positioned away from the body collision; it does not directly kick the ball
or guarantee a turnover. All challenges have cooldowns.
Players keep identity and gain participation XP after completed matches. Touch,
stamina and balance grow gradually with explicit caps; speed does not inflate.
Career data is saved in `%APPDATA%/Godot/app_userdata/Based Football/squad.json`.

## Courtyard visuals

Muted textured turf, trimmed rebound boards, open-looking nets and courtyard
seating frame the angled camera. Players have human proportions, shaped blue/coral
kits, boots, socks and shirt details. Elbows and knees articulate during running,
standing tackles, slides and shoulder challenges. These are original procedural
athletes rather than scanned humans.
The compact HUD keeps the score, player stamina and controller hints at the edges.
Visual netting keeps the original solid rebound collision geometry behind it.
The later handling pass adds coordinated dribbling and three physical challenges;
career progression and the court/goal collision boxes are retained.

Original textures in `assets/court/` can be rebuilt with
`tools/make_court_textures.py` (Python + Pillow). No downloaded or paid assets are
used. Standard Godot materials keep this compatible with the existing OpenGL
renderer.

## Physical rules

The 22 cm diameter, 430 g ball is a free rigid body, beside roughly 1.8 m athletes.
Kicks have a wind-up, boot contact and follow-through; an impulse and sound occur
only when the animated boot reaches the ball during its contact window. Incoming
velocity contributes to the result. A ball moved away during the wind-up can be
missed. Ground passes have minimal lift; shots and lofted passes use distinct lift
and power, then follow gravity, spin, drag and collisions. Dribble touches are also
reach-limited impulses, with short stride adjustments for control.
The upright player bodies accelerate through capped forces; collision response is
physical. Animated limbs illustrate motion and do not each have their own collider.
The shared body capsule lowers during a slide and returns to standing afterward.
Human and AI players share the same movement/kick functions. AI has a fixed decision
delay, no score-driven boosts and no access to future controller inputs. A goal
requires the entire ball to cross the goal plane within the opening. Balls escaping
over a low board visibly restart at centre. Restarts are the only ball repositioning
in normal gameplay.

## Build and validation

Run `powershell -NoProfile -ExecutionPolicy Bypass -File .\Launch.ps1 -Build`.
Set `GODOT_EXE` if Godot 4.6.1 is installed elsewhere. The local bundle pairs an
exported game pack with the installed Godot executable; it is larger than a normal
export-template build. Keep the executable and `.pck` together. `-Editor` opens the
project for editing.

The current game-dev adapter provides three local scenarios after a clean build:

- `visual-scene-check`: CPU-only headless scene, assets, HUD and collision checks.
- `handling-and-tackles`: a bounded rendered sequence with 82 checks and 36 frames,
  including walking/sprint animation sequences, turns, stops, physical challenges,
  contextual controls, carrying versus free-running and contact-timed kick flight.
- `decision-match`: 30 seconds of reactive controller decisions against normal AI,
  with an opposing kickoff, production match rules, facing telemetry and seven frames.

Run, for example, `game-dev.cmd scenario run decision-match --project
C:\repos\RegularFootball --output-dir C:\repos\RegularFootball\evidence\game-dev
--confirm --allow-gpu --jsonl`. Rendered tests open a muted 960x600 game window;
complete off-screen isolation is not claimed. They disable hardware input and use
isolated career data. Normal desktop launches contain no automated inputs.
`capture verify RUN_PATH` verifies the sealed evidence hashes and artifact roster.
The harness does not establish hardware controller feel, subjective fun or GPU
performance. Results and tuning history are recorded in `VERIFICATION.md`.

The older `-Acceptance` and `-DribbleAcceptance` launch modes remain historical
fixtures; their original thresholds have not been revalidated for the current
22 cm ball and timed-touch model. Use the game-dev scenarios for current checks.

No online mode, keepers, licensed assets, packs, transfers, or full ragdolls yet.
All meshes and sounds are generated by project code. Git delivery is local only;
the supplied GitHub origin is recorded but no push is authorized for this milestone.
