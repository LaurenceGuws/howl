# DP-1 fullscreen race calibration · 21 October 2026

Qualified on physical **DP-1: 1920×1080, scale 1, 240 Hz**, and separately in
private KWin. The complete native PTY grid is **384×83 = 31,872 cells** for
all four horses. Use the full 384×83 producer lattice in the next race.

| Horse | Installed version / build | Font | Native grid | Cell pixels |
|---|---|---|---|---|
| Howl | ffa4cbd / executable 226 | 10 px, explicit font files | 384×83 | 5×13 |
| Foot | 1.28.0 | pixelsize=10 | 384×83 | 5×13 |
| Kitty | 0.49.2 | 7.5 pt | 384×83 | 5×13 |
| Alacritty | 0.17.0 | 7.5 pt, zero font/glyph offsets | 384×83 | 5×13 |

Every actual window is native fullscreen at 1920×1080. The cell drawing area is
1920×1079; Howl centres the one spare pixel row above it, the others leave it below.
No cells are cropped. PTY size/pixel queries, window reports, all eight screenshots
and exact first/last-row colour bounds agree. No warning banner, panel, title or
tab bar covers the corner markers. Alacritty's accepted calibration stderr is empty.

All use Iosevka Nerd Font, including corresponding bold/italic faces; the regular
source resolves to /usr/share/fonts/TTF/IosevkaNerdFont-Regular.ttf. Backgrounds
are opaque; configured padding, blur and cursor animation are off. History remains
ordinary 4096 rows. Daily settings and the installed Howl binary are unchanged.

## Documented choices

- **Howl:** existing explicit 10 px fonts, hide_single_tab=true, SDL vsync=1.
  Its existing F11 action selects fullscreen. No product source changes.
- **Foot:** documented pixel font sizing and natural metrics; normal renderer
  worker policy, zero padding, no CSD. No forced line-height is necessary.
- **Kitty:** normal input_delay=3 and sync_to_monitor=yes. repaint_delay=4 allows
  the ordinary repaint budget to fit DP-1's 240 Hz; its documented 10 ms default
  targets about 100 FPS. This config permits 240 Hz; displayed cadence is unmeasured.
  Previous forced zero input delay and ligature suppression are removed.
  Size persistence is off. Other renderer/shaping defaults remain.
- **Alacritty:** live_config_reload and ipc_socket belong under [general].
  Fixing their deprecated root placement removes the warning instead of suppressing
  it. The old +1 vertical cell/glyph offsets are removed; documented zero defaults
  naturally match the others. Renderer selection stays automatic.
- F11 selects native fullscreen in all four isolated benchmark profiles.

Read sources: version-matched installed upstream foot.ini(5), kitty.conf(5) and
alacritty(5), Kitty's installed config/performance documentation, Howl's maintained
README/config/source, and the official online references:

- https://sw.kovidgoyal.net/kitty/conf/
- https://sw.kovidgoyal.net/kitty/performance/
- https://alacritty.org/config-alacritty.html
- Foot: /usr/share/man/man5/foot.ini.5.gz; upstream https://codeberg.org/dnkl/foot.

The previous CPU tables used different grids and Kitty pacing choices. Preserve
their original conditions; these profiles need fresh timing. This calibration
provides geometry and configuration qualification, without a new CPU ranking.

## Launch and acceptance

Use fresh isolated config/cache/state roots and one owned client at a time.
For physical DP-1, move only that exact PID/stable window to the intended existing
workspace, place it, then send F11 through WMIO. Before releasing tui-zoo, require:

- native fullscreen, DP-1 1920×1080 at scale 1;
- **384 columns, 83 rows, terminal pixels 1920×1079**;
- readable top/bottom corners and no overlay or configuration warning.

Abort a mismatch. Do not shrink a common payload to hide unequal native grids.
Keep the same profile name and initial OSC title across timing labels. Record
every terminal thread/helper separately from producer/coordinator/compositor CPU;
retain every sample, cold memory peak and producer miss. Keep physical/private
cohorts and pacing choices separate.

Use Walker delegated cgroup v2 containment with **512 tasks**. The first private
attempt reached the old128-task bound and a Kitty watcher helper aborted. Retain
that rejected attempt. The accepted private run peaked at140 tasks, physical at75,
both with zero task-limit, OOM or CPU-throttle events. The earlier32/40-run cohorts
were checked separately: peaks123/124, zero task-limit events and no helper aborts.

For physical clients, the live user-manager Wayland environment was verified
against its Hyprland socket peer and WMIO monitor. A per-workload private D-Bus
keeps Kitty's automatic child-scope request from moving the producer outside
the contained experiment. Its scope/notification diagnostics and Foot's missing
toplevel-icon diagnostic are retained in logs; none covers cells. This isolates
desktop integration; it is not a claim about ordinary desktop notification cost.

The historical horses.sh uses retired WMIO APIs and must not launch this race.
Current calibration argv, configurations and bounded launcher are retained in
the workstream. No existing user window was moved or closed; focus was restored.

## Evidence

Home: ~/.local/state/workstreams/howl-current/day-20261021/dp1-calibration/

qualified.json records all eight accepted views. private-attempt2/ and
dp1-attempt1/ contain geometry, terminal queries, owned window identities, logs,
screenshots and exact hashes. docs/ contains manual snapshots. DECISIONS.md
records settings and rejected-attempt details. No diagnostic code enters product
source.
