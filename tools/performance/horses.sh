#!/usr/bin/env bash
set -euo pipefail

# Howl terminal performance-index track marshal.
#
# TUI Zoo owns deterministic terminal workloads. WMIO owns graphical identity,
# exact placement/focus/close, and compositor abstraction. This script owns only
# benchmark policy, process-tree sampling, receipts, and fresh-process launch.

SELF=$(readlink -f "${BASH_SOURCE[0]}")
REPO_ROOT=$(cd "$(dirname "$SELF")/../.." && pwd)
HOME_DIR=${HOME:?HOME is required}
WMIO=${WMIO:-"$HOME_DIR/.local/bin/wmio"}
TUI_ZOO=${TUI_ZOO:-"$HOME_DIR/personal/tui-zoo/zig-out/bin/tui-zoo"}
EVIDENCE_ROOT=${HORSES_EVIDENCE_ROOT:-"$HOME_DIR/.local/state/howl-performance-index"}
HOWL_BIN=${HOWL_BIN:-"$EVIDENCE_ROOT/howl-fast/bin/howl-odin"}
CONFIG_ROOT=${HORSES_CONFIG_ROOT:-"$REPO_ROOT/tools/performance/configs"}
MONITOR=${HORSES_MONITOR:-DP-1}
COLS=${HORSES_COLS:-192}
ROWS=${HORSES_ROWS:-47}
FPS=${HORSES_FPS:-240}
DURATION_MS=${HORSES_DURATION_MS:-8000}
GLYPH_SET=${HORSES_GLYPH_SET:-alnum}
SAMPLE_MS=${HORSES_SAMPLE_MS:-250}
SETTLE_MS=${HORSES_SETTLE_MS:-1200}
WINDOW_RECT=${HORSES_RECT:-auto}
SYNCHRONIZED_OUTPUT=${HORSES_SYNCHRONIZED_OUTPUT:-1}
IFS=',' read -r -a DOSES <<< "${HORSES_DOSES:-1,4,16,64,256,1024,4096,8192,16384,32768,65536}"
HORSES=(howl kitty alacritty ghostty konsole wezterm)

usage() {
    cat <<'USAGE'
usage: horses.sh COMMAND [ARGS]

commands:
  doctor                  verify race dependencies and print track inventory
  plan                    print the deterministic poison race matrix as JSON
  probe HORSE             report one horse PTY geometry in the canonical frame
  calibrate               probe all horses and print their common PTY geometry
  run HORSE DOSE          run one poison trial and retain raw evidence
  sweep HORSE             run doses 1,4,16,64,256,1024,4096 for one horse
  __probe ...             internal terminal-side geometry probe
  __runner ...            internal terminal-side workload entrypoint

Environment:
  HORSES_MONITOR=DP-1             benchmark monitor (default DP-1)
  HORSES_RECT=auto|X,Y,W,H        exact WMIO frame rectangle; auto=monitor geometry
  HORSES_COLS=192 HORSES_ROWS=47  required PTY/workload geometry
  HORSES_FPS=240                  semantic producer cadence
  HORSES_DURATION_MS=8000         duration per poison dose
  HORSES_GLYPH_SET=alnum          printable|alnum
  HORSES_SAMPLE_MS=250            process-tree sample interval
  HORSES_SETTLE_MS=1200           settle after exact placement before start
  HORSES_SYNCHRONIZED_OUTPUT=1    use CSI ?2026 frame bracketing
  HORSES_EVIDENCE_ROOT=PATH       retained run evidence root
  HORSES_DOSES=1,4,...            comma-separated poison dose sweep
  HORSES_CONFIG_ROOT=PATH         benchmark config pack override
  HOWL_BIN=PATH                   benchmark Howl binary override
USAGE
}

fail() {
    printf 'horses: %s\n' "$*" >&2
    exit 1
}

have_horse() {
    local want=$1 h
    for h in "${HORSES[@]}"; do [[ $h == "$want" ]] && return 0; done
    return 1
}

require_file() {
    [[ -x $1 ]] || fail "required executable missing: $1"
}

horse_argv() {
    local horse=$1
    case "$horse" in
        howl)
            printf '%s\0' /usr/bin/env "XDG_CONFIG_HOME=$CONFIG_ROOT/howl-xdg" "$HOWL_BIN"
            ;;
        kitty)
            printf '%s\0' /usr/bin/kitty --config "$CONFIG_ROOT/kitty.conf" --single-instance=no --detach=no
            ;;
        alacritty)
            printf '%s\0' /usr/bin/alacritty --config-file "$CONFIG_ROOT/alacritty.toml"
            ;;
        ghostty)
            printf '%s\0' /usr/bin/env "XDG_CONFIG_HOME=$CONFIG_ROOT/ghostty-xdg" /usr/bin/ghostty --gtk-single-instance=false
            ;;
        konsole)
            printf '%s\0' /usr/bin/env "XDG_CONFIG_HOME=$EVIDENCE_ROOT/konsole-xdg" \
                /usr/bin/konsole --separate --builtin-profile --hide-menubar --hide-tabbar --hide-toolbars --notransparency \
                -p 'Font=IosevkaTerm Nerd Font,7,-1,5,50,0,0,0,0,0' \
                -p HistoryMode=1 -p HistorySize=4096 -p ScrollBarPosition=2 -p TerminalMargin=0 \
                -p BlinkingCursorEnabled=false -p AnimatingCursorEnabled=false \
                -p BidiRenderingEnabled=false -p SemanticHints=0 -p ShowTerminalSizeHint=false \
                -p LineSpacing=1 -p AntiAliasFonts=true
            ;;
        wezterm)
            printf '%s\0' /usr/bin/wezterm --config-file "$CONFIG_ROOT/wezterm.lua" start --always-new-process
            ;;
        *) return 1 ;;
    esac
}

horse_executable() {
    local horse=$1
    case "$horse" in
        howl) printf '%s\n' "$HOWL_BIN" ;;
        kitty) printf '%s\n' /usr/bin/kitty ;;
        alacritty) printf '%s\n' /usr/bin/alacritty ;;
        ghostty) printf '%s\n' /usr/bin/ghostty ;;
        konsole) printf '%s\n' /usr/bin/konsole ;;
        wezterm) printf '%s\n' /usr/bin/wezterm ;;
        *) return 1 ;;
    esac
}

horse_config_digest() {
    local horse=$1
    case "$horse" in
        howl) sha256sum "$CONFIG_ROOT/howl-xdg/howl/odin.json" | awk '{print $1}' ;;
        kitty) sha256sum "$CONFIG_ROOT/kitty.conf" | awk '{print $1}' ;;
        alacritty) sha256sum "$CONFIG_ROOT/alacritty.toml" | awk '{print $1}' ;;
        ghostty) sha256sum "$CONFIG_ROOT/ghostty-xdg/ghostty/config" | awk '{print $1}' ;;
        wezterm) sha256sum "$CONFIG_ROOT/wezterm.lua" | awk '{print $1}' ;;
        konsole) sha256sum "$SELF" | awk '{print $1}' ;;
        *) return 1 ;;
    esac
}

horse_version() {
    local horse=$1
    case "$horse" in
        howl) "$HOWL_BIN" --version 2>&1 | head -n 1 ;;
        kitty) kitty --version 2>&1 | head -n 1 ;;
        alacritty) alacritty --version 2>&1 | head -n 1 ;;
        ghostty) ghostty --version 2>&1 | head -n 1 ;;
        konsole) konsole --version 2>&1 | head -n 1 ;;
        wezterm) wezterm --version 2>&1 | head -n 1 ;;
    esac
}

wmio_data() {
    "$WMIO" "$@"
}

monitor_rect() {
    wmio_data monitors | python3 -c 'import json,sys; want=sys.argv[1]; d=json.load(sys.stdin); m=next((v for v in d.get("data",[]) if v.get("id")==want or v.get("name")==want),None); m is not None or sys.exit(2); g=m["geometry"]; print("%s,%s,%s,%s" % (g["x"],g["y"],g["width"],g["height"]))' "$MONITOR"
}

resolved_rect() {
    if [[ $WINDOW_RECT == auto ]]; then monitor_rect; else printf '%s\n' "$WINDOW_RECT"; fi
}

window_ids() {
    wmio_data windows | python3 -c 'import json,sys; print("\n".join(w["stable_id"] for w in json.load(sys.stdin).get("data",[])))'
}

new_window_id() {
    local before=$1 timeout_ms=${2:-10000}
    python3 - "$WMIO" "$before" "$timeout_ms" <<'PY'
import json, subprocess, sys, time
wmio, before_raw, timeout_raw = sys.argv[1:]
before=set(filter(None, before_raw.splitlines()))
deadline=time.monotonic()+int(timeout_raw)/1000
while time.monotonic() < deadline:
    p=subprocess.run([wmio,"windows"],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
    if p.returncode == 0:
        data=json.loads(p.stdout).get("data",[])
        fresh=[w for w in data if w.get("stable_id") not in before and w.get("mapped",True)]
        if len(fresh)==1:
            print(fresh[0]["stable_id"])
            raise SystemExit(0)
        if len(fresh)>1:
            print(json.dumps({"error":"ambiguous_new_windows","windows":fresh},separators=(",",":")),file=sys.stderr)
            raise SystemExit(3)
    time.sleep(.05)
raise SystemExit(2)
PY
}

window_pid() {
    local stable=$1
    wmio_data window --stable-id "$stable" | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["pid"])'
}

record_metadata() {
    local run_dir=$1 horse=$2 dose=$3 stable=$4 root_pid=$5 rect=$6
    local version executable executable_sha config_sha tui_head tui_sha howl_head wmio_sha howl_bridge_sha
    version=$(horse_version "$horse")
    executable=$(horse_executable "$horse")
    executable_sha=$(sha256sum "$executable" | awk '{print $1}')
    config_sha=$(horse_config_digest "$horse")
    howl_bridge_sha=""
    if [[ $horse == howl && -f $(dirname "$executable")/libhowl_odin_bridge.so ]]; then
        howl_bridge_sha=$(sha256sum "$(dirname "$executable")/libhowl_odin_bridge.so" | awk '{print $1}')
    fi
    tui_head=$(git -C "$HOME_DIR/personal/tui-zoo" rev-parse HEAD)
    tui_sha=$(sha256sum "$TUI_ZOO" | awk '{print $1}')
    howl_head=$(git -C "$REPO_ROOT" rev-parse HEAD)
    wmio_sha=$(sha256sum "$WMIO" | awk '{print $1}')
    HORSE_VERSION=$version HORSE_EXECUTABLE=$executable HORSE_SHA=$executable_sha HORSE_CONFIG_SHA=$config_sha HOWL_BRIDGE_SHA=$howl_bridge_sha \
    TUI_HEAD=$tui_head TUI_SHA=$tui_sha HOWL_HEAD=$howl_head WMIO_SHA=$wmio_sha \
    RUN_DIR=$run_dir HORSE=$horse DOSE=$dose STABLE=$stable ROOT_PID=$root_pid RECT=$rect \
    COLS=$COLS ROWS=$ROWS FPS=$FPS DURATION_MS=$DURATION_MS GLYPH_SET=$GLYPH_SET \
    SYNCHRONIZED_OUTPUT=$SYNCHRONIZED_OUTPUT MONITOR=$MONITOR \
    python3 <<'PY' > "$run_dir/metadata.json"
import json, os, platform, time
print(json.dumps({
  "schema":"howl-performance-index/v1",
  "captured_unix_ns":time.time_ns(),
  "horse":os.environ["HORSE"],
  "horse_version":os.environ["HORSE_VERSION"],
  "horse_executable":os.environ["HORSE_EXECUTABLE"],
  "horse_sha256":os.environ["HORSE_SHA"],
  "benchmark_config_sha256":os.environ["HORSE_CONFIG_SHA"],
  "howl_bridge_sha256":os.environ["HOWL_BRIDGE_SHA"] or None,
  "root_pid":int(os.environ["ROOT_PID"]),
  "stable_window_id":os.environ["STABLE"],
  "monitor":os.environ["MONITOR"],
  "window_rect":os.environ["RECT"],
  "workload":{
    "name":"poison","dose":int(os.environ["DOSE"]),
    "cols":int(os.environ["COLS"]),"rows":int(os.environ["ROWS"]),
    "fps":int(os.environ["FPS"]),"duration_ms":int(os.environ["DURATION_MS"]),
    "glyph_set":os.environ["GLYPH_SET"],
    "synchronized_output":os.environ["SYNCHRONIZED_OUTPUT"]=="1"
  },
  "source":{"howl":os.environ["HOWL_HEAD"],"tui_zoo":os.environ["TUI_HEAD"],
            "tui_zoo_binary_sha256":os.environ["TUI_SHA"],"wmio_sha256":os.environ["WMIO_SHA"]},
  "host":{"node":platform.node(),"kernel":platform.release(),"machine":platform.machine()},
},separators=(",",":")))
PY
}

capture_host() {
    local run_dir=$1
    uname -a > "$run_dir/host-uname.txt"
    cat /proc/loadavg > "$run_dir/host-loadavg.txt"
    lscpu -J > "$run_dir/host-lscpu.json" 2>/dev/null || true
    if command -v nvidia-smi >/dev/null 2>&1; then
        nvidia-smi --query-gpu=name,driver_version,pstate,clocks.current.graphics,clocks.current.memory,power.draw --format=csv,noheader > "$run_dir/host-gpu.csv" 2>/dev/null || true
    fi
    {
        for governor in /sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_governor; do
            [[ -r $governor ]] || continue
            printf '%s=' "$governor"
            cat "$governor"
        done
    } > "$run_dir/host-cpu-governors.txt"
}

sample_tree() {
    local root_pid=$1 output=$2 stop_file=$3 interval_ms=$4
    python3 - "$root_pid" "$output" "$stop_file" "$interval_ms" <<'PY'
import json, os, sys, time
from pathlib import Path
root=int(sys.argv[1]); output=Path(sys.argv[2]); stop=Path(sys.argv[3]); interval=int(sys.argv[4])/1000
hz=os.sysconf(os.sysconf_names['SC_CLK_TCK']); ncpu=os.cpu_count() or 1

def children(pid):
    result=set()
    try:
        for path in Path(f'/proc/{pid}/task').glob('*/children'):
            try: result.update(int(x) for x in path.read_text().split())
            except: pass
    except: pass
    return list(result)

def tree(pid):
    out=[]; stack=[pid]; seen=set()
    while stack:
        p=stack.pop()
        if p in seen: continue
        seen.add(p)
        if Path(f'/proc/{p}').exists():
            out.append(p); stack.extend(children(p))
    return out

def metrics(pid):
    d={}
    try:
        for line in Path(f'/proc/{pid}/smaps_rollup').read_text().splitlines():
            if ':' not in line: continue
            k,v=line.split(':',1); a=v.strip().split()
            if a and a[0].isdigit(): d[k]=int(a[0])
    except: pass
    return d

def status(pid):
    threads=vol=nvol=0
    try:
        for line in Path(f'/proc/{pid}/status').read_text().splitlines():
            if line.startswith('Threads:'): threads=int(line.split()[1])
            elif line.startswith('voluntary_ctxt_switches:'): vol=int(line.split()[1])
            elif line.startswith('nonvoluntary_ctxt_switches:'): nvol=int(line.split()[1])
    except: pass
    return threads,vol,nvol

def ticks(pid):
    try:
        s=Path(f'/proc/{pid}/stat').read_text(); r=s.rfind(')'); fields=s[r+2:].split()
        return int(fields[11])+int(fields[12])
    except:return 0

keys=['Rss','Pss','Pss_Anon','Pss_File','Private_Clean','Private_Dirty','Anonymous','AnonHugePages','Swap']
prev_ticks=None; prev_t=None; target=time.monotonic()
with output.open('w') as f:
    while True:
        now=time.monotonic(); pids=tree(root)
        total={k:0 for k in keys}; threads=vol=nvol=cpu_ticks=0
        for p in pids:
            m=metrics(p)
            for k in keys: total[k]+=m.get(k,0)
            th,v,nv=status(p); threads+=th; vol+=v; nvol+=nv; cpu_ticks+=ticks(p)
        core_pct=machine_pct=None
        if prev_ticks is not None and now>prev_t:
            core_pct=(cpu_ticks-prev_ticks)/hz/(now-prev_t)*100
            machine_pct=core_pct/ncpu
        row={"t_ns":time.monotonic_ns(),"processes":len(pids),"threads":threads,
             "cpu_core_pct":core_pct,"cpu_machine_pct":machine_pct,
             "voluntary_ctxt_switches":vol,"nonvoluntary_ctxt_switches":nvol}
        row.update({k.lower()+"_kib":v for k,v in total.items()})
        f.write(json.dumps(row,separators=(',',':'))+'\n'); f.flush()
        prev_ticks=cpu_ticks; prev_t=now
        if stop.exists() or not Path(f'/proc/{root}').exists(): break
        target += interval
        delay=target-time.monotonic()
        if delay>0: time.sleep(delay)
        else: target=time.monotonic()
PY
}

summarize_run() {
    local run_dir=$1
    python3 - "$run_dir" <<'PY'
import json, math, sys
from pathlib import Path
p=Path(sys.argv[1]); samples=[]
for line in (p/'samples.jsonl').read_text().splitlines():
    try:samples.append(json.loads(line))
    except:pass
producer=None
for line in (p/'producer.stderr').read_text().splitlines() if (p/'producer.stderr').exists() else []:
    try:
        value=json.loads(line)
        if isinstance(value,dict): producer=value
    except:pass

def vals(key): return [x[key] for x in samples if x.get(key) is not None]
def peak(key):
    v=vals(key); return max(v) if v else None
def mean(key):
    v=vals(key); return sum(v)/len(v) if v else None
meta=json.loads((p/'metadata.json').read_text())
runner=json.loads((p/'runner.json').read_text()) if (p/'runner.json').exists() else None
exit_code=int((p/'producer.exit').read_text().strip()) if (p/'producer.exit').exists() else None
out={"schema":"howl-performance-index/v1","metadata":meta,"runner":runner,"producer":producer,
     "producer_exit":exit_code,"samples":len(samples),
     "resources":{"peak_rss_kib":peak('rss_kib'),"peak_pss_kib":peak('pss_kib'),
       "peak_anonymous_kib":peak('anonymous_kib'),"peak_private_dirty_kib":peak('private_dirty_kib'),
       "peak_threads":peak('threads'),"peak_processes":peak('processes'),
       "mean_cpu_core_pct":mean('cpu_core_pct'),"peak_cpu_core_pct":peak('cpu_core_pct'),
       "mean_cpu_machine_pct":mean('cpu_machine_pct'),"peak_cpu_machine_pct":peak('cpu_machine_pct')}}
print(json.dumps(out,separators=(',',':')))
PY
}

wait_for_file() {
    local path=$1 timeout_ms=$2
    python3 - "$path" "$timeout_ms" <<'PY'
from pathlib import Path
import sys,time
p=Path(sys.argv[1]); deadline=time.monotonic()+int(sys.argv[2])/1000
while time.monotonic()<deadline:
    if p.exists(): raise SystemExit(0)
    time.sleep(.02)
raise SystemExit(1)
PY
}

runner_eligible() {
    local run_dir=$1
    python3 - "$run_dir/runner.json" <<'PYIN'
import json,sys
raise SystemExit(0 if json.load(open(sys.argv[1])).get("eligible") else 1)
PYIN
}

wait_pid_exit() {
    local pid=$1 timeout_ms=${2:-3000}
    python3 - "$pid" "$timeout_ms" <<'PYIN'
from pathlib import Path
import sys,time
pid=sys.argv[1]; deadline=time.monotonic()+int(sys.argv[2])/1000
while time.monotonic()<deadline:
    if not Path('/proc/'+pid).exists(): raise SystemExit(0)
    time.sleep(.05)
raise SystemExit(1)
PYIN
}

probe_one() {
    local horse=$1
    have_horse "$horse" || fail "unknown horse: $horse"
    require_file "$WMIO"; require_file "$HOWL_BIN"

    local stamp run_dir before stable rect x y width height root_pid launcher_pid typed
    stamp=$(date +%Y%m%dT%H%M%S)
    run_dir="$EVIDENCE_ROOT/calibration/$stamp-$horse"
    mkdir -p "$run_dir"
    wmio_data capabilities > "$run_dir/wmio-capabilities.json"
    wmio_data desktop > "$run_dir/desktop-before.json"
    before=$(window_ids)

    local -a argv
    mapfile -d '' -t argv < <(horse_argv "$horse")
    "${argv[@]}" >"$run_dir/launcher.stdout" 2>"$run_dir/launcher.stderr" &
    launcher_pid=$!
    printf '%s\n' "$launcher_pid" > "$run_dir/launcher.pid"

    stable=$(new_window_id "$before" 12000) || {
        kill "$launcher_pid" 2>/dev/null || true
        fail "could not discover exactly one fresh window for $horse; evidence: $run_dir"
    }
    printf '%s\n' "$stable" > "$run_dir/window.stable-id"
    rect=$(resolved_rect) || fail "monitor not found: $MONITOR"
    IFS=, read -r x y width height <<<"$rect"
    wmio_data place --stable-id "$stable" --x "$x" --y "$y" --width "$width" --height "$height" --float > "$run_dir/window-place.json"
    wmio_data focus --stable-id "$stable" > "$run_dir/window-focus.json"
    sleep "$(python3 -c "print($SETTLE_MS/1000)")"
    wmio_data window --stable-id "$stable" > "$run_dir/window-ready.json"
    root_pid=$(window_pid "$stable")
    printf '%s\n' "$root_pid" > "$run_dir/root.pid"

    local ready_cmd
    printf -v ready_cmd ': > %q' "$run_dir/shell.ready"
    wmio_data type --stable-id "$stable" --text "$ready_cmd" > "$run_dir/readiness-type.json"
    wmio_data key --stable-id "$stable" --key enter > "$run_dir/readiness-enter.json"
    if ! wait_for_file "$run_dir/shell.ready" 5000; then
        sleep 1
        wmio_data type --stable-id "$stable" --text "$ready_cmd" > "$run_dir/readiness-retry-type.json"
        wmio_data key --stable-id "$stable" --key enter > "$run_dir/readiness-retry-enter.json"
        wait_for_file "$run_dir/shell.ready" 5000 || {
            wmio_data close --stable-id "$stable" > "$run_dir/window-close.json" || true
            fail "shell did not become command-ready for $horse; evidence: $run_dir"
        }
    fi

    printf -v typed '%q __probe %q' "$SELF" "$run_dir"
    wmio_data type --stable-id "$stable" --text "$typed" > "$run_dir/input-type.json"
    wmio_data key --stable-id "$stable" --key enter > "$run_dir/input-enter.json"
    wait_for_file "$run_dir/probe.json" 5000 || {
        wmio_data close --stable-id "$stable" > "$run_dir/window-close.json" || true
        fail "PTY probe did not start for $horse; evidence: $run_dir"
    }
    cat "$run_dir/probe.json"
    touch "$run_dir/release"
    sleep .10
    if wmio_data window --stable-id "$stable" >/dev/null 2>&1; then
        wmio_data close --stable-id "$stable" > "$run_dir/window-close.json" || true
    fi
    if ! wait_pid_exit "$launcher_pid" 3000; then kill "$launcher_pid" 2>/dev/null || true; fi
    wait "$launcher_pid" 2>/dev/null || true
}

calibrate() {
    local out tmp h
    tmp=$(mktemp)
    : > "$tmp"
    for h in "${HORSES[@]}"; do
        probe_one "$h" >> "$tmp"
    done
    python3 - "$tmp" <<'PYIN'
import json,sys
rows=[json.loads(x) for x in open(sys.argv[1]) if x.strip()]
common_rows=min(x['pty']['rows'] for x in rows)
common_cols=min(x['pty']['cols'] for x in rows)
print(json.dumps({"schema":"howl-performance-index/calibration-v1","horses":rows,"common":{"rows":common_rows,"cols":common_cols}},separators=(',',':')))
PYIN
    rm -f "$tmp"
}

run_one() {
    local horse=$1 dose=$2
    have_horse "$horse" || fail "unknown horse: $horse"
    [[ $dose =~ ^[0-9]+$ ]] || fail "dose must be an integer"
    require_file "$WMIO"; require_file "$TUI_ZOO"; require_file "$HOWL_BIN"

    local stamp run_dir before stable rect x y width height root_pid launcher_pid sampler_pid
    stamp=$(date +%Y%m%dT%H%M%S)
    run_dir="$EVIDENCE_ROOT/$stamp-$horse-poison-d${dose}"
    mkdir -p "$run_dir"
    wmio_data capabilities > "$run_dir/wmio-capabilities.json"
    wmio_data desktop > "$run_dir/desktop-before.json"
    before=$(window_ids)

    local -a argv
    mapfile -d '' -t argv < <(horse_argv "$horse")
    "${argv[@]}" >"$run_dir/launcher.stdout" 2>"$run_dir/launcher.stderr" &
    launcher_pid=$!
    printf '%s\n' "$launcher_pid" > "$run_dir/launcher.pid"

    stable=$(new_window_id "$before" 12000) || {
        kill "$launcher_pid" 2>/dev/null || true
        fail "could not discover exactly one fresh window for $horse; evidence: $run_dir"
    }
    printf '%s\n' "$stable" > "$run_dir/window.stable-id"
    wmio_data window --stable-id "$stable" > "$run_dir/window-created.json"

    rect=$(resolved_rect) || fail "monitor not found: $MONITOR"
    IFS=, read -r x y width height <<<"$rect"
    [[ $x =~ ^-?[0-9]+$ && $y =~ ^-?[0-9]+$ && $width =~ ^[0-9]+$ && $height =~ ^[0-9]+$ ]] || fail "invalid HORSES_RECT: $rect"
    wmio_data place --stable-id "$stable" --x "$x" --y "$y" --width "$width" --height "$height" --float > "$run_dir/window-place.json"
    wmio_data focus --stable-id "$stable" > "$run_dir/window-focus.json"
    sleep "$(python3 -c "print($SETTLE_MS/1000)")"
    wmio_data window --stable-id "$stable" > "$run_dir/window-ready.json"
    root_pid=$(window_pid "$stable")
    printf '%s\n' "$root_pid" > "$run_dir/root.pid"
    record_metadata "$run_dir" "$horse" "$dose" "$stable" "$root_pid" "$rect"
    capture_host "$run_dir"

    # Prove the terminal's shell is actually accepting commands before sending
    # the longer runner command. Window focus alone is not shell readiness.
    local ready_cmd
    printf -v ready_cmd ': > %q' "$run_dir/shell.ready"
    wmio_data type --stable-id "$stable" --text "$ready_cmd" > "$run_dir/readiness-type.json"
    wmio_data key --stable-id "$stable" --key enter > "$run_dir/readiness-enter.json"
    if ! wait_for_file "$run_dir/shell.ready" 5000; then
        sleep 1
        wmio_data type --stable-id "$stable" --text "$ready_cmd" > "$run_dir/readiness-retry-type.json"
        wmio_data key --stable-id "$stable" --key enter > "$run_dir/readiness-retry-enter.json"
        wait_for_file "$run_dir/shell.ready" 5000 || {
            wmio_data close --stable-id "$stable" > "$run_dir/window-close.json" || true
            fail "shell did not become command-ready for $horse; evidence: $run_dir"
        }
    fi

    # The terminal-side runner reports actual PTY geometry, then waits for our
    # explicit go gate. No workload bytes are emitted before sampling starts.

    local typed
    printf -v typed '%q __runner %q %q %q %q %q %q %q %q' \
        "$SELF" "$run_dir" "$COLS" "$ROWS" "$FPS" "$DURATION_MS" "$dose" "$GLYPH_SET" "$SYNCHRONIZED_OUTPUT"
    wmio_data type --stable-id "$stable" --text "$typed" > "$run_dir/input-type.json"
    wmio_data key --stable-id "$stable" --key enter > "$run_dir/input-enter.json"

    wait_for_file "$run_dir/runner.json" 5000 || {
        wmio_data close --stable-id "$stable" > "$run_dir/window-close.json" || true
        fail "runner did not start for $horse; evidence: $run_dir"
    }
    if ! runner_eligible "$run_dir"; then
        touch "$run_dir/release"
        wmio_data close --stable-id "$stable" > "$run_dir/window-close.json" || true
        fail "PTY is smaller than ${COLS}x${ROWS} for $horse; evidence: $run_dir"
    fi

    sample_tree "$root_pid" "$run_dir/samples.jsonl" "$run_dir/producer.exit" "$SAMPLE_MS" &
    sampler_pid=$!
    touch "$run_dir/go"

    local run_timeout=$((DURATION_MS + 12000))
    wait_for_file "$run_dir/producer.exit" "$run_timeout" || {
        printf '124\n' > "$run_dir/producer.exit"
    }
    wait "$sampler_pid" || true
    wmio_data window --stable-id "$stable" > "$run_dir/window-post.json" || true
    summarize_run "$run_dir" > "$run_dir/summary.json"
    cat "$run_dir/summary.json"

    touch "$run_dir/release"
    sleep .15
    if wmio_data window --stable-id "$stable" >/dev/null 2>&1; then
        wmio_data close --stable-id "$stable" > "$run_dir/window-close.json" || true
    fi
    if ! wait_pid_exit "$launcher_pid" 3000; then
        kill "$launcher_pid" 2>/dev/null || true
    fi
    wait "$launcher_pid" 2>/dev/null || true
}

doctor() {
    require_file "$WMIO"; require_file "$TUI_ZOO"; require_file "$HOWL_BIN"
    local rect backend stale_tui expected_zig actual_zig
    expected_zig=$(cat "$HOME_DIR/personal/tui-zoo/.zigversion")
    actual_zig=$(zig version)
    [[ $actual_zig == "$expected_zig" ]] || fail "tui-zoo Zig mismatch: expected $expected_zig, got $actual_zig"
    stale_tui=$(find "$HOME_DIR/personal/tui-zoo/src" -type f -newer "$TUI_ZOO" -print -quit)
    [[ -z $stale_tui ]] || fail "tui-zoo binary is older than source: $stale_tui (run: cd ~/personal/tui-zoo && zig build install -Doptimize=ReleaseFast)"
    rect=$(resolved_rect) || fail "benchmark monitor not found: $MONITOR"
    backend=$(wmio_data capabilities | python3 -c 'import json,sys; d=json.load(sys.stdin); b=d["data"]["backend"]; print("%s %s" % (b["name"],b["version"]))')
    printf 'track backend: %s\n' "$backend"
    printf 'monitor: %s rect=%s\n' "$MONITOR" "$rect"
    printf 'workload: poison cols=%s rows=%s fps=%s duration_ms=%s glyph_set=%s sync=%s\n' "$COLS" "$ROWS" "$FPS" "$DURATION_MS" "$GLYPH_SET" "$SYNCHRONIZED_OUTPUT"
    printf 'tui-zoo: %s head=%s sha256=%s\n' "$TUI_ZOO" "$(git -C "$HOME_DIR/personal/tui-zoo" rev-parse --short HEAD)" "$(sha256sum "$TUI_ZOO" | awk '{print $1}')"
    local h
    for h in "${HORSES[@]}"; do printf '%-10s %s config=%s\n' "$h" "$(horse_version "$h")" "$(horse_config_digest "$h")"; done
}

plan() {
    local backend rect
    backend=$(wmio_data capabilities | python3 -c 'import json,sys; d=json.load(sys.stdin); b=d["data"]["backend"]; print(b["name"]+"@"+b["version"])')
    rect=$(resolved_rect)
    BACKEND=$backend RECT=$rect python3 - "${HORSES[*]}" "${DOSES[*]}" "$MONITOR" "$COLS" "$ROWS" "$FPS" "$DURATION_MS" "$GLYPH_SET" "$SYNCHRONIZED_OUTPUT" <<'PY'
import json,os,sys
horses=sys.argv[1].split(); doses=[int(x) for x in sys.argv[2].split()]
print(json.dumps({"schema":"howl-performance-index/plan-v1","track":{"backend":os.environ["BACKEND"],"monitor":sys.argv[3],"window_rect":os.environ["RECT"]},"workload":{"name":"poison","cols":int(sys.argv[4]),"rows":int(sys.argv[5]),"fps":int(sys.argv[6]),"duration_ms":int(sys.argv[7]),"glyph_set":sys.argv[8],"synchronized_output":sys.argv[9]=="1","doses":doses},"horses":horses,"trials":[{"horse":h,"dose":d} for h in horses for d in doses]},separators=(",",":")))
PY
}

probe_runner() {
    local run_dir=$1
    mkdir -p "$run_dir"
    local tty_rows tty_cols
    read -r tty_rows tty_cols < <(stty size)
    TTY_ROWS=$tty_rows TTY_COLS=$tty_cols python3 <<'PYIN' > "$run_dir/probe.json"
import json,os,time
print(json.dumps({"schema":"howl-performance-index/probe-v1","t_ns":time.monotonic_ns(),"pty":{"rows":int(os.environ['TTY_ROWS']),"cols":int(os.environ['TTY_COLS'])}},separators=(',',':')))
PYIN
    while [[ ! -e "$run_dir/release" ]]; do sleep .02; done
}

runner() {
    local run_dir=$1 cols=$2 rows=$3 fps=$4 duration_ms=$5 dose=$6 glyph_set=$7 sync=$8
    mkdir -p "$run_dir"
    local tty_rows tty_cols
    read -r tty_rows tty_cols < <(stty size)
    TTY_ROWS=$tty_rows TTY_COLS=$tty_cols REQ_ROWS=$rows REQ_COLS=$cols python3 <<'PY' > "$run_dir/runner.json"
import json,os,time
r=int(os.environ['TTY_ROWS']); c=int(os.environ['TTY_COLS']); rr=int(os.environ['REQ_ROWS']); rc=int(os.environ['REQ_COLS'])
print(json.dumps({"schema":"howl-performance-index/runner-v1","t_ns":time.monotonic_ns(),"pty":{"rows":r,"cols":c},"required":{"rows":rr,"cols":rc},"eligible":r>=rr and c>=rc},separators=(",",":")))
PY
    if (( tty_rows < rows || tty_cols < cols )); then
        printf '64\n' > "$run_dir/producer.exit"
        while [[ ! -e "$run_dir/release" ]]; do sleep .05; done
        return 64
    fi
    while [[ ! -e "$run_dir/go" ]]; do sleep .02; done
    local args=(poison --dose "$dose" --fps "$fps" --duration-ms "$duration_ms" --cols "$cols" --rows "$rows" --glyph-set "$glyph_set")
    if [[ $sync == 1 ]]; then args+=(--synchronized-output); fi
    set +e
    "$TUI_ZOO" "${args[@]}" 2> "$run_dir/producer.stderr"
    local rc=$?
    set -e
    printf '%s\n' "$rc" > "$run_dir/producer.exit"
    while [[ ! -e "$run_dir/release" ]]; do sleep .05; done
    return "$rc"
}

main() {
    local command=${1:-}
    case "$command" in
        doctor) [[ $# == 1 ]] || fail 'doctor takes no arguments'; doctor ;;
        plan) [[ $# == 1 ]] || fail 'plan takes no arguments'; plan ;;
        probe) [[ $# == 2 ]] || fail 'probe requires HORSE'; probe_one "$2" ;;
        calibrate) [[ $# == 1 ]] || fail 'calibrate takes no arguments'; calibrate ;;
        run) [[ $# == 3 ]] || fail 'run requires HORSE DOSE'; run_one "$2" "$3" ;;
        sweep)
            [[ $# == 2 ]] || fail 'sweep requires HORSE'
            have_horse "$2" || fail "unknown horse: $2"
            local d
            for d in "${DOSES[@]}"; do run_one "$2" "$d"; done
            ;;
        __probe) [[ $# == 2 ]] || fail 'internal probe argument mismatch'; shift; probe_runner "$@" ;;
        __runner) [[ $# == 9 ]] || fail 'internal runner argument mismatch'; shift; runner "$@" ;;
        -h|--help|help|'') usage ;;
        *) fail "unknown command: $command" ;;
    esac
}

main "$@"
