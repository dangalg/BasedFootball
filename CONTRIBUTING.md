# Contributing to Based Football

The project is a playable prototype focused on physical football and a permanent
squad. Useful changes make movement, contact, decision-making or presentation
clearer without introducing packs, player churn or score-based assistance.

## Reporting how it feels

Open an [issue](https://github.com/dangalg/BasedFootball/issues) with:

- The build or commit, controller model and connection method, or keyboard controls.
- A short sequence to reproduce the problem: movement direction, sprint state,
  nearby players, and the action you attempted.
- What you expected and what happened instead.
- A short clip or screenshot when motion or contact is involved.

Specific reports help: “the ball escapes after releasing R2 during a right-to-left
turn” gives more to work with than “dribbling is bad.” Include runtime errors if
present, but leave personal paths or unrelated information out of shared logs.

## Making a change

1. Follow the [development guide](docs/DEVELOPMENT.md) and reproduce the behavior.
2. Keep the change focused. Preserve shared human/AI physical rules and normal saves.
3. Build and use the verification scenario relevant to the change. For visual or
   handling changes, inspect rendered motion as well as numerical results.
4. Describe the resulting behavior, validation and remaining limitations in the PR.

Automated contact checks and reactive decision sessions provide evidence about
behavior. Human controller feel, visual quality and fun need human playtesting too.
For documentation-only changes, check links, images and commands; a new gameplay
test is unnecessary.
