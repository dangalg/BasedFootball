# Physical football foundation

The player rigid body supplies movement and collisions. Grounded footsteps use
world-space support anchors; the other leg swings to a reachable landing. A
collision can force an early step rather than stretching the planted leg.

Running with the ball follows a forward boot contact, free ball flight under
rolling resistance, catch-up strides and the next reachable foot contact. Close
turns, stopping, reception and cramped-net retrieval use separate touches. There
is no continuous possession force or ball attachment. Off-ball pace is unchanged;
touches and changes of direction require finite stride adjustments.

Each accepted kick retains an ID, purpose, direction and intended recipient.
Repeated rejected input cannot rewrite that swing. Sideways and backward requests
can require a physical step into a clear stance. Visible swept-boot contact makes
the impulse; missed or cancelled actions make no strike.

The coordinator owns tactical jobs. A pass in flight retains one recipient until
actual reception, interception or expiry. That player meets and cushions the ball
before choosing the next action. Recent-pass memory permits return combinations.

Goal preparation retrieves the ball and passes it toward centre, then settles and
signals kickoff. Only the authorized actual kickoff contact resumes play. The
goal floor is flush with the pitch; displaced preparation balls remain physical
and can be recovered from nets as well as open pitch. Referee return warnings
judge progress toward legal positioning rather than an AI formation point.

## Verification and local delivery

The `football-foundation` game-dev scenario runs one bounded production-loop
sequence using injected input, while normal referee, AI and rigid-body processing
remain active. It records action/contact events, actual trajectories, support-foot
anchors, close continuous movement frames and mirrored goal-to-kickoff sequences.
Planted-foot drift is checked within a continuous stance epoch. Rendered evidence
still requires visual review; a numerical result alone cannot establish natural
movement or fun controls.

Build candidates with `Launch.ps1 -Build -OutputDirectory build/candidate`. The
off-screen scenario uses that bundle, leaving the desktop launcher bundle separate.
Only a passing reviewed candidate is promoted to `build` and delivered to Git.

The 2026-10-14 foundation verification passed 86/86 checks in one 88-second
production-loop sequence, with 150 continuous movement frames. The retained run
is `run_1792009540985_5a381eeb9afa4682a049f761fcf7cedb`. It includes actual backward
reception, receive-pass-receive combinations, grounded steps, free-travel catch-up
dribbling and both physical goal-to-kickoff sequences. This establishes the
observed scenarios; controller feel and visual style remain for player evaluation.
