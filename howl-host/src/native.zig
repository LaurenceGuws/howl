//! Imports the native host's concrete Wayland, EGL, GLES, xkb, and Linux C namespace.

pub const c = @cImport({
    @cDefine("_FORTIFY_SOURCE", "0");
    @cInclude("EGL/egl.h");
    @cInclude("GLES2/gl2.h");
    @cInclude("errno.h");
    @cInclude("poll.h");
    @cInclude("sys/eventfd.h");
    @cInclude("sys/mman.h");
    @cInclude("sys/timerfd.h");
    @cInclude("linux/input-event-codes.h");
    @cInclude("unistd.h");
    @cInclude("wayland-client.h");
    @cInclude("wayland-egl.h");
    @cInclude("xkbcommon/xkbcommon.h");
    @cInclude("xkbcommon/xkbcommon-keysyms.h");
    @cInclude("xdg-shell-client-protocol.h");
});
