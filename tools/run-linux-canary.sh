#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
mode=${1:-both}
session_port=${HOWL_SESSION_PORT:-43127}
web_port=${HOWL_WEB_PORT:-43129}
zig=${ZIG:-$(command -v zig || true)}

case "$mode" in
  both|flutter|web) ;;
  *) echo 'usage: tools/run-linux-canary.sh [both|flutter|web]' >&2; exit 64 ;;
esac

if [[ -z "$zig" ]]; then
  echo 'ZIG must name the tracked Howl compiler' >&2
  exit 2
fi
tracked_zig=$(<"$root/.zigversion")
if [[ "$($zig version)" != "$tracked_zig" ]]; then
  echo "ZIG version must match $tracked_zig" >&2
  exit 2
fi

flutter=''
if [[ "$mode" != web ]]; then
  if [[ -n "${FLUTTER:-}" ]]; then
    flutter=$FLUTTER
  elif [[ -x "$HOME/fvm/versions/3.47.2/bin/flutter" ]]; then
    flutter="$HOME/fvm/versions/3.47.2/bin/flutter"
  else
    flutter=$(command -v flutter || true)
  fi
  if [[ -z "$flutter" || ! -x "$flutter" ]]; then
    echo 'FLUTTER must name Flutter 3.47.2' >&2
    exit 2
  fi
  flutter_version=$($flutter --version | sed -n '1s/^Flutter \([^ ]*\).*/\1/p')
  if [[ "$flutter_version" != 3.47.2 ]]; then
    echo "Flutter 3.47.2 required; found ${flutter_version:-unknown} at $flutter" >&2
    exit 2
  fi
fi

ports=("$session_port")
if [[ "$mode" != flutter ]]; then
  ports+=("$web_port")
fi
python3 - "${ports[@]}" <<'PY'
import socket, sys
for raw in sys.argv[1:]:
    port = int(raw)
    sock = socket.socket()
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        sock.bind(('127.0.0.1', port))
    except OSError as exc:
        raise SystemExit(f'loopback port {port} is already in use: {exc}')
    finally:
        sock.close()
PY

runtime="$root/.zig/work/linux-canary"
rm -rf "$runtime"
mkdir -p "$runtime"

session_pid=''
gateway_pid=''
flutter_pid=''
cleanup() {
  trap - EXIT INT TERM
  for pid in "$flutter_pid" "$gateway_pid" "$session_pid"; do
    [[ -n "$pid" ]] || continue
    kill "$pid" 2>/dev/null || true
  done
  for pid in "$flutter_pid" "$gateway_pid" "$session_pid"; do
    [[ -n "$pid" ]] || continue
    wait "$pid" 2>/dev/null || true
  done
}
trap cleanup EXIT INT TERM

printf '%s\n' 'Building local Howl session owner...'
(
  cd "$root/howl-session"
  "$zig" build install -Doptimize=ReleaseSafe
)

if [[ "$mode" != web ]]; then
  printf '%s\n' 'Building Linux Flutter client...'
  (
    cd "$root/howl-flutter"
    ZIG="$zig" ./native/build-linux.sh
    "$flutter" build linux --release
  )
fi

if [[ "$mode" != flutter ]]; then
  printf '%s\n' 'Building Linux Web/PWA client...'
  (
    cd "$root/howl-web"
    "$zig" build render-web gateway-install -j2
  )
fi

session="$root/howl-session/zig-out/bin/howl-sessiond"
endpoint="tcp://127.0.0.1:$session_port"
"$session" "tcp:$session_port" /bin/bash 40 100 'exec /bin/bash --noprofile --norc -i' \
  >"$runtime/session.log" 2>&1 &
session_pid=$!

for _ in $(seq 1 100); do
  if grep -q "HOWL_ENDPOINT=$endpoint" "$runtime/session.log" 2>/dev/null; then
    break
  fi
  if ! kill -0 "$session_pid" 2>/dev/null; then
    cat "$runtime/session.log" >&2
    exit 1
  fi
  sleep 0.05
done
if ! grep -q "HOWL_ENDPOINT=$endpoint" "$runtime/session.log"; then
  echo 'Howl session did not become ready' >&2
  exit 1
fi

if [[ "$mode" != web ]]; then
  bundle="$root/howl-flutter/build/linux/x64/release/bundle"
  HOWL_GEOMETRY_LEADER=true "$bundle/howl_flutter" "$endpoint" \
    >"$runtime/flutter.log" 2>&1 &
  flutter_pid=$!
fi

if [[ "$mode" != flutter ]]; then
  gateway="$root/howl-web/gateway/zig-out/bin/howl-web-gateway"
  site="$root/howl-web/render/zig-out/live-web"
  wire="$root/howl-web/zig-out/bin/howl-web.wasm"
  host="127.0.0.1:$web_port"
  origin="http://$host"
  "$gateway" "$web_port" "$session_port" "$host" "$origin" "$site" "$wire" \
    >"$runtime/gateway.log" 2>&1 &
  gateway_pid=$!
  for _ in $(seq 1 100); do
    if python3 - "$web_port" <<'PY' 2>/dev/null
import socket, sys
with socket.create_connection(('127.0.0.1', int(sys.argv[1])), timeout=.1):
    pass
PY
    then
      break
    fi
    if ! kill -0 "$gateway_pid" 2>/dev/null; then
      cat "$runtime/gateway.log" >&2
      exit 1
    fi
    sleep 0.05
  done
  browser=${HOWL_BROWSER:-$(command -v chromium || true)}
  if [[ -n "$browser" ]]; then
    "$browser" --no-first-run --no-default-browser-check --app="$origin/" \
      >"$runtime/browser-launch.log" 2>&1 &
  else
    echo "Chromium not found; set HOWL_BROWSER or open $origin/ manually" >&2
  fi
fi

printf '\nHowl Linux canary is live.\n'
printf '  session: %s\n' "$endpoint"
if [[ "$mode" != flutter ]]; then
  printf '  Web/PWA: http://127.0.0.1:%s/\n' "$web_port"
fi
if [[ "$mode" != web ]]; then
  printf '  Flutter: release bundle PID %s\n' "$flutter_pid"
fi
printf '  logs:    %s\n' "$runtime"
printf '\nBoth clients share the same canonical PTY. Type in either one and compare.\n'
printf 'Press Ctrl-C here to stop the canary session and owned client processes.\n\n'

wait "$session_pid"
