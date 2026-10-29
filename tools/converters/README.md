# Standalone FT2 installation converters

These modules read only the installation selected by the user. They do not read
the old Godot workspace, its extracted cache, or a bundled original game. Outputs
are private, user-side content caches and are not part of the engine release.

Entry point: `python tools/convert_installation.py --source GAME --cache-parent CACHE`.
Install dependencies from the release-root `requirements.txt` first. Python 3.11+,
Pillow and Unicorn are required. On Apple Silicon M1 or later use arm64 Python.
Actual execution on macOS has not yet been verified in the development environment.

- `graphics.convert(source, output)`: indexed BMP/SZDD, APD and FM2 conversion.
- `tables_audio.convert(source, output)`: source tables, saves, text and wave/MIDI.
- `scenario.convert(source, output)`: EVENT, credit/cinematic and PE UI resources.
- `compatibility.convert(source, output)`: small supported-edition PE data tables.
- `fonts.convert(output, font=..., full_charset=...)`: private masks from a supplied
  or system font; FreeType metrics, not captured Win95 GDI pixels.

The supported canonical Korean FTO_O executable profile is checked before
edition-specific addresses are used. An incompatible executable is rejected;
the converter does not download or replace it. Some original APD sheets are
missing in that edition and are recorded as missing, without substitute art.

Optional CD audio and SF2 banks must be supplied by the user. When those music
sources are unavailable the runtime disables that BGM source, while converted
wave sound effects remain available. This release contains no music or font bank.

Support modules are parser/compiler code only. Test files, Python caches and
private converted game data must not be copied into a distribution.
