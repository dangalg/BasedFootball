# 4v4 preview checkpoint - 2026-10-17

This preview builds on `efbc4ca`, the isolated recovery of `2d5d7ad` chosen by
the user as the fun version. It adds one keeper per side, discrete kick-ahead
dribbling with both feet, loose/incoming-ball strikes and active pass receivers.

## Build and recorded session

Godot 4.6.1 Mono imported and exported the project cleanly. Ten affected script
entry points passed explicit parse checks. One continuous rendered acceptance
session ran the labelled drills followed by a fresh normal 180-second match.
The full match reached full-time at 0-0 in 181.48 wall seconds, including kickoff.
Median frame rate was 60 FPS. The controlled side made six passes and four shots;
both AI teams physically played the ball. A 0-0 result is valid football and is
not a failure criterion.

All 8,665 encoded frames decoded valid identity/counter markers. The recording
covered the whole action sequence, with unchanged source/build hashes and no
intervening screenshots or pauses. Evidence is retained locally under
`evidence/keeper-preview-r1/`; videos, builds, saves and machine receipts are not
committed.

Tested pack SHA-256:
`c7cb8a3c3297a968cd47e3ebf38827093fe119f3b0147fd9b95d324d9be8dc2d`.

## Diagnostic results and limits

18 of 22 automated checks passed. These include sprint touch-ahead cycles,
loose and first-time shots, a genuine missed swing, raw-direction lob/through
passes, moving reception, outside-area keeper handling restrictions, full-time,
isolated progression and preservation of the original saves.

Four checks remain unresolved:

- Walking: no qualifying cycles; the tester also repeatedly turned away at
  1.05 m while collection requires 0.95 m. Small initial walking separation
  remains a separate observation.
- Interception: the ball physically reversed near the opponent and the pass
  intent cleared, but body contacts do not produce the scripted foot-touch
  receipt required by that check. Exact native collider IDs were not recorded.
- Keeper catch/release and parry: minimum glove gaps were 0.194 m and 0.245 m,
  exceeding the 0.175 m contact reach. Body blocks are inferred; actual hand
  catches, sustained grip and release were not exercised.

Two report fields were stale (maximum gap and assigned interception receiver).
The preserved telemetry and measurement audit distinguish those reporting bugs
from the observed behavior. These results are not a claim of a fully passing
automated suite or uniformly natural animation.

## User evaluation and delivery

After seeing the diagnostics, the user explicitly requested the playable build
through the existing desktop icon and reserved the judgment of game feel. The
exact tested pack was frozen separately and the same shortcut was updated. The
previous shortcut, 3v3 executable and saves remain available for rollback.

The user then played it and reported: "the game is much better", requesting only
a small directional turn-touch correction and better AI return/through passes.
This commit is the user-accepted playable preview checkpoint before those
changes. It preserves the unresolved diagnostics above; it does not relabel
their automated results as passing. Git push was explicitly authorized.
