# Based Football — Recovered 3v3

This separate local checkout restores `2d5d7ad413f2490e1065b6224932869fccf0497f` from 11 October 2026. It preserves the historical 3v3 gameplay, procedural characters, rebound boards, switching, ragdoll falls and timed hops.

Branch: `codex/recovery-3v3`. The existing operator and development checkouts, installed releases and desktop shortcut are separate and must remain unchanged. No remote push is part of this recovery.

The only production configuration changes are the application display name and a dedicated custom user directory: `BasedFootball-Recovered-3v3` under Windows roaming application data. This recovered game starts a separate career and never imports the existing game's saves.

The test-only SceneTree runner uses the historical match scene and existing decision-driver interface. Its isolated career file is inside the evidence session. It must not change gameplay scripts, initial positions, ball impulses, AI abilities, the 180-second match clock or the normal main scene. The test runs one full match and records continuous footage. Numeric checks and footage review are separate; subjective fun remains for the player to evaluate.

Build with the historical `Launch.ps1 -Build` using Godot 4.6.1. The normal executable uses the original match scene, without the test driver. A separately named desktop shortcut is delivered only after the focused match passes.

Results, build identity and preservation receipts are stored under ignored `evidence/`. Existing source snapshots and recordings remain intact in their original locations.

## Completed recovery verification

One full match reached the production full-time signal at 180 match-clock seconds, score 6–0. The 190.55-second simulation includes the initial kickoff and six ordinary goal restarts. All 12 declared recovery checks passed: movement, sprinting, turning/stopping, passing, shooting, dribble contacts, active AI, finite physics and isolated progression. Controlled contacts: 26 passes, eight shots, 288 dribbles. Median frame rate: 60 FPS.

Continuous WGC footage has 6,410 valid frame markers, zero action gaps or counter regressions, and coverage through the final counter. Source, executable and pack stayed unchanged during the match. The earlier capture preflight failed before any behavior began; it is preserved separately. No second match or gameplay changes followed the completed test.

Actual saved frames across the match and the full-resolution full-time frame were reviewed alongside events. This verifies recovery and exercised actions, not subjective fun, realistic animation, physical-controller feel or balanced AI. The earlier stylized characters and immediate centre restarts remain.

The new desktop shortcut is `Based Football - Recovered 3v3`. It launches the frozen tested pack from `build/recovered-2d5d7ad-cd49e926e66acbf2/` with no test arguments. Pack SHA256: `cd49e926e66acbf2efff18acf4668cbd03f6f104e775a9f4addeec6c71eea55c`.

Normal career data is separate at `%APPDATA%/BasedFootball-Recovered-3v3/`. The test career is isolated inside its evidence session and contains one completed match; it is not the normal recovered career.

Local results and recording: `evidence/recovery-match-r2/review.html`. Preservation snapshot: `evidence/preservation/manifest.json`. The post-match audit found all 758 original files, existing saves, key builds and original shortcut unchanged.
