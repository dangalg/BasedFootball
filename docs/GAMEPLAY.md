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

Animated limbs illustrate movement and supply boot-contact positions. They are
not independent limb colliders; the shared body capsule supplies player collision.

## AI and progression

AI players have a decision delay and use the same movement, kick and challenge
functions as the human-controlled player. There are no score-driven boosts or
future controller inputs available to the AI.

Home players retain their identity and earn XP for participation in completed
matches. At 1,200 XP, development reaches its current caps: +12% touch, +12%
stamina and +6% mass for balance. Pace does not grow. Normal career data is stored
locally; test scenarios use isolated career data.

This prototype is still being tuned. These rules describe the implementation,
not a claim that every contact or animation already feels ideal.
