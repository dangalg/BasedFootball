# 4v4 from the recovered fun version

This branch starts at the verified recovery commit `efbc4ca` (gameplay base
`2d5d7ad`). It keeps the original court, procedural players, three outfield
players, controls and three-minute match. Each side gets one AI keeper.

The change is deliberately limited to keepers, kicking, running touches and reception.
The ball remains a free rigid body. Outfield control uses visible boot contact
and bounded impulses. Dribbling replaces the fixed-separation controller with
kick-ahead, free-roll and catch-up phases. Turns require another foot contact;
stopping requires a physical trap, and either foot may be selected for a touch.
A kick can strike a loose or incoming ball without first claiming possession.
The stick selects its direction; receiver selection never redirects the strike.
Keeper catches require visible glove contact inside the
marked box; a finite force grip can spill, and the keeper quickly distributes.
Pass intent follows an actual kick and ends on contact, deflection or expiry.
The intended receiver meets the observed flight; other teammates keep supporting.

## Saves and rollback

This build uses `%APPDATA%\BasedFootball-KeeperPreview\squad.json`.
Acceptance uses its own `acceptance_squad.json`; the recovered 3v3 save profile
and frozen executable remain intact. The verified recovery source is preserved
on `codex/recovery-3v3` at the trusted origin.

After successful acceptance and actual footage review,
`tools/promote_keeper_preview.ps1` freezes the exact tested EXE/PCK and changes
the **existing** `Based Football - Recovered 3v3` shortcut to that normal game.
It retains the old shortcut bytes and target in the release folder. It creates
no additional desktop icon. Restore the backed-up `.lnk` to return to 3v3.

## One acceptance session

Build with `Launch.ps1 -Build`, then parse-check the new script entry points.
The external test runner is never used by the desktop shortcut.

The recorded session contains labelled walking and sprint touch/roll/catch-up,
turn/stop, loose and incoming strikes, a missed swing, pass/reception,
interception and keeper drills, then one fresh normal 180-second 4v4 match.
Initial fixtures are declared; outcomes come from production physics. The match
uses production clocks and goal restarts, with no tester resets. The game runs
continuously during action, while Windows Graphics Capture records its exact
window. An encoded frame counter ties footage to the physics timeline.

`result.json` reports measured behavior. `capture-review.json` reports capture
integrity. A separate `delivery-review.json` records the actual footage review;
neither a full-time event nor capture integrity alone establishes good football.
Do not promote or push this implementation as completed if acceptance fails.

The first candidate completed that session and was installed for human
evaluation at the user's explicit request. The user played it and reported that
the game is much better. See [the checkpoint verification](VERIFICATION_4V4.md)
for the exact build, manual evaluation and four unresolved automated checks.
