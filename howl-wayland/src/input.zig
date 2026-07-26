//! Exact, bounded Wayland input facts. Ordered protocol occurrences remain in
//! arrival order; only pointer motion, modifier, and configure snapshots are
//! coalesced with checked revisions.

const std = @import("std");

/// Maximum number of ordered protocol occurrences retained before saturation.
pub const capacity: usize = 128;
/// Maximum UTF-8 payload bytes retained for one interpreted key fact; one
/// additional byte is reserved for xkbcommon's terminating NUL.
pub const key_text_limit: usize = 65;
/// Maximum pressed-key entries copied from keyboard.enter.
pub const pressed_key_limit: usize = 32;
/// Wayland v10 keyboard transition, including the compositor's repeated-key pseudo-state.
pub const KeyState = enum { pressed, released, repeated };
/// Wayland pointer-button transition.
pub const ButtonState = enum { pressed, released };
/// Wayland pointer axis.
pub const Axis = enum { horizontal, vertical };
/// Wayland axis source advertised by pointer.axis_source.
pub const AxisSource = enum { wheel, finger, continuous, wheel_tilt };
/// Wayland axis relative-direction value.
pub const RelativeDirection = enum { identical, inverted };
/// Four protocol modifier masks plus group, without convenience booleans.
pub const Modifiers = struct { serial: u32, depressed: u32, latched: u32, locked: u32, group: u32 };
/// Ordered keyboard fact. The keymap owns interpretation of keycode.
pub const Key = struct {
    keycode: u32,
    time: u32,
    state: KeyState,
    serial: u32,
    modifiers: Modifiers,
    keysym: u32,
    text_len: u8,
    text: [key_text_limit]u8,
};
/// Ordered pointer-button fact with its protocol serial and timestamp.
pub const Button = struct { button: u32, time: u32, state: ButtonState, serial: u32, point: Point };
/// Ordered pointer-axis fact; each union arm is one exact protocol callback.
pub const AxisEvent = union(enum) {
    value: struct { axis: Axis, time: u32, value: f64 },
    source: AxisSource,
    stop: struct { axis: Axis, time: u32 },
    discrete: struct { axis: Axis, value: i32 },
    value120: struct { axis: Axis, value: i32 },
    relative_direction: struct { axis: Axis, direction: RelativeDirection },
    frame: void,
};
/// Surface-local pointer coordinates.
pub const Point = struct { x: f64, y: f64 };
/// Ordered pointer enter fact; serial is not discarded.
pub const KeyboardEnter = struct { serial: u32, pressed_count: u8, pressed: [pressed_key_limit]u32 };
/// Ordered keyboard leave fact.
pub const KeyboardLeave = struct { serial: u32 };
/// Ordered pointer enter fact; serial and coordinates are preserved.
pub const PointerEnter = struct { serial: u32, point: Point };
/// Ordered pointer leave fact; serial is not discarded.
pub const PointerLeave = struct { serial: u32 };
/// Latest motion snapshot. Motion events may coalesce.
pub const Motion = struct { time: u32, point: Point };
/// Repeat timing delivered by wl_keyboard.repeat_info.
pub const Repeat = struct { rate: u32, delay: u32 };
/// Latest compositor configure dimensions and checked revision.
pub const Configure = struct { width: u32, height: u32, revision: u64 };
/// Coalesced snapshots consumed by the embedding runtime.
pub const Snapshot = struct { motion: ?Motion, modifiers: Modifiers, repeat: ?Repeat, configure: ?Configure, revision: u64 };
/// Ordered facts that must never coalesce.
pub const Ordered = union(enum) { key: Key, keyboard_enter: KeyboardEnter, keyboard_leave: KeyboardLeave, button: Button, axis: struct { event: AxisEvent, point: ?Point }, pointer_enter: PointerEnter, pointer_leave: PointerLeave };

/// Exact bounded-state failures. Revision exhaustion is never wrapped.
pub const Error = error{ OrderedFull, RevisionOverflow };

/// Fixed-storage input state. Queue indices and count are private so callers
/// cannot break ring invariants or manufacture stale revisions.
const Storage = struct {
    ordered: [capacity]Ordered = undefined,
    head: u16 = 0,
    count: u16 = 0,
    motion: ?Motion = null,
    modifiers: Modifiers = .{ .serial = 0, .depressed = 0, .latched = 0, .locked = 0, .group = 0 },
    repeat: ?Repeat = null,
    configure: ?Configure = null,
    revision: u64 = 0,
};

pub const State = struct {
    /// Opaque-to-callers fixed storage; mutate only through State methods.
    storage: Storage = .{},

    /// Appends one exact ordered occurrence without changing state on full.
    pub fn push(self: *State, event: Ordered) Error!void {
        if (self.storage.count == capacity) return error.OrderedFull;
        const tail = (@as(usize, self.storage.head) + self.storage.count) % capacity;
        self.storage.ordered[tail] = event;
        self.storage.count += 1;
    }

    /// Replaces latest motion and increments its checked coalescing revision.
    pub fn setMotion(self: *State, motion: Motion) Error!void {
        try self.nextRevision();
        self.storage.motion = motion;
    }

    /// Replaces the exact four Wayland modifier masks.
    pub fn setModifiers(self: *State, modifiers: Modifiers) Error!void {
        try self.nextRevision();
        self.storage.modifiers = modifiers;
    }

    /// Replaces keyboard repeat timing and increments its checked revision.
    pub fn setRepeat(self: *State, repeat: Repeat) Error!void {
        try self.nextRevision();
        self.storage.repeat = repeat;
    }

    /// Replaces the newest configure dimensions, including zero “unspecified”.
    pub fn setConfigure(self: *State, width: u32, height: u32) Error!void {
        try self.nextRevision();
        self.storage.configure = .{ .width = width, .height = height, .revision = self.storage.revision };
    }

    /// Removes the oldest ordered occurrence in O(1), if present.
    pub fn take(self: *State) ?Ordered {
        if (self.storage.count == 0) return null;
        const result = self.storage.ordered[self.storage.head];
        self.storage.head = @intCast((@as(usize, self.storage.head) + 1) % capacity);
        self.storage.count -= 1;
        return result;
    }

    /// Returns the number of ordered occurrences retained.
    pub fn orderedCount(self: *const State) u16 {
        return self.storage.count;
    }

    /// Returns the current coalescing revision.
    pub fn currentRevision(self: *const State) u64 {
        return self.storage.revision;
    }

    /// Borrows the latest modifier masks, if a snapshot has been received.
    pub fn modifiersSnapshot(self: *const State) Modifiers {
        return self.storage.modifiers;
    }

    /// Borrows the latest pointer motion snapshot, if one was received.
    pub fn motionSnapshot(self: *const State) ?Motion {
        return self.storage.motion;
    }

    /// Borrows the latest configure fact, if one has been received.
    pub fn configureSnapshot(self: *const State) ?Configure {
        return self.storage.configure;
    }

    /// Takes motion and configure snapshots while retaining the latest masks.
    pub fn takeSnapshots(self: *State) Snapshot {
        const result = Snapshot{ .motion = self.storage.motion, .modifiers = self.storage.modifiers, .repeat = self.storage.repeat, .configure = self.storage.configure, .revision = self.storage.revision };
        self.storage.motion = null;
        self.storage.configure = null;
        return result;
    }

    /// Drops every fact and resets the revision.
    pub fn reset(self: *State) void {
        self.* = .{};
    }

    fn nextRevision(self: *State) Error!void {
        if (self.storage.revision == std.math.maxInt(u64)) return error.RevisionOverflow;
        self.storage.revision += 1;
    }
};
