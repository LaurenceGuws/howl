//! Owns monotonic mutation and snapshot identities for terminal surface publication.

const std = @import("std");
const screen_set = @import("screen_set.zig");

/// Tracks monotonic mutation, snapshot, and acknowledgement identities.
pub const Publication = struct {
    seq: u64 = 1,
    dirty_generation: u64 = 0,
    scrollback_offset: u64 = 0,
    start: u64 = 0,
    rows: u16 = 0,
    cols: u16 = 0,
    alt: bool = false,

    /// Publishes a new snapshot only when mutation advanced beyond the last publication.
    pub fn publish(self: *Publication, view: screen_set.View, scrollback_offset: u64, dirty_generation: u64) u64 {
        std.debug.assert(view.rows > 0);
        std.debug.assert(view.cols > 0);
        const same_dirty = self.dirty_generation == dirty_generation;
        const same_offset = self.scrollback_offset == scrollback_offset;
        const same_start = self.start == view.start;
        const same_rows = self.rows == view.rows;
        const same_cols = self.cols == view.cols;
        const same_alt = self.alt == view.is_alternate_screen;
        if (!(same_dirty and same_offset and same_start and same_rows and same_cols and same_alt)) {
            if (self.dirty_generation != 0) self.seq +%= 1;
            self.dirty_generation = dirty_generation;
            self.scrollback_offset = scrollback_offset;
            self.start = view.start;
            self.rows = view.rows;
            self.cols = view.cols;
            self.alt = view.is_alternate_screen;
        }
        std.debug.assert(self.seq != 0);
        return self.seq;
    }

    /// Accepts acknowledgement only for a nonzero snapshot no newer than publication.
    pub fn canAck(self: Publication, snapshot_seq: u64, dirty_generation_current: u64) bool {
        if (snapshot_seq == 0) return false;
        return self.seq == snapshot_seq and self.dirty_generation == dirty_generation_current;
    }
};
