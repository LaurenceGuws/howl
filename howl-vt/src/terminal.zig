//! Owns one terminal instance and its curated native embedding operations.

const std = @import("std");
const input_encode = @import("input/encode.zig");
const input_encoded = @import("input/encoded.zig");
const input_event = @import("input/event.zig");
const input_keyboard = @import("input/keyboard.zig");
const input_mouse = @import("input/mouse.zig");
const iterm = @import("iterm.zig");
const locator = @import("locator.zig");
const mode = @import("mode.zig");
const osc_color = @import("osc_color.zig");
const screen = @import("screen.zig");
const host_state = @import("host_state.zig");
const kitty_state = @import("kitty/state.zig");
const parser_mod = @import("parser.zig");
const semantic_event = @import("semantic_event.zig");
const selection = @import("selection.zig");
const selection_projection = @import("selection_projection.zig");
const screen_set = @import("screen_set.zig");
const stream_terminal = @import("stream_terminal.zig");
const surface_publication = @import("publication.zig");
const savepoint_mod = @import("terminal/savepoint.zig");

const ScreenNs = screen.Screen;
const TerminalModeNs = mode;
const FeedSummary = stream_terminal.FeedSummary;
const FeedError = stream_terminal.FeedError;
const SemanticEvent = semantic_event.SemanticEvent;

/// Host-neutral terminal state and protocol engine.
pub const Terminal = struct {
    const HostState = host_state.State;
    const KittyState = kitty_state.KittyState;
    /// Exposes the terminal-borrowing byte stream type used by native hosts.
    pub const Stream = stream_terminal.Stream;
    /// Reports invalid zero dimensions or allocation failure during construction.
    pub const InitError = error{ InvalidDimensions, OutOfMemory };
    /// Reports invalid zero dimensions or allocation failure before resize mutation.
    pub const ResizeError = error{InvalidDimensions} || std.mem.Allocator.Error;
    /// Reports a zero cell-pixel dimension before any screen mutation.
    pub const CellPixelSizeError = error{InvalidDimensions};
    /// Copies one nonzero host-provided terminal cell size in logical pixels.
    pub const CellPixelSize = struct {
        width: u32,
        height: u32,
    };
    /// Borrows validated shell-integration identity from one surface publication.
    pub const ShellIntegration = iterm.ShellIntegration;
    /// Bounds the optional copied shell name in shell-integration metadata.
    pub const shell_name_max_bytes = iterm.shell_name_max_bytes;
    /// Exposes the typed host-input vocabulary accepted by encodeInput.
    pub const InputEvent = input_event.Event;
    /// Exposes named physical keys whose terminal identity is not Unicode text.
    pub const NamedKey = input_keyboard.NamedKey;
    /// Validates Unicode physical-key identities before input encoding.
    pub const Key = input_keyboard.Key;
    /// Provides caller-owned fixed scratch storage for allocation-free input encoding.
    pub const InputScratch = input_encode.Scratch;
    /// Returns encoded input with explicit borrowed-or-owned byte lifetime.
    pub const EncodedInput = input_encoded.Encoded;
    /// Reports paste construction or bounded locator-report retention failure.
    pub const InputError = input_encode.PasteError || host_state.ApplyError ||
        error{ InvalidUtf8, InvalidText, KeyTextLimit };
    /// Uses the canonical copied terminal RGB value.
    pub const Rgb = ScreenNs.Rgb;
    /// Uses the canonical default, indexed, or RGB cell color.
    pub const Color = ScreenNs.Color;
    /// Uses the canonical complete cell attribute value.
    pub const CellAttrs = ScreenNs.CellAttrs;
    /// Uses the canonical terminal underline style.
    pub const UnderlineStyle = ScreenNs.UnderlineStyle;
    /// Uses the canonical resolved cursor shape.
    pub const CursorShape = ScreenNs.CursorShape;
    /// Provides the canonical default terminal cell attributes.
    pub const default_cell_attrs = ScreenNs.default_cell_attrs;
    /// Provides the immutable terminal palette and dynamic-color defaults.
    pub const default_presentation = defaultPresentation();
    /// Bounds each borrowed title or icon value in a surface publication.
    pub const metadata_max_bytes = host_state.metadata_max_bytes;

    const ScreenSet = screen_set.Set;

    allocator: std.mem.Allocator,
    stream_state: stream_terminal.TerminalStreamState,
    screen_state: ScreenSet,
    modes: TerminalModeNs.ModeState = .{},
    kitty: KittyState = .{},
    xtchecksum_flags: u16 = 0,
    host: HostState,
    gl_index: u8 = 0,
    g0_designation: u8 = 'B',
    g1_designation: u8 = 'B',
    primary_savepoint: savepoint_mod.Savepoint = .{},
    alternate_savepoint: savepoint_mod.Savepoint = .{},
    dirty_generation: u64 = 1,
    surface_publication: surface_publication.Publication = .{},
    scrollback_offset: u32 = 0,

    /// Selects absolute, relative, or edge-based history viewport movement.
    pub const ScrollViewport = union(enum) {
        top,
        bottom,
        delta: i64,
        absolute: u64,
    };

    fn initWithScreens(allocator: std.mem.Allocator, stream_state: stream_terminal.TerminalStreamState, state: ScreenNs, alt_state: ScreenNs) Terminal {
        return .{
            .allocator = allocator,
            .stream_state = stream_state,
            .screen_state = ScreenSet.init(state, alt_state),
            .host = HostState.init(allocator),
        };
    }

    /// Initialize terminal state with owned primary and alternate cell storage.
    ///
    /// Both dimensions must be nonzero. The caller owns the returned terminal
    /// and must call `deinit`.
    pub fn init(allocator: std.mem.Allocator, rows: u16, cols: u16) InitError!Terminal {
        try validateDimensions(rows, cols);
        var stream_state = try stream_terminal.TerminalStreamState.initAlloc(allocator);
        errdefer stream_state.deinit();
        var state = try ScreenNs.initWithCells(allocator, rows, cols);
        errdefer state.deinit(allocator);
        var alt_state = try ScreenNs.initWithCells(allocator, rows, cols);
        errdefer alt_state.deinit(allocator);
        return initWithScreens(allocator, stream_state, state, alt_state);
    }

    /// Initialize terminal state with owned cells and bounded primary history.
    ///
    /// Both dimensions must be nonzero. The caller owns the returned terminal
    /// and must call `deinit`. `history_capacity` bounds retained logical rows;
    /// the alternate screen never retains history.
    pub fn initWithHistory(allocator: std.mem.Allocator, rows: u16, cols: u16, history_capacity: u16) InitError!Terminal {
        try validateDimensions(rows, cols);
        var stream_state = try stream_terminal.TerminalStreamState.initAlloc(allocator);
        errdefer stream_state.deinit();
        var state = try ScreenNs.initWithCellsAndHistory(allocator, rows, cols, history_capacity);
        errdefer state.deinit(allocator);
        var alt_state = try ScreenNs.initWithCells(allocator, rows, cols);
        errdefer alt_state.deinit(allocator);
        return initWithScreens(allocator, stream_state, state, alt_state);
    }

    /// Release Terminal resources.
    pub fn deinit(self: *Terminal) void {
        const allocator = self.allocator;
        self.host.deinit();
        self.screen_state.deinit(allocator);
        self.stream_state.deinit();
    }

    /// Returns a stream borrowing this terminal; the terminal must outlive its use.
    pub fn vtStream(self: *Terminal) Stream {
        return .init(self);
    }

    /// Applies a borrowed byte slice and reports mutation; failures reset transient parser state.
    pub fn feed(self: *Terminal, bytes: []const u8) FeedError!FeedSummary {
        const history_before = self.visibleHistoryCount();
        const was_scrolled = self.scrollback_offset > 0;
        var stream = self.vtStream();
        const summary = try stream.nextSliceSummary(bytes);
        self.postApply(summary.state_changed);
        self.repairScrollbackAfterHistoryChange(history_before, was_scrolled);
        return summary;
    }

    /// Publishes mutation identity and enforces cursor and selection invariants after routing.
    pub fn postApply(self: *Terminal, state_changed: bool) void {
        self.screen_state.activeSelection().clearIfInvalidatedByGrid(
            self.screen_state.activeConst(),
        );
        if (state_changed) self.dirty_generation +%= 1;
    }

    /// Resize both terminal screens.
    ///
    /// Both dimensions must be nonzero. Invalid dimensions or allocation
    /// failure leave both screens and terminal publication state unchanged.
    pub fn resize(self: *Terminal, rows: u16, cols: u16) ResizeError!void {
        try validateDimensions(rows, cols);
        try self.screen_state.resize(self.allocator, rows, cols);
        self.screen_state.activeSelection().clearIfInvalidatedByGrid(
            self.screen_state.activeConst(),
        );
        self.clampScrollbackOffset();
        self.dirty_generation +%= 1;
    }

    /// Sets nonzero cell pixels on both screens; zero dimensions are rejected unchanged.
    pub fn setCellPixelSize(
        self: *Terminal,
        width: u32,
        height: u32,
    ) CellPixelSizeError!void {
        if (width == 0 or height == 0) return error.InvalidDimensions;
        const previous = self.screen_state.primary.cellPixelSize();
        if (previous) |cell| {
            if (cell.width == width and cell.height == height) return;
        }

        self.screen_state.setCellPixelSize(width, height);
    }

    /// Returns configured nonzero cell pixels for protocol reports, when known.
    pub fn cellPixelSize(self: *const Terminal) ?CellPixelSize {
        const value = self.screen_state.activeConst().cellPixelSize() orelse return null;
        return .{ .width = value.width, .height = value.height };
    }

    /// Applies terminal reset while preserving dimensions and owned allocations.
    pub fn resetScreen(self: *Terminal) void {
        self.screen_state.reset();
        self.primary_savepoint.clear();
        self.alternate_savepoint.clear();
        self.gl_index = 0;
        self.g0_designation = 'B';
        self.g1_designation = 'B';
        self.kitty.resetTerminalState();
        self.host.resetTerminalState();
    }

    /// Saves cursor, charset, origin, and wrap state into the active screen slot.
    pub fn saveCursor(self: *Terminal) void {
        const active = self.screen_state.activeConst();
        const savepoint = self.activeSavepoint();
        savepoint.* = .{
            .valid = true,
            .cursor = .{
                .row = active.cursor.row,
                .col = active.cursor.col,
                .style = active.cursor.effectiveStyle(),
            },
            .current_attrs = active.current_attrs,
            .reverse_screen_mode = self.modes.reverse_screen_mode,
            .origin_mode = active.origin_mode,
            .auto_wrap = active.auto_wrap,
            .gl_index = self.gl_index,
            .g0_designation = self.g0_designation,
            .g1_designation = self.g1_designation,
        };
    }

    /// Restores the active screen savepoint and clamps position to current bounds.
    pub fn restoreCursor(self: *Terminal) void {
        const active = self.screen_state.active();
        const savepoint = self.activeSavepointConst();
        active.wrap_pending = false;
        if (!savepoint.valid) {
            active.cursor.setPositionStructural(0, 0);
            self.modes.reverse_screen_mode = false;
            active.origin_mode = false;
            self.gl_index = 0;
            self.g0_designation = 'B';
            self.g1_designation = 'B';
            return;
        }

        self.modes.reverse_screen_mode = savepoint.reverse_screen_mode;
        active.origin_mode = savepoint.origin_mode;
        active.auto_wrap = savepoint.auto_wrap;
        active.current_attrs = savepoint.current_attrs;
        active.cursor.restoreSavedStyle(savepoint.cursor.style);
        restoreCursorPosition(active, savepoint.cursor.row, savepoint.cursor.col);
        self.gl_index = savepoint.gl_index;
        self.g0_designation = savepoint.g0_designation;
        self.g1_designation = savepoint.g1_designation;
    }

    /// Switches primary or alternate screen with explicit clear and cursor-save behavior.
    pub fn switchScreenMode(self: *Terminal, enable_alt: bool, clear_alt: bool, save_restore_cursor: bool) void {
        if (enable_alt) {
            if (self.screen_state.alt_active) return;
            if (save_restore_cursor) self.saveCursor();
            self.screen_state.alt_active = true;
            self.scrollback_offset = 0;
            self.screen_state.activeSelection().clear();
            if (clear_alt) self.screen_state.alternate.clearVisibleCells();
            self.screen_state.alternate.resetCursorForAltEntry();
            self.screen_state.alternate.markAllRowsDirty();
            return;
        }

        if (!self.screen_state.alt_active) return;
        self.screen_state.alt_active = false;
        self.clampScrollbackOffset();
        self.screen_state.activeSelection().clear();
        if (save_restore_cursor) self.restoreCursor();
        self.screen_state.primary.markAllRowsDirty();
    }

    /// Apply one canonical semantic mode event.
    pub fn applyModeEvent(self: *Terminal, event: SemanticEvent) void {
        switch (event) {
            .application_cursor_keys => |enabled| self.modes.application_cursor_keys = enabled,
            .application_keypad => |enabled| self.modes.application_keypad = enabled,
            .reverse_screen_mode => |enabled| self.modes.reverse_screen_mode = enabled,
            .ansi_mode_set => |modes| self.setAnsiModes(modes.params[0..modes.param_count], true),
            .ansi_mode_reset => |modes| self.setAnsiModes(modes.params[0..modes.param_count], false),
            .modify_other_keys_set => |value| self.modes.modify_other_keys = value,
            .modify_other_keys_disable => self.modes.modify_other_keys = -1,
            .key_format_change => |change| {
                if (change.resource) |resource| {
                    if (isKeyFormatResource(resource)) self.modes.key_format[resource] = change.value orelse 0;
                } else {
                    self.modes.key_format = [_]u16{0} ** 8;
                }
            },
            .pointer_mode => |value| self.modes.pointer_mode = value,
            .reverse_wraparound_mode => |enabled| self.modes.reverse_wraparound_mode = enabled,
            .extended_reverse_wraparound_mode => |enabled| self.modes.extended_reverse_wraparound_mode = enabled,
            .focus_reporting => |enabled| self.modes.focus_reporting = enabled,
            .bracketed_paste => |enabled| self.modes.bracketed_paste = enabled,
            .synchronized_output => |enabled| self.modes.synchronized_output = enabled,
            .mouse_tracking_off => self.modes.mouse_tracking = .off,
            .mouse_tracking_x10 => self.modes.mouse_tracking = .x10,
            .mouse_tracking_normal => self.modes.mouse_tracking = .normal,
            .mouse_tracking_button_event => self.modes.mouse_tracking = .button_event,
            .mouse_tracking_any_event => self.modes.mouse_tracking = .any_event,
            .mouse_protocol_utf8 => |enabled| self.modes.mouse_protocol = if (enabled) .utf8 else .none,
            .mouse_protocol_sgr => |enabled| self.modes.mouse_protocol = if (enabled) .sgr else .none,
            .mouse_protocol_urxvt => |enabled| self.modes.mouse_protocol = if (enabled) .urxvt else .none,
            .dec_mode_save => |modes| self.saveDecModes(modes.params[0..modes.param_count]),
            .dec_mode_restore => |modes| self.restoreDecModes(modes.params[0..modes.param_count]),
            else => unreachable,
        }
    }

    fn decModeState(self: *const Terminal, mode_number: u16) u8 {
        const active = self.screen_state.activeConst();
        return TerminalModeNs.decModeStateForView(.{
            .application_cursor_keys = self.modes.application_cursor_keys,
            .application_keypad = self.modes.application_keypad,
            .reverse_screen_mode = self.modes.reverse_screen_mode,
            .auto_wrap = active.auto_wrap,
            .left_right_margin_mode = active.left_right_margin_mode,
            .cursor_visible = active.cursor.visible,
            .alt_active = self.screen_state.alt_active,
            .mouse_tracking = self.modes.mouse_tracking,
            .mouse_protocol = self.modes.mouse_protocol,
            .focus_reporting = self.modes.focus_reporting,
            .bracketed_paste = self.modes.bracketed_paste,
            .synchronized_output = self.modes.synchronized_output,
        }, mode_number);
    }

    fn saveDecModes(self: *Terminal, mode_numbers: []const u16) void {
        for (mode_numbers) |mode_number| {
            if (!TerminalModeNs.canSetDecMode(mode_number)) continue;
            const slot = TerminalModeNs.savedDecModeSlot(self.modes.saved_dec_modes[0..], &self.modes.saved_dec_mode_count, mode_number);
            self.modes.saved_dec_modes[@intCast(slot)] = .{
                .mode = mode_number,
                .state = self.decModeState(mode_number),
            };
        }
    }

    fn restoreDecModes(self: *Terminal, mode_numbers: []const u16) void {
        for (mode_numbers) |mode_number| {
            const state = TerminalModeNs.savedDecModeState(self.modes.saved_dec_modes[0..], self.modes.saved_dec_mode_count, mode_number) orelse continue;
            switch (state) {
                1 => self.setDecMode(mode_number, true),
                2 => self.setDecMode(mode_number, false),
                else => {},
            }
        }
    }

    fn setDecMode(self: *Terminal, mode_number: u16, enabled: bool) void {
        const active = self.screen_state.active();
        switch (mode_number) {
            1 => self.modes.application_cursor_keys = enabled,
            5 => self.modes.reverse_screen_mode = enabled,
            6 => active.applyScreen(.{ .origin_mode = enabled }),
            7 => active.applyScreen(.{ .auto_wrap = enabled }),
            69 => active.applyScreen(.{ .left_right_margin_mode = enabled }),
            25 => active.applyScreen(.{ .cursor_visible = enabled }),
            66 => self.modes.application_keypad = enabled,
            47 => self.switchScreenMode(enabled, false, false),
            1047 => self.switchScreenMode(enabled, true, false),
            1049 => self.switchScreenMode(enabled, true, true),
            9 => self.modes.mouse_tracking = if (enabled) .x10 else .off,
            1000 => self.modes.mouse_tracking = if (enabled) .normal else .off,
            1002 => self.modes.mouse_tracking = if (enabled) .button_event else .off,
            1003 => self.modes.mouse_tracking = if (enabled) .any_event else .off,
            1004 => self.modes.focus_reporting = enabled,
            1005 => self.modes.mouse_protocol = if (enabled) .utf8 else .none,
            1006 => self.modes.mouse_protocol = if (enabled) .sgr else .none,
            1015 => self.modes.mouse_protocol = if (enabled) .urxvt else .none,
            2004 => self.modes.bracketed_paste = enabled,
            2026 => self.modes.synchronized_output = enabled,
            else => {},
        }
    }

    fn setAnsiModes(self: *Terminal, mode_numbers: []const u16, enabled: bool) void {
        const active = self.screen_state.active();
        for (mode_numbers) |mode_number| switch (mode_number) {
            2 => self.modes.keyboard_action_mode = enabled,
            4 => active.applyScreen(.{ .insert_mode = enabled }),
            12 => self.modes.send_receive_mode = enabled,
            20 => self.modes.newline_mode = enabled,
            else => {},
        };
    }

    /// Acknowledges a published snapshot and retires dirty state only for valid identities.
    pub fn ackSurface(self: *Terminal, snapshot_seq: u64) bool {
        if (!self.surface_publication.canAck(snapshot_seq, self.dirty_generation)) return false;
        screen_set.clearDirtyRows(&self.screen_state);
        return true;
    }

    /// Moves the history viewport within current visible-history bounds.
    pub fn scrollViewport(self: *Terminal, behavior: ScrollViewport) bool {
        const history_count = self.visibleHistoryCount();
        const previous = self.scrollback_offset;
        self.scrollback_offset = switch (behavior) {
            .top => history_count,
            .bottom => 0,
            .delta => |delta| offset: {
                if (delta < 0) {
                    const decrease: u64 = if (delta == std.math.minInt(i64))
                        @as(u64, @intCast(std.math.maxInt(i64))) + 1
                    else
                        @intCast(-delta);
                    break :offset if (decrease >= previous) 0 else previous - @as(u32, @intCast(decrease));
                }
                const increase: u64 = @intCast(delta);
                const target = @as(u64, previous) + increase;
                break :offset @intCast(@min(target, history_count));
            },
            .absolute => |offset| @intCast(@min(offset, history_count)),
        };
        std.debug.assert(self.scrollback_offset <= history_count);
        return self.scrollback_offset != previous;
    }

    /// Returns history rows currently reachable above the active screen.
    pub fn visibleHistoryCount(self: *const Terminal) u32 {
        if (self.screen_state.alt_active) return 0;
        return self.screen_state.activeConst().historyCount();
    }

    fn clampScrollbackOffset(self: *Terminal) void {
        const history_count = self.visibleHistoryCount();
        self.scrollback_offset = @min(self.scrollback_offset, history_count);
        std.debug.assert(self.scrollback_offset <= history_count);
    }

    fn repairScrollbackAfterHistoryChange(self: *Terminal, history_before: u32, was_scrolled: bool) void {
        const history_after = self.visibleHistoryCount();
        if (history_after > history_before) {
            if (was_scrolled) {
                const delta = history_after - history_before;
                const target = @as(u64, self.scrollback_offset) + delta;
                self.scrollback_offset = @intCast(@min(target, history_after));
                std.debug.assert(self.scrollback_offset <= history_after);
            }
            return;
        }
        self.scrollback_offset = @min(self.scrollback_offset, history_after);
        std.debug.assert(self.scrollback_offset <= history_after);
    }

    /// Publishes and borrows the current surface until terminal mutation.
    pub fn surfaceSnapshot(self: *Terminal) SurfacePublication {
        const snapshot = screen_set.surfaceSnapshot(&self.screen_state, self.scrollback_offset);
        const active = self.screen_state.activeConst();
        const colors = self.host.terminalColorState();
        return .{
            .snapshot_seq = self.surface_publication.publish(
                snapshot.view,
                self.scrollback_offset,
                self.dirty_generation,
            ),
            .dirty_generation = self.dirty_generation,
            .snapshot = snapshot,
            .presentation = .{
                .palette = colors.palette,
                .foreground = colors.foreground,
                .background = colors.background,
                .cursor = active.cursor.cursor_color orelse colors.cursor,
                .cursor_text = active.cursor.cursor_text_color orelse colors.cursor_text,
                .reverse_screen = self.modes.reverse_screen_mode,
            },
            .title = self.host.current_title,
            .icon = self.host.current_icon,
            .shell_integration = if (self.host.shell_integration) |integration| .{
                .version = integration.version,
                .shell = integration.shell,
            } else null,
            .shell_mark = self.host.shell_mark,
            .bell_generation = self.host.bell_generation,
            .is_alternate_screen = snapshot.view.is_alternate_screen,
        };
    }

    /// Returns copied dimensions, cursor, history, and active-screen metadata.
    pub fn visibleMeta(self: *Terminal) VisibleMeta {
        const publication = self.surfaceSnapshot();
        const view = publication.snapshot.view;
        return .{
            .rows = view.rows,
            .cols = view.cols,
            .history_count = view.history_count,
            .is_alternate_screen = view.is_alternate_screen,
            .snapshot_seq = publication.snapshot_seq,
            .dirty_generation = publication.dirty_generation,
        };
    }

    /// Borrows a cell hyperlink URI only when snapshot identity and coordinates are valid.
    pub fn visibleCellHyperlinkUri(self: *Terminal, snapshot_seq: u64, row: u16, col: u16) error{InvalidArgument}!?[]const u8 {
        if (snapshot_seq == 0) return error.InvalidArgument;
        const publication = self.surfaceSnapshot();
        if (publication.snapshot_seq != snapshot_seq) return error.InvalidArgument;
        const view = publication.snapshot.view;
        if (row >= view.rows or col >= view.cols) return error.InvalidArgument;
        return self.host.hyperlinkUriForId(view.cellInfoAt(row, col).attrs.link_id);
    }

    /// Borrows the current cell hyperlink URI, or null for invalid coordinates or no link.
    pub fn visibleCellHyperlinkUriCurrent(self: *Terminal, row: u16, col: u16) ?[]const u8 {
        const publication = self.surfaceSnapshot();
        const view = publication.snapshot.view;
        if (row >= view.rows or col >= view.cols) return null;
        return self.host.hyperlinkUriForId(view.cellInfoAt(row, col).attrs.link_id);
    }

    /// Returns a copied active-screen selection when one exists.
    pub fn selectionState(self: *const Terminal) ?selection.TerminalSelection {
        return self.screen_state.activeSelectionConst().state();
    }

    /// Starts selection at a clamped column and VT/history row.
    pub fn startSelection(self: *Terminal, row: i32, col: u16) void {
        self.screen_state.activeSelection().start(self.selectionAbsoluteRow(row), col);
        self.noteSelectionChanged();
    }

    /// Moves the active selection endpoint to a clamped column.
    pub fn updateSelection(self: *Terminal, row: i32, col: u16) void {
        const before = self.selectionState() orelse return;
        self.screen_state.activeSelection().update(self.selectionAbsoluteRow(row), col);
        const after = self.selectionState() orelse return;
        if (before.end.row == after.end.row and before.end.col == after.end.col) return;
        self.noteSelectionChanged();
    }

    /// Marks the active selection complete without changing its endpoints.
    pub fn finishSelection(self: *Terminal) void {
        const before = self.selectionState() orelse return;
        self.screen_state.activeSelection().finish();
        const after = self.selectionState() orelse return;
        if (before.selecting == after.selecting) return;
        self.noteSelectionChanged();
    }

    /// Clears active-screen selection state.
    pub fn clearSelection(self: *Terminal) void {
        if (self.selectionState() == null) return;
        self.screen_state.activeSelection().clear();
        self.noteSelectionChanged();
    }

    /// Copy selected terminal text into caller-owned memory.
    ///
    /// The returned slice is always owned by `allocator`, including when no
    /// selection exists, and the caller must free it.
    pub fn copySelection(self: *const Terminal, allocator: std.mem.Allocator) selection_projection.CopyError![]const u8 {
        if (self.selectionState() == null) return allocator.dupe(u8, "");
        return selection_projection.copyText(allocator, &self.screen_state, self.selectionState());
    }

    /// Encode one host input event according to current terminal modes.
    ///
    /// Non-paste results borrow `scratch` or event bytes. Paste encoding may
    /// allocate through `allocator`; callers must always call `deinit` on the
    /// returned value. Paste length overflow is reported separately from
    /// allocator exhaustion. Mouse input may also fail while retaining a
    /// bounded locator report; failure preserves pending output and report
    /// latches.
    pub fn encodeInput(
        self: *Terminal,
        allocator: std.mem.Allocator,
        scratch: *InputScratch,
        event: InputEvent,
    ) InputError!EncodedInput {
        return switch (event) {
            .bytes => |bytes| .{ .bytes = bytes },
            .key => |key| .{ .bytes = try self.encodeKeyInput(scratch, key) },
            .mouse => |mouse| .{ .bytes = try self.encodeMouseInput(scratch, mouse) },
            .focus => |focus| .{ .bytes = self.encodeFocusInput(scratch, focus) },
            .paste => |text| input_encode.encodePaste(self.modes.bracketed_paste, allocator, text),
        };
    }

    fn encodeKeyInput(
        self: *Terminal,
        scratch: *InputScratch,
        event: input_event.KeyEvent,
    ) error{ InvalidUtf8, InvalidText, KeyTextLimit }![]const u8 {
        if (self.modes.keyboard_action_mode) return scratch.buf[0..0];
        const kitty_flags = self.kitty.activeScreenConst(
            self.screen_state.alt_active,
        ).keyboard.flags;
        comptime std.debug.assert(@sizeOf(InputScratch) >=
            input_keyboard.max_kitty_encoded_bytes);
        const encoded = input_keyboard.encodeEvent(
            scratch.buf[0..],
            event.key,
            event.mods,
            event.action,
            event.shifted,
            event.alternate,
            event.legacy_text,
            event.text,
            self.modes.application_cursor_keys,
            self.modes.application_keypad,
            self.modes.modify_other_keys,
            self.modes.key_format[4],
            kitty_flags,
        ) catch |failure| switch (failure) {
            error.InvalidUtf8 => return error.InvalidUtf8,
            error.InvalidText => return error.InvalidText,
            error.KeyTextLimit => return error.KeyTextLimit,
            // InputScratch is mechanically larger than the complete encoding
            // bound asserted above; callers cannot reach this encoder error.
            error.EncodingLimit => unreachable,
        };
        std.debug.assert(encoded.len <= scratch.buf.len);
        if (self.modes.newline_mode and event.key == .named and event.key.named == .enter and std.mem.eql(u8, encoded, "\r")) {
            return input_encode.writeScratch(scratch, "\r\n");
        }
        return encoded;
    }

    fn encodeMouseInput(self: *Terminal, scratch: *InputScratch, event: input_mouse.MouseEvent) host_state.ApplyError![]const u8 {
        try locator.handleMouseEvent(&self.host.locator, self.allocator, &self.host.pending_output, scratch.buf[0..], event);
        const encoded = input_mouse.encodeMouse(scratch.buf[0..], event, self.modes.mouse_tracking, self.modes.mouse_protocol);
        std.debug.assert(encoded.len <= scratch.buf.len);
        return encoded;
    }

    fn encodeFocusInput(self: *const Terminal, scratch: *InputScratch, event: input_event.FocusEvent) []const u8 {
        if (!self.modes.focus_reporting) return scratch.buf[0..0];
        return input_encode.writeScratch(scratch, switch (event) {
            .in => "\x1b[I",
            .out => "\x1b[O",
        });
    }

    /// Drain pending terminal reply bytes into caller-owned memory.
    ///
    /// Allocation failure preserves the pending bytes. The caller must free a
    /// successful result with `allocator`.
    pub fn drainPendingOutput(self: *Terminal, allocator: std.mem.Allocator) error{OutOfMemory}![]u8 {
        const owned = try allocator.dupe(u8, self.host.pendingOutput());
        self.host.clearPendingOutput();
        return owned;
    }

    /// Drain and decode a pending OSC 52 clipboard-set consequence.
    ///
    /// A returned slice is owned by `allocator`; `null` means no decodable set
    /// request was pending. Allocation failure preserves the request.
    pub fn drainPendingClipboard(self: *Terminal, allocator: std.mem.Allocator) error{OutOfMemory}!?[]u8 {
        return self.host.drainPendingClipboardSet(allocator);
    }

    fn noteSelectionChanged(self: *Terminal) void {
        self.screen_state.active().markAllRowsDirty();
        self.dirty_generation +%= 1;
    }

    fn selectionAbsoluteRow(self: *const Terminal, row: i32) i32 {
        if (row < 0) return row;
        const absolute = @as(u64, self.screen_state.activeConst().historyRowBase()) + @as(u64, @intCast(row));
        return std.math.cast(i32, absolute) orelse std.math.maxInt(i32);
    }

    fn activeSavepoint(self: *Terminal) *savepoint_mod.Savepoint {
        return if (self.screen_state.alt_active) &self.alternate_savepoint else &self.primary_savepoint;
    }

    fn activeSavepointConst(self: *const Terminal) *const savepoint_mod.Savepoint {
        return if (self.screen_state.alt_active) &self.alternate_savepoint else &self.primary_savepoint;
    }

    fn restoreCursorPosition(active: *ScreenNs, row: u16, col: u16) void {
        if (active.rows == 0 or active.cols == 0) {
            active.cursor.setPositionStructural(0, 0);
            return;
        }

        const top = if (active.origin_mode) active.scroll_top else 0;
        const bottom = if (active.origin_mode) @min(active.scroll_bottom, active.rows - 1) else active.rows - 1;
        const bounded_row = @max(top, @min(row, bottom));
        const bounded_col = @min(col, active.cols - 1);
        active.cursor.setPositionStructural(bounded_row, bounded_col);
    }

    /// Pairs a borrowed complete surface and metadata until terminal mutation.
    pub const SurfacePublication = struct {
        snapshot_seq: u64,
        dirty_generation: u64,
        snapshot: screen_set.SurfaceSnapshot,
        presentation: Presentation,
        title: ?[]const u8,
        icon: ?[]const u8,
        shell_integration: ?ShellIntegration,
        shell_mark: host_state.ShellMark,
        /// Monotonic count of accepted BEL controls; presentation belongs to the embedder.
        bell_generation: u64,
        is_alternate_screen: bool,
    };

    /// Copies the palette, dynamic defaults, cursor colors, and screen-wide
    /// reverse state that resolve one complete surface publication.
    pub const Presentation = struct {
        palette: [256]Rgb,
        foreground: Rgb,
        background: Rgb,
        cursor: ?Rgb,
        cursor_text: ?Rgb,
        reverse_screen: bool,
    };

    fn defaultPresentation() Presentation {
        const colors = osc_color.TerminalColorState{};
        return .{
            .palette = colors.palette,
            .foreground = colors.foreground,
            .background = colors.background,
            .cursor = null,
            .cursor_text = null,
            .reverse_screen = false,
        };
    }

    /// Copies host-facing viewport dimensions, cursor, history, and active-screen facts.
    pub const VisibleMeta = struct {
        rows: u16,
        cols: u16,
        history_count: u32,
        is_alternate_screen: bool,
        snapshot_seq: u64,
        dirty_generation: u64,
    };

    /// Returns the active G0, G1, and GL charset selection for DECCIR reporting.
    pub fn deccirCharsetState(self: *const Terminal) parser_mod.DeccirCharsetState {
        return .{
            .gl_index = self.gl_index,
            .g0_designation = self.g0_designation,
            .g1_designation = self.g1_designation,
        };
    }
};

fn validateDimensions(rows: u16, cols: u16) error{InvalidDimensions}!void {
    if (rows == 0 or cols == 0) return error.InvalidDimensions;
}

fn isKeyFormatResource(resource: u8) bool {
    return resource <= 4 or resource == 6 or resource == 7;
}

comptime {
    const maximum_cell_count =
        @as(u64, std.math.maxInt(u16)) * @as(u64, std.math.maxInt(u16));
    std.debug.assert(maximum_cell_count <= std.math.maxInt(u32));
    std.debug.assert(maximum_cell_count <= std.math.maxInt(usize));
}

test "terminal scroll viewport owns bottom intent" {
    var vt = try Terminal.initWithHistory(std.testing.allocator, 3, 5, 8);
    defer vt.deinit();

    const feed = try vt.feed("1AAAA\r\n2BBBB\r\n3CCCC\r\n4DDDD");
    try std.testing.expect(feed.state_changed);
    try std.testing.expect(vt.visibleHistoryCount() > 0);
    try std.testing.expect(vt.scrollViewport(.top));
    try std.testing.expect(vt.scrollback_offset > 0);
    try std.testing.expect(vt.scrollViewport(.bottom));
    try std.testing.expectEqual(@as(u32, 0), vt.scrollback_offset);
    try std.testing.expect(!vt.scrollViewport(.bottom));
}

test "terminal feed preserves scrolled viewport as history grows" {
    var vt = try Terminal.initWithHistory(std.testing.allocator, 3, 5, 8);
    defer vt.deinit();

    const initial_feed = try vt.feed("1AAAA\r\n2BBBB\r\n3CCCC\r\n4DDDD");
    try std.testing.expect(initial_feed.state_changed);
    try std.testing.expect(vt.scrollViewport(.{ .absolute = 1 }));
    const before = vt.surfaceSnapshot().snapshot.view.cellAt(0, 0);
    const offset_before = vt.scrollback_offset;

    const append_feed = try vt.feed("\r\n5EEEE");
    try std.testing.expect(append_feed.state_changed);

    try std.testing.expect(vt.scrollback_offset > offset_before);
    try std.testing.expectEqual(before, vt.surfaceSnapshot().snapshot.view.cellAt(0, 0));
}

test "terminal publishes every bounded bell and remains reusable" {
    var vt = try Terminal.init(std.testing.allocator, 2, 2);
    defer vt.deinit();

    const first = try vt.feed("\x07");
    try std.testing.expect(first.state_changed);
    try std.testing.expectEqual(@as(u64, 1), vt.surfaceSnapshot().bell_generation);

    const second = try vt.feed("\x07x");
    try std.testing.expect(second.state_changed);
    const publication = vt.surfaceSnapshot();
    try std.testing.expectEqual(@as(u64, 2), publication.bell_generation);
    try std.testing.expectEqual(@as(u21, 'x'), publication.snapshot.view.cellAt(0, 0));

    vt.host.bell_generation = std.math.maxInt(u64);
    try std.testing.expectError(error.ConsequenceLimit, vt.feed("\x07"));
    try std.testing.expectEqual(std.math.maxInt(u64), vt.host.bell_generation);
    vt.host.bell_generation = 2;
    const reused = try vt.feed("y");
    try std.testing.expect(reused.state_changed);
    try std.testing.expectEqual(@as(u21, 'y'), vt.surfaceSnapshot().snapshot.view.cellAt(0, 1));
}
