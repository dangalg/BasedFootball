# Changelog

This project does not have numbered releases yet. Entries describe the source
prototype; build binaries and raw test runs are not stored in Git.

## Playable prototype — 2026-10-11

### Match and squad

- Local Windows 3v3 football against AI, with an angled camera, rebound boards
  and small goals without keepers.
- Three-minute matches, teammate switching, pause and rematch.
- Permanent home players with participation XP, bounded touch/stamina/balance
  growth and local career saves.

### Handling and challenges

- A 22 cm, 430 g free physical ball with contact-timed dribbling and kicking.
- Earlier trap touches and braking for sharp turns; sprint touch planning and
  nearby-ball settling when movement is released.
- PlayStation Classic-style core controls with contextual attack/defence actions.
- Ground, lofted and through passes; charged shots with distinct physical flight.
- Standing, sliding and shoulder challenges with physical contacts and recovery.
- Smoothed dribble leg poses and running facing based on actual movement.
- Kickoff possession markers cleared correctly after restarts.
- Corrected elbow flexion so forearms bend towards the front of each athlete.

### Presentation and verification

- Original courtyard textures, articulated procedural athletes, compact HUD
  and custom desktop icon.
- Game-dev scene, handling and reactive decision scenarios with sealed evidence.
- Recorded checks: 82/82 handling and 10/10 live AI.
  See [VERIFICATION.md](VERIFICATION.md) for the test history and limitations.

### Repository presentation

- Illustrated README with play instructions and controller reference.
- Separate gameplay and development guides, contribution notes and this changelog.
