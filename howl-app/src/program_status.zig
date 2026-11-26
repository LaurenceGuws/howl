//! Bounded OSC 7501 status index owned by one Howl terminal worker.
//! VT validates protocol bytes and transports typed events. This host owns
//! per-pane status identity, recency, clear/seen/exit/reset lifetimes,
//! and a tiny copied UI summary. No renderer access, allocation or raw messages.
const std = @import("std");
const vt = @import("howl_vt");

const status = vt.Terminal.ProgramStatus;

/// Rex revision 0.4 requires at least 64 records per terminal.
/// Choose the minimum supported capacity; evict the least recently updated.
pub const max_records: usize = 64;

/// The only status facts copied from the PTY worker to the SDL header.
pub const Summary = struct {
    state: ?status.State = null,
    kind: ?status.Kind = null,
    progress: ?u8 = null,
    count: u8 = 0,
    /// Already validated ASCII application name; no raw program title or
    /// arbitrary OSC string enters the graphical worker snapshot.
    app: [32]u8 = @splat(0),
    app_len: u8 = 0,

    /// Exact validated program name, or empty when the child did not provide one.
    pub fn appText(self: *const Summary) []const u8 {
        return self.app[0..self.app_len];
    }
};

const Record = struct {
    id: [128]u8 = undefined,
    id_len: u8,
    app: [32]u8 = @splat(0),
    app_len: u8 = 0,
    state: status.State,
    kind: ?status.Kind,
    progress: ?u8,
    changed_at: u64,
    reported_at: u64,

    fn idBytes(self: *const Record) []const u8 {
        return self.id[0..self.id_len];
    }

    fn appText(self: *const Record) []const u8 {
        return self.app[0..self.app_len];
    }
};

/// Fixed per-window host status store. No app-global state or activity clock.
pub const Index = struct {
    records: [max_records]Record = undefined,
    len: usize = 0,
    sequence: u64 = 0,
    reset_generation: u64 = 0,

    /// Discards prior process status when VT signals a hard reset.
    /// Caller must ignore old queued events with earlier reset tags.
    pub fn syncReset(self: *Index, current: u64) bool {
        if (self.reset_generation == current) return false;
        const changed = self.len != 0;
        self.len = 0;
        self.reset_generation = current;
        return changed;
    }

    /// Applies a validated, borrowed OSC 7501 event within this host owner.
    pub fn apply(self: *Index, action: status.Action) bool {
        return switch (action) {
            .query => false,
            .report => |report| self.applyReport(report),
            .clear => |id| self.clear(id),
            .process_exited => self.processExited(),
        };
    }

    /// Clears idle, working and blocked records after process exit/prompt.
    pub fn processExited(self: *Index) bool {
        var changed = false;
        var i: usize = 0;
        while (i < self.len) {
            const state = self.records[i].state;
            if (state == .idle or state == .working or state == .blocked) {
                self.remove(i);
                changed = true;
            } else i += 1;
        }
        return changed;
    }

    /// User input acknowledges unseen finished/error indications but leaves
    /// still-blocked work pending until its program reports a resolution.
    pub fn seenByUser(self: *Index) bool {
        var changed = false;
        var i: usize = 0;
        while (i < self.len) {
            const state = self.records[i].state;
            if (state == .done or state == .@"error") {
                self.remove(i);
                changed = true;
            } else i += 1;
        }
        return changed;
    }

    /// Highest urgency wins, most recently changed record breaks ties.
    /// Identical updates refresh eviction recency without changing urgency.
    pub fn summary(self: *const Index) Summary {
        if (self.len == 0) return .{};
        var chosen: usize = 0;
        for (self.records[1..self.len], 1..) |record, i| {
            const best = self.records[chosen];
            if (rank(record.state) > rank(best.state) or
                (record.state == best.state and record.changed_at > best.changed_at))
                chosen = i;
        }
        const selected = &self.records[chosen];
        var same: u8 = 0;
        for (self.records[0..self.len]) |record| {
            if (record.state == selected.state) same += 1;
        }
        var result: Summary = .{
            .state = selected.state,
            .kind = selected.kind,
            .progress = selected.progress,
            .count = same,
        };
        const app = self.effectiveApp(selected);
        @memcpy(result.app[0..app.len], app);
        result.app_len = @intCast(app.len);
        return result;
    }

    fn find(self: *const Index, id: []const u8) ?usize {
        for (self.records[0..self.len], 0..) |*record, i| {
            if (std.mem.eql(u8, record.idBytes(), id)) return i;
        }
        return null;
    }

    // Resolve from current records, not a copied inherited name. Ancestors
    // may appear, change, disappear, or lack an explicit app of their own.
    fn effectiveApp(self: *const Index, record: *const Record) []const u8 {
        const own = record.appText();
        if (own.len != 0) return own;
        var id = record.idBytes();
        while (id.len != 0) {
            id = if (std.mem.lastIndexOfScalar(u8, id, '/')) |slash| id[0..slash] else "";
            if (self.find(id)) |ancestor| {
                const app = self.records[ancestor].appText();
                if (app.len != 0) return app;
            }
        }
        return "";
    }

    fn nextSequence(self: *Index) u64 {
        // zig-audit: acknowledge panic
        // reason: Process-lifetime update IDs cannot wrap and invert recency order.
        self.sequence = std.math.add(u64, self.sequence, 1) catch @panic("program status sequence exhausted");
        return self.sequence;
    }

    fn applyReport(self: *Index, report: status.Report) bool {
        std.debug.assert(report.id.len <= 128);
        const now = self.nextSequence();
        var index: usize = undefined;
        if (self.find(report.id)) |existing| {
            index = existing;
            const old = &self.records[index];
            const changed = old.state != report.state or
                old.kind != report.kind or old.progress != report.progress or
                !std.mem.eql(u8, old.appText(), report.app);
            old.reported_at = now;
            if (!changed) return false;
        } else if (self.len < max_records) {
            index = self.len;
            self.len += 1;
        } else {
            index = 0;
            for (self.records[1..self.len], 1..) |record, i| {
                if (record.reported_at < self.records[index].reported_at) index = i;
            }
        }
        const entry = &self.records[index];
        @memcpy(entry.id[0..report.id.len], report.id);
        entry.id_len = @intCast(report.id.len);
        @memcpy(entry.app[0..report.app.len], report.app);
        entry.app_len = @intCast(report.app.len);
        entry.state = report.state;
        entry.kind = report.kind;
        entry.progress = report.progress;
        entry.changed_at = now;
        entry.reported_at = now;
        return true;
    }

    fn clear(self: *Index, ancestor: []const u8) bool {
        var changed = false;
        var i: usize = 0;
        while (i < self.len) {
            const id = self.records[i].idBytes();
            if (ancestor.len == 0 or
                std.mem.eql(u8, ancestor, id) or
                (id.len > ancestor.len and std.mem.startsWith(u8, id, ancestor) and id[ancestor.len] == '/'))
            {
                self.remove(i);
                changed = true;
            } else i += 1;
        }
        return changed;
    }

    fn remove(self: *Index, index: usize) void {
        std.debug.assert(index < self.len);
        self.len -= 1;
        if (index < self.len) self.records[index] = self.records[self.len];
    }
};

fn rank(state: status.State) u8 {
    return switch (state) {
        .idle => 1,
        .working => 2,
        .done => 3,
        .@"error" => 4,
        .blocked => 5,
    };
}
