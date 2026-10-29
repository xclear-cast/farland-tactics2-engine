# Scenario conversion implementation

`scenario.convert(source, output)` reads EVENT, STAFF, VSLLST and PE resources
without launching any executable. Its basic parsers use the Python standard
library and perform no file access at import time.

`scenario.convert_leaf_graphs(source, output)` additionally uses Unicorn to map
the user's original PE bytes into a bounded private x86 address space. It does
not create a Windows process or guest OS. Engine/API services are intercepted
and recorded as data; guest network/filesystem calls never execute. Unknown
unmapped calls, instruction limits, state limits and conversion errors fail
explicitly. `scenario.convert(..., include_leaf_graphs=True)` runs both steps.

Install `unicorn>=2.1,<3` for the active Python architecture. Apple Silicon users
must use arm64 Python and its native macOS Unicorn library; a Windows DLL or an
Intel wheel is not a substitute.

The supported executable hash and its entry points describe compatibility
locations. No original machine-code bytes, game dialogue or cinematic command
payloads are embedded in these source modules. All such bytes and resulting
normalized commands are read/generated on the user's computer.

Parser logic was separated from the existing local `godot_port` implementation.
Its license/provenance review remains part of the containing engine project;
this directory does not assign a new license to inherited code.

Validation on the currently supplied canonical installation:

- 40 EVENT files / 47,713 parsed commands, VSLLST 249 records per variant,
  STAFF and 40 canonical PE UI resources generated from raw files.
- 129 baseline schema/payload comparisons passed.
- 36 cinematic leaf controllers, 149 states and 394 edges generated in private
  x86 memory; all edge/state arrays exactly match the existing reference cache.
- Six synthetic parser tests pass without original game data.

These checks establish the converter outputs for the supported executable;
they are not a statement of every gameplay path or Mac execution validation.
