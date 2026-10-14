# Restarts and refereeing

The courtyard keeps its 3v3, rebound-board and no-keeper format. Restart spacing
uses the standard 3.0 metres. Formation targets are AI choices, not player rules.

At kickoff, everyone except the taker stays in their own half; opponents also
stay outside the centre circle. At a free kick, teammates may move anywhere,
while opponents stay at least 3.0 metres away (or on their own goal line between
the posts). Being legally positioned away from an AI target never earns a card.
The referee checks visible infringements, not invisible exclusion zones.

Goals retain celebrations and disappointment. A teammate retrieves the physical
ball, then passes toward a teammate waiting near centre. The recipient meets and
cushions that preparation pass, settles it at the spot and prepares kickoff.
Players return using normal locomotion and are not teleported. The ball becomes
live on the actual kickoff contact after the referee's signal. Preparation passes
remain dead-ball actions.

For a managed free kick, defenders organise between the ball and goal while
attackers offer passing options. The referee walks to the measured distance,
scuffs the mark progressively with his foot and steps away. The visible line
marks a minimum distance, not a mandatory standing place, and has no collider.
Boot scuffing is a deliberate presentation convention for this prototype.

Observation uses actual head direction, range and physics obstruction. There is
no video review or score-dependent discipline. Careless contact does not itself
earn a card; reckless, excessive and persistent offences are assessed separately.
Contact direction, height and studs are evidence, rather than speed alone. Mild
ball-first slides can be legal; dangerous challenges are not exempted simply for
touching the ball. Advantage can preserve a beneficial possession after a minor
foul and return to the free kick if that advantage disappears promptly.

Illegal positioning is explained by the referee. Movement toward compliance
resets the delay; repeated deliberate refusal can lead to yellow, then red.
Dismissal transfers human control to an eligible teammate. Players walk out and
physically cross the low board. A rematch restores the squad and discipline.

These are the implemented courtyard rules, not the complete eleven-a-side law
package. Offside, goalkeeper handling and a full penalty/throw-in system are
outside this stage. Initial setup and explicit rematches establish starting
positions; later goal and foul restarts preserve continuous player movement.

Restart retrieval uses normal swept-foot dribble contacts, with no hand carry, force tether or ball teleport. The retriever approaches behind the ball, slows near the spot, cushions it, then steps behind the outgoing pass direction. AI kickoffs select an available teammate in their own half and use the shared physical pass delivery. Actual kicker identity survives the restart to keep reception assignments valid.
Kickoff lane selection excludes blockers from either team and admits nearby legal backward outlets. Launch verification reads the integrated physics velocity rather than the pre-impulse strike callback.
At the back net, the retriever plants beside the ball and uses a swept-boot sole pull toward the pitch. The ball's exit lane clears the planted capsule; the player then resumes ordinary behind-ball dribbling. No body target lies behind the solid net, including in side-net corners.
Live goals are recognised at the whole-ball crossing of the goal plane, using the interpolated crossing location. A subsequent net-corner bounce cannot invalidate that goal. Restart preparation is explicitly labelled in the HUD; ordinary team AI resumes only on the legal physical restart kick.
The goal floor continues the pitch at the same height. During cramped-net retrieval, normal dribble swings are paused while the player takes a side stance. The stance stays planted during the inward sole pull, then normal return dribbling resumes.
For goal restarts, the retriever passes from a clear foot stance to an AI teammate waiting near centre. This is a dead-ball preparation pass, not kickoff. The recipient meets and cushions the delivery, settles it at the restart spot, and prepares a backward kickoff after the signal. Idle teammates do not automatically trap the preparation ball; physical collisions and deliberate human intervention remain possible. Free kicks continue to use direct retrieval to their awarded spot.
