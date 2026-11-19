//! Settings SDL presentation: cards, controls, fields and clipped page painting.
const std = @import("std");
const c = @import("desktop");
const chrome = @import("chrome.zig");
const input_ui_module = @import("settings_input.zig");
const config = @import("config.zig");
const settings = @import("settings.zig");
const widgets = @import("widgets.zig");
const layout = @import("layout.zig");
const appearance = @import("appearance.zig");
const color_config = @import("colors.zig");
const drawing = @import("pixels.zig");
const icons = @import("icons.zig");
const pages = @import("settings_pages.zig");
const fill = drawing.fill;
const outline = drawing.outline;
const setClip = drawing.setClip;
const clearClip = drawing.clearClip;
const SettingsHeaderAction = pages.SettingsHeaderAction;
const StartupForm = pages.StartupForm;
const AppearanceForm = pages.AppearanceForm;
const ColorForm = pages.ColorForm;
const ShortcutForm = pages.ShortcutForm;
const ProfilesForm = pages.ProfilesForm;
const settings_header_height = pages.settings_header_height;
const settings_nav_top = pages.settings_nav_top;
const settings_card_gutter = pages.settings_card_gutter;
const settings_card_padding = pages.settings_card_padding;
const corner_radius = chrome.Geometry.chip_radius;
const inset_radius = corner_radius - 1;

/// Bind Settings painting to the same concrete host as its input geometry.
pub fn ForHost(comptime Host: type) type {
    return struct {
        const Paint = @This();
        const Input = input_ui_module.ForHost(Host);

        /// Paint the active choice menu above the Settings page.
        pub fn drawSettingsDropdown(self: *Host) !void {
            const e = &self.settings_editor.?;
            const target = e.editing orelse return;
            if (!(settings.Row{ .page = e.page, .label = "", .target = target }).choice()) return;
            const menu = Input.settingsDropdown(self);
            const count = settings.choiceCount(target, self.settingsConfiguration());
            e.choice_list.reveal(count, menu.rows.visible());
            const start = e.choice_list.first;
            try Paint.drawSettingsCard(self, menu.rect);
            for (start..@min(count, start + menu.rows.visible())) |index| {
                const rect = menu.rows.row(index - start);
                try Paint.drawSettingsCardRow(self, rect, e.choice_list.selected == index, self.isHovered(rect), true);
                try self.clippedText((try settings.choiceAt(target, self.settingsConfiguration(), index)).label, rect, rect.x + 9);
            }
            try self.drawListScroll(menu.rows, start, count);
        }
        /// Paint the rounded card surface shared by all Settings pages.
        pub fn drawSettingsCard(self: *Host, rect: layout.Rect) !void {
            const colors = try self.uiPalette();
            try drawing.fillRounded(self.renderer, rect, colors.border, corner_radius);
            try drawing.fillRounded(self.renderer, .{ .x = rect.x + 1, .y = rect.y + 1, .width = @max(1, rect.width - 2), .height = @max(1, rect.height - 2) }, colors.panel, inset_radius);
        }
        /// Paint Settings row focus with the same corner radius as tab chips.
        pub fn drawSettingsCardRow(self: *Host, rect: layout.Rect, selected: bool, hovered: bool, focused: bool) !void {
            if (!selected and !hovered) return;
            const colors = try self.uiPalette();
            const base = if (selected) colors.active else colors.idle;
            try drawing.fillRounded(self.renderer, rect, if (hovered) appearance.hover(base) else base, corner_radius);
            if (selected and focused) try drawing.fillRounded(self.renderer, .{ .x = rect.x, .y = rect.y + 7, .width = 2, .height = @max(1, rect.height - 14) }, colors.accent, 1);
        }
        /// Paint a source or startup switch with its current state.
        pub fn drawStartupSwitch(self: *Host, rect: layout.Rect, enabled: bool, focused: bool) !void {
            const colors = try self.uiPalette();
            const control = widgets.Switch.init(rect, enabled);
            try drawing.fillRounded(self.renderer, control.track, if (focused) colors.accent else colors.border, 13);
            const inside: layout.Rect = .{ .x = rect.x + 1, .y = rect.y + 1, .width = @max(1, rect.width - 2), .height = @max(1, rect.height - 2) };
            try drawing.fillRounded(self.renderer, inside, if (enabled) colors.accent else if (self.isHovered(rect)) appearance.hover(colors.idle) else colors.idle, 12);
            try drawing.fillRounded(self.renderer, control.thumb, if (enabled) colors.title else colors.text, 10);
        }
        /// Paint a bounded clickable Settings control surface.
        pub fn drawSettingsControl(self: *Host, rect: layout.Rect, focused: bool) !void {
            const colors = try self.uiPalette();
            try drawing.fillRounded(self.renderer, rect, if (focused) colors.accent else colors.border, corner_radius);
            try drawing.fillRounded(self.renderer, .{ .x = rect.x + 1, .y = rect.y + 1, .width = @max(1, rect.width - 2), .height = @max(1, rect.height - 2) }, if (self.isHovered(rect)) appearance.hover(colors.idle) else colors.idle, inset_radius);
        }
        /// Paint a choice field with label and expansion affordance.
        pub fn drawSettingsSelect(self: *Host, rect: layout.Rect, label: []const u8, focused: bool, expanded: bool) !void {
            const colors = try self.uiPalette();
            const selector = widgets.Select.init(rect);
            try Paint.drawSettingsControl(self, selector.surface, focused);
            try self.clippedText(label, selector.label, selector.label.x);
            try icons.draw(self.renderer, if (expanded) .chevron_up else .chevron_down, selector.arrow, colors.text);
        }
        /// Paint Startup controls from its immutable page geometry.
        pub fn drawStartupForm(self: *Host) !void {
            const editor = &self.settings_editor.?;
            const form = Input.startupForm(self);
            const colors = try self.uiPalette();
            const body = Input.settingsBody(self);
            const card = form.card(0);
            if (card.y >= body.y + body.height or card.y + card.height <= body.y) return;
            try setClip(self.renderer, body);
            defer clearClip(self.renderer);
            try Paint.drawSettingsCard(self, card);
            try self.clippedText("New terminals", .{ .x = card.x + 16, .y = card.y + 10, .width = @max(1, card.width - 32), .height = 25 }, card.x + 16);
            try self.clippedTextColor("Used for new tabs and windows.", .{ .x = card.x + 16, .y = card.y + 34, .width = @max(1, card.width - 32), .height = 24 }, card.x + 16, colors.muted);
            const first = form.row(0);
            const label_width = if (form.compact) first.width else @max(1, form.select().x - first.x - 12);
            try self.clippedText("Default profile", .{ .x = first.x, .y = first.y + 3, .width = label_width, .height = 24 }, first.x);
            if (!form.compact) try self.clippedTextColor("For future tabs only", .{ .x = first.x, .y = first.y + 24, .width = label_width, .height = 24 }, first.x, colors.muted);
            const focused = self.isHovered(form.select()) or (editor.editing != null and editor.editing.? == .default_profile);
            const profile_name = if (editor.editing != null and editor.editing.? == .default_profile)
                (try settings.choiceAt(.default_profile, self.settingsConfiguration(), editor.choice_list.selected)).label
            else
                (try self.settingsConfiguration().defaultProfile()).name;
            try Paint.drawSettingsSelect(self, form.select(), profile_name, focused, editor.editing != null and editor.editing.? == .default_profile);
        }
        /// Paint Appearance section headings and card surfaces.
        pub fn drawAppearanceCards(self: *Host, form: AppearanceForm) !void {
            const colors = try self.uiPalette();
            for (AppearanceForm.sections, 0..) |section, number| {
                const card = form.card(number);
                if (card.y >= form.view.bounds.y + form.view.bounds.height or card.y + card.height <= form.view.bounds.y) continue;
                try Paint.drawSettingsCard(self, card);
                const heading: layout.Rect = .{ .x = card.x + 16, .y = card.y + 10, .width = @max(1, card.width - 32), .height = 25 };
                const hint: layout.Rect = .{ .x = card.x + 16, .y = card.y + 34, .width = @max(1, card.width - 32), .height = 24 };
                try self.clippedText(section.title, heading, heading.x);
                try self.clippedTextColor(section.hint, hint, hint.x, colors.muted);
            }
        }
        /// Paint application and terminal color card surfaces.
        pub fn drawColorCards(self: *Host, form: ColorForm) !void {
            const colors = try self.uiPalette();
            for (ColorForm.sections, 0..) |section, number| {
                const card = form.card(number);
                if (card.y >= form.view.bounds.y + form.view.bounds.height or card.y + card.height <= form.view.bounds.y) continue;
                try Paint.drawSettingsCard(self, card);
                const heading: layout.Rect = .{ .x = card.x + 16, .y = card.y + 10, .width = @max(1, card.width - 32), .height = 25 };
                const hint: layout.Rect = .{ .x = card.x + 16, .y = card.y + 34, .width = @max(1, card.width - 32), .height = 24 };
                try self.clippedText(section.title, heading, heading.x);
                try self.clippedTextColor(section.hint, hint, hint.x, colors.muted);
            }
            const card = form.previewCard();
            if (card.y >= form.view.bounds.y + form.view.bounds.height or card.y + card.height <= form.view.bounds.y) return;
            try Paint.drawSettingsCard(self, card);
            try self.clippedText("Terminal preview", .{ .x = card.x + 16, .y = card.y + 10, .width = @max(1, card.width - 32), .height = 25 }, card.x + 16);
            try self.clippedTextColor("Live sample of the staged terminal palette.", .{ .x = card.x + 16, .y = card.y + 34, .width = @max(1, card.width - 32), .height = 24 }, card.x + 16, colors.muted);
            const current = self.settingsConfiguration();
            const resolved = try current.value.terminal_colors.resolve(current.value.terminal_theme);
            const preview: layout.Rect = .{ .x = card.x + 16, .y = card.y + 66, .width = @max(1, card.width - 32), .height = 32 };
            try drawing.fillRounded(self.renderer, preview, .{ .r = resolved.background.r, .g = resolved.background.g, .b = resolved.background.b, .a = 255 }, corner_radius);
            try self.clippedTextColor("Terminal  AaBb 0123", preview, preview.x + 8, .{ .r = resolved.foreground.r, .g = resolved.foreground.g, .b = resolved.foreground.b, .a = 255 });
            const swatch_width = preview.width / 16;
            for (resolved.palette[0..16], 0..) |rgb, index| try drawing.fillRounded(self.renderer, .{ .x = preview.x + @as(f32, @floatFromInt(index)) * swatch_width, .y = preview.y + 42, .width = @max(1, swatch_width - 2), .height = 16 }, .{ .r = rgb.r, .g = rgb.g, .b = rgb.b, .a = 255 }, inset_radius);
        }
        /// Paint the active RGB editor in the expanded section immediately after its row.
        pub fn drawColorEditor(self: *Host) !void {
            const rgb = try Input.editedColor(self);
            const colors = try self.uiPalette();
            for ([_]u8{ rgb.r, rgb.g, rgb.b }, [_][]const u8{ "R", "G", "B" }, 0..) |value, label, channel| {
                const bar = Input.colorBar(self, channel);
                try self.clippedText(label, .{ .x = bar.x - 24, .y = bar.y - 4, .width = 24, .height = 24 }, bar.x - 24);
                for (0..64) |step| {
                    var shade = rgb;
                    const component: u8 = @intCast(step * 4);
                    switch (channel) {
                        0 => shade.r = component,
                        1 => shade.g = component,
                        2 => shade.b = component,
                        else => return error.InvalidColorRole,
                    }
                    try fill(self.renderer, .{ .x = bar.x + @as(f32, @floatFromInt(step)) * bar.width / 64, .y = bar.y, .width = bar.width / 64 + 1, .height = bar.height }, .{ .r = shade.r, .g = shade.g, .b = shade.b, .a = 255 });
                }
                try outline(self.renderer, bar, colors.border);
                const thumb: layout.Rect = .{ .x = bar.x + @as(f32, @floatFromInt(value)) * bar.width / 255 - 2, .y = bar.y - 2, .width = 4, .height = bar.height + 4 };
                try fill(self.renderer, thumb, colors.text);
            }
            const reset = Input.colorReset(self);
            try Paint.drawSettingsControl(self, reset, self.isHovered(reset));
            try self.clippedText("Preset", reset, reset.x + 8);
            const sample: layout.Rect = .{ .x = reset.x + 8, .y = reset.y + 30, .width = reset.width - 16, .height = 22 };
            try drawing.fillRounded(self.renderer, sample, colors.border, corner_radius);
            try drawing.fillRounded(self.renderer, .{ .x = sample.x + 1, .y = sample.y + 1, .width = @max(1, sample.width - 2), .height = @max(1, sample.height - 2) }, .{ .r = rgb.r, .g = rgb.g, .b = rgb.b, .a = 255 }, inset_radius);
        }
        /// Paint grouped shortcut category headings and cards.
        pub fn drawShortcutCards(self: *Host, form: ShortcutForm) !void {
            const colors = try self.uiPalette();
            for (ShortcutForm.sections, 0..) |section, number| {
                const card = form.card(number);
                if (card.y >= form.view.bounds.y + form.view.bounds.height or card.y + card.height <= form.view.bounds.y) continue;
                try Paint.drawSettingsCard(self, card);
                const heading: layout.Rect = .{ .x = card.x + 16, .y = card.y + 10, .width = @max(1, card.width - 32), .height = 25 };
                const hint: layout.Rect = .{ .x = card.x + 16, .y = card.y + 34, .width = @max(1, card.width - 32), .height = 24 };
                try self.clippedText(section.title, heading, heading.x);
                try self.clippedTextColor(section.hint, hint, hint.x, colors.muted);
            }
        }
        /// Paint the scrolled Discovery card and its source controls.
        pub fn drawProfileScanCard(self: *Host) !void {
            const colors = try self.uiPalette();
            const card = Input.settingsScanCard(self);
            const button = Input.settingsToolbarButton(self, 2);
            try Paint.drawSettingsCard(self, card);
            const label_width = @max(1, button.x - card.x - 24);
            try self.clippedText("Discovery", .{ .x = card.x + 16, .y = card.y + 10, .width = label_width, .height = 25 }, card.x + 16);
            try self.clippedTextColor("Read-only recipes, cached when you scan.", .{ .x = card.x + 16, .y = card.y + 34, .width = @max(1, card.width - 32), .height = 24 }, card.x + 16, colors.muted);
            for (0..2) |number| {
                const row = Input.settingsScanSourceRow(self, number);
                const toggle = Input.scanSourceSwitch(row);
                const enabled = if (number == 0) self.settingsConfiguration().value.discover_shells else self.settingsConfiguration().value.discover_ssh_hosts;
                const narrow = card.width < 500;
                const label: []const u8 = if (number == 0) (if (narrow) "Shells" else "Local shells and REPLs") else if (Input.settingsScanCompact(self)) "SSH" else if (narrow) "SSH hosts" else "SSH config hosts";
                try self.clippedText(label, .{ .x = row.x, .y = row.y, .width = @max(1, toggle.x - row.x - (if (narrow) @as(f32, 8) else 44)), .height = row.height }, row.x);
                if (!narrow) try self.clippedTextColor(if (enabled) "On" else "Off", .{ .x = toggle.x - 37, .y = row.y, .width = 30, .height = row.height }, toggle.x - 37, colors.muted);
                try Paint.drawStartupSwitch(self, toggle, enabled, self.isHovered(toggle));
            }
        }
        /// Paint Discovery, Saved and Scanned cards with optional inline details.
        pub fn drawProfilesCards(self: *Host, form: ProfilesForm) !void {
            const colors = try self.uiPalette();
            const scan = form.card(0);
            if (scan.y < form.view.bounds.y + form.view.bounds.height and scan.y + scan.height > form.view.bounds.y) try Paint.drawProfileScanCard(self);
            for (1..form.cardCount()) |number| {
                const card = form.card(number);
                if (card.y >= form.view.bounds.y + form.view.bounds.height or card.y + card.height <= form.view.bounds.y) continue;
                try Paint.drawSettingsCard(self, card);
                const width = if (number == 1) @max(1, Input.settingsToolbarButton(self, 0).x - card.x - 24) else @max(1, card.width - 32);
                const heading: layout.Rect = .{ .x = card.x + 16, .y = card.y + 10, .width = width, .height = 25 };
                const hint: layout.Rect = .{ .x = card.x + 16, .y = card.y + 34, .width = width, .height = 24 };
                try self.clippedText(if (number == 1) "Saved profiles" else "Scanned profiles", heading, heading.x);
                try self.clippedTextColor(if (number == 1) "Local and editable recipes." else "Read-only cached discoveries.", hint, hint.x, colors.muted);
                if (number == 2 and form.scanned_count == 0) {
                    const empty: layout.Rect = .{ .x = card.x + ProfilesForm.inner_inset, .y = card.y + ProfilesForm.heading_height, .width = @max(1, card.width - 2 * ProfilesForm.inner_inset), .height = 44 };
                    try self.clippedTextColor("Nothing scanned yet", empty, empty.x, colors.muted);
                }
            }
            if (form.expanded == null) return;
            const detail = form.detailCard();
            if (detail.y >= form.view.bounds.y + form.view.bounds.height or detail.y + detail.height <= form.view.bounds.y) return;
            try Paint.drawSettingsCard(self, detail);
            const heading: layout.Rect = .{ .x = detail.x + 16, .y = detail.y + 10, .width = @max(1, detail.width - 32), .height = 25 };
            const hint: layout.Rect = .{ .x = detail.x + 16, .y = detail.y + 34, .width = @max(1, detail.width - 32), .height = 24 };
            try self.clippedText("Profile details", heading, heading.x);
            var buffer: [160]u8 = undefined;
            const note = try std.fmt.bufPrint(&buffer, "{s} · Save applies your changes.", .{(try self.settingsConfiguration().profile(self.settings_editor.?.profile)).name});
            try self.clippedTextColor(note, hint, hint.x, colors.muted);
        }
        /// Paint contextual profile actions inside the owning card.
        pub fn drawProfilesToolbar(self: *Host) !void {
            const e = self.settings_editor.?;
            const labels: [3][]const u8 = if (Input.profilesForm(self).card(1).width < 500) .{ "New", "Copy", "Scan now" } else .{ "New profile", "Duplicate", "Scan now" };
            for (labels, 0..) |label, number| {
                const button = Input.settingsToolbarButton(self, number);
                try Paint.drawSettingsControl(self, button, e.button == @as(u8, @intCast(number)));
                try self.clippedText(label, button, button.x + 8);
            }
            if (!e.details_open) return;
            const detail_labels = [_][]const u8{ "Close", "Duplicate", if (e.profile == 0) "Built-in" else if (e.delete_pending != null) "Delete?" else "Delete" };
            for (detail_labels, 0..) |label, number| {
                const button = Input.settingsDetailButton(self, number);
                try Paint.drawSettingsControl(self, button, self.isHovered(button));
                try self.clippedText(label, button, button.x + 8);
            }
        }
        /// Paint the global search-result heading and hint.
        pub fn drawSettingsListHeading(self: *Host) !void {
            std.debug.assert(self.settings_editor.?.search);
            const colors = try self.uiPalette();
            const card = Input.settingsListCard(self);
            const width = @max(1, card.width - 32);
            try self.clippedText("Search results", .{ .x = card.x + 16, .y = card.y + 10, .width = width, .height = 25 }, card.x + 16);
            try self.clippedTextColor("Select a result to open its settings section.", .{ .x = card.x + 16, .y = card.y + 34, .width = width, .height = 24 }, card.x + 16, colors.muted);
        }
        /// Paint fixed Save, Cancel, search and close actions.
        pub fn drawSettingsHeaderButtons(self: *Host) !void {
            const colors = try self.uiPalette();
            const pending = self.settings_draft != null or self.settings_editor.?.editing != null;
            for ([_]SettingsHeaderAction{ .save, .cancel, .search, .close }) |action| {
                const rect = Input.settingsHeaderButton(self, action);
                const hovered = self.isHovered(rect);
                if (action == .save or action == .cancel) {
                    const active = pending and action == .save;
                    try drawing.fillRounded(self.renderer, rect, if (active) colors.accent else colors.border, chrome.Geometry.chip_radius);
                    try drawing.fillRounded(self.renderer, .{ .x = rect.x + 1, .y = rect.y + 1, .width = rect.width - 2, .height = rect.height - 2 }, if (hovered) appearance.hover(colors.idle) else colors.idle, chrome.Geometry.chip_radius - 1);
                    try self.clippedTextColor(if (action == .save) "Save" else "Cancel", rect, rect.x + (if (action == .save) @as(f32, 16) else 10), if (pending) colors.text else colors.muted);
                    continue;
                }
                if (hovered or (action == .search and self.settings_editor.?.search)) {
                    try drawing.fillRounded(self.renderer, rect, if (hovered) (if (action == .close) appearance.closeHover(colors.idle) else appearance.hover(colors.idle)) else colors.active, chrome.Geometry.chip_radius);
                }
                const color = if (hovered) colors.text else colors.muted;
                try icons.draw(self.renderer, if (action == .search) .search else .x, .{ .x = rect.x + 5, .y = rect.y + 5, .width = 20, .height = 20 }, color);
            }
        }

        /// Compose the Settings document and its single outer scrollbar.
        pub fn drawSettings(self: *Host) !void {
            const e = &self.settings_editor.?;
            const colors = try self.uiPalette();
            const box = Input.settingsRect(self);
            const body = Input.settingsBody(self);
            e.profile = @min(e.profile, self.settingsConfiguration().profileCount() - 1);
            try drawing.fillRounded(self.renderer, box, colors.border, corner_radius);
            try drawing.fillRounded(self.renderer, .{ .x = box.x + 1, .y = box.y + 1, .width = @max(1, box.width - 2), .height = @max(1, box.height - 2) }, colors.title, inset_radius);
            // The sidebar and header share one inset surface without squaring the
            // outside corners of the Settings shell.
            const side_width = @max(1, body.x - box.x - 13);
            try drawing.fillRounded(self.renderer, .{ .x = box.x + 1, .y = box.y + 1, .width = side_width, .height = @max(1, box.height - 2) }, colors.idle, inset_radius);
            try fill(self.renderer, .{ .x = box.x + corner_radius, .y = box.y + 1, .width = @max(1, side_width - inset_radius), .height = @max(1, box.height - 2) }, colors.idle);
            try drawing.fillRounded(self.renderer, .{ .x = box.x + 1, .y = box.y + 1, .width = @max(1, box.width - 2), .height = @min(settings_header_height, @max(1, box.height - 2)) }, colors.idle, inset_radius);
            try fill(self.renderer, .{ .x = box.x + 1, .y = box.y + corner_radius, .width = @max(1, box.width - 2), .height = @max(1, @min(settings_header_height - corner_radius, box.height - corner_radius - 2)) }, colors.idle);
            // The content's top-left corner sits inside the header/sidebar elbow.
            // Restore its rounded cutout without changing the square page viewport.
            const corner: layout.Rect = .{ .x = box.x + 1 + side_width, .y = box.y + settings_header_height, .width = corner_radius, .height = corner_radius };
            if (corner.x + corner.width < box.x + box.width - 1 and corner.y + corner.height < box.y + box.height - 1) {
                try fill(self.renderer, corner, colors.idle);
                {
                    try setClip(self.renderer, corner);
                    defer clearClip(self.renderer);
                    try drawing.fillRounded(self.renderer, .{ .x = corner.x, .y = corner.y, .width = corner_radius * 2, .height = corner_radius * 2 }, colors.title, corner_radius);
                }
            }
            if (box.width > 360) try self.drawText("Settings", box.x + 14, box.y + chrome.Geometry.top + 6);
            const title_width = Input.settingsHeaderButton(self, .save).x - body.x - 10;
            if (title_width > 20) try self.clippedText(if (e.search) "Search settings" else "All settings", .{ .x = body.x, .y = box.y + chrome.Geometry.top, .width = title_width, .height = chrome.Geometry.chip_height }, body.x);
            try Paint.drawSettingsHeaderButtons(self);
            const active = if (e.search) @as(usize, 0) else Input.settingsDocument(self).active();
            for (settings.titles, 0..) |title, index| {
                const row = Input.settingsNavRow(self, index);
                if (!e.search and active == index) {
                    try drawing.fillRounded(self.renderer, row, colors.active, corner_radius);
                    try drawing.fillRounded(self.renderer, .{ .x = row.x, .y = row.y + 6, .width = 2, .height = row.height - 12 }, colors.accent, 1);
                } else if (self.isHovered(row)) try drawing.fillRounded(self.renderer, row, appearance.hover(colors.idle), corner_radius);
                try self.clippedText(title, row, row.x + 10);
            }
            if (e.search) {
                try Paint.drawSettingsSection(self, null);
            } else {
                const document = Input.settingsDocument(self);
                for (0..settings.titles.len) |index| {
                    const form_bounds = document.formBounds(index);
                    const heading = document.heading(index);
                    if (heading.y >= body.y + body.height or form_bounds.y + form_bounds.height <= body.y) continue;
                    try setClip(self.renderer, body);
                    try self.clippedTextColor(settings.titles[index], heading, heading.x, colors.text);
                    clearClip(self.renderer);
                    try Paint.drawSettingsSection(self, @fromBackingInt(@intCast(index)));
                }
                if (document.view.scrollbar()) |bar| {
                    try drawing.fillRounded(self.renderer, bar.track, colors.border, 2);
                    try drawing.fillRounded(self.renderer, bar.thumb, colors.muted, 2);
                }
            }
            try Paint.drawSettingsDropdown(self);
        }
        /// Paint a borrowed section without creating a second scroll owner.
        /// A null section is the separate, bounded global Search result list.
        pub fn drawSettingsSection(self: *Host, page: ?settings.Page) !void {
            const e = &self.settings_editor.?;
            const colors = try self.uiPalette();
            const body = Input.settingsBody(self);
            const startup_form = page != null and page.? == .startup;
            const simple_form = page == null;
            const appearance_form = page != null and page.? == .appearance;
            const color_form = page != null and page.? == .colors;
            const shortcut_form = page != null and page.? == .mappings;
            const profiles_form = page != null and page.? == .defaults;
            const card_form = appearance_form or color_form or shortcut_form or profiles_form;
            if (simple_form and !card_form) {
                try Paint.drawSettingsCard(self, Input.settingsListCard(self));
                try Paint.drawSettingsListHeading(self);
            }
            if (e.search) try self.drawField(Input.settingsField(self), &e.query_edit, e.query[0..e.query_len], "Search settings", true);
            if (startup_form) {
                try Paint.drawStartupForm(self);
                return;
            }
            var all: [settings.row_limit]settings.Row = undefined;
            var indices: [settings.row_limit]u16 = undefined;
            const count = try settings.rows(self.settingsConfiguration(), &all);
            var current_section = e.*;
            if (page) |section| {
                current_section.page = section;
                current_section.search = false;
            }
            const visible = current_section.indices(all[0..count], &indices);
            if (simple_form) e.list.selected = @min(e.list.selected, visible -| 1);
            if (profiles_form and e.page == .defaults) e.form_row = @min(e.form_row, visible -| 1);
            const start = if (card_form) @as(usize, 0) else Input.settingsStart(self, visible);
            const rows = Input.settingsRows(self);
            const form: AppearanceForm = if (appearance_form) Input.appearanceForm(self) else undefined;
            const colors_form: ColorForm = if (color_form) Input.colorForm(self) else undefined;
            const shortcuts_form: ShortcutForm = if (shortcut_form) Input.shortcutForm(self) else undefined;
            const profiles: ProfilesForm = if (profiles_form) Input.profilesForm(self) else undefined;
            var clipped_rows = false;
            defer if (clipped_rows) clearClip(self.renderer);
            if (card_form) {
                try setClip(self.renderer, body);
                clipped_rows = true;
                if (appearance_form) {
                    try Paint.drawAppearanceCards(self, form);
                } else if (color_form) {
                    try Paint.drawColorCards(self, colors_form);
                } else if (shortcut_form) {
                    try Paint.drawShortcutCards(self, shortcuts_form);
                } else {
                    try Paint.drawProfilesCards(self, profiles);
                    try Paint.drawProfilesToolbar(self);
                }
            } else if (simple_form) {
                try setClip(self.renderer, rows.rect);
                clipped_rows = true;
            }
            const paint_start = if (card_form) @as(usize, 0) else start;
            const paint_end = if (card_form) visible else @min(visible, start + Input.settingsVisible(self));
            for (indices[paint_start..paint_end], paint_start..) |index, number| {
                const row = all[index];
                const rect = if (appearance_form) form.row(number) else if (color_form) colors_form.row(number) else if (shortcut_form) shortcuts_form.row(number) else if (profiles_form) profiles.row(number) else rows.row(number - start);
                if (card_form and (rect.y >= body.y + body.height or rect.y + rect.height <= body.y)) continue;
                if (profiles_form) {
                    try Paint.drawSettingsCardRow(self, rect, e.page == .defaults and number == e.form_row, self.isHovered(rect), e.content_focus and e.page == .defaults);
                } else if (simple_form and !card_form) {
                    try Paint.drawSettingsCardRow(self, rect, number == e.list.selected, e.list.hovered == number, e.content_focus);
                } else if (!card_form) {
                    try self.drawListRow(rect, number == e.list.selected, e.list.hovered == number, e.content_focus);
                    try outline(self.renderer, rect, colors.border);
                }
                const editing_row = e.editing != null and (if (card_form) e.page == page.? and number == e.form_row else number == e.list.selected);
                var label: [512]u8 = undefined;
                const name = if (row.scope.len == 0 or (page != null and page.? != .colors)) row.label else try std.fmt.bufPrint(&label, "{s} / {s}", .{ row.scope, row.label });
                var value: [4096]u8 = undefined;
                const raw_contents = if (editing_row) (if (e.recording) "Press a shortcut — Esc cancels" else e.buffer[0..e.len]) else try row.text(self.settingsConfiguration(), &value);
                const contents = if (raw_contents.len != 0 or editing_row) raw_contents else switch (row.target) {
                    .binding => "Unbound",
                    .app_color, .terminal_color => "Preset",
                    .font => "Inherited",
                    .profile => |field| switch (field.field) {
                        .command => "Interactive shell",
                        .shell, .cwd, .font_pixels => "Inherited",
                        .arguments => "Shell mode",
                        .name => "",
                    },
                    else => "",
                };
                const left: layout.Rect = .{ .x = rect.x + 6, .y = rect.y, .width = @max(1, rect.width * 0.46 - 12), .height = rect.height };
                const right: layout.Rect = .{ .x = rect.x + rect.width * 0.46, .y = rect.y, .width = @max(1, rect.width * 0.54 - (if (row.editable()) @as(f32, 42) else 6)), .height = rect.height };
                if (editing_row and !e.recording) {
                    try self.clippedText(name, left, left.x);
                    if (row.choice()) {
                        const display = (try settings.choiceAt(row.target, self.settingsConfiguration(), e.choice_list.selected)).label;
                        const select_rect = Input.settingsField(self);
                        if (simple_form) try Paint.drawSettingsSelect(self, select_rect, display, true, true) else {
                            try fill(self.renderer, select_rect, colors.panel);
                            try outline(self.renderer, select_rect, colors.accent);
                            try self.clippedText(display, .{ .x = select_rect.x + 7, .y = select_rect.y, .width = @max(1, select_rect.width - 32), .height = select_rect.height }, select_rect.x + 7);
                            try icons.draw(self.renderer, .chevron_up, .{ .x = select_rect.x + select_rect.width - 23, .y = select_rect.y, .width = 20, .height = select_rect.height }, colors.text);
                        }
                    } else try self.drawFieldStyled(Input.settingsField(self), &e.edit, contents, if (e.edit.kind == .color) "#RRGGBB; blank = preset" else "", e.button == null, simple_form);
                } else if (row.target == .set_default and !e.search) {
                    try self.clippedText(row.label, .{ .x = rect.x + 8, .y = rect.y, .width = @max(1, rect.width - 94), .height = rect.height }, rect.x + 8);
                    const button = Input.savedEditButton(rect);
                    try Paint.drawSettingsControl(self, button, self.isHovered(button));
                    try self.clippedText(if (e.details_open and e.profile == row.target.set_default) "Close" else "Edit", button, button.x + 17);
                } else if (row.target == .scanned and !e.search) {
                    const entry = self.settingsConfiguration().value.scanned_profiles[row.target.scanned];
                    const name_rect: layout.Rect = .{ .x = rect.x + 8, .y = rect.y, .width = @max(1, rect.width - 180), .height = rect.height };
                    try self.clippedText(entry.recipe.name, name_rect, name_rect.x);
                    const status_rect: layout.Rect = .{ .x = rect.x + rect.width - 175, .y = rect.y, .width = 76, .height = rect.height };
                    try self.clippedTextColor(if (entry.stale) "Missing" else if (entry.enabled) "Scanned" else "Disabled", status_rect, status_rect.x, colors.muted);
                    const button = Input.scannedEnableButton(rect);
                    try Paint.drawSettingsControl(self, button, self.isHovered(button));
                    try self.clippedText(if (entry.enabled) "Disable" else "Enable", button, button.x + 12);
                } else if ((row.target == .discover_shells or row.target == .discover_ssh_hosts) and !e.search and e.page == .defaults) {
                    try self.clippedText(row.label, .{ .x = rect.x + 8, .y = rect.y, .width = @max(1, rect.width - 106), .height = rect.height }, rect.x + 8);
                    const toggle = Input.scanSourceSwitch(rect);
                    const enabled = if (row.target == .discover_shells) self.settingsConfiguration().value.discover_shells else self.settingsConfiguration().value.discover_ssh_hosts;
                    try self.clippedTextColor(if (enabled) "On" else "Off", .{ .x = toggle.x - 39, .y = rect.y, .width = 34, .height = rect.height }, toggle.x - 39, colors.muted);
                    try Paint.drawStartupSwitch(self, toggle, enabled, self.isHovered(toggle));
                } else {
                    try self.clippedText(name, left, left.x);
                    if (profiles_form and (row.target == .add_environment or row.target == .delete_environment)) {
                        const action = Input.settingsRowField(rect);
                        try Paint.drawSettingsControl(self, action, self.isHovered(action));
                        try self.clippedText(if (row.target == .add_environment) "Add" else "Remove", action, action.x + 8);
                    } else if (color_form and (row.target == .reset_app_colors or row.target == .reset_terminal_colors)) {
                        const reset_button = Input.settingsResetButton(rect);
                        try Paint.drawSettingsControl(self, reset_button, self.isHovered(reset_button));
                        try self.clippedText("Reset", reset_button, reset_button.x + 8);
                    } else if (simple_form and row.choice()) {
                        try Paint.drawSettingsSelect(self, Input.settingsRowField(rect), contents, if (card_form) self.isHovered(Input.settingsRowField(rect)) else number == e.list.selected and e.content_focus, false);
                    } else {
                        const rgb = try settings.resolvedColor(self.settingsConfiguration(), row.target);
                        var value_rect = right;
                        if (row.target == .font_family and !e.search) {
                            if (simple_form) {
                                try Paint.drawSettingsControl(self, right, if (card_form) self.isHovered(right) else number == e.list.selected and e.content_focus);
                            } else {
                                try fill(self.renderer, right, if (self.isHovered(right)) appearance.hover(colors.idle) else colors.idle);
                                try outline(self.renderer, right, colors.border);
                            }
                            value_rect.x += 8;
                            value_rect.width = @max(1, value_rect.width - (if (simple_form) @as(f32, 30) else 8));
                            if (simple_form) try icons.draw(self.renderer, .chevron_right, .{ .x = right.x + right.width - 23, .y = right.y + 8, .width = 18, .height = @max(1, right.height - 16) }, colors.text);
                        }
                        if (row.target == .font and row.target.font < 4 and !e.search) {
                            const action = widgets.InlineAction.init(right, 76);
                            value_rect = action.value;
                            if (simple_form) {
                                try Paint.drawSettingsControl(self, action.button, if (card_form) self.isHovered(action.button) else number == e.list.selected and e.content_focus);
                            } else {
                                try fill(self.renderer, action.button, if (self.isHovered(action.button)) appearance.hover(colors.idle) else colors.idle);
                                try outline(self.renderer, action.button, colors.border);
                            }
                            try self.clippedText("Browse", action.button, action.button.x + 6);
                        }
                        if (rgb) |swatch_color| {
                            const swatch: layout.Rect = .{ .x = right.x + right.width - 23, .y = rect.y + 12, .width = 16, .height = @min(20, rect.height - 16) };
                            value_rect.width = @max(1, swatch.x - value_rect.x - 6);
                            try drawing.fillRounded(self.renderer, swatch, colors.border, 4);
                            try drawing.fillRounded(self.renderer, .{ .x = swatch.x + 1, .y = swatch.y + 1, .width = @max(1, swatch.width - 2), .height = @max(1, swatch.height - 2) }, .{ .r = swatch_color.r, .g = swatch_color.g, .b = swatch_color.b, .a = 255 }, 3);
                        }
                        try self.clippedTextColor(contents, value_rect, value_rect.x, if (row.target == .information) colors.muted else colors.text);
                    }
                }
                if (row.editable() and !(!e.search and e.page == .defaults and (row.target == .discover_shells or row.target == .discover_ssh_hosts))) {
                    const edit_button = Input.settingsEditButton(rect);
                    const active = editing_row;
                    if (simple_form or active or self.isHovered(edit_button)) try Paint.drawSettingsControl(self, edit_button, active);
                    try icons.draw(self.renderer, .pencil, .{ .x = edit_button.x + 5, .y = edit_button.y + 5, .width = edit_button.width - 10, .height = edit_button.height - 10 }, if (active or self.isHovered(edit_button)) colors.text else colors.muted);
                }
            }
            if (color_form and e.page == .colors and e.editing != null and e.edit.kind == .color) try Paint.drawColorEditor(self);
            if (clipped_rows) {
                clearClip(self.renderer);
                clipped_rows = false;
            }
            if (simple_form) try self.drawListScroll(rows, start, visible);
        }
    };
}
