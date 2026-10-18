# User-played turn and teamwork preview - 2026-10-18

This checkpoint preserves the exact gameplay the user played through the
existing desktop shortcut and called "pretty fun" before asking for another
small turn-only adjustment. It is a manually accepted preview, not a claim
that all automated diagnostics passed.

The frozen pack is `build/turn-teamwork-5b328a072b007cc6/BasedFootball.pck`.
Its SHA-256 is
`5b328a072b007cc6de41c919357dcf1267ba2d0f4fc75d349165a19039fd18e4`.
The previous keeper preview and original recovered 3v3 builds remain preserved.

## Recorded verification

Godot 4.6.1 imported/exported cleanly and four affected script entry points
passed explicit parse checks. The single recorded session completed all 24
labelled cases in 133.375 simulation seconds at a median 60 FPS. There were no
same-case resets or retries. Source/build hashes and normal saves stayed fixed.
Hardware-controller feel and subjective fun were evaluated by the user later.

22 of 27 checks passed. Straight control, all walking/jogging turn checks,
four sprint turn checks, active initial reception and the blocked-return passing
chain passed. All six 30-degree turns continued without tester recovery input.
Sharper turns needed recovery; numeric contact coverage does not establish
fluent control along the requested route.

Five checks remain unresolved:

- Sprint 60/90-degree left cuts steered at actual contact but produced no later
  touch. Both directions initially lost reach; tester recovery timing amplified
  the later left/right difference.
- The AI genuinely struck a through ball to the running human and a pass to an
  open AI instead of a marked human. Both balls deflected after contact and
  failed to reach their intended receivers. Self-body collision is suspected;
  exact native collider identities were not recorded.
- A backward pass reached the human, but the opponent was 3.54m away at contact,
  so close-pressure passing was not exercised.

The original recording also failed its whole-video 95% marker-validity gate:
83.852% of all frames were valid. The invalid frames were entirely preflight
while the fully off-desktop window did not supply usable capture. After moving
only the test window behind other windows without activation, the full action
interval had zero invalid frames, gaps or counter regressions. The unchanged
original, exact-frame action copy, measurements and footage review remain under
`evidence/turn-teamwork-r1/` locally. These original failed verdicts are retained.

## Delivery and next scope

After seeing the results, the user explicitly chose to play this candidate
before further repairs. Its exact tested EXE/PCK were frozen and the SAME
desktop shortcut was updated, with the previous shortcut saved for rollback.
The user then reported the game was pretty fun and approved a turn-only tune.

That next tune is scoped to steering target velocity: remove steering's speed
boost, permit a modestly greater contact bend and trim speed slightly on sharp
cuts. AI, passing, animation, keeper and rules repairs are outside that scope.
Normal saves, the currently installed build and older recoveries stay intact.
