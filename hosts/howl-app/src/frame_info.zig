//! Copied host interaction facts from one immutable terminal output cut.
const instance = @import("howl_instance");
const output = @import("howl_vt_output");
const render = instance.render.terminal;

/// Visible cursor geometry, independent of the underlying command storage.
pub const Cursor = struct {
    rect: render.Rect,
    shape: enum { block, bar, underline },
};

/// Small copied facts used by host input, cursor clocks, selection and scrolling.
pub const Info = struct {
    sequence: u64 = 0,
    presentation_generation: u64 = 0,
    terminal_revision: u64 = 0,
    content_revision: u64 = 0,
    cursor: ?Cursor = null,
    cursor_blink: bool = false,
    cursor_movement: u64 = 0,
    has_cursor_command: bool = false,
    history_offset: u32 = 0,
    history_count: u32 = 0,
    history_row_base: u32 = 0,
    alternate_screen: bool = false,
    surface: render.Size = .{ .width = 0, .height = 0 },
    cell_size: render.Size = .{ .width = 0, .height = 0 },

    /// Projects old publication metadata while the legacy path is removed.
    pub fn fromLegacy(frame: instance.PublishedFrame) Info {
        return .{
            .sequence = frame.sequence,
            .presentation_generation = frame.presentation_generation,
            .terminal_revision = frame.terminal_revision,
            .content_revision = frame.content_revision,
            .cursor = if (frame.cursor) |cursor| switch (cursor.shape) {
                .block => Cursor{ .rect = cursor.rect, .shape = .block },
                .bar => Cursor{ .rect = cursor.rect, .shape = .bar },
                .underline => Cursor{ .rect = cursor.rect, .shape = .underline },
                .none => null,
            } else null,
            .cursor_blink = frame.cursor_blink,
            .cursor_movement = frame.cursor_movement,
            .has_cursor_command = frame.commands.len != frame.content_command_count,
            .history_offset = frame.history_offset,
            .history_count = frame.history_count,
            .history_row_base = frame.history_row_base,
            .alternate_screen = frame.alternate_screen,
            .surface = frame.surface,
            .cell_size = frame.cell_size,
        };
    }

    /// Copies the same facts from a pinned direct VT cut.
    pub fn fromSnapshot(snapshot: *const output.Snapshot, generation: u64, sequence: u64) Info {
        return .{
            .sequence = sequence,
            .presentation_generation = generation,
            .terminal_revision = snapshot.terminal_revision,
            .content_revision = snapshot.content_revision,
            .cursor = if (snapshot.cursor_cell) |rect| if (snapshot.cursor_shape) |shape| switch (shape) {
                .block => Cursor{ .rect = rect, .shape = .block },
                .bar => Cursor{ .rect = rect, .shape = .bar },
                .underline => Cursor{ .rect = rect, .shape = .underline },
                .none => null,
            } else null else null,
            .cursor_blink = snapshot.cursor_blink,
            .cursor_movement = snapshot.cursor_movement,
            .has_cursor_command = snapshot.cursor != null,
            .history_offset = snapshot.history_offset,
            .history_count = snapshot.history_count,
            .history_row_base = snapshot.history_row_base,
            .alternate_screen = snapshot.alternate,
            .surface = snapshot.surface,
            .cell_size = .{ .width = snapshot.cell_width, .height = snapshot.cell_height },
        };
    }
};
