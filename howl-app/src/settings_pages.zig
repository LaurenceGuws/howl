//! Settings page geometry: each page owns a clipped, pixel-scrolled viewport.
const std = @import("std");
const chrome = @import("chrome.zig");
const layout = @import("layout.zig");
const widgets = @import("widgets.zig");
const keybindings = @import("keybindings.zig");
const color_config = @import("colors.zig");

/// Header actions available in the Settings panel.
pub const SettingsHeaderAction = enum { save, cancel, search, close };
/// Settings header height inherited from shared window chrome.
pub const settings_header_height: f32 = chrome.height;
/// Vertical origin of the Settings sidebar navigation rows.
pub const settings_nav_top: f32 = settings_header_height + chrome.Geometry.bottom;
/// Symmetric gap between the Settings viewport and each card.
pub const settings_card_gutter: f32 = 12;
/// Horizontal inset from card edges to field rows.
pub const settings_card_padding: f32 = 16;

/// Startup owns only the default profile; scanning lives under Profiles.
pub const StartupForm = struct {
    view: widgets.FormViewport,
    compact: bool,
    /// Symmetric gap separating each card from the viewport edges.
    pub const outer_inset: f32 = settings_card_gutter;
    /// Horizontal padding from card edges to interactive rows.
    pub const inner_inset: f32 = settings_card_padding;
    /// Padding before the first card in the scrollable page.
    pub const top_inset: f32 = settings_card_gutter;

    /// Construct the page geometry with one clamped pixel scroll offset.
    pub fn init(bounds: layout.Rect, offset: f32) StartupForm {
        const compact = bounds.width < 390;
        return .{ .view = widgets.FormViewport.atOffset(bounds, (if (compact) @as(f32, 178) else 146) + top_inset, offset), .compact = compact };
    }
    /// Place one painted card within the page-owned scroll coordinates.
    pub fn card(self: StartupForm, _: usize) layout.Rect {
        return self.view.place(outer_inset, 2 + top_inset, @max(1, self.view.bounds.width - 2 * outer_inset), if (self.compact) 164 else 132);
    }
    /// Place one interactive row within its owning card.
    pub fn row(self: StartupForm, _: usize) layout.Rect {
        const top: f32 = if (self.compact) 70 else 74;
        const height: f32 = if (self.compact) 88 else 52;
        const inset = outer_inset + inner_inset;
        return self.view.place(inset, top + top_inset, @max(1, self.view.bounds.width - 2 * inset), height);
    }
    /// Place the default-profile select control inside the Startup card.
    pub fn select(self: StartupForm) layout.Rect {
        const field = self.row(0);
        const width = if (self.compact) field.width else @min(field.width, @max(1, field.width * 0.53));
        return .{ .x = field.x + field.width - width, .y = field.y + (if (self.compact) @as(f32, 44) else 8), .width = width, .height = 36 };
    }
};
/// Appearance groups independent controls in cards and uses pixel scrolling.
pub const AppearanceForm = struct {
    view: widgets.FormViewport,

    /// Named section with its starting row and row count.
    pub const Section = struct { title: []const u8, hint: []const u8, first: usize, count: usize };
    /// Ordered card sections shared by hit testing and painting.
    pub const sections = [_]Section{
        .{ .title = "Tab bar", .hint = "Visibility and tab sizing.", .first = 0, .count = 2 },
        .{ .title = "Fonts", .hint = "Typefaces and fallback coverage.", .first = 2, .count = 8 },
        .{ .title = "Cursor", .hint = "Shape, motion, and blink behavior.", .first = 10, .count = 10 },
    };
    /// Padding before the first card in the scrollable page.
    pub const top_inset: f32 = settings_card_gutter;
    /// Symmetric gap separating each card from the viewport edges.
    pub const outer_inset: f32 = settings_card_gutter;
    /// Horizontal padding from card edges to interactive rows.
    pub const inner_inset: f32 = settings_card_padding;
    /// Vertical spacing between adjacent cards.
    pub const card_gap: f32 = 14;
    /// Vertical space reserved for the card heading and hint.
    pub const heading_height: f32 = 66;
    /// Vertical pitch for one field row including its gap.
    pub const row_stride: f32 = 48;
    /// Interactive row height excluding the inter-row gap.
    pub const row_height: f32 = 44;
    /// Blank space retained after the last row in a card.
    pub const card_bottom: f32 = 12;
    /// Total indexed field rows on this Settings page.
    pub const count: usize = sections[sections.len - 1].first + sections[sections.len - 1].count;

    /// Height of one card, including its heading and rows.
    pub fn cardHeight(number: usize) f32 {
        return heading_height + @as(f32, @floatFromInt(sections[number].count)) * row_stride + card_bottom;
    }
    /// Unscrolled vertical origin of a card in the shared viewport.
    pub fn cardTop(number: usize) f32 {
        var top = top_inset;
        for (0..number) |index| top += cardHeight(index) + card_gap;
        return top;
    }
    /// Unscrolled vertical origin of an indexed row.
    pub fn rowTop(number: usize) f32 {
        std.debug.assert(number < count);
        var index: usize = 0;
        while (index + 1 < sections.len and number >= sections[index + 1].first) : (index += 1) {}
        return cardTop(index) + heading_height + @as(f32, @floatFromInt(number - sections[index].first)) * row_stride;
    }
    /// Total page scroll extent including trailing padding.
    pub fn contentHeight() f32 {
        return cardTop(sections.len - 1) + cardHeight(sections.len - 1) + top_inset;
    }
    /// Construct the page geometry with one clamped pixel scroll offset.
    pub fn init(bounds: layout.Rect, offset: f32) AppearanceForm {
        return .{ .view = widgets.FormViewport.atOffset(bounds, contentHeight(), offset) };
    }
    /// Place one painted card within the page-owned scroll coordinates.
    pub fn card(self: AppearanceForm, number: usize) layout.Rect {
        return self.view.place(outer_inset, cardTop(number), @max(1, self.view.bounds.width - 2 * outer_inset), cardHeight(number));
    }
    /// Place one interactive row within its owning card.
    pub fn row(self: AppearanceForm, number: usize) layout.Rect {
        const inset = outer_inset + inner_inset;
        return self.view.place(inset, rowTop(number), @max(1, self.view.bounds.width - 2 * inset), row_height);
    }
    /// Resolve a row only when the pointer is inside the page viewport.
    pub fn hit(self: AppearanceForm, x: f32, y: f32) ?usize {
        if (!self.view.bounds.contains(x, y)) return null;
        for (0..count) |number| if (self.row(number).contains(x, y)) return number;
        return null;
    }
};
/// App chrome, terminal colors, inline editing and sample share one scroll owner.
pub const ColorForm = struct {
    view: widgets.FormViewport,
    editor_row: ?usize,

    /// Named section with its starting row and row count.
    pub const Section = struct { title: []const u8, hint: []const u8, first: usize, count: usize };
    /// Application palette rows before the terminal palette section.
    pub const app_count = 1 + color_config.app_labels.len + 1;
    /// Ordered card sections shared by hit testing and painting.
    pub const sections = [_]Section{
        .{ .title = "Application", .hint = "Window chrome, tabs, and controls.", .first = 0, .count = app_count },
        .{ .title = "Terminal", .hint = "Text, cursor, and the ANSI palette.", .first = app_count, .count = 1 + color_config.terminal_labels.len + 2 },
    };
    /// Total indexed field rows on this Settings page.
    pub const count = sections[sections.len - 1].first + sections[sections.len - 1].count;
    /// Symmetric gap separating each card from the viewport edges.
    pub const outer_inset: f32 = settings_card_gutter;
    /// Horizontal padding from card edges to interactive rows.
    pub const inner_inset: f32 = settings_card_padding;
    /// Vertical space reserved for the card heading and hint.
    pub const heading_height: f32 = 66;
    /// Vertical pitch for one field row including its gap.
    pub const row_stride: f32 = 48;
    /// Interactive row height excluding the inter-row gap.
    pub const row_height: f32 = 44;
    /// Vertical spacing between adjacent cards.
    pub const card_gap: f32 = 14;
    /// Blank space retained after the last row in a card.
    pub const card_bottom: f32 = 12;
    /// Space inserted after the active color row for its RGB editor.
    pub const editor_extra: f32 = 104;
    /// Height of the separate terminal preview card.
    pub const preview_height: f32 = 144;

    /// Height of one card, including its heading and rows.
    pub fn cardHeight(number: usize) f32 {
        return heading_height + @as(f32, @floatFromInt(sections[number].count)) * row_stride + card_bottom;
    }
    /// Unscrolled vertical origin of a card in the shared viewport.
    pub fn cardTop(number: usize) f32 {
        var top = outer_inset;
        for (0..number) |index| top += cardHeight(index) + card_gap;
        return top;
    }
    /// Unscrolled vertical origin of an indexed row.
    pub fn rowTop(number: usize) f32 {
        std.debug.assert(number < count);
        const section: usize = if (number < app_count) 0 else 1;
        return cardTop(section) + heading_height + @as(f32, @floatFromInt(number - sections[section].first)) * row_stride;
    }
    /// Position the sample after both color sections and any open editor.
    pub fn previewTop(self: ColorForm) f32 {
        return cardTop(sections.len - 1) + cardHeight(sections.len - 1) + card_gap +
            (if (self.editor_row != null) editor_extra else @as(f32, 0));
    }
    /// Total page scroll extent including the preview card and trailing padding.
    pub fn contentHeight(self: ColorForm) f32 {
        return self.previewTop() + preview_height + outer_inset;
    }
    /// Construct the page geometry with one clamped pixel scroll offset.
    pub fn init(bounds: layout.Rect, offset: f32, editor_row: ?usize) ColorForm {
        std.debug.assert(editor_row == null or editor_row.? < count);
        var form: ColorForm = .{ .view = undefined, .editor_row = editor_row };
        form.view = widgets.FormViewport.atOffset(bounds, form.contentHeight(), offset);
        return form;
    }
    /// Place one painted card within the page-owned scroll coordinates.
    pub fn card(self: ColorForm, number: usize) layout.Rect {
        std.debug.assert(number < sections.len);
        const section = sections[number];
        const before: f32 = if (self.editor_row) |index| (if (index < section.first) editor_extra else 0) else 0;
        const within: f32 = if (self.editor_row) |index| (if (index >= section.first and index < section.first + section.count) editor_extra else 0) else 0;
        return self.view.place(outer_inset, cardTop(number) + before, @max(1, self.view.bounds.width - 2 * outer_inset), cardHeight(number) + within);
    }
    /// Place one interactive row within its owning card.
    pub fn row(self: ColorForm, number: usize) layout.Rect {
        std.debug.assert(number < count);
        const inset = outer_inset + inner_inset;
        const shift: f32 = if (self.editor_row) |index| (if (number > index) editor_extra else 0) else 0;
        return self.view.place(inset, rowTop(number) + shift, @max(1, self.view.bounds.width - 2 * inset), row_height);
    }
    /// Inline editor bounds immediately after its selected color row.
    pub fn editor(self: ColorForm) layout.Rect {
        const selected = self.row(self.editor_row.?);
        return .{ .x = selected.x, .y = selected.y + row_stride + 4, .width = selected.width, .height = editor_extra - 8 };
    }
    /// RGB slider geometry that moves with the selected row.
    pub fn editorBar(self: ColorForm, channel: usize) layout.Rect {
        std.debug.assert(channel < 3);
        const area = self.editor();
        return .{ .x = area.x + 24, .y = area.y + 8 + @as(f32, @floatFromInt(channel)) * 22, .width = @max(1, area.width - 116), .height = 18 };
    }
    /// Preset reset and its color sample beside the inline sliders.
    pub fn editorReset(self: ColorForm) layout.Rect {
        const area = self.editor();
        return .{ .x = area.x + area.width - 82, .y = area.y + 8, .width = 78, .height = 62 };
    }
    /// Terminal sample is another card in the same scrollable form.
    pub fn previewCard(self: ColorForm) layout.Rect {
        return self.view.place(outer_inset, self.previewTop(), @max(1, self.view.bounds.width - 2 * outer_inset), preview_height);
    }
    /// Resolve a row only when the pointer is inside the page viewport.
    pub fn hit(self: ColorForm, x: f32, y: f32) ?usize {
        if (!self.view.bounds.contains(x, y)) return null;
        for (0..count) |number| if (self.row(number).contains(x, y)) return number;
        return null;
    }
};
/// Shortcuts use their registry categories as distinct cards on one viewport.
/// The registry order and persisted action IDs never change for presentation.
pub const ShortcutForm = struct {
    view: widgets.FormViewport,

    /// Named section with its starting row and row count.
    pub const Section = struct { category: keybindings.Category, title: []const u8, hint: []const u8 };
    /// Ordered card sections shared by hit testing and painting.
    pub const sections = [_]Section{
        .{ .category = .application, .title = "Application", .hint = "Launchers, menus, and settings." },
        .{ .category = .window, .title = "Windows", .hint = "Window creation and display." },
        .{ .category = .tab, .title = "Tabs", .hint = "Switch, arrange, and name tabs." },
        .{ .category = .pane, .title = "Panes", .hint = "Split, manage, and restart panes." },
        .{ .category = .pane_navigation, .title = "Pane navigation", .hint = "Focus, resize, and exchange panes." },
        .{ .category = .terminal, .title = "Terminal", .hint = "Fonts, find, clipboard, and history." },
    };
    /// Symmetric gap separating each card from the viewport edges.
    pub const outer_inset: f32 = settings_card_gutter;
    /// Horizontal padding from card edges to interactive rows.
    pub const inner_inset: f32 = settings_card_padding;
    /// Vertical space reserved for the card heading and hint.
    pub const heading_height: f32 = 66;
    /// Vertical pitch for one field row including its gap.
    pub const row_stride: f32 = 48;
    /// Interactive row height excluding the inter-row gap.
    pub const row_height: f32 = 44;
    /// Vertical spacing between adjacent cards.
    pub const card_gap: f32 = 14;
    /// Blank space retained after the last row in a card.
    pub const card_bottom: f32 = 12;

    /// Resolve one registered shortcut category to its card index.
    pub fn sectionFor(category: keybindings.Category) usize {
        const index: usize = @backingInt(category);
        std.debug.assert(index < sections.len and sections[index].category == category);
        return index;
    }
    /// Count the shortcut definitions owned by one category.
    pub fn rowCount(number: usize) usize {
        var count: usize = 0;
        for (keybindings.definitions) |definition| if (definition.category == sections[number].category) {
            count += 1;
        };
        return count;
    }
    /// Height of one card, including its heading and rows.
    pub fn cardHeight(number: usize) f32 {
        return heading_height + @as(f32, @floatFromInt(rowCount(number))) * row_stride + card_bottom;
    }
    /// Unscrolled vertical origin of a card in the shared viewport.
    pub fn cardTop(number: usize) f32 {
        var top = outer_inset;
        for (0..number) |index| top += cardHeight(index) + card_gap;
        return top;
    }
    /// Unscrolled vertical origin of an indexed row.
    pub fn rowTop(index: usize) f32 {
        std.debug.assert(index < keybindings.definitions.len);
        const category = keybindings.definitions[index].category;
        var preceding: usize = 0;
        for (keybindings.definitions[0..index]) |definition| if (definition.category == category) {
            preceding += 1;
        };
        return cardTop(sectionFor(category)) + heading_height + @as(f32, @floatFromInt(preceding)) * row_stride;
    }
    /// Total page scroll extent including trailing padding.
    pub fn contentHeight() f32 {
        return cardTop(sections.len - 1) + cardHeight(sections.len - 1) + outer_inset;
    }
    /// Construct the page geometry with one clamped pixel scroll offset.
    pub fn init(bounds: layout.Rect, offset: f32) ShortcutForm {
        return .{ .view = widgets.FormViewport.atOffset(bounds, contentHeight(), offset) };
    }
    /// Place one painted card within the page-owned scroll coordinates.
    pub fn card(self: ShortcutForm, number: usize) layout.Rect {
        return self.view.place(outer_inset, cardTop(number), @max(1, self.view.bounds.width - 2 * outer_inset), cardHeight(number));
    }
    /// Place one interactive row within its owning card.
    pub fn row(self: ShortcutForm, index: usize) layout.Rect {
        const inset = outer_inset + inner_inset;
        return self.view.place(inset, rowTop(index), @max(1, self.view.bounds.width - 2 * inset), row_height);
    }
    /// Resolve a row only when the pointer is inside the page viewport.
    pub fn hit(self: ShortcutForm, x: f32, y: f32) ?usize {
        if (!self.view.bounds.contains(x, y)) return null;
        for (keybindings.definitions, 0..) |_, index| if (self.row(index).contains(x, y)) return index;
        return null;
    }
};
/// Profiles owns one viewport for discovery, saved recipes, scanned recipes,
/// and the saved-profile editor. Rows own only selection and hit geometry.
pub const ProfilesForm = struct {
    view: widgets.FormViewport,
    overview: bool,
    compact: bool,
    saved_count: usize,
    scanned_count: usize,
    detail_count: usize,

    /// Symmetric gap separating each card from the viewport edges.
    pub const outer_inset: f32 = settings_card_gutter;
    /// Horizontal padding from card edges to interactive rows.
    pub const inner_inset: f32 = settings_card_padding;
    /// Vertical spacing between adjacent cards.
    pub const card_gap: f32 = 14;
    /// Vertical space reserved for the card heading and hint.
    pub const heading_height: f32 = 66;
    /// Vertical space for profile details and its action bar.
    pub const detail_heading_height: f32 = 112;
    /// Vertical pitch for one field row including its gap.
    pub const row_stride: f32 = 48;
    /// Interactive row height excluding the inter-row gap.
    pub const row_height: f32 = 44;
    /// Blank space retained after the last row in a card.
    pub const card_bottom: f32 = 12;

    /// Construct the page geometry with one clamped pixel scroll offset.
    pub fn init(bounds: layout.Rect, offset: f32, overview: bool, saved_count: usize, scanned_count: usize, detail_count: usize) ProfilesForm {
        var form: ProfilesForm = .{
            .view = undefined,
            .overview = overview,
            .compact = bounds.width < 320,
            .saved_count = saved_count,
            .scanned_count = scanned_count,
            .detail_count = detail_count,
        };
        form.view = widgets.FormViewport.atOffset(bounds, form.contentHeight(), offset);
        return form;
    }
    /// Number of catalogue or details cards visible in this mode.
    pub fn cardCount(self: ProfilesForm) usize {
        return if (self.overview) 3 else 1;
    }
    /// Height of one card, including its heading and rows.
    pub fn cardHeight(self: ProfilesForm, number: usize) f32 {
        if (!self.overview) {
            std.debug.assert(number == 0);
            return detail_heading_height + @as(f32, @floatFromInt(self.detail_count)) * row_stride + card_bottom;
        }
        std.debug.assert(number < 3);
        if (number == 0) return if (self.compact) 146 else 112;
        if (number == 1) return heading_height + @as(f32, @floatFromInt(self.saved_count)) * row_stride + card_bottom;
        return heading_height + @as(f32, @floatFromInt(@max(1, self.scanned_count))) * row_stride + card_bottom;
    }
    /// Unscrolled vertical origin of a card in the shared viewport.
    pub fn cardTop(self: ProfilesForm, number: usize) f32 {
        std.debug.assert(number < self.cardCount());
        var top = outer_inset;
        for (0..number) |index| top += self.cardHeight(index) + card_gap;
        return top;
    }
    /// Total page scroll extent including trailing padding.
    pub fn contentHeight(self: ProfilesForm) f32 {
        const last = self.cardCount() - 1;
        return self.cardTop(last) + self.cardHeight(last) + outer_inset;
    }
    /// Place one painted card within the page-owned scroll coordinates.
    pub fn card(self: ProfilesForm, number: usize) layout.Rect {
        return self.view.place(outer_inset, self.cardTop(number), @max(1, self.view.bounds.width - 2 * outer_inset), self.cardHeight(number));
    }
    /// Unscrolled vertical origin of an indexed row.
    pub fn rowTop(self: ProfilesForm, index: usize) f32 {
        if (!self.overview) {
            std.debug.assert(index < self.detail_count);
            return self.cardTop(0) + detail_heading_height + @as(f32, @floatFromInt(index)) * row_stride;
        }
        std.debug.assert(index < self.saved_count + self.scanned_count);
        const saved = index < self.saved_count;
        return self.cardTop(if (saved) 1 else 2) + heading_height + @as(f32, @floatFromInt(if (saved) index else index - self.saved_count)) * row_stride;
    }
    /// Place one interactive row within its owning card.
    pub fn row(self: ProfilesForm, index: usize) layout.Rect {
        const inset = outer_inset + inner_inset;
        return self.view.place(inset, self.rowTop(index), @max(1, self.view.bounds.width - 2 * inset), row_height);
    }
    /// Resolve a row only when the pointer is inside the page viewport.
    pub fn hit(self: ProfilesForm, x: f32, y: f32) ?usize {
        if (!self.view.bounds.contains(x, y)) return null;
        const count = if (self.overview) self.saved_count + self.scanned_count else self.detail_count;
        for (0..count) |index| if (self.row(index).contains(x, y)) return index;
        return null;
    }
    /// Place a Discovery source control within its card.
    pub fn scanSourceRow(self: ProfilesForm, number: usize) layout.Rect {
        std.debug.assert(self.overview and number < 2);
        const scan = self.card(0);
        if (self.compact) return .{
            .x = scan.x + 16,
            .y = scan.y + 54 + @as(f32, @floatFromInt(number)) * 39,
            .width = @max(1, scan.width - 32),
            .height = 34,
        };
        const width = @max(1, (scan.width - 40) / 2);
        return .{
            .x = scan.x + 16 + @as(f32, @floatFromInt(number)) * (width + 8),
            .y = scan.y + 64,
            .width = width,
            .height = 34,
        };
    }
};
