# Grounded player movement

The physical player remains a rigid body. Animation observes its actual velocity
and plans steps along its actual travel direction, including lateral movement and
backpedalling. Each stance foot stores a world-space ankle position and toe yaw.
That footprint stays fixed until the foot lifts; body rotation, cosmetic sway and
ball control do not move it across the pitch.

Swing placement forecasts the body's travel to landing. Step timing uses the
available reach of the existing 0.41 m thigh and 0.34 m shin. Swing targets retain
a small reach margin, and the pelvis can lower within its ordinary movement range
to preserve a stance. If a collision pushes the hip beyond that range, the foot
lifts into a recovery step rather than dragging or restraining the rigid body.
At a stop or a turn on the spot, the athlete relocates one footprint at a time.

Walking and jogging start from an upright pelvis rather than a continuous crouch.
Ordinary trailing steps are released against that upright reach budget before a
constraint can lower the pelvis farther. Support weight shifts in the athlete's
own lateral direction, and a small landing compression follows actual landings.
Arm counter-swing follows the opposite leg's real stance/swing target. Walking
keeps relaxed elbows; jogging and sprinting progressively bend them and increase
arm drive and forward lean. Torso and head anticipate a requested turn while
the feet continue to follow physical momentum.

Only an unplanted swing boot pitches for toe-off and toe clearance. Planted boots
retain the accepted flat footprint and toe yaw. Slow, seeded posture variations
affect presentation without consuming AI randomness or altering ball impulses.

A running ball touch temporarily uses the kicking foot and preserves the other
foot's support anchor while it remains reachable. The kicking leg returns to the
gait after its short follow-through, so the ball's free travel and the player's
catch-up strides can continue without a ball-control pose replacing the run.
Receiving, braking, tight turns, shots and tackles retain their distinct actions.

## Inspection data

`FootballPlayerVisual` exposes `planted_feet`, `stance_anchors`, `stance_yaws`,
`stance_epochs`, `swing_progress`, `gait_stride_length`, `gait_step_interval`, and
`planted_mask()`. Left is index/bit 0 and right is index/bit 1. A new landing or
gait reset increments that foot's epoch. Slip comparisons should use consecutive
samples with the same planted epoch and exclude ragdolls, airborne actions and
action poses. A low boot height alone does not establish stance.

`preferred_dribble_right(ball_world, fallback)` prefers a free swinging foot when
it can approach the nearby ball; lateral distance still influences the choice.
`touch_foot_ready(right)` describes animation eligibility, not ball ownership.
`reset_gait()` invalidates anchors after an explicit fixture or body reset.
`pose_snapshot(player)` returns JSON-safe pelvis, torso, arm, elbow and head pose
arrays plus support bias, turn anticipation, swing boot pitch and movement mode.

Trace data supports diagnosis. Acceptance also requires a continuous rendered
sequence showing foot support, swing, landing, turning and catch-up strides.
