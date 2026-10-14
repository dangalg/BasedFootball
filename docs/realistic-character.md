# Realistic football squad

All six players use the detailed human mesh, with blue/orange kits, shirt numbers
and stable skin/hair colour variants. Physics bodies, movement speed, contact
rules and controller bindings are unchanged. This stage shares one anatomical
base rather than providing six individually sculpted faces.

The MakeHuman/MPFB core mesh, hair and clothing source assets are CC0-1.0.
See [MakeHuman's official licence](https://github.com/makehumancommunity/makehuman/blob/master/LICENSE.md).
The generated GLB contains anatomical hands and a face, football shorts, socks,
shoes and embedded cloth textures. Its thirteen deformation bones follow the
same pose anchors used by physical touches, kicks and ragdolls. Fingers retain
their modelled shape and are not individually animated in this prototype.

The natural-character pass retains that CC0 mesh and its embedded cloth textures.
Matte fabric and hair, softer skin highlights, stable eye/boot variants and original
cuff/crest/lace details reduce the uniform plastic appearance. Details follow the
existing torso, arm and boot anchors and add no colliders. Grounded steps, support
weight transfer and step-driven arm rhythms provide the movement; this pass does
not replace the physical action rig or alter player pace.

`tools/build_realistic_athlete.py` records the local source paths and writes
only to the explicitly supplied output directory. Reproduction requires Blender
5.2, the MPFB extension, the local MakeHuman asset bundle and the existing
HumanLife2 source builder. The provenance file records the builder digest.
The package manifest and vendor lock bind the exported bytes; Godot imports the
vendored GLB directly.

The `realistic-player` Game Development Studio scenario runs one finite
off-screen sequence: standing, running, turning, dribbling, shooting, sliding,
jumping and a physical fall/recovery. It saves actual rendered frames and
physical-action checks. It does not establish full-match AI quality, controller
hardware compatibility or subjective artistic quality.
