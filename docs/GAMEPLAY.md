# How Based Football plays

[← Back to the README](../README.md)

## The match

Three players per team play a three-minute match in a courtyard with small goals
and rebound boards. There are no keepers. Blue attacks right; orange attacks left.
You control one blue player at a time, with AI controlling the other five players.

A goal requires the entire ball to cross the goal plane inside the opening.
Balls escaping over a low board visibly restart at centre. Restarts reposition
the ball; ordinary dribbling does not attach or teleport it.

## A free ball, one contact at a time

The ball is a **22 cm diameter, 430 g rigid body**. Gravity, spin, bounded aerodynamic
force, rolling resistance and collisions determine its flight and roll.

Dribbling schedules a foot approach, contact and follow-through. The visible
boot's swept contact window gates a bounded impulse. Between those contacts the
ball travels freely, without a continuous position-correction force.

Touch planning considers acceleration and the interval before the next touch.
Sharp turns request an earlier trap and require physical braking. Small stick
movements produce smaller touches; releasing the stick settles a nearby ground
ball. Fast relative motion, an airborne ball, a challenge or a ball outside
foot reach can break control.

One eligible nearby player is granted control assistance per physics tick, with
a small continuity preference for the last toucher. Both teams use this rule.

## Movement and facing

Player bodies accelerate through capped forces. Taking a control touch briefly
shortens the stride; it does not reduce the player's base pace statistic.
Sprinting uses stamina and pushes the ball farther ahead. Jockeying reduces
movement speed and allows a ball-facing stance.

Normal running faces actual horizontal motion, so a changed movement target does
not instantly turn a forward run into backwards travel. Kicks and challenges use
their action direction. Intentional jockey backpedalling reverses the gait.

## Passing and shooting

Your last movement direction is your aim, shown by the gold line. Ground and lofted
passes follow that aim. Through passes choose a teammate ahead and aim into their
path once; the ball does not home toward the receiver.

Kicks have a wind-up, visible boot contact and follow-through. The impulse and
sound occur at contact, and incoming ball velocity contributes to the result.
Moving the ball out of reach during the wind-up can cause a miss. Ground passes,
shots and lofted passes use different power and lift before the physical ball
continues under gravity, drag, spin and collisions.

## Challenges

| Challenge | Contact | Cost |
| --- | --- | --- |
| Standing | A brief extended-foot contact window | Cooldown and recovery after the attempt |
| Sliding | The animated boot's swept path; the body capsule lowers during the slide | Longer recovery and a temporary lowered stance |
| Shoulder | Side contact with an opposing rigid body | Cooldown; the opponent can be staggered |

Standing and sliding contacts can dislodge the ball. Misses cannot apply impulses
to a distant ball. Shoulder contacts exchange equal and opposite impulses between
player bodies; they do not directly kick the ball or guarantee a turnover. A ball
away from the body collision can be freed by the resulting player displacement.

During upright play, animated limbs illustrate movement and supply boot-contact
positions; the shared body capsule supplies collision. A slide's swept boot can
contact another player's lower legs. Relative closing speed, direction, movement,
balance, stamina and jockey stance determine whether upright balance is lost.

A light hit produces a stumble and interrupts close control. A stronger hit hands
the athlete to 11 joined rigid body parts, inheriting momentum and receiving the
impact. The ordinary capsule is disabled during the fall. Once the body settles,
the player blends through a get-up pose at a nearby clear standing position.
Getting up is an authored blend, not a fully muscular physics simulation. Fallen
players cannot control the ball, kick, tackle or jump; you can switch teammates.

Press **R3 / E** for a timed hop. After a short preparation, an upward impulse lifts
the real collision body. Reduced air steering, gravity, leg clearance and landing
determine the result. A late attempt can be hit before clearing the tackle. The
ball stays free, and repeated hops have a cooldown and stamina cost.

## AI and progression

AI players use the same movement, kick, hop and challenge functions as the
human-controlled player. Reaction intervals, support positioning, sprint/challenge
choices, pass receivers and kick direction/power vary within bounds. AI hop
attempts depend on the visible incoming slide and player agility/stamina.
Randomness changes decisions and execution attempts, never physical hit or fall
outcomes. There are no score-driven boosts or future controller inputs available
to the AI. Tests seed each player's random generator for repeatable choices.

Home players retain their identity and earn XP for participation in completed
matches. At 1,200 XP, development reaches its current caps: +12% touch, +12%
stamina and +6% mass for balance. Explicit balance and agility traits also develop
by up to 6%, affecting marginal-hit resistance, hop cooldown and recovery. Pace does
not grow. Normal career data is stored
locally; test scenarios use isolated career data.

This prototype is still being tuned. These rules describe the implementation,
not a claim that every contact or animation already feels ideal.

## Athlete presentation

The original articulated athletes have tapered limbs, shaped shoulders and jaws,
individual hair and skin variations, kit trim and boot laces. Locomotion uses a
ground-height stance phase and a lifted swing phase through the same leg IK used
by action contacts. Acceleration adds bounded torso lean; kicks add torso rotation
and supporting-arm poses. These remain procedural models and animation, rather
than scanned humans or motion capture. Ragdolls reuse this exact mesh hierarchy.

## First skinned athlete and shot

Ari is the first skinned athlete: original runtime-generated limb tubes have
blended weights around knees and elbows, bound to a 13-bone Skeleton3D. Existing
pose anchors drive those bones and physical boot contact; ragdoll body transforms
drive the same skin during falls and recovery. Other players retain their previous
models while this first athlete is evaluated. This is an original procedural rig,
not a downloaded or motion-captured character.

Holding Circle adds a visible torso preparation. Release starts a supporting-foot
plant, bent-knee backswing, fast strike and extended follow-through. Stronger
shots take a slightly longer wind-up (0.17 to 0.22 seconds). Both teams use the
same shot poses and physical contact rules. Swept boot speed and contact distance
affect impulse transfer; requested lift supplies bounded off-centre contact spin.
The ball remains free and an out-of-reach wind-up can miss.

Shot preparation now re-estimates a world-space ball intercept until the final
swing commits. The player retains physical run-up momentum until contact rather
than braking at release. The supporting foot steps toward the estimated plant;
a late deflection can still remove the ball from the committed swing. Ball
position, collision radius and hit tolerance are unchanged.

## Kick variety and coordinated teams

R1 + Circle requests inside-foot finesse; L2 + Circle requests outside-foot curl.
Signed angular momentum at boot contact produces opposite Magnus curvature.
L1 + R1 + Circle requests a stronger, longer-prepared power strike. L1 + Circle
requests a chip. Square and L1 + Square choose standard/high lofted passes with
launch arcs aimed at roughly 3/4 metre apexes, adjusted for pass distance.
Gravity, drag, contact quality and collisions still affect actual clearance.

Left-stick direction at request/release selects the kick direction independently
of body facing; swing and toe orientation use that direction. Side and backward
passes are available when physically reachable. The ball never homes to a receiver.
L1 + Triangle requests a lofted through pass. In possession L1 asks a teammate
to run, R1 asks for support; outside attacking contact L1 switches teammates.
R3 is the custom timed-hop button; R1 is now the finesse/support modifier.

AI players choose distinct carrier/press, support, marking and goal-cover jobs.
Support evaluates passing-lane obstruction and teammate spacing, with a deeper
safety option. Passing considers lane clearance, receiver space and advancement;
blocked lanes can produce lobs. AI seeks shooting opportunities and uses the same
kick profiles as the controller. Bounded reaction/decision randomness remains;
physical outcomes and launch rules are shared.

## Human movement variation

Each player has a repeatable cosmetic movement style with small cadence, arm
swing and posture differences. Stride variation changes smoothly between cycles;
breathing, weight shifts and looking toward the visible ball add idle movement.
The cosmetic random generator is independent of AI decisions. Base pace, jump
impulse and hit/fall rules are unchanged. Action feet retain physical-contact
targets; arm and non-action leg rotations have bounded angular changes.

Slides have an entry, low hip/extended tackling leg and tucked supporting leg,
with balancing arms and a rising recovery. R3 hops crouch before the physical
launch, tuck during ascent, extend during descent and compress on landing.
Landing presentation uses actual fall speed without adding a control penalty.

Dribble touches now select the reachable left or right boot from ball side,
relative foot reach and recent touches, keeping that boot selected through its
contact window. Inside/outside cuts orient the boot; stopping can raise the sole
over the ball for a trap. The selected boot supplies the swept contact check.
Foot endpoints are blended before leg IK, with a ground-height constraint,
rather than independently interpolating joints through below-ground arcs.

## Active team play
Automatic defensive switching prefers available goal-side cover. Manual right-stick switching retains direction selection. Pursuers reach legal board positions and attempt physical escape kicks. Successful passes assign a receiver to intercept the current trajectory; assignment expires or ends on another touch. Receiving uses a wider cushioning speed window but requires boot contact. Pressure near the home goal can prompt a clearance. No ball homing or score-dependent outcomes.

## Physical contact play
Square in defence commits a slide to its initial direction and momentum. Ground friction slows it; impact does not trigger renewed acceleration. The tackling boot can win the ball, clip legs, cause a balance-dependent stumble/fall, or miss a timed R3 hop. Recovery leaves an opening.
Circle in defence pushes a nearby opponent or attempts a standing tackle. L2 + Circle attempts a brief grab; hold both buttons to maintain it, release either to let go. Visible hands must reach an opposing torso. Grabs apply capped equal-and-opposite spring/damping forces and break with separation, speed, a hop, a fall or low stamina. Duration is limited to 0.72 seconds. L2 + Circle remains an outside-foot shot in attack. Both teams share contact rules; AI varies occasional shove/grab choices. Keyboard equivalents are J and Ctrl + J, with H retaining shoulder challenges.

## Core action overhaul: handling
Kicks choose the reachable left or right foot, with that foot supplying contact. Incoming passes use a distinct cushioning impulse; movement can redirect the first touch. A short first-time pass/shot buffer waits for physical reach and still permits misses. Turns retain limited pivot movement. Releasing movement changes an approaching push into a timed braking touch and requests a stopping touch before the escape threshold.

## Charged deliveries and strike profiles
Hold/release Cross for ground-pass strength, Triangle for a leading through pass, and Square for lob distance. L1 raises a Square lob or makes a Triangle delivery airborne. Aim and receiver lead are selected at release; the ball never homes. Chips use a lower scoop arc. Normal shots prepare faster; power shots commit longer then swing quickly. Opposite spin profiles produce finesse/outside curves. Physical contacts play distinct synthesized sounds. Pause and press Triangle / I to cycle vibration intensity, including off; controller support determines availability.
