# Licensing status

## Standalone converter: GPL-2.0-only

Copyright (c) 2026 FT2 converter contributors.

The newly authored standalone converter component identified in
[CONVERTER_LICENSE.json](CONVERTER_LICENSE.json) is free software: you may
redistribute and modify that component under the GNU General Public License,
version 2 only. It is provided without warranty, including the implied warranties
of merchantability and fitness for a particular purpose. The full terms are in
[COPYING-converter](COPYING-converter).

This grant covers `tools/convert_installation.py`, `tools/import_content.py`,
`tools/converters/**`, the converter freezer/source-packaging scripts, the UI
character-catalog generator, and the declared converter/build dependency lists.
The JSON scope manifest is authoritative for the listed paths. Existing upstream
third-party notices are preserved and are not replaced by this grant.

The converter uses Unicorn's native CPU emulator. Unicorn 2.1.4's top-level
[README](https://github.com/unicorn-engine/unicorn/blob/2.1.4/README.md) and
[COPYING](https://github.com/unicorn-engine/unicorn/blob/2.1.4/COPYING) identify
GPLv2, even though the Python package metadata says BSD. This project does not
treat that metadata as a BSD grant for the native core.

## Engine and original game: outside that grant

There is no blanket GPL/MIT grant for the engine or for the whole repository.
The pre-existing engine's code-origin and redistribution review remains separate.
Source publication must not be described as legal clearance or proof of strict
clean-room development. The engine runs the converter as a separate executable;
the converter licence declaration does not purport to grant rights over engine
code, third-party code, or the original game.

Keeping source code separate from original game files does not determine the
copyright status of every pre-existing engine implementation.

Third-party files retain their existing licences:

- `game/native/include/gdextension_interface.h`: Godot Engine MIT notice.
- `game/native/include/tsf.h`: TinySoundFont MIT notice, including its SFZero credit.
- A built Godot runtime retains Godot's licence and its bundled dependency notices;
  `write_notices.gd` writes those notices into the binary distribution.
- Frozen converter distributions include CPython, Pillow, Unicorn and the
  PyInstaller bootloader. Their exact notices accompany the binaries. Unicorn's
  native core is handled as GPLv2; PyInstaller retains its bootloader exception.

See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and the original notices in
the included headers. Those notices do not relicense the rest of the repository.

Original game executables, graphics, audio, scripts, maps, tables, fonts and
generated user caches are not licensed by this repository and are not distributed
with the source. Users must supply their own lawful installation and any optional
font, CD audio or SoundFont inputs. Generated caches stay on the user's computer.

Before applying a project-wide open-source licence, record the origin and
applicable rights of the pre-existing engine files, resolve any outstanding
restrictions, and choose the licence's exact scope with the rights holder.

## Frozen converter source delivery

For every binary release, publish `FT2-Converter-Source.zip` at the same release
download location. Generate it from the same source revision with
`python tools/package_converter_source.py --output-dir private/release_sources`.
It contains the licensed converter source, build/dependency scripts, the exact
published Unicorn 2.1.4 source archive, the exact PyInstaller source archive,
preserved licence texts, a file/hash manifest and rebuild instructions. The
Windows recipe records the `--no-cfg` PyInstaller bootloader build flag.

GPLv2 section 3 requires complete corresponding source or another permitted
source-delivery arrangement; an upstream URL alone is not the release policy
used here. The binary/source packages must be retained together, and changed
third-party code or build scripts must be reflected in the corresponding source.
This source package is not a claim of overall legal clearance.
