//! Settings behaviour and software-render acceptance, isolated from terminal host tests.
const std = @import("std");
const c = @import("desktop");
const vt = @import("howl_vt");
const config = @import("config.zig");
const settings = @import("settings.zig");
const widgets = @import("widgets.zig");
const layout = @import("layout.zig");
const chrome = @import("chrome.zig");
const appearance = @import("appearance.zig");
const color_config = @import("colors.zig");
const keybindings = @import("keybindings.zig");
const input = @import("input.zig");
const font_owner = @import("fonts.zig");
const pages = @import("settings_pages.zig");
const root = @import("main.zig");
const App = root.App;
const testFonts = root.testFonts;
const testPixel = root.testPixel;
const settings_header_height = pages.settings_header_height;
const settings_nav_top = pages.settings_nav_top;
const StartupForm = pages.StartupForm;
const AppearanceForm = pages.AppearanceForm;
const ColorForm = pages.ColorForm;
const ShortcutForm = pages.ShortcutForm;
const ProfilesForm = pages.ProfilesForm;

test "Profiles footer remains actionable across scroll selection and cached entry availability" {
    var configuration = try config.Config.parse(std.testing.allocator, std.testing.io,
        \\{"schema":1,"terminal_font_pixels":15,"scanned_profiles":[{"kind":"repl","recipe":{"id":"auto.repl.python","name":"Python","shell":"/usr/bin/python3"}},{"kind":"ssh","recipe":{"id":"auto.ssh.off","name":"Disabled host","shell":"/usr/bin/ssh"},"enabled":false},{"kind":"ssh","recipe":{"id":"auto.ssh.stale","name":"Missing host","shell":"/usr/bin/ssh"},"stale":true}]}
    );
    defer configuration.deinit();
    var app: App = .{
        .init = .{
            .minimal = undefined,
            .arena = undefined,
            .gpa = std.testing.allocator,
            .io = std.testing.io,
            .environ_map = undefined,
            .preopens = undefined,
        },
        .configuration = &configuration,
        .fonts = undefined,
        .window = undefined,
        .renderer = undefined,
        .ui_fonts = undefined,
        .geometry = undefined,
        .wake_event = 0,
        .scale = 1,
        .width = 1000,
        .height = 650,
        .bindings = try keybindings.Bindings.init(),
        .settings_editor = .{ .page = .defaults },
    };
    defer if (app.settings_draft) |*draft| draft.deinit();
    const footer = app.settingsDefaultButton();
    try std.testing.expectEqualStrings("local", (try app.overviewDefaultID()).?);
    app.settings_editor.?.form_row = 1;
    try std.testing.expectEqualStrings("auto.repl.python", (try app.overviewDefaultID()).?);
    try std.testing.expectEqualDeep(footer, app.settingsDefaultButton());
    app.settingsScrollBy(100000);
    try std.testing.expect(app.settings_scroll_offset > 0);
    try std.testing.expectEqualStrings("auto.repl.python", (try app.overviewDefaultID()).?);
    try std.testing.expectEqualDeep(footer, app.settingsDefaultButton());
    try app.settingsClick(footer.x + 10, footer.y + 10, 1);
    try std.testing.expectEqualStrings("auto.repl.python", (try app.settingsConfiguration().defaultProfile()).id);
    try std.testing.expectEqualStrings("local", (try configuration.defaultProfile()).id);
    app.settings_editor.?.form_row = 2;
    try std.testing.expect((try app.overviewDefaultID()) == null);
    try std.testing.expectEqualDeep(footer, app.settingsDefaultButton());
    try app.settingsClick(footer.x + 10, footer.y + 10, 1);
    try std.testing.expectEqualStrings("auto.repl.python", (try app.settingsConfiguration().defaultProfile()).id);
}

test "startup controls own clicks; choice editing and global Cancel preserve the live configuration" {
    try std.testing.expect(c.SDL_SetHint(c.SDL_HINT_VIDEO_DRIVER, "dummy"));
    if (!c.SDL_Init(c.SDL_INIT_VIDEO)) return error.SDL;
    defer c.SDL_Quit();
    const window = c.SDL_CreateWindow("settings focus proof", 1000, 650, 0) orelse return error.SDL;
    defer c.SDL_DestroyWindow(window);
    var configuration = try config.Config.parse(std.testing.allocator, std.testing.io,
        \\{"schema":1,"terminal_font_pixels":15,"profiles":[{"id":"build","name":"Build"}]}
    );
    defer configuration.deinit();
    var app: App = .{
        .init = undefined,
        .configuration = &configuration,
        .fonts = undefined,
        .window = window,
        .renderer = undefined,
        .ui_fonts = undefined,
        .geometry = undefined,
        .wake_event = 0,
        .scale = 1,
        .width = 1000,
        .height = 650,
        .bindings = try keybindings.Bindings.init(),
        .settings_editor = .{ .content_focus = true },
    };
    var event_value = std.mem.zeroes(c.SDL_KeyboardEvent);
    event_value.key = c.SDLK_RETURN;
    try app.settingsKey(event_value);
    try std.testing.expect(app.settings_editor.?.editing == null);
    const startup_label = app.startupForm().row(0);
    try app.settingsClick(startup_label.x + 8, startup_label.y + 10, 1);
    try std.testing.expect(app.settings_draft == null);
    try std.testing.expect(app.settings_editor.?.editing == null);

    const control = app.startupForm().select();
    try app.settingsClick(control.x + 10, control.y + 10, 1);
    try std.testing.expectEqual(settings.Target.default_profile, app.settings_editor.?.editing.?);
    try app.settings_editor.?.append("not a profile");
    try std.testing.expectEqualStrings("local", app.settings_editor.?.buffer[0..app.settings_editor.?.len]);
    event_value.key = c.SDLK_DOWN;
    try app.settingsKey(event_value);
    try std.testing.expectEqualStrings("build", app.settings_editor.?.buffer[0..app.settings_editor.?.len]);
    try std.testing.expectEqualStrings("local", (try configuration.defaultProfile()).id);
    event_value.key = c.SDLK_ESCAPE;
    try app.settingsKey(event_value);
    try std.testing.expect(app.settings_editor.?.editing == null);

    try app.settingsClick(control.x + 10, control.y + 10, 1);
    try std.testing.expectEqual(settings.Target.default_profile, app.settings_editor.?.editing.?);
    try std.testing.expectEqual(control.y, app.startupForm().select().y);
    try app.settingsClick(control.x + 10, control.y + 10, 1);
    try std.testing.expect(app.settings_editor.?.editing == null);
    try std.testing.expect(!app.settings_editor.?.content_focus);
    try app.settingsClick(control.x + 10, control.y + 10, 1);
    try std.testing.expectEqual(settings.Target.default_profile, app.settings_editor.?.editing.?);
    try std.testing.expect(!configuration.value.discover_shells);
    event_value.key = c.SDLK_ESCAPE;
    try app.settingsKey(event_value);
    try std.testing.expect(app.settings_editor.?.editing == null);
    event_value.key = c.SDLK_DOWN;
    try app.settingsKey(event_value);
    try std.testing.expectEqual(@as(usize, 0), app.settings_editor.?.list.selected);

    app.settings_editor.?.page = .defaults;
    const ssh_toggle = App.scanSourceSwitch(app.settingsScanSourceRow(1));
    try app.settingsClick(ssh_toggle.x + 10, ssh_toggle.y + 10, 1);
    try std.testing.expect(app.settings_draft != null);
    try std.testing.expect(app.settingsConfiguration().value.discover_ssh_hosts != configuration.value.discover_ssh_hosts);
    app.settingsCancel();
    try std.testing.expect(app.settings_draft == null);
    app.settings_editor.?.page = .startup;

    app.width = 788;
    app.height = 528;
    try std.testing.expect(app.settingsBody().height >= 350);
    try std.testing.expect(app.startupForm().view.scrollbar() == null);
    app.width = 560;
    app.height = 490;
    try std.testing.expect(app.startupForm().view.scrollbar() == null);
    const search_button = app.settingsHeaderButton(.search);
    const save_button = app.settingsHeaderButton(.save);
    const cancel_button = app.settingsHeaderButton(.cancel);
    const close_button = app.settingsHeaderButton(.close);
    try std.testing.expect(save_button.x + save_button.width < cancel_button.x);
    try std.testing.expect(cancel_button.x + cancel_button.width < search_button.x);
    try std.testing.expect(search_button.x + search_button.width < close_button.x);
    app.settings_draft = try settings.change(&configuration, std.testing.io, .discover_shells, "On");
    try app.settingsClick(cancel_button.x + 8, cancel_button.y + 8, 1);
    try std.testing.expect(app.settings_draft == null);
    try std.testing.expect(!configuration.value.discover_shells);
    const settings_box = app.settingsRect();
    try std.testing.expectEqual(chrome.height, settings_header_height);
    try std.testing.expectEqual(settings_box.y + chrome.Geometry.top, search_button.y);
    try std.testing.expectEqual(settings_box.y + settings_header_height, app.settingsBody().y);
    try app.settingsClick(settings_box.x + 12, settings_box.y + settings_nav_top + 34 + 16, 1);
    try std.testing.expectEqual(settings.Page.appearance, app.settings_editor.?.page);
    const nav_gap = app.settingsNavRow(0);
    try app.settingsClick(nav_gap.x + nav_gap.width + 2, nav_gap.y + 12, 1);
    try std.testing.expectEqual(settings.Page.appearance, app.settings_editor.?.page);
    try app.settingsClick(nav_gap.x + 12, nav_gap.y + nav_gap.height + 1, 1);
    try std.testing.expectEqual(settings.Page.appearance, app.settings_editor.?.page);
    try app.settingsClick(settings_box.x + 12, settings_box.y + settings_nav_top + 16, 1);
    try std.testing.expectEqual(settings.Page.startup, app.settings_editor.?.page);
    try app.settingsClick(search_button.x + 10, search_button.y + 10, 1);
    try std.testing.expect(app.settings_editor.?.search);
    try app.settingsClick(search_button.x + 10, search_button.y + 10, 1);
    try std.testing.expect(!app.settings_editor.?.search);

    event_value.key = c.SDLK_F;
    event_value.mod = c.SDL_KMOD_CTRL;
    try app.settingsKey(event_value);
    try app.settings_editor.?.append("palette");
    try std.testing.expect(app.settings_editor.?.search);
    event_value.mod = 0;
    event_value.key = c.SDLK_ESCAPE;
    try app.settingsKey(event_value);
    try std.testing.expect(!app.settings_editor.?.search and app.settings_editor.?.content_focus);
    try app.settingsKey(event_value);
    try std.testing.expect(app.settings_editor == null);
}

test "Profiles label clicks navigate while explicit scan controls stage only their own changes" {
    try std.testing.expect(c.SDL_SetHint(c.SDL_HINT_VIDEO_DRIVER, "dummy"));
    if (!c.SDL_Init(c.SDL_INIT_VIDEO)) return error.SDL;
    defer c.SDL_Quit();
    const window = c.SDL_CreateWindow("profiles pointer proof", 1000, 650, 0) orelse return error.SDL;
    defer c.SDL_DestroyWindow(window);
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    var configuration = try config.Config.parse(std.testing.allocator, threaded.io(),
        \\{"schema":1,"terminal_font_pixels":15,"profiles":[{"id":"build","name":"Build"}],"scanned_profiles":[{"kind":"ssh","recipe":{"id":"auto.ssh.host","name":"Host","shell":"/usr/bin/ssh"}}]}
    );
    defer configuration.deinit();
    var app: App = .{
        .init = undefined,
        .configuration = &configuration,
        .fonts = undefined,
        .window = window,
        .renderer = undefined,
        .ui_fonts = undefined,
        .geometry = undefined,
        .wake_event = 0,
        .scale = 1,
        .width = 1000,
        .height = 650,
        .bindings = try keybindings.Bindings.init(),
        .settings_editor = .{ .page = .defaults, .content_focus = true },
    };
    app.init.io = threaded.io();
    defer app.discardSettings();
    try std.testing.expectEqual(@as(usize, 5), settings.titles.len);
    const cached_row = app.profilesForm().row(2);
    try app.settingsClick(cached_row.x + 12, cached_row.y + 12, 1);
    try std.testing.expect(app.settings_draft == null);
    try std.testing.expectEqual(@as(usize, 2), app.settings_editor.?.form_row);
    const toggle = App.scannedEnableButton(cached_row);
    try app.settingsClick(toggle.x + 12, toggle.y + 12, 1);
    try std.testing.expect(!app.settingsConfiguration().value.scanned_profiles[0].enabled);
    try std.testing.expect(configuration.value.scanned_profiles[0].enabled);
    app.settingsCancel();
    try std.testing.expect(app.settingsConfiguration().value.scanned_profiles[0].enabled);

    const source_row = app.settingsScanSourceRow(0);
    try app.settingsClick(source_row.x + 12, source_row.y + 12, 1);
    try std.testing.expect(app.settings_draft == null);
    const source_switch = App.scanSourceSwitch(source_row);
    try app.settingsClick(source_switch.x + 12, source_switch.y + 12, 1);
    try std.testing.expect(app.settingsConfiguration().value.discover_shells);
    app.settingsCancel();
    try std.testing.expect(!configuration.value.discover_shells);

    try app.settingsClick(cached_row.x + 12, cached_row.y + 12, 1);
    const duplicate = app.settingsToolbarButton(1);
    try app.settingsClick(duplicate.x + 12, duplicate.y + 12, 1);
    try std.testing.expectEqual(settings.Page.profiles, app.settings_editor.?.page);
    try std.testing.expectEqual(@as(usize, 1), app.settingsConfiguration().value.profiles.len - configuration.value.profiles.len);
    try std.testing.expectEqualStrings("Host", app.settingsConfiguration().value.profiles[1].name);
    app.settingsCancel();
    try std.testing.expectEqual(@as(usize, 1), configuration.value.profiles.len);
}

test "Profiles page owns both catalogue and detail scrolling, independent of selection" {
    try std.testing.expect(c.SDL_SetHint(c.SDL_HINT_VIDEO_DRIVER, "dummy"));
    if (!c.SDL_Init(c.SDL_INIT_VIDEO)) return error.SDL;
    defer c.SDL_Quit();
    const window = c.SDL_CreateWindow("profiles page scroll proof", 920, 650, 0) orelse return error.SDL;
    defer c.SDL_DestroyWindow(window);
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    var configuration = try config.Config.parse(std.testing.allocator, threaded.io(),
        \\{"schema":1,"terminal_font_pixels":15,"profiles":[{"id":"build","name":"Build"}],"scanned_profiles":[{"kind":"ssh","recipe":{"id":"auto.ssh.a","name":"Host A","shell":"/usr/bin/ssh"}},{"kind":"ssh","recipe":{"id":"auto.ssh.b","name":"Host B","shell":"/usr/bin/ssh"}},{"kind":"ssh","recipe":{"id":"auto.ssh.c","name":"Host C","shell":"/usr/bin/ssh"}},{"kind":"ssh","recipe":{"id":"auto.ssh.d","name":"Host D","shell":"/usr/bin/ssh"}},{"kind":"ssh","recipe":{"id":"auto.ssh.e","name":"Host E","shell":"/usr/bin/ssh"}},{"kind":"ssh","recipe":{"id":"auto.ssh.f","name":"Host F","shell":"/usr/bin/ssh"}}]}
    );
    defer configuration.deinit();
    var app: App = .{
        .init = undefined,
        .configuration = &configuration,
        .fonts = undefined,
        .window = window,
        .renderer = undefined,
        .ui_fonts = undefined,
        .geometry = undefined,
        .wake_event = 0,
        .scale = 1,
        .width = 920,
        .height = 650,
        .bindings = try keybindings.Bindings.init(),
        .settings_editor = .{ .page = .defaults, .content_focus = true },
    };
    app.init.io = threaded.io();
    defer app.discardSettings();

    const body = app.settingsBody();
    const overview = app.profilesForm();
    try std.testing.expectEqual(@as(usize, 3), overview.cardCount());
    try std.testing.expectEqual(@as(usize, 2), overview.saved_count);
    try std.testing.expectEqual(@as(usize, 6), overview.scanned_count);
    const bar = overview.view.scrollbar().?;
    try std.testing.expectApproxEqAbs(body.x + body.width - 4, bar.track.x, 0.01);
    for (0..overview.cardCount()) |number| try std.testing.expect(bar.track.x > overview.card(number).x + overview.card(number).width);
    var all: [settings.row_limit]settings.Row = undefined;
    var indices: [settings.row_limit]u16 = undefined;
    const count = try settings.rows(&configuration, &all);
    try std.testing.expectEqual(overview.saved_count + overview.scanned_count, app.settings_editor.?.indices(all[0..count], &indices));
    try std.testing.expectEqual(settings.Target{ .set_default = 0 }, all[indices[0]].target);
    try std.testing.expectEqual(settings.Target{ .set_default = 1 }, all[indices[1]].target);
    try std.testing.expectEqual(settings.Target{ .scanned = 0 }, all[indices[2]].target);
    try std.testing.expectEqual(settings.Target{ .scanned = 5 }, all[indices[7]].target);

    app.settings_editor.?.form_row = 1;
    const selected_id = (try app.overviewDefaultID()).?;
    const footer = app.settingsDefaultButton();
    const original_scan_y = overview.card(0).y;
    const original_saved_y = overview.card(1).y;
    const original_row_y = overview.row(2).y;
    var wheel = std.mem.zeroes(c.SDL_MouseWheelEvent);
    wheel.y = -2;
    wheel.mouse_x = body.x + 60;
    wheel.mouse_y = body.y + 60;
    try app.pointerWheel(wheel);
    try std.testing.expectEqual(@as(f32, 96), app.settings_scroll_offset);
    const scrolled = app.profilesForm();
    try std.testing.expectApproxEqAbs(original_scan_y - 96, scrolled.card(0).y, 0.01);
    try std.testing.expectApproxEqAbs(original_saved_y - 96, scrolled.card(1).y, 0.01);
    try std.testing.expectApproxEqAbs(original_row_y - 96, scrolled.row(2).y, 0.01);
    try std.testing.expectEqual(@as(usize, 1), app.settings_editor.?.form_row);
    try std.testing.expectEqual(@as(usize, 0), app.settings_editor.?.list.first);
    try std.testing.expectEqualStrings(selected_id, (try app.overviewDefaultID()).?);
    try std.testing.expectEqualDeep(footer, app.settingsDefaultButton());

    const scanned_row = scrolled.row(2);
    try std.testing.expect(body.contains(scanned_row.x + 12, scanned_row.y + 12));
    try std.testing.expectEqual(@as(?usize, 2), scrolled.hit(scanned_row.x + 12, scanned_row.y + 12));
    try app.settingsClick(scanned_row.x + 12, scanned_row.y + 12, 1);
    try std.testing.expectEqual(@as(usize, 2), app.settings_editor.?.form_row);
    try std.testing.expect(app.settings_draft == null);
    const toggle = App.scannedEnableButton(scanned_row);
    try app.settingsClick(toggle.x + 12, toggle.y + 12, 1);
    try std.testing.expect(!app.settingsConfiguration().value.scanned_profiles[0].enabled);
    try std.testing.expect(configuration.value.scanned_profiles[0].enabled);
    app.settingsCancel();
    try std.testing.expect(app.settingsConfiguration().value.scanned_profiles[0].enabled);

    try std.testing.expect(app.settingsScrollbarPress(bar.track.x - 5, bar.track.y + bar.track.height - 5));
    try std.testing.expect(app.settings_scroll_offset > 96);
    const end = app.profilesForm();
    const last_row = end.row(7);
    try std.testing.expect(body.contains(last_row.x + 12, last_row.y + 12));
    try std.testing.expectEqual(@as(?usize, 7), end.hit(last_row.x + 12, last_row.y + 12));
    try std.testing.expectEqual(@as(usize, 2), app.settings_editor.?.form_row);
    try std.testing.expectEqual(@as(usize, 0), app.settings_editor.?.list.first);
    try std.testing.expectEqualDeep(footer, app.settingsDefaultButton());
    try std.testing.expect(app.settingsScanSourceRow(0).y + 34 < body.y);
    try app.settingsClick(footer.x + 10, footer.y + 10, 1);
    try std.testing.expectEqualStrings("auto.ssh.a", (try app.settingsConfiguration().defaultProfile()).id);
    try std.testing.expectEqualStrings("local", (try configuration.defaultProfile()).id);
    app.settingsCancel();

    app.settings_scroll_offset = 0;
    const edit = App.savedEditButton(app.profilesForm().row(1));
    try app.settingsClick(edit.x + 10, edit.y + 10, 1);
    try std.testing.expectEqual(settings.Page.profiles, app.settings_editor.?.page);
    try std.testing.expectEqual(@as(u8, 1), app.settings_editor.?.profile);
    app.height = 470;
    const details = app.profilesForm();
    try std.testing.expectEqual(@as(usize, 1), details.cardCount());
    try std.testing.expectEqual(@as(usize, 7), details.detail_count);
    const detail_count = try settings.rows(&configuration, &all);
    try std.testing.expectEqual(details.detail_count, app.settings_editor.?.indices(all[0..detail_count], &indices));
    try std.testing.expect(details.view.scrollbar() != null);
    const detail_bar = details.view.scrollbar().?;
    try std.testing.expect(detail_bar.track.x > details.card(0).x + details.card(0).width);
    try std.testing.expect(app.settingsScrollbarPress(detail_bar.track.x - 5, detail_bar.track.y + detail_bar.track.height - 5));
    try std.testing.expect(app.settings_scroll_offset > 0);
    const last_detail_row = app.profilesForm().row(6);
    try std.testing.expect(app.settingsBody().contains(last_detail_row.x + 10, last_detail_row.y + 10));
    try std.testing.expectEqual(@as(?usize, 6), app.profilesForm().hit(last_detail_row.x + 10, last_detail_row.y + 10));
    try std.testing.expectEqual(@as(usize, 0), app.settings_editor.?.form_row);
    try std.testing.expectEqual(@as(usize, 0), app.settings_editor.?.list.first);
    app.settings_scroll_grab = null;
}

test "Profiles cards paint inside the shared page viewport with an outer scrollbar" {
    try std.testing.expect(c.SDL_SetHint(c.SDL_HINT_VIDEO_DRIVER, "dummy"));
    if (!c.SDL_Init(c.SDL_INIT_VIDEO)) return error.SDL;
    defer c.SDL_Quit();
    if (!c.TTF_Init()) return error.TTF;
    defer c.TTF_Quit();
    const a = std.testing.allocator;
    const window = c.SDL_CreateWindow("profiles card paint", 920, 470, 0) orelse return error.SDL;
    defer c.SDL_DestroyWindow(window);
    const surface = c.SDL_CreateSurface(920, 470, c.SDL_PIXELFORMAT_RGBA32) orelse return error.SDL;
    defer c.SDL_DestroySurface(surface);
    const renderer = c.SDL_CreateSoftwareRenderer(surface) orelse return error.SDL;
    defer c.SDL_DestroyRenderer(renderer);
    var fonts = try testFonts(a);
    defer fonts.deinit();
    var ui_fonts = try font_owner.TextFonts.open(a, &fonts, 15);
    defer ui_fonts.deinit();
    var configuration = try config.Config.parse(a, std.testing.io,
        \\{"schema":1,"terminal_font_pixels":15,"profiles":[{"id":"build","name":"Build"}],"scanned_profiles":[{"kind":"ssh","recipe":{"id":"auto.ssh.a","name":"Host A","shell":"/usr/bin/ssh"}},{"kind":"ssh","recipe":{"id":"auto.ssh.b","name":"Host B","shell":"/usr/bin/ssh"}},{"kind":"ssh","recipe":{"id":"auto.ssh.c","name":"Host C","shell":"/usr/bin/ssh"}}]}
    );
    defer configuration.deinit();
    var app: App = .{
        .init = undefined,
        .configuration = &configuration,
        .fonts = &fonts,
        .window = window,
        .renderer = renderer,
        .ui_fonts = &ui_fonts,
        .geometry = undefined,
        .wake_event = 0,
        .scale = 1,
        .width = 920,
        .height = 470,
        .bindings = try keybindings.Bindings.init(),
        .settings_editor = .{ .page = .defaults },
    };
    const colors = try app.uiPalette();
    try app.drawSettings();
    try std.testing.expect(c.SDL_RenderPresent(renderer));
    const saved = app.profilesForm().card(1);
    try std.testing.expectEqual(colors.panel, try testPixel(surface, @intFromFloat(saved.x + 8), @intFromFloat(saved.y + 61)));
    try std.testing.expectEqual(colors.title, try testPixel(surface, @intFromFloat(saved.x - 5), @intFromFloat(saved.y + 61)));
    const bar = app.profilesForm().view.scrollbar().?;
    try std.testing.expect(bar.track.x > saved.x + saved.width);
    try std.testing.expectEqual(colors.muted, try testPixel(surface, @intFromFloat(bar.thumb.x + bar.thumb.width / 2), @intFromFloat(bar.thumb.y + bar.thumb.height / 2)));
    app.settings_scroll_offset = 100000;
    try app.drawSettings();
    try std.testing.expect(c.SDL_RenderPresent(renderer));
    const scanned = app.profilesForm().card(2);
    try std.testing.expectEqual(colors.panel, try testPixel(surface, @intFromFloat(scanned.x + 8), @intFromFloat(scanned.y + scanned.height - 20)));

    app.settings_editor.?.page = .profiles;
    app.settings_editor.?.profile = 1;
    app.settings_scroll_offset = 100000;
    try app.drawSettings();
    try std.testing.expect(c.SDL_RenderPresent(renderer));
    const detail = app.profilesForm().card(0);
    try std.testing.expect(app.profilesForm().view.scrollbar() != null);
    try std.testing.expectEqual(colors.panel, try testPixel(surface, @intFromFloat(detail.x + 8), @intFromFloat(detail.y + detail.height - 20)));
}
test "shortcut cards paint separately from the page and retain the outer scrollbar" {
    try std.testing.expect(c.SDL_SetHint(c.SDL_HINT_VIDEO_DRIVER, "dummy"));
    if (!c.SDL_Init(c.SDL_INIT_VIDEO)) return error.SDL;
    defer c.SDL_Quit();
    if (!c.TTF_Init()) return error.TTF;
    defer c.TTF_Quit();
    const a = std.testing.allocator;
    const window = c.SDL_CreateWindow("shortcut card paint", 920, 650, 0) orelse return error.SDL;
    defer c.SDL_DestroyWindow(window);
    const surface = c.SDL_CreateSurface(920, 650, c.SDL_PIXELFORMAT_RGBA32) orelse return error.SDL;
    defer c.SDL_DestroySurface(surface);
    const renderer = c.SDL_CreateSoftwareRenderer(surface) orelse return error.SDL;
    defer c.SDL_DestroyRenderer(renderer);
    var fonts = try testFonts(a);
    defer fonts.deinit();
    var ui_fonts = try font_owner.TextFonts.open(a, &fonts, 15);
    defer ui_fonts.deinit();
    var configuration = config.Config.defaults(a);
    defer configuration.deinit();
    var app: App = .{
        .init = undefined,
        .configuration = &configuration,
        .fonts = &fonts,
        .window = window,
        .renderer = renderer,
        .ui_fonts = &ui_fonts,
        .geometry = undefined,
        .wake_event = 0,
        .scale = 1,
        .width = 920,
        .height = 650,
        .bindings = try keybindings.Bindings.init(),
        .settings_editor = .{ .page = .mappings },
    };
    const colors = try app.uiPalette();
    try app.drawSettings();
    try std.testing.expect(c.SDL_RenderPresent(renderer));
    const first = app.shortcutForm().card(0);
    // The Settings card and its header/sidebar elbow share the tab chip's
    // four-pixel corner; no square cutout or oversized card radius remains.
    const box = app.settingsRect();
    const elbow_x = app.settingsBody().x - 12;
    const elbow_y = box.y + settings_header_height;
    try std.testing.expectEqual(colors.idle, try testPixel(surface, @intFromFloat(elbow_x), @intFromFloat(elbow_y)));
    try std.testing.expectEqual(colors.title, try testPixel(surface, @intFromFloat(elbow_x + chrome.Geometry.chip_radius - 1), @intFromFloat(elbow_y + chrome.Geometry.chip_radius - 1)));
    try std.testing.expectEqual(colors.title, try testPixel(surface, @intFromFloat(first.x), @intFromFloat(first.y)));
    try std.testing.expectEqual(colors.border, try testPixel(surface, @intFromFloat(first.x + chrome.Geometry.chip_radius), @intFromFloat(first.y)));
    try std.testing.expectEqual(colors.panel, try testPixel(surface, @intFromFloat(first.x + 8), @intFromFloat(first.y + 74)));
    try std.testing.expectEqual(colors.title, try testPixel(surface, @intFromFloat(first.x - 5), @intFromFloat(first.y + 74)));
    const bar = app.shortcutForm().view.scrollbar().?;
    try std.testing.expect(bar.track.x > first.x + first.width);
    app.settings_scroll_offset = 100000;
    try app.drawSettings();
    try std.testing.expect(c.SDL_RenderPresent(renderer));
    const last = app.shortcutForm().card(ShortcutForm.sections.len - 1);
    try std.testing.expectEqual(colors.panel, try testPixel(surface, @intFromFloat(last.x + 8), @intFromFloat(last.y + last.height - 20)));

    app.settings_editor.?.page = .startup;
    app.settings_editor.?.editing = .default_profile;
    app.settings_scroll_offset = 0;
    try app.drawSettings();
    try std.testing.expect(c.SDL_RenderPresent(renderer));
    const select = app.startupForm().select();
    const menu = app.settingsDropdown();
    try std.testing.expectEqual(colors.panel, try testPixel(surface, @intFromFloat(select.x), @intFromFloat(select.y)));
    try std.testing.expectEqual(colors.accent, try testPixel(surface, @intFromFloat(select.x + chrome.Geometry.chip_radius), @intFromFloat(select.y)));
    try std.testing.expect(!std.meta.eql(colors.border, try testPixel(surface, @intFromFloat(menu.rect.x), @intFromFloat(menu.rect.y))));
    try std.testing.expectEqual(colors.border, try testPixel(surface, @intFromFloat(menu.rect.x + chrome.Geometry.chip_radius), @intFromFloat(menu.rect.y)));
}

test "Settings Save commits the complete draft once; Cancel and failed Save preserve the live configuration" {
    const a = std.testing.allocator;
    var threaded = std.Io.Threaded.init(a, .{});
    defer threaded.deinit();
    var current = config.Config.defaults(a);
    defer current.deinit();
    var fonts = try testFonts(a);
    defer fonts.deinit();
    var app: App = .{
        .init = undefined,
        .configuration = &current,
        .fonts = &fonts,
        .window = undefined,
        .renderer = undefined,
        .ui_fonts = undefined,
        .geometry = undefined,
        .wake_event = 0,
        .scale = 1,
        .bindings = try keybindings.Bindings.init(),
        .settings_editor = .{},
    };
    app.init.io = threaded.io();
    defer app.discardSettings();
    try app.changeSetting(.discover_shells, "On");
    try app.changeSetting(.cursor_blink, "Always");
    try std.testing.expect(!current.value.discover_shells);
    try std.testing.expect(app.settingsConfiguration().value.discover_shells);
    try std.testing.expectEqual(.always, app.settingsConfiguration().value.cursor_blink);
    app.settingsCancel();
    try std.testing.expect(app.settings_draft == null);
    try std.testing.expect(!current.value.discover_shells);

    try app.changeSetting(.discover_shells, "On");
    try app.changeSetting(.cursor_blink, "Always");
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.createDir(threaded.io(), "occupied", .default_dir);
    try std.testing.expectError(error.IsDir, app.settingsSaveAt(temporary.dir, "occupied"));
    try std.testing.expect(!current.value.discover_shells);
    try std.testing.expect(app.settings_draft != null);
    try app.settingsSaveAt(temporary.dir, "settings.json");
    try std.testing.expect(app.settings_draft == null);
    try std.testing.expect(current.value.discover_shells);
    try std.testing.expectEqual(.always, current.value.cursor_blink);
    var reloaded = try config.Config.loadAt(a, threaded.io(), temporary.dir, "settings.json");
    defer reloaded.deinit();
    try std.testing.expect(reloaded.value.discover_shells);
    try std.testing.expectEqual(.always, reloaded.value.cursor_blink);
}

test "startup form keeps the default selector inside its card at compact widths" {
    for ([_]f32{ 554, 320, 180 }) |width| {
        const bounds: layout.Rect = .{ .x = 400, .y = 150, .width = width, .height = 210 };
        for ([_]f32{ 0, 72, 400 }) |scroll_offset| {
            const form = StartupForm.init(bounds, scroll_offset);
            const first = form.card(0);
            const selector = form.select();
            try std.testing.expectEqual(first.x - bounds.x, bounds.x + bounds.width - first.x - first.width);
            try std.testing.expect(first.y >= bounds.y + StartupForm.top_inset - form.view.offset);
            const first_row = form.row(0);
            try std.testing.expectEqual(first_row.x - first.x, first.x + first.width - first_row.x - first_row.width);
            try std.testing.expect(selector.x >= first.x);
            try std.testing.expect(selector.x + selector.width <= first.x + first.width);
            try std.testing.expect(selector.y >= first.y and selector.y + selector.height <= first.y + first.height);
        }
    }
}

test "settings cards share symmetric painted and pointer geometry" {
    try std.testing.expect(c.SDL_SetHint(c.SDL_HINT_VIDEO_DRIVER, "dummy"));
    if (!c.SDL_Init(c.SDL_INIT_VIDEO)) return error.SDL;
    defer c.SDL_Quit();
    const window = c.SDL_CreateWindow("settings card geometry", 920, 650, 0) orelse return error.SDL;
    defer c.SDL_DestroyWindow(window);
    var configuration = config.Config.defaults(std.testing.allocator);
    defer configuration.deinit();
    var app: App = .{
        .init = undefined,
        .configuration = &configuration,
        .fonts = undefined,
        .window = window,
        .renderer = undefined,
        .ui_fonts = undefined,
        .geometry = undefined,
        .wake_event = 0,
        .scale = 1,
        .bindings = try keybindings.Bindings.init(),
        .tab_count = 1,
        .settings_editor = .{ .page = .appearance, .content_focus = true },
    };
    for ([_]struct { width: f32, height: f32 }{
        .{ .width = 920, .height = 650 },
        .{ .width = 560, .height = 450 },
        .{ .width = 300, .height = 300 },
    }) |size| {
        app.width = size.width;
        app.height = size.height;
        app.settings_editor.?.page = .defaults;
        const overview = app.profilesForm();
        const profile_body = app.settingsBody();
        const scan = overview.card(0);
        const saved = overview.card(1);
        const cached = overview.card(2);
        const scan_button = app.settingsToolbarButton(2);
        const new_button = app.settingsToolbarButton(0);
        const duplicate_button = app.settingsToolbarButton(1);
        try std.testing.expect(scan.y >= app.settingsRect().y + settings_header_height);
        try std.testing.expect(scan.y + scan.height < saved.y);
        try std.testing.expect(saved.y + saved.height < cached.y);
        try std.testing.expectApproxEqAbs(scan.x, saved.x, 0.01);
        try std.testing.expectApproxEqAbs(saved.x, cached.x, 0.01);
        for (0..overview.cardCount()) |number| {
            const card = overview.card(number);
            try std.testing.expectApproxEqAbs(card.x - profile_body.x, profile_body.x + profile_body.width - card.x - card.width, 0.01);
        }
        try std.testing.expect(scan_button.x >= scan.x and scan_button.x + scan_button.width <= scan.x + scan.width);
        try std.testing.expect(new_button.x >= saved.x and duplicate_button.x + duplicate_button.width <= saved.x + saved.width);
        try std.testing.expect(new_button.x + new_button.width < duplicate_button.x);
        for (0..2) |number| {
            const source = app.settingsScanSourceRow(number);
            const toggle = App.scanSourceSwitch(source);
            try std.testing.expect(source.x >= scan.x and source.x + source.width <= scan.x + scan.width);
            try std.testing.expect(source.y >= scan.y and source.y + source.height <= scan.y + scan.height);
            try std.testing.expect(toggle.x >= source.x and toggle.x + toggle.width <= source.x + source.width);
            try std.testing.expect(toggle.y >= source.y and toggle.y + toggle.height <= source.y + source.height);
        }
        if (overview.view.scrollbar()) |bar| try std.testing.expect(bar.track.x > saved.x + saved.width);
        app.settings_editor.?.page = .profiles;
        const details = app.profilesForm();
        const card = details.card(0);
        try std.testing.expect(app.simpleSettingsForm());
        try std.testing.expectApproxEqAbs(card.x - profile_body.x, profile_body.x + profile_body.width - card.x - card.width, 0.01);
        try std.testing.expect(card.y >= profile_body.y);
        const first = details.row(0);
        try std.testing.expectApproxEqAbs(first.x - card.x, card.x + card.width - first.x - first.width, 0.01);
        try std.testing.expect(first.y >= card.y + ProfilesForm.detail_heading_height);
        if (details.view.bounds.contains(first.x + 1, first.y + 1))
            try std.testing.expectEqual(@as(?usize, 0), details.hit(first.x + 1, first.y + 1));
        try std.testing.expect(details.hit(card.x + 1, first.y + 1) == null);
        if (details.view.scrollbar()) |bar| try std.testing.expect(bar.track.x > card.x + card.width);

        app.settings_editor.?.page = .mappings;
        const body = app.settingsBody();
        const shortcuts = app.shortcutForm();
        try std.testing.expect(shortcuts.view.scrollbar() != null);
        try std.testing.expectApproxEqAbs(shortcuts.view.bounds.x + shortcuts.view.bounds.width - 4, shortcuts.view.scrollbar().?.track.x, 0.01);
        var grouped: usize = 0;
        for (ShortcutForm.sections, 0..) |section, number| {
            const group = shortcuts.card(number);
            try std.testing.expectApproxEqAbs(group.x - body.x, body.x + body.width - group.x - group.width, 0.01);
            if (number > 0) try std.testing.expect(group.y >= shortcuts.card(number - 1).y + shortcuts.card(number - 1).height + ShortcutForm.card_gap);
            var count_in_group: usize = 0;
            for (keybindings.definitions, 0..) |definition, index| {
                if (definition.category != section.category) continue;
                const item = shortcuts.row(index);
                try std.testing.expectApproxEqAbs(item.x - group.x, group.x + group.width - item.x - item.width, 0.01);
                try std.testing.expect(item.y >= group.y + ShortcutForm.heading_height);
                try std.testing.expect(item.y + item.height < group.y + group.height);
                const near = ShortcutForm.init(body, ShortcutForm.rowTop(index) - ShortcutForm.outer_inset);
                const visible_row = near.row(index);
                if (near.view.bounds.contains(visible_row.x + 1, visible_row.y + 1))
                    try std.testing.expectEqual(@as(?usize, index), near.hit(visible_row.x + 1, visible_row.y + 1));
                count_in_group += 1;
            }
            try std.testing.expect(count_in_group > 0);
            try std.testing.expectEqual(count_in_group, ShortcutForm.rowCount(number));
            grouped += count_in_group;
        }
        try std.testing.expectEqual(keybindings.definitions.len, grouped);
        const tail = ShortcutForm.init(body, 100000);
        var last_index: usize = 0;
        for (keybindings.definitions, 0..) |_, index| if (ShortcutForm.rowTop(index) > ShortcutForm.rowTop(last_index)) {
            last_index = index;
        };
        const last_shortcut = tail.row(last_index);
        try std.testing.expect(last_shortcut.y >= body.y);
        try std.testing.expect(last_shortcut.y + last_shortcut.height <= body.y + body.height);

        app.settings_editor.?.page = .appearance;
        const form = app.appearanceForm();
        try std.testing.expect(app.simpleSettingsForm());
        try std.testing.expectApproxEqAbs(body.y + AppearanceForm.top_inset, form.card(0).y, 0.01);
        for (AppearanceForm.sections, 0..) |section, number| {
            const group = form.card(number);
            const group_first = form.row(section.first);
            const group_last = form.row(section.first + section.count - 1);
            try std.testing.expectApproxEqAbs(group.x - body.x, body.x + body.width - group.x - group.width, 0.01);
            try std.testing.expectApproxEqAbs(group_first.x - group.x, group.x + group.width - group_first.x - group_first.width, 0.01);
            try std.testing.expect(group_first.y >= group.y + AppearanceForm.heading_height);
            try std.testing.expect(group_last.y + group_last.height < group.y + group.height);
            if (number > 0) try std.testing.expect(group.y >= form.card(number - 1).y + form.card(number - 1).height + AppearanceForm.card_gap);
        }
        const first_appearance = form.row(0);
        try std.testing.expectEqual(@as(?usize, 0), form.hit(first_appearance.x + 1, first_appearance.y + 1));
        try std.testing.expect(form.hit(form.card(0).x + 16, form.card(0).y + 16) == null);
        const next_row = AppearanceForm.init(body, AppearanceForm.row_stride);
        try std.testing.expectApproxEqAbs(AppearanceForm.row_stride, next_row.view.offset, 0.01);
        const fonts = AppearanceForm.init(body, AppearanceForm.rowTop(2) - AppearanceForm.rowTop(0));
        try std.testing.expectApproxEqAbs(AppearanceForm.rowTop(2) - AppearanceForm.rowTop(0), fonts.view.offset, 0.01);
        app.settings_scroll_offset = 100000;
        const scrolled = app.appearanceForm();
        const last_appearance = scrolled.row(AppearanceForm.count - 1);
        try std.testing.expect(last_appearance.y >= body.y);
        try std.testing.expect(last_appearance.y + last_appearance.height <= body.y + body.height);
        try std.testing.expectEqual(@as(?usize, AppearanceForm.count - 1), scrolled.hit(last_appearance.x + 1, last_appearance.y + 1));
        app.settings_scroll_offset = 0;
        app.settings_editor.?.page = .colors;
        try std.testing.expect(app.simpleSettingsForm());
        const color_form = app.colorForm();
        for (ColorForm.sections, 0..) |section, number| {
            const group = color_form.card(number);
            const first_color = color_form.row(section.first);
            const last_color = color_form.row(section.first + section.count - 1);
            try std.testing.expectApproxEqAbs(group.x - body.x, body.x + body.width - group.x - group.width, 0.01);
            try std.testing.expectApproxEqAbs(first_color.x - group.x, group.x + group.width - first_color.x - first_color.width, 0.01);
            try std.testing.expect(first_color.y >= group.y + ColorForm.heading_height);
            try std.testing.expect(last_color.y + last_color.height <= group.y + group.height);
        }
        app.settings_editor.?.page = .appearance;
        app.settings_editor.?.search = true;
        try std.testing.expect(app.simpleSettingsForm());
        try std.testing.expect(app.settingsRows().rect.x > app.settingsBody().x);
        app.settings_editor.?.search = false;
    }
    app.width = 920;
    app.height = 650;
    var all: [settings.row_limit]settings.Row = undefined;
    var indices: [settings.row_limit]u16 = undefined;
    const count = try settings.rows(&configuration, &all);
    app.settings_editor.?.page = .mappings;
    try std.testing.expectEqual(keybindings.definitions.len, app.settings_editor.?.indices(all[0..count], &indices));
    for (indices[0..keybindings.definitions.len], 0..) |index, number| {
        try std.testing.expectEqual(settings.Page.mappings, all[index].page);
        try std.testing.expectEqual(@as(u8, @intCast(number)), all[index].target.binding);
    }
    const history_index = keybindings.indexForId("history_page_up").?;
    app.settings_editor.?.search = true;
    try app.activateSetting(all[indices[history_index]]);
    try std.testing.expect(!app.settings_editor.?.search);
    try std.testing.expectEqual(settings.Page.mappings, app.settings_editor.?.page);
    try std.testing.expectEqual(history_index, app.settings_editor.?.form_row);
    try std.testing.expect(app.settings_scroll_offset > 0);
    const history_row = app.shortcutForm().row(history_index);
    const history_edit = App.settingsEditButton(history_row);
    try std.testing.expect(app.settingsBody().contains(history_edit.x + 5, history_edit.y + 5));
    try app.settingsClick(history_edit.x + 5, history_edit.y + 5, 1);
    try std.testing.expectEqual(settings.Target{ .binding = @intCast(history_index) }, app.settings_editor.?.editing.?);
    try std.testing.expectEqualDeep(App.settingsRowField(app.shortcutForm().row(history_index)), app.settingsField());
    app.settings_editor.?.cancel();
    app.settings_scroll_offset = 0;
    var shortcut_wheel = std.mem.zeroes(c.SDL_MouseWheelEvent);
    shortcut_wheel.y = -2;
    shortcut_wheel.mouse_x = app.settingsBody().x + 60;
    shortcut_wheel.mouse_y = app.settingsBody().y + 60;
    try app.pointerWheel(shortcut_wheel);
    try std.testing.expectEqual(@as(f32, 96), app.settings_scroll_offset);
    app.settings_scroll_offset = 0;
    const shortcut_bar = app.shortcutForm().view.scrollbar().?;
    try std.testing.expect(app.settingsScrollbarPress(shortcut_bar.track.x - 5, shortcut_bar.track.y + shortcut_bar.track.height - 5));
    try std.testing.expect(app.settings_scroll_offset > 0);
    app.settingsScrollbarMove(shortcut_bar.track.y + 5);
    try std.testing.expectEqual(@as(f32, 0), app.settings_scroll_offset);
    app.settings_scroll_grab = null;
    app.settings_editor.?.page = .appearance;
    app.settings_editor.?.form_row = 0;
    try std.testing.expectEqual(AppearanceForm.count, app.settings_editor.?.indices(all[0..count], &indices));
    const starts = [_]settings.Target{ .hide_single_tab, .font_family, .cursor_blink };
    const ends = [_]settings.Target{ .tab_width, .{ .font = 5 }, .cursor_blink_idle_ms };
    for (AppearanceForm.sections, 0..) |section, number| {
        try std.testing.expectEqualDeep(starts[number], all[indices[section.first]].target);
        try std.testing.expectEqualDeep(ends[number], all[indices[section.first + section.count - 1]].target);
    }
    const row = app.appearanceForm().row(0);
    try app.settingsClick(row.x + 8, row.y + 15, 1);
    try std.testing.expect(app.settings_editor.?.editing == null);
    try std.testing.expectEqual(@as(usize, 0), app.settings_editor.?.form_row);
    const form_body = app.settingsBody();
    var wheel = std.mem.zeroes(c.SDL_MouseWheelEvent);
    wheel.y = -2;
    wheel.mouse_x = form_body.x + 60;
    wheel.mouse_y = form_body.y + 60;
    try app.pointerWheel(wheel);
    try std.testing.expectEqual(@as(f32, 96), app.settings_scroll_offset);
    wheel.mouse_x = form_body.x - 10;
    try app.pointerWheel(wheel);
    try std.testing.expectEqual(@as(f32, 96), app.settings_scroll_offset);
    app.settings_scroll_offset = 0;
    const edit_button = App.settingsEditButton(row);
    try app.settingsClick(edit_button.x + 8, edit_button.y + 8, 1);
    try std.testing.expectEqual(settings.Target.hide_single_tab, app.settings_editor.?.editing.?);
    const edited_row = app.appearanceForm().row(0);
    const field = app.settingsField();
    try std.testing.expectEqualDeep(App.settingsRowField(edited_row), field);
    try std.testing.expect(field.x >= edited_row.x and field.x + field.width <= edited_row.x + edited_row.width);
    try std.testing.expect(field.y >= edited_row.y and field.y + field.height <= edited_row.y + edited_row.height);
    try app.settingsClick(field.x + 2, field.y + 2, 1);
    try std.testing.expect(app.settings_editor.?.editing == null);
    const bar = app.appearanceForm().view.scrollbar().?;
    try std.testing.expect(app.settingsScrollbarPress(bar.track.x - 5, bar.track.y + bar.track.height - 5));
    try std.testing.expect(app.settings_scroll_offset > 0);
    app.settingsScrollbarMove(bar.track.y + 5);
    try std.testing.expectEqual(@as(f32, 0), app.settings_scroll_offset);
    app.settings_scroll_grab = null;

    app.init.io = std.testing.io;
    app.settings_editor.?.page = .colors;
    try std.testing.expectEqual(ColorForm.count, app.settings_editor.?.indices(all[0..count], &indices));
    try std.testing.expectEqualDeep(settings.Target.theme, all[indices[0]].target);
    try std.testing.expectEqualDeep(settings.Target.reset_app_colors, all[indices[ColorForm.app_count - 1]].target);
    try std.testing.expectEqualDeep(settings.Target.terminal_theme, all[indices[ColorForm.app_count]].target);
    try std.testing.expectEqualDeep(settings.Target.reset_terminal_colors, all[indices[ColorForm.count - 2]].target);
    const color_label = app.colorForm().row(1);
    try app.settingsClick(color_label.x + 8, color_label.y + 12, 1);
    try std.testing.expect(app.settings_editor.?.editing == null and app.settings_draft == null);
    const color_edit = App.settingsEditButton(color_label);
    try app.settingsClick(color_edit.x + 8, color_edit.y + 8, 1);
    try std.testing.expectEqualDeep(settings.Target{ .app_color = 0 }, app.settings_editor.?.editing.?);
    try std.testing.expectEqualDeep(App.settingsRowField(app.colorForm().row(1)), app.settingsField());
    const red_bar = app.colorBar(0);
    try app.settingsClick(red_bar.x + red_bar.width / 2, red_bar.y + 8, 1);
    try std.testing.expectEqual(@as(?u8, 0), app.color_drag);
    try std.testing.expectEqual(@as(usize, 7), app.settings_editor.?.len);
    try std.testing.expectEqual(@as(u8, '#'), app.settings_editor.?.buffer[0]);
    app.color_drag = null;
    var event_value = std.mem.zeroes(c.SDL_KeyboardEvent);
    event_value.key = c.SDLK_ESCAPE;
    try app.settingsKey(event_value);
    try std.testing.expect(app.settings_editor.?.editing == null);
    app.settings_scroll_offset = ColorForm.rowTop(ColorForm.app_count - 1) - 100;
    const app_reset = app.colorForm().row(ColorForm.app_count - 1);
    try std.testing.expect(app.settingsBody().contains(app_reset.x + 8, app_reset.y + 10));
    try app.settingsClick(app_reset.x + 8, app_reset.y + 10, 1);
    try std.testing.expect(app.settings_draft == null);
    const reset_button = App.settingsResetButton(app_reset);
    try app.settingsClick(reset_button.x + 8, reset_button.y + 8, 1);
    try std.testing.expect(app.settings_draft != null);
    app.settingsCancel();
    try std.testing.expect(app.settings_draft == null);
    app.settings_scroll_offset = ColorForm.rowTop(ColorForm.count - 2) - 100;
    const terminal_reset = app.colorForm().row(ColorForm.count - 2);
    try std.testing.expect(app.settingsBody().contains(terminal_reset.x + 8, terminal_reset.y + 10));
    try app.settingsClick(terminal_reset.x + 8, terminal_reset.y + 10, 1);
    try std.testing.expect(app.settings_draft == null);
    const terminal_reset_button = App.settingsResetButton(terminal_reset);
    try app.settingsClick(terminal_reset_button.x + 8, terminal_reset_button.y + 8, 1);
    try std.testing.expect(app.settings_draft != null);
    app.settingsCancel();
    app.settings_scroll_offset = 0;
    const color_body = app.settingsBody();
    wheel.mouse_x = color_body.x + 60;
    wheel.mouse_y = color_body.y + 60;
    try app.pointerWheel(wheel);
    try std.testing.expectEqual(@as(f32, 96), app.settings_scroll_offset);
    app.settings_scroll_offset = 0;
    const color_bar = app.colorForm().view.scrollbar().?;
    try std.testing.expect(app.settingsScrollbarPress(color_bar.track.x - 5, color_bar.track.y + color_bar.track.height - 5));
    try std.testing.expect(app.settings_scroll_offset > 0);
    app.settings_scroll_grab = null;
}
