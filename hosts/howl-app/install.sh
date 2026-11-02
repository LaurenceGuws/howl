#!/bin/sh
# Install an already-built Howl App for the current Linux desktop user.
set -eu

usage() {
    printf '%s\n' 'Usage: ./install.sh [BUILT_BINARY]' \
        'Default binary: ./zig-out/bin/howl-app (relative to this script)' \
        'Installs ~/.local/bin/howl-app and the XDG user icon/desktop entry.' \
        'Replaces those three files only. Does not build or install dependencies.'
}
case "${1-}" in -h|--help) usage; exit 0 ;; esac
[ "$#" -le 1 ] || { usage >&2; exit 2; }
[ "$(id -u)" -ne 0 ] || { echo 'Run as your desktop user, not root.' >&2; exit 1; }
root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
binary=${1:-"$root/zig-out/bin/howl-app"}
data=${XDG_DATA_HOME:-"$HOME/.local/share"}
bin="$HOME/.local/bin"
id=io.github.laurenceguws.howl
icon="$data/icons/hicolor/512x512/apps/$id.png"
desktop="$data/applications/$id.desktop"

# XDG paths must be absolute; line breaks cannot be represented by this installer.
for path in "$HOME" "$data"; do
    case "$path" in *%*) echo 'Install paths cannot contain desktop field-code marker %.' >&2; exit 1 ;; esac
    case "$path" in /*) ;; *) echo 'HOME and XDG_DATA_HOME must be absolute.' >&2; exit 1 ;; esac
    case "$path" in *'
'*|*"$(printf '\r')"*) echo 'Paths cannot contain line breaks.' >&2; exit 1 ;; esac
done
[ -f "$binary" ] && [ -x "$binary" ] || { echo "Built executable not found: $binary" >&2; exit 1; }
[ -r "$root/assets/$id.desktop.in" ] && [ -r "$root/assets/howl.png" ] ||
    { echo 'Installer assets missing.' >&2; exit 1; }
for path in "$bin/howl-app" "$icon" "$desktop"; do
    [ ! -L "$path" ] && { [ ! -e "$path" ] || [ -f "$path" ]; } ||
        { echo "Refusing non-regular destination: $path" >&2; exit 1; }
done

# Desktop-entry string escaping, followed by Exec's additional argument quoting.
desktop_string() { printf '%s' "$1" | sed 's/\\/\\\\/g'; }
exec_string() {
    printf '%s' "$1" | sed 's/\\/\\\\\\\\/g; s/"/\\\\"/g; s/`/\\\\`/g; s/\$/\\\\$/g; s/%/%%/g'
}
replacement() { printf '%s' "$1" | sed 's/[\\&|]/\\&/g'; }
exec_value=$(replacement "\"$(exec_string "$bin/howl-app")\"")
icon_value=$(replacement "$(desktop_string "$icon")")
home_value=$(replacement "$(desktop_string "$HOME")")

mkdir -p "$bin" "$(dirname "$icon")" "$(dirname "$desktop")"
pending=
trap '[ -z "$pending" ] || rm -f -- "$pending"' 0
trap 'exit 130' INT
trap 'exit 143' HUP TERM
# Replace files by rename so an already-running Howl keeps its executable inode.
publish() {
    pending=$(mktemp "$2.new.XXXXXX")
    install -m "$3" -- "$1" "$pending"
    mv -f -- "$pending" "$2"
    pending=
}
publish "$binary" "$bin/howl-app" 755
publish "$root/assets/howl.png" "$icon" 644
pending=$(mktemp "$(dirname "$desktop")/.howl-new.XXXXXX.desktop")
sed -e "s|@EXEC@|$exec_value|g" -e "s|@ICON@|$icon_value|g" \
    -e "s|@HOME@|$home_value|g" "$root/assets/$id.desktop.in" > "$pending"
chmod 644 "$pending"
if command -v desktop-file-validate >/dev/null 2>&1; then
    desktop-file-validate "$pending"
fi
mv -f -- "$pending" "$desktop"
pending=
printf 'Installed %s\nLauncher: %s\n' "$bin/howl-app" "$desktop"
