# Gentle turn touches and combination passing

Approved scope: preserve the user-accepted 4v4 preview at `eaf5aa3`, guide the ball
into dribbling turns with actual foot contact, and improve AI return/back/through
passes. The older recovery and frozen 4v4 release remain available for rollback.

## Handling

A steering touch compares the stick with the ball's actual rolling direction.
The foot can prepare near the end of the normal touch interval, but contact must
still satisfy the same reach, cooldown and visible-foot sweep. A bounded change
of heading preserves most rolling speed instead of treating every turn as a
heavy stop. Stops and reversals retain physical traps. The ball travels freely
between contacts; straight dribbling, pass/shot controls and keeper behavior are
outside this change.

## Team play

The AI evaluates teammate space, the passing lane, actual running velocity and
pressure relief. Backward and sideways passes can be useful options. An actual
reception briefly remembers the passer, allowing a give-and-go when that player
moves into space. A runner can receive a physical through pass aimed ahead;
a stationary or checking teammate can receive to feet. A marked return option
loses value, while a useful shot or clear dribble remains available.

The same rules apply to both teams and to human/AI recipients. Decisions do not
read future human input, alter the ball in flight or guarantee a reception.
Short settling and delivery intervals limit repetitive passing.

## Focused verification and delivery

After completing implementation, import/export with pinned Godot 4.6.1 and
explicitly parse affected scripts. Run one continuous off-screen recording of
straight dribbling, mirrored 30/60/90-degree turns at several running speeds,
give-and-go passes into runs, pressure-relieving returns and blocked alternatives.
Declared initial fixtures supply opportunities; production movement, AI, kicks
and actual foot contacts determine outcomes. There are no same-case rescues,
forced passes or retries. Normal saves are isolated from the acceptance data.

Measure the actual turn contact and change of heading, continued free travel,
AI choices and real kick/reception events. Report unexercised opportunities and
physical misses separately from decision errors. The recorded result and actual
footage are evidence for the user's evaluation; score is not a criterion here.

Review the final diff and push verified source to `origin/codex/keeper-reception`.
Freeze the exact reviewed pack before updating the existing desktop shortcut.
Keep the previous executable, pack, shortcut and normal saves intact. This
document describes the original plan. The recorded results and later user
evaluation are documented in [VERIFICATION_TURN_TEAMWORK.md](VERIFICATION_TURN_TEAMWORK.md),
including the unresolved diagnostic checks.
