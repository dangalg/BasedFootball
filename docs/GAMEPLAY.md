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

Press **R1 / E** for a timed hop. After a short preparation, an upward impulse lifts
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
