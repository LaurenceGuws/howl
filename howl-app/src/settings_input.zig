//! Settings interaction and host-bound geometry; stage mutations through App policy.
const std = @import("std");
const c = @import("desktop");
const vt = @import("howl_vt");
const chrome = @import("chrome.zig");
const color_config = @import("colors.zig");
const config = @import("config.zig");
const settings = @import("settings.zig");
const widgets = @import("widgets.zig");
const layout = @import("layout.zig");
const discovery = @import("discovery.zig");
const keybindings = @import("keybindings.zig");
const input = @import("input.zig");
const pages = @import("settings_pages.zig");
const allocator = std.heap.smp_allocator;
const SettingsHeaderAction = pages.SettingsHeaderAction;
const StartupForm = pages.StartupForm;
const AppearanceForm = pages.AppearanceForm;
const ColorForm = pages.ColorForm;
const ShortcutForm = pages.ShortcutForm;
const ProfilesForm = pages.ProfilesForm;
const SettingsDocument = pages.SettingsDocument;
const settings_header_height = pages.settings_header_height;
const settings_nav_top = pages.settings_nav_top;
const settings_card_gutter = pages.settings_card_gutter;
const settings_card_padding = pages.settings_card_padding;

/// Bind Settings pointer and keyboard behavior to its concrete SDL host type.
pub fn ForHost(comptime Host: type) type {
    return struct {
        const Input = @This();
        /// Rectangle of the right-side Settings shell after window sizing.
        pub fn settingsRect(self: *const Host) layout.Rect {
            const width = @min(860, @max(1, self.width - 16));
            const top = self.headerHeight() + 8;
            return .{ .x = self.width - width - 8, .y = top, .width = width, .height = @max(1, self.height - top - 8) };
        }
        /// Sidebar navigation hit and paint area for one section.
        pub fn settingsNavRow(self: *const Host, number: usize) layout.Rect {
            const box = Input.settingsRect(self);
            const sidebar = @min(160, box.width / 3);
            return .{
                .x = box.x + 8,
                .y = box.y + settings_nav_top + @as(f32, @floatFromInt(number)) * 34,
                .width = @max(1, sidebar - 12),
                .height = 32,
            };
        }
        /// Fixed header action target independent of page scrolling.
        pub fn settingsHeaderButton(self: *const Host, action: SettingsHeaderAction) layout.Rect {
            const box = Input.settingsRect(self);
            const width: f32 = switch (action) {
                .save, .cancel => 66,
                else => chrome.Geometry.chip_height,
            };
            const right: f32 = switch (action) {
                .save => 222,
                .cancel => 150,
                .search => 74,
                .close => 40,
            };
            return .{ .x = box.x + box.width - right, .y = box.y + chrome.Geometry.top, .width = width, .height = chrome.Geometry.chip_height };
        }
        /// Enter or exit global search and reset its transient selection.
        pub fn settingsSetSearch(self: *Host, enabled: bool) void {
            const e = &self.settings_editor.?;
            self.cancelComposition();
            if (e.editing != null) e.cancel();
            if (enabled and !e.search) e.search_origin_offset = self.settings_scroll_offset;
            e.search = enabled;
            e.content_focus = !enabled;
            e.query_len = 0;
            e.query_edit = .{};
            e.list = .{};
            e.delete_pending = null;
            self.settings_scroll_offset = if (enabled) 0 else e.search_origin_offset;
            self.settings_scroll_grab = null;
        }
        /// Page viewport bounds with one uniform bottom inset.
        pub fn settingsBody(self: *const Host) layout.Rect {
            const box = Input.settingsRect(self);
            const e = self.settings_editor.?;
            const sidebar = @min(160, box.width / 3);
            const top: f32 = settings_header_height + (if (e.search) @as(f32, 42) else 0);
            return .{ .x = box.x + sidebar + 12, .y = box.y + top, .width = @max(1, box.width - sidebar - 24), .height = @max(1, box.height - top - 12) };
        }
        /// Whether the Discovery source controls stack vertically.
        pub fn settingsScanCompact(self: *const Host) bool {
            return Input.profilesForm(self).compact;
        }
        /// Discovery card placed in the Profiles page viewport.
        pub fn settingsScanCard(self: *const Host) layout.Rect {
            return Input.profilesForm(self).card(0);
        }
        /// One source-switch row derived from the scrolled Discovery card.
        pub fn settingsScanSourceRow(self: *const Host, number: usize) layout.Rect {
            return Input.profilesForm(self).scanSourceRow(number);
        }
        /// The single Settings scroll owner and its five indexed sections.
        pub fn settingsDocument(self: *const Host) SettingsDocument {
            const e = self.settings_editor.?;
            const current = self.settingsConfiguration();
            const selected = @min(e.profile, current.profileCount() - 1);
            const details: usize = if (selected == 0) 5 else 7 + 3 * current.value.profiles[@as(usize, selected) - 1].environment.len;
            const color_editor: ?usize = if (!e.search and e.page == .colors and e.editing != null and e.edit.kind == .color) e.form_row else null;
            const expanded: ?usize = if (!e.search and e.details_open) selected else null;
            return SettingsDocument.init(Input.settingsBody(self), self.settings_scroll_offset, color_editor, current.profileCount(), current.value.scanned_profiles.len, expanded, details);
        }
        /// Startup controls borrow their position from the document scroll.
        pub fn startupForm(self: *const Host) StartupForm {
            return StartupForm.init(Input.settingsDocument(self).formBounds(0), 0);
        }
        /// Appearance cards borrow their position from the document scroll.
        pub fn appearanceForm(self: *const Host) AppearanceForm {
            return AppearanceForm.init(Input.settingsDocument(self).formBounds(1), 0);
        }
        /// Color cards borrow their position from the document scroll.
        pub fn colorForm(self: *const Host) ColorForm {
            const editor = self.settings_editor.?;
            const expanded = if (!editor.search and editor.page == .colors and editor.editing != null and editor.edit.kind == .color) editor.form_row else null;
            return ColorForm.init(Input.settingsDocument(self).formBounds(2), 0, expanded);
        }
        /// Shortcut category cards borrow their position from the document scroll.
        pub fn shortcutForm(self: *const Host) ShortcutForm {
            return ShortcutForm.init(Input.settingsDocument(self).formBounds(3), 0);
        }
        /// Profiles catalogue and inline details borrow one document position.
        pub fn profilesForm(self: *const Host) ProfilesForm {
            const e = self.settings_editor.?;
            const current = self.settingsConfiguration();
            const selected = @min(e.profile, current.profileCount() - 1);
            const detail_count: usize = if (selected == 0) 5 else 7 + 3 * current.value.profiles[@as(usize, selected) - 1].environment.len;
            const expanded: ?usize = if (!e.search and e.details_open) selected else null;
            return ProfilesForm.init(Input.settingsDocument(self).formBounds(4), 0, current.profileCount(), current.value.scanned_profiles.len, expanded, detail_count);
        }
        /// Whether Appearance owns the active non-search Settings page.
        pub fn appearanceSettings(self: *const Host) bool {
            const editor = self.settings_editor.?;
            return !editor.search and editor.page == .appearance;
        }
        /// Whether Colors owns the active non-search Settings page.
        pub fn colorSettings(self: *const Host) bool {
            const editor = self.settings_editor.?;
            return !editor.search and editor.page == .colors;
        }
        /// Whether Shortcuts owns the active non-search Settings page.
        pub fn shortcutSettings(self: *const Host) bool {
            const editor = self.settings_editor.?;
            return !editor.search and editor.page == .mappings;
        }
        /// Whether Profiles owns the active catalogue and inline details.
        pub fn profilesSettings(self: *const Host) bool {
            const editor = self.settings_editor.?;
            return !editor.search and editor.page == .defaults;
        }
        /// One document viewport; global search retains its distinct list.
        pub fn settingsFormView(self: *const Host) ?widgets.FormViewport {
            const editor = self.settings_editor orelse return null;
            if (editor.search) return null;
            return Input.settingsDocument(self).view;
        }
        /// Reconcile the active sidebar label after manual document scrolling.
        pub fn settingsTrackSection(self: *Host) void {
            const e = &self.settings_editor.?;
            if (e.search or e.editing != null) return;
            const section: settings.Page = @fromBackingInt(@intCast(Input.settingsDocument(self).active()));
            if (section != e.page) {
                e.page = section;
                e.form_row = 0;
                e.content_focus = false;
            }
        }
        /// Clamp mouse-wheel movement in the single document-owned viewport.
        pub fn settingsScrollBy(self: *Host, delta: f32) void {
            const view = Input.settingsFormView(self) orelse return;
            self.settings_scroll_offset = std.math.clamp(view.offset + delta, 0, @max(0, view.content_height - view.bounds.height));
            Input.settingsTrackSection(self);
        }
        /// Begin or reposition the page scrollbar thumb drag.
        pub fn settingsScrollbarPress(self: *Host, x: f32, y: f32) bool {
            const view = Input.settingsFormView(self) orelse return false;
            const bar = view.scrollbar() orelse return false;
            if (x < bar.track.x - 11 or x >= bar.track.x + bar.track.width + 1 or y < bar.track.y or y >= bar.track.y + bar.track.height) return false;
            self.settings_scroll_grab = if (y >= bar.thumb.y and y < bar.thumb.y + bar.thumb.height) y - bar.thumb.y else bar.thumb.height / 2;
            Input.settingsScrollbarMove(self, y);
            return true;
        }
        /// Update the page offset from a captured scrollbar thumb.
        pub fn settingsScrollbarMove(self: *Host, y: f32) void {
            const grab = self.settings_scroll_grab orelse return;
            const view = Input.settingsFormView(self) orelse return;
            const bar = view.scrollbar() orelse return;
            const travel = bar.track.height - bar.thumb.height;
            if (travel <= 0) return;
            const thumb_y = std.math.clamp(y - grab - bar.track.y, 0, travel);
            self.settings_scroll_offset = thumb_y / travel * (view.content_height - view.bounds.height);
            Input.settingsTrackSection(self);
        }
        /// Card rectangle for the global search-results list.
        pub fn settingsListCard(self: *const Host) layout.Rect {
            const body = Input.settingsBody(self);
            const horizontal = @min(settings_card_gutter, @max(0, (body.width - 1) / 2));
            const vertical = @min(settings_card_gutter, @max(0, (body.height - 1) / 2));
            return .{ .x = body.x + horizontal, .y = body.y + vertical, .width = @max(1, body.width - 2 * horizontal), .height = @max(1, body.height - 2 * vertical) };
        }
        /// Search-result row geometry, separate from the document scrollbar.
        pub fn settingsRows(self: *const Host) widgets.Rows {
            const card = Input.settingsListCard(self);
            const horizontal = @min(settings_card_padding, @max(0, (card.width - 1) / 2));
            const heading = @min(64, @max(0, card.height - 1));
            const bottom = @min(settings_card_gutter, @max(0, card.height - heading - 1));
            return .{ .rect = .{ .x = card.x + horizontal, .y = card.y + heading, .width = @max(1, card.width - 2 * horizontal), .height = @max(1, card.height - heading - bottom) }, .stride = 48, .gap = 4 };
        }
        /// Value field rectangle inside an interactive Settings row.
        pub fn settingsRowField(rect: layout.Rect) layout.Rect {
            return .{ .x = rect.x + rect.width * 0.46, .y = rect.y + 5, .width = @max(1, rect.width * 0.54 - 42), .height = rect.height - 10 };
        }
        /// Explicit edit-button rectangle at the end of a row.
        pub fn settingsEditButton(rect: layout.Rect) layout.Rect {
            return .{ .x = rect.x + rect.width - 33, .y = rect.y + 6, .width = 29, .height = @max(1, rect.height - 12) };
        }
        /// Reset action area within a color Settings row.
        pub fn settingsResetButton(rect: layout.Rect) layout.Rect {
            return settingsRowField(rect);
        }
        /// Active text or choice field, including its page-scrolled row.
        pub fn settingsField(self: *const Host) layout.Rect {
            const box = Input.settingsRect(self);
            const body = Input.settingsBody(self);
            if (self.settings_editor.?.editing != null) {
                const e = self.settings_editor.?;
                if (!e.search and e.page == .startup and e.editing.? == .default_profile) return Input.startupForm(self).select();
                if (Input.appearanceSettings(self)) return settingsRowField(Input.appearanceForm(self).row(e.form_row));
                if (Input.colorSettings(self)) return settingsRowField(Input.colorForm(self).row(e.form_row));
                if (Input.shortcutSettings(self)) return settingsRowField(Input.shortcutForm(self).row(e.form_row));
                if (Input.profilesSettings(self)) return settingsRowField(Input.profilesForm(self).row(e.form_row));
                const rect = Input.settingsRows(self).row(e.list.selected -| e.list.first);
                return settingsRowField(rect);
            }
            return .{ .x = body.x, .y = box.y + settings_header_height, .width = body.width, .height = 32 };
        }
        /// Choice menu anchored to the active Settings field.
        pub fn settingsDropdown(self: *const Host) widgets.Dropdown {
            return widgets.Dropdown.init(Input.settingsField(self), Input.settingsBody(self), settings.choiceCount(self.settings_editor.?.editing.?, self.settingsConfiguration()));
        }
        /// Number of whole rows visible in the search-results list.
        pub fn settingsVisible(self: *const Host) usize {
            return Input.settingsRows(self).visible();
        }
        /// Reveal the selected search result in its list viewport.
        pub fn settingsStart(self: *Host, count: usize) usize {
            self.settings_editor.?.list.reveal(count, Input.settingsVisible(self));
            return self.settings_editor.?.list.first;
        }
        /// Number of contextual profile toolbar actions.
        pub fn settingsToolbarCount(_: *const Host) usize {
            return 3;
        }
        /// Contextual New, Duplicate and Scan controls in the catalogue.
        pub fn settingsToolbarButton(self: *const Host, number: usize) layout.Rect {
            std.debug.assert(number < 3);
            if (number == 2) {
                const card = Input.settingsScanCard(self);
                const width = @min(96, @max(1, card.width - 20));
                return .{ .x = card.x + card.width - width - 12, .y = card.y + 10, .width = width, .height = 32 };
            }
            const card = Input.profilesForm(self).card(1);
            const width = if (card.width < 500) @min(78, @max(42, (card.width - 170) / 2)) else @as(f32, 102);
            const start = card.x + card.width - 14 - 2 * width - 6;
            return .{ .x = start + @as(f32, @floatFromInt(number)) * (width + 6), .y = card.y + 14, .width = width, .height = 32 };
        }
        /// Close, Duplicate and Delete controls inside the expanded recipe.
        pub fn settingsDetailButton(self: *const Host, number: usize) layout.Rect {
            std.debug.assert(number < 3);
            const card = Input.profilesForm(self).detailCard();
            const width = @max(1, (card.width - 32 - 12) / 3);
            return .{ .x = card.x + 16 + @as(f32, @floatFromInt(number)) * (width + 6), .y = card.y + 66, .width = width, .height = 32 };
        }
        /// Reveal the expanded row and its first details without a nested scroll.
        pub fn settingsRevealProfile(self: *Host) void {
            const form = Input.profilesForm(self);
            const document = Input.settingsDocument(self).view;
            self.settings_scroll_offset = std.math.clamp(
                document.offset + form.row(self.settings_editor.?.profile).y - document.bounds.y - 40,
                0,
                @max(0, document.content_height - document.bounds.height),
            );
        }
        /// Bring a search result into the document without opening a second page.
        pub fn settingsRevealRow(self: *Host, section: settings.Page, number: usize) void {
            const bounds = Input.settingsBody(self);
            const rect = switch (section) {
                .startup => Input.startupForm(self).row(0),
                .appearance => Input.appearanceForm(self).row(number),
                .colors => Input.colorForm(self).row(number),
                .mappings => Input.shortcutForm(self).row(number),
                .defaults => Input.profilesForm(self).row(number),
                .profiles => Input.profilesForm(self).row(number),
            };
            const document = Input.settingsDocument(self).view;
            self.settings_scroll_offset = std.math.clamp(document.offset + rect.y - bounds.y - 36, 0, @max(0, document.content_height - document.bounds.height));
        }
        /// Reveal a searched field or begin its validated draft mutation.
        pub fn activateSetting(self: *Host, row: settings.Row) !void {
            const e = &self.settings_editor.?;
            if (e.search) {
                e.search = false;
                e.query_len = 0;
                e.page = if (row.page == .profiles) .defaults else row.page;
                e.profile = switch (row.target) {
                    .profile => |field| field.index,
                    .environment => |field| field.profile,
                    .clone_profile, .set_default, .delete_profile, .add_environment => |index| index,
                    .delete_environment => |field| field.profile,
                    .information => if (row.page == .profiles) 0 else e.profile,
                    else => e.profile,
                };
                e.details_open = row.page == .profiles;
                e.list = .{};
                e.form_row = 0;
                e.content_focus = true;
                self.settings_scroll_offset = Input.settingsDocument(self).anchor(@backingInt(e.page));
                self.settings_scroll_grab = null;
                var all: [settings.row_limit]settings.Row = undefined;
                var shown: [settings.row_limit]u16 = undefined;
                const count = try settings.rows(self.settingsConfiguration(), &all);
                const visible = e.indices(all[0..count], &shown);
                var found = false;
                for (shown[0..visible], 0..) |index, number| {
                    if (!std.meta.eql(all[index].target, row.target)) continue;
                    e.form_row = number;
                    e.list.selected = number;
                    found = true;
                    break;
                }
                // Duplicate/Delete search results resolve to inline actions,
                // not field rows; reveal their owning saved profile.
                if (!found and e.page == .defaults and e.details_open) e.form_row = e.profile;
                Input.settingsRevealRow(self, e.page, e.form_row);
                self.cancelComposition();
                return;
            }
            if (row.target == .information or row.target == .scanned) return;
            if (row.target == .set_default) {
                e.profile = row.target.set_default;
                e.page = .defaults;
                e.details_open = true;
                e.form_row = e.profile;
                Input.settingsRevealProfile(self);
                e.content_focus = true;
                return;
            }
            if (row.target == .font_family) return self.openFontChooser(.family, self.settingsConfiguration().value.font.paths()[0]);
            if (row.target == .delete_profile) {
                if (try self.profileInUse(row.target.delete_profile)) return error.ProfileInUse;
                if (e.delete_pending != row.target.delete_profile) {
                    e.delete_pending = row.target.delete_profile;
                    self.setNotice("Confirm Delete to remove this profile");
                    return;
                }
            }
            self.cancelComposition();
            if (row.editable()) {
                try e.begin(row, self.settingsConfiguration());
                if (row.target == .binding) {
                    e.recording = true;
                    self.setNotice("Press a shortcut — Esc cancels");
                }
            } else try self.changeSetting(row.target, "");
        }
        /// Execute one contextual profile action against the staged draft.
        pub fn settingsToolbarAction(self: *Host, number: usize) !void {
            const e = &self.settings_editor.?;
            switch (number) {
                0 => {
                    try self.changeSetting(.add_profile, "");
                    e.profile = self.settingsConfiguration().profileCount() - 1;
                    e.details_open = true;
                    e.form_row = @as(usize, e.profile) + 1;
                    Input.settingsRevealProfile(self);
                    try e.begin(.{ .page = .profiles, .label = "Name", .target = .{ .profile = .{ .index = e.profile, .field = .name } } }, self.settingsConfiguration());
                },
                1 => {
                    const target = (try Input.overviewCloneTarget(self)) orelse return error.SelectProfileToDuplicate;
                    try self.changeSetting(target, "");
                    e.profile = self.settingsConfiguration().profileCount() - 1;
                    e.details_open = true;
                    e.form_row = e.profile;
                    Input.settingsRevealProfile(self);
                },
                2 => try Input.scanSettingsProfiles(self),
                else => {},
            }
            e.content_focus = true;
        }
        /// Inline profile actions do not leave the Profiles section.
        pub fn settingsDetailAction(self: *Host, number: usize) !void {
            const e = &self.settings_editor.?;
            switch (number) {
                0 => {
                    e.details_open = false;
                    e.form_row = e.profile;
                    self.settings_scroll_offset = Input.settingsDocument(self).view.offset;
                },
                1 => {
                    try self.changeSetting(.{ .clone_profile = e.profile }, "");
                    e.profile = self.settingsConfiguration().profileCount() - 1;
                    e.details_open = true;
                    e.form_row = e.profile;
                    Input.settingsRevealProfile(self);
                },
                2 => {
                    if (e.profile == 0) return;
                    const before = self.settingsConfiguration().profileCount();
                    try Input.activateSetting(self, .{ .page = .profiles, .label = "Delete profile", .target = .{ .delete_profile = e.profile } });
                    if (self.settingsConfiguration().profileCount() < before) {
                        e.details_open = false;
                        e.profile = @min(e.profile, self.settingsConfiguration().profileCount() - 1);
                        e.form_row = e.profile;
                        self.settings_scroll_offset = Input.settingsDocument(self).view.offset;
                    }
                },
                else => {},
            }
            e.content_focus = true;
        }
        /// Stage explicit discovery results under global Save/Cancel.
        pub fn scanSettingsProfiles(self: *Host) !void {
            const current = self.settingsConfiguration();
            if (!current.value.discover_shells and !current.value.discover_ssh_hosts) return error.NoScanSources;
            const found = try discovery.Catalogue.create(allocator, self.init.io, self.init.environ_map, current.value);
            defer found.destroy(allocator);
            const candidate = try discovery.reconcile(current, self.init.io, found);
            const default_reset = !std.mem.eql(u8, (try current.defaultProfile()).id, (try candidate.defaultProfile()).id);
            if (self.settings_draft) |*draft| draft.deinit();
            self.settings_draft = candidate;
            self.setNotice(if (default_reset) "Missing default reset to Local — Save or Cancel" else "Scan cached — Save to keep, Cancel to discard");
        }
        /// Map selected catalogue row to a saved or scanned clone target.
        pub fn overviewCloneTarget(self: *Host) !?settings.Target {
            const e = &self.settings_editor.?;
            if (Input.profilesForm(self).detailIndex(e.form_row) != null) return .{ .clone_profile = e.profile };
            var all: [settings.row_limit]settings.Row = undefined;
            var shown: [settings.row_limit]u16 = undefined;
            const count = try settings.rows(self.settingsConfiguration(), &all);
            const visible = e.indices(all[0..count], &shown);
            if (e.form_row >= visible) return null;
            return switch (all[shown[e.form_row]].target) {
                .set_default => |index| .{ .clone_profile = index },
                .scanned => |index| .{ .clone_scanned = index },
                else => null,
            };
        }
        /// Bounds of one inline RGB channel slider.
        pub fn colorBar(self: *const Host, channel: usize) layout.Rect {
            return Input.colorForm(self).editorBar(channel);
        }
        /// Edit action aligned with a saved profile row.
        pub fn savedEditButton(row: layout.Rect) layout.Rect {
            return .{ .x = row.x + row.width - 80, .y = row.y + 5, .width = 76, .height = row.height - 10 };
        }
        /// Independent enable/disable action for a cached scan row.
        pub fn scannedEnableButton(row: layout.Rect) layout.Rect {
            return .{ .x = row.x + row.width - 92, .y = row.y + 5, .width = 88, .height = row.height - 10 };
        }
        /// Discovery source switch aligned inside its own source row.
        pub fn scanSourceSwitch(row: layout.Rect) layout.Rect {
            return .{ .x = row.x + row.width - 50, .y = row.y + @max(0, (row.height - 26) / 2), .width = 46, .height = 26 };
        }
        /// Preset reset action beside the inline color sliders.
        pub fn colorReset(self: *const Host) layout.Rect {
            return Input.colorForm(self).editorReset();
        }
        /// Resolve the in-progress color edit against its current value.
        pub fn editedColor(self: *Host) !vt.Terminal.Rgb {
            const e = self.settings_editor.?;
            return color_config.parse(e.buffer[0..e.len]) catch (try settings.resolvedColor(self.settingsConfiguration(), e.editing.?)).?;
        }
        /// Update the edited RGB hex buffer from a slider position.
        pub fn colorPoint(self: *Host, channel: u8, x: f32) !void {
            const e = &self.settings_editor.?;
            const bar = Input.colorBar(self, channel);
            var rgb = try Input.editedColor(self);
            const value: u8 = @intFromFloat(@round(std.math.clamp((x - bar.x) / bar.width, 0, 1) * 255));
            switch (channel) {
                0 => rgb.r = value,
                1 => rgb.g = value,
                2 => rgb.b = value,
                else => return error.InvalidColorRole,
            }
            const text = try std.fmt.bufPrint(&e.buffer, "#{x:0>2}{x:0>2}{x:0>2}", .{ rgb.r, rgb.g, rgb.b });
            e.len = text.len;
            e.edit = .{ .kind = .color, .cursor = text.len };
            e.button = null;
        }

        /// Route Settings pointer input through the owning page geometry.
        pub fn settingsClick(self: *Host, x: f32, y: f32, clicks: u8) !void {
            const e = &self.settings_editor.?;
            const box = Input.settingsRect(self);
            if (Input.settingsHeaderButton(self, .close).contains(x, y)) return self.toggleSettings();
            if (Input.settingsHeaderButton(self, .save).contains(x, y)) return self.settingsSave();
            if (Input.settingsHeaderButton(self, .cancel).contains(x, y)) return self.settingsCancel();
            if (e.recording) e.cancel(); // A pointer leaves uncompleted capture unchanged.
            if (Input.settingsHeaderButton(self, .search).contains(x, y)) {
                if (e.editing) |target| try self.changeSetting(target, e.buffer[0..e.len]);
                Input.settingsSetSearch(self, !e.search);
                return;
            }
            if (e.editing) |target| {
                const choice = (settings.Row{ .page = e.page, .label = "", .target = target }).choice();
                if (choice) {
                    const menu = Input.settingsDropdown(self);
                    if (menu.rows.hit(x, y)) |number| {
                        e.choice_list.reveal(settings.choiceCount(target, self.settingsConfiguration()), menu.rows.visible());
                        const index = number + e.choice_list.first;
                        if (index < settings.choiceCount(target, self.settingsConfiguration())) {
                            try e.selectChoice(self.settingsConfiguration(), index);
                            return self.changeSetting(target, e.buffer[0..e.len]);
                        }
                        return;
                    }
                    if (Input.settingsField(self).contains(x, y)) {
                        e.cancel();
                        e.content_focus = false;
                        return;
                    }
                }
                if (Input.settingsField(self).contains(x, y)) {
                    if (choice) e.cancel() else e.button = null;
                    return;
                }
                if (e.edit.kind == .color) {
                    for (0..3) |channel| if (Input.colorBar(self, channel).contains(x, y)) {
                        self.color_drag = @intCast(channel);
                        return Input.colorPoint(self, @intCast(channel), x);
                    };
                    if (Input.colorReset(self).contains(x, y)) {
                        e.len = 0;
                        e.edit = .{ .kind = .color };
                        return;
                    }
                }
                // Leaving a field stages its validated value, even when navigating
                // to another page. Only the header Save writes the configuration.
                const collapsing_color_editor = e.edit.kind == .color;
                try self.changeSetting(target, e.buffer[0..e.len]);
                // Closing an inline editor shifts every following color row.
                // Never reinterpret this same pointer position after that shift.
                if (collapsing_color_editor) {
                    self.settings_scroll_offset = Input.settingsDocument(self).view.offset;
                    return;
                }
            }
            if (!box.contains(x, y)) return;
            const body = Input.settingsBody(self);
            if (Input.settingsScrollbarPress(self, x, y)) return;
            if (x < body.x - 12 and y >= box.y + settings_nav_top) {
                for (0..settings.titles.len) |page| {
                    if (!Input.settingsNavRow(self, page).contains(x, y)) continue;
                    self.cancelComposition();
                    e.page = @fromBackingInt(@intCast(page));
                    e.content_focus = false;
                    e.search = false;
                    e.query_len = 0;
                    e.list = .{};
                    e.delete_pending = null;
                    e.form_row = 0;
                    self.settings_scroll_offset = Input.settingsDocument(self).anchor(page);
                    self.settings_scroll_grab = null;
                    break;
                }
                return;
            }
            if (!e.search) {
                const section = Input.settingsDocument(self).sectionAt(y) orelse return;
                const next: settings.Page = @fromBackingInt(@intCast(section));
                if (e.page != next) {
                    e.page = next;
                    e.form_row = 0;
                    e.content_focus = false;
                    e.delete_pending = null;
                }
            }
            if (!e.search and e.page == .startup) {
                if (!body.contains(x, y)) return;
                const form = Input.startupForm(self);
                if (form.select().contains(x, y)) return Input.activateSetting(self, .{ .page = .startup, .label = "", .target = .default_profile });
                return;
            }
            if (Input.appearanceSettings(self)) {
                if (body.contains(x, y)) try Input.settingsAppearanceClick(self, x, y);
                return;
            }
            if (Input.colorSettings(self)) {
                if (body.contains(x, y)) try Input.settingsColorClick(self, x, y);
                return;
            }
            if (Input.shortcutSettings(self)) {
                if (body.contains(x, y)) try Input.settingsShortcutClick(self, x, y);
                return;
            }
            if (Input.profilesSettings(self)) {
                for ([_]settings.Target{ .discover_shells, .discover_ssh_hosts }, 0..) |target, number| {
                    const row = Input.settingsScanSourceRow(self, number);
                    if (!body.contains(x, y) or !row.contains(x, y)) continue;
                    if (scanSourceSwitch(row).contains(x, y)) try self.changeSetting(target, "");
                    return;
                }
            }
            if (Input.profilesSettings(self)) {
                for (0..Input.settingsToolbarCount(self)) |number| {
                    if (body.contains(x, y) and Input.settingsToolbarButton(self, number).contains(x, y)) return Input.settingsToolbarAction(self, number);
                }
                if (e.details_open) for (0..3) |number| {
                    if (body.contains(x, y) and Input.settingsDetailButton(self, number).contains(x, y)) return Input.settingsDetailAction(self, number);
                };
            }
            if (Input.profilesSettings(self)) {
                if (body.contains(x, y)) try Input.settingsProfilesClick(self, x, y, clicks);
                return;
            }
            const field = Input.settingsField(self);
            if (e.search and field.contains(x, y)) {
                e.query_edit = .{ .cursor = e.query_len };
                self.cancelComposition();
                return;
            }
            if (!body.contains(x, y)) return;
            var all: [settings.row_limit]settings.Row = undefined;
            var indices: [settings.row_limit]u16 = undefined;
            const count = try settings.rows(self.settingsConfiguration(), &all);
            const visible = e.indices(all[0..count], &indices);
            const start = Input.settingsStart(self, visible);
            const row = Input.settingsRows(self).hit(x, y) orelse return;
            const chosen = row + start;
            if (chosen >= visible) return;
            if (e.list.selected != chosen) e.delete_pending = null;
            e.list.selected = chosen;
            const selected_row = all[indices[chosen]];
            const row_rect = Input.settingsRows(self).row(row);
            if (selected_row.editable() and settingsEditButton(row_rect).contains(x, y)) {
                e.content_focus = true;
                if (e.search) try Input.activateSetting(self, selected_row);
                return Input.activateSetting(self, selected_row);
            }
            if (selected_row.target == .font_family and !e.search and x >= row_rect.x + row_rect.width * 0.46) {
                e.content_focus = true;
                return Input.activateSetting(self, selected_row);
            }
            if (selected_row.target == .font and !e.search and selected_row.target.font < 4) {
                const row_field = settingsRowField(row_rect);
                const right: layout.Rect = .{ .x = row_field.x, .y = row_rect.y, .width = row_field.width, .height = row_rect.height };
                if (widgets.InlineAction.init(right, 76).button.contains(x, y)) {
                    e.content_focus = true;
                    const face: u2 = @intCast(selected_row.target.font);
                    return self.openFontChooser(.{ .face = face }, self.settingsConfiguration().value.font.paths()[face]);
                }
            }
            e.content_focus = true;
            if (clicks >= 2 and selected_row.target == .set_default) try Input.activateSetting(self, selected_row);
        }
        /// Resolve Appearance row interactions from its page viewport.
        pub fn settingsAppearanceClick(self: *Host, x: f32, y: f32) !void {
            const form = Input.appearanceForm(self);
            const number = form.hit(x, y) orelse return;
            var all: [settings.row_limit]settings.Row = undefined;
            var indices: [settings.row_limit]u16 = undefined;
            const count = try settings.rows(self.settingsConfiguration(), &all);
            const visible = self.settings_editor.?.indices(all[0..count], &indices);
            if (number >= visible) return;
            const row = all[indices[number]];
            const rect = form.row(number);
            const field = settingsRowField(rect);
            const edit_button = settingsEditButton(rect);
            if (row.editable() and edit_button.contains(x, y)) {
                self.settings_editor.?.form_row = number;
                return Input.activateSetting(self, row);
            }
            if (row.target == .font_family and field.contains(x, y)) {
                self.settings_editor.?.form_row = number;
                return Input.activateSetting(self, row);
            }
            if (row.target == .font and row.target.font < 4) {
                const right: layout.Rect = .{ .x = field.x, .y = rect.y, .width = field.width, .height = rect.height };
                if (widgets.InlineAction.init(right, 76).button.contains(x, y)) {
                    const face: u2 = @intCast(row.target.font);
                    return self.openFontChooser(.{ .face = face }, self.settingsConfiguration().value.font.paths()[face]);
                }
            }
            if (row.editable() and row.choice() and field.contains(x, y)) {
                self.settings_editor.?.form_row = number;
                return Input.activateSetting(self, row);
            }
        }
        /// Resolve Color row edits and reset actions from its viewport.
        pub fn settingsColorClick(self: *Host, x: f32, y: f32) !void {
            const form = Input.colorForm(self);
            const number = form.hit(x, y) orelse return;
            var all: [settings.row_limit]settings.Row = undefined;
            var indices: [settings.row_limit]u16 = undefined;
            const count = try settings.rows(self.settingsConfiguration(), &all);
            const visible = self.settings_editor.?.indices(all[0..count], &indices);
            if (number >= visible) return;
            const row = all[indices[number]];
            const rect = form.row(number);
            const field = settingsRowField(rect);
            if (row.editable() and (settingsEditButton(rect).contains(x, y) or (row.choice() and field.contains(x, y)))) {
                self.settings_editor.?.form_row = number;
                try Input.activateSetting(self, row);
                if (self.settings_editor.?.editing != null and self.settings_editor.?.edit.kind == .color) {
                    const area = Input.colorForm(self).editor();
                    const body = Input.settingsBody(self);
                    if (area.y + area.height > body.y + body.height) Input.settingsScrollBy(self, area.y + area.height - body.y - body.height);
                }
                return;
            }
            if ((row.target == .reset_app_colors or row.target == .reset_terminal_colors) and settingsResetButton(rect).contains(x, y)) {
                return Input.activateSetting(self, row);
            }
        }
        /// Resolve a shortcut binding edit from its grouped card.
        pub fn settingsShortcutClick(self: *Host, x: f32, y: f32) !void {
            const form = Input.shortcutForm(self);
            const number = form.hit(x, y) orelse return;
            var all: [settings.row_limit]settings.Row = undefined;
            var indices: [settings.row_limit]u16 = undefined;
            const count = try settings.rows(self.settingsConfiguration(), &all);
            const visible = self.settings_editor.?.indices(all[0..count], &indices);
            if (number >= visible) return;
            const row = all[indices[number]];
            if (row.editable() and settingsEditButton(form.row(number)).contains(x, y)) {
                self.settings_editor.?.form_row = number;
                return Input.activateSetting(self, row);
            }
        }
        /// Resolve catalogue selection, toggles and detail edits.
        pub fn settingsProfilesClick(self: *Host, x: f32, y: f32, clicks: u8) !void {
            const form = Input.profilesForm(self);
            const number = form.hit(x, y) orelse return;
            var all: [settings.row_limit]settings.Row = undefined;
            var indices: [settings.row_limit]u16 = undefined;
            const count = try settings.rows(self.settingsConfiguration(), &all);
            const visible = self.settings_editor.?.indices(all[0..count], &indices);
            if (number >= visible) return;
            const e = &self.settings_editor.?;
            if (e.form_row != number) e.delete_pending = null;
            e.form_row = number;
            e.content_focus = true;
            const row = all[indices[number]];
            const rect = form.row(number);
            if (e.page == .defaults) switch (row.target) {
                .scanned => |index| {
                    if (scannedEnableButton(rect).contains(x, y)) return self.changeSetting(.{ .toggle_scanned = index }, "");
                },
                .set_default => |index| {
                    const same_open = e.details_open and e.profile == index;
                    const toggled = savedEditButton(rect).contains(x, y) or clicks >= 2;
                    e.profile = index;
                    if (toggled or !same_open) e.details_open = toggled and !same_open;
                    // The previous expansion may have interleaved rows before
                    // this entry. Its own catalogue index stays stable.
                    e.form_row = index;
                    self.settings_scroll_offset = Input.settingsDocument(self).view.offset;
                    return;
                },
                else => {},
            };
            if ((row.target == .add_environment or row.target == .delete_environment) and settingsRowField(rect).contains(x, y)) return Input.activateSetting(self, row);
            if (row.editable() and settingsEditButton(rect).contains(x, y)) return Input.activateSetting(self, row);
            if (row.editable() and row.choice() and settingsRowField(rect).contains(x, y)) return Input.activateSetting(self, row);
        }

        /// Handle Settings search, inline editing and shortcut capture keys.
        pub fn settingsKey(self: *Host, event_value: c.SDL_KeyboardEvent) !void {
            const e = &self.settings_editor.?;
            const key = event_value.key;
            const mods = input.semanticModifiers(event_value.mod);
            if (mods.control and key == c.SDLK_S and !e.recording) return self.settingsSave();
            if (mods.control and key == c.SDLK_F and !e.recording) {
                if (e.editing) |target| try self.changeSetting(target, e.buffer[0..e.len]);
                Input.settingsSetSearch(self, true);
                return;
            }
            if (e.recording) {
                if (key == c.SDLK_ESCAPE) {
                    self.cancelComposition();
                    e.cancel();
                    return;
                }
                if (key == c.SDLK_LCTRL or key == c.SDLK_RCTRL or key == c.SDLK_LSHIFT or key == c.SDLK_RSHIFT or
                    key == c.SDLK_LALT or key == c.SDLK_RALT or key == c.SDLK_LGUI or key == c.SDLK_RGUI) return;
                self.keyboard.suppress_text = true;
                var buffer: [64]u8 = undefined;
                const shortcut = try keybindings.format(key, event_value.mod, &buffer);
                @memcpy(e.buffer[0..shortcut.len], shortcut);
                e.len = shortcut.len;
                e.edit = .{ .cursor = shortcut.len };
                e.recording = false;
                self.setNotice("Shortcut captured — Enter stages; Save applies");
                return;
            }
            if (e.editing) |target| {
                if (key == c.SDLK_ESCAPE) {
                    self.cancelComposition();
                    e.cancel();
                } else if (key == c.SDLK_TAB) {
                    try self.changeSetting(target, e.buffer[0..e.len]);
                } else if (key == c.SDLK_RETURN) {
                    try self.changeSetting(target, e.buffer[0..e.len]);
                } else if (e.button == null) {
                    const row: settings.Row = .{ .page = e.page, .label = "", .target = target };
                    if (row.choice()) {
                        if (key == c.SDLK_LEFT or key == c.SDLK_UP or key == c.SDLK_RIGHT or key == c.SDLK_DOWN or key == c.SDLK_SPACE) try e.cycle(self.settingsConfiguration(), if (key == c.SDLK_LEFT or key == c.SDLK_UP) -1 else 1);
                    } else if (try self.textKey(&e.edit, e.buffer[0 .. e.buffer.len - 1], &e.len, event_value)) self.cancelComposition();
                }
                return;
            }
            if (key == c.SDLK_ESCAPE) {
                self.cancelComposition();
                if (e.search) {
                    Input.settingsSetSearch(self, false);
                } else try self.toggleSettings();
                return;
            }
            if (e.search and (key == c.SDLK_LEFT or key == c.SDLK_RIGHT or key == c.SDLK_HOME or key == c.SDLK_END or key == c.SDLK_DELETE or key == c.SDLK_BACKSPACE or (mods.control and (key == c.SDLK_A or key == c.SDLK_C or key == c.SDLK_X or key == c.SDLK_V)))) {
                if (try self.textKey(&e.query_edit, &e.query, &e.query_len, event_value)) e.list = .{};
                return;
            }
            // The Settings sidebar and form controls are pointer navigated.
            // Keyboard input is reserved for active editors and the search field.
        }
    };
}
