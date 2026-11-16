#!/usr/bin/env bash
# Build inputs are Zig-pinned sources; all CMake outputs belong to Zig's cache.
set -euo pipefail

if (( $# != 3 )); then
    printf 'usage: static-sdl.sh SDL3_SOURCE SDL3_TTF_SOURCE OUTPUT_DIR\n' >&2
    exit 64
fi

sdl_source=$1
ttf_source=$2
output_dir=$3

cmake -S "$sdl_source" -B "$output_dir/sdl" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DSDL_STATIC=ON -DSDL_SHARED=OFF \
    -DSDL_TESTS=OFF -DSDL_EXAMPLES=OFF \
    -DSDL_HIDAPI=OFF -DSDL_JOYSTICK=OFF -DSDL_HAPTIC=OFF \
    -DSDL_SENSOR=OFF -DSDL_CAMERA=OFF -DSDL_AUDIO=OFF
cmake --build "$output_dir/sdl" --parallel 6

# The native text module supplies its own pinned FreeType/HarfBuzz objects.
# SDL_ttf's static archive refers to those symbols without bundling another
# copy; the build host still needs their headers for this initial Linux path.
cmake -S "$ttf_source" -B "$output_dir/ttf" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF \
    -DSDL3_DIR="$output_dir/sdl" \
    -DSDLTTF_VENDORED=OFF -DSDLTTF_PLUTOSVG=OFF \
    -DSDLTTF_SAMPLES=OFF -DSDLTTF_INSTALL=OFF -DSDLTTF_STRICT=ON
cmake --build "$output_dir/ttf" --parallel 6

test -s "$output_dir/sdl/libSDL3.a"
test -s "$output_dir/ttf/libSDL3_ttf.a"
