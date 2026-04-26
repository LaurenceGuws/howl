# ZIDE REPO FREEZE / HOWL EXTRACTION RULE
taken from ~/personal/zide/ at the moment of code freeze:
THIS REPO IS FROZEN AS A REFERENCE COPYBOOK FOR THE HOWL REBUILD.

DO NOT TREAT ZIDE AS THE PRODUCT AUTHORITY FOR NEW WORK.
DO NOT ADD NEW PRODUCT FEATURES HERE.
DO NOT ADD COMPATIBILITY SHIMS FOR HOWL.
DO NOT PRESERVE `zide_*`, `Zide*`, `ZIDE_*`, PACKAGE IDS, ABI NAMES, OR
LEGACY PATHS WHEN MOVING IDEAS INTO HOWL.

HOWL IS THE NEW PRODUCT FAMILY. THE OLD ZIDE REPO MAY BE READ FOR PRIOR ART,
IMPLEMENTATION DETAILS, TEST IDEAS, AND BUG HISTORY, BUT IT IS NOT A BIBLE.
MOVED CODE MUST BE PURPOSE-CHECKED, RENAMED CLEANLY, AND FIT THE NEW HOWL
ARCHITECTURE.

PRIMARY DIRECTION:

- `howl-vt-core`: portable terminal engine, VT core, runtime, tests, and clean
  public API.
- `howl-sdl-host`: first Linux host shell (SDL window/input + host loop composition).
- `howl-session`: shared session runtime (engine lifecycle + PTY/process loop).
- `howl-render-gl`: shared OpenGL renderer module.
- `howl-editor`: future editor engine; do not let it distract from terminal
  extraction.
- `howl-shared`: independent reusable engines/dependencies only; not a dumping
  ground for old Zide leftovers.

Before making any change in this repo, ask whether the work should happen in
Howl instead. The default answer is yes unless the user explicitly asks to
preserve, inspect, or checkpoint the frozen Zide source.

Next lane handoff:

- `app_architecture/checkins/checkin2.txt`
