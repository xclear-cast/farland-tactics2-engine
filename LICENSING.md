# Licensing status

This source repository does not currently apply a blanket open-source licence to
the engine or the converters. A source publication and an OSI-licensed release
are different milestones. The project's code-origin and redistribution review is
not complete, and publication must not be described as legal clearance or proof
of a strict clean-room development process.

The new content separation layer, converter pipeline, mod support and tests are
kept separate from original game files. That separation alone does not determine
the copyright status of every pre-existing engine implementation. A project-wide
MIT/GPL grant has therefore not been invented for this upload.

Third-party files retain their existing licences:

- `game/native/include/gdextension_interface.h`: Godot Engine MIT notice.
- `game/native/include/tsf.h`: TinySoundFont MIT notice, including its SFZero credit.
- A built Godot runtime retains Godot's licence and its bundled dependency notices;
  `write_notices.gd` writes those notices into the binary distribution.
- Pillow and Unicorn are declared as external Python dependencies. Their own
  licences apply when installed or redistributed.

See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and the original notices in
the included headers. Those notices do not relicense the rest of the repository.

Original game executables, graphics, audio, scripts, maps, tables, fonts and
generated user caches are not licensed by this repository and are not distributed
with the source. Users must supply their own lawful installation and any optional
font, CD audio or SoundFont inputs. Generated caches stay on the user's computer.

Before applying a project-wide open-source licence, record the origin and
applicable rights of the pre-existing engine files, resolve any outstanding
restrictions, and choose the licence's exact scope with the rights holder.
