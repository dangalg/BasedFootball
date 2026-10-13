# Coordinated 3v3 decisions

Each team shares a coordinator with short, varied decision intervals. One
eligible player pursues the ball, receives an assigned pass or pressures its
carrier. A small commitment preference prevents rapid pursuit swapping.
Dismissed players are excluded. Human movement is never overwritten.

In possession, the other players provide distinct forward/wide and supporting
options. Candidate positions account for passing lanes, opponents, teammates
and travel distance. The carrier chooses a route around blocked lanes. Safe
backward recycling is deprioritised when forward progress is available.

Out of possession, one defender pressures from the goal side, a suitable deeper
defender covers the route to goal at 4.8-7 metres, and another tracks or screens
an off-ball threat near that opponent. Cover assignments have a continuity
preference; loose-ball possession retains its shape for only 0.8 seconds.
Non-contenders choose targets outside a 4.5 metre radius of the ball (3.2 near
their goal). These are movement decisions, not collision barriers. Teammates
yield around one another and slow on arrival. An idle human is deprioritised as
retriever unless already holding the ball; human input is never overwritten.
The same coordinator serves both teams using present state, never the score.

The focused acceptance sequence keeps the selected human idle throughout:
human possession, opposing possession, board retrieval, then 24 seconds of
five autonomous AI players. Physical positions and roles are sampled every
0.2 seconds, alongside 12 rendered snapshots. After a 3-second settling period
and excluding dead balls, three teammates within 3 metres of the ball must
not persist beyond 1.2 seconds or occupy 10% of team observations; four AI
players together within that radius must occupy under 15% of observations.
Attacking options must stay over 4 metres apart in at least 75% of applicable
samples. The fixture also requires physical contacts and board retrieval.
This establishes bounded spacing observations, not comprehensive tactical
quality or subjective fun.
