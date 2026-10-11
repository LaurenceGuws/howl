const std = @import("std");
const c = @import("desktop");
const config = @import("config.zig");

const family_limit = 256;
const path_limit = 512;
const Family = struct {
    name_bytes: [128]u8 = undefined,
    name_len: u8 = 0,
    paths: [4][path_limit]u8 = undefined,
    lengths: [4]u16 = @splat(0),
    scores: [4]u8 = @splat(0),

    fn name(self: *const Family) []const u8 {
        return self.name_bytes[0..self.name_len];
    }
    fn path(self: *const Family, index: usize) []const u8 {
        return self.paths[index][0..self.lengths[index]];
    }
};

/// Bounded installed-family chooser; owns its catalogue and cancellation recipe.
pub const Chooser = struct {
    original: config.Config,
    families: [family_limit]Family = undefined,
    count: u16 = 0,
    results: [family_limit]u16 = undefined,
    result_count: u16 = 0,
    selected: u16 = 0,
    query: [128]u8 = undefined,
    query_len: u8 = 0,
    truncated: bool = false,
    previewed: bool = false,
    sample_font: ?*c.TTF_Font = null,
    sample_index: ?u16 = null,
    sample_scale: f32 = 0,

    /// Copies the cancellation recipe before querying owned terminal-width font families.
    pub fn create(allocator: std.mem.Allocator, io: std.Io, current: *const config.Config, regular: []const u8) !*Chooser {
        const self = try allocator.create(Chooser);
        errdefer allocator.destroy(self);
        self.* = .{ .original = try config.Config.fromValue(allocator, io, current.value) };
        errdefer self.original.deinit();
        try self.load();
        self.refresh();
        for (self.results[0..self.result_count], 0..) |index, number| {
            if (std.mem.eql(u8, self.families[index].path(0), regular)) self.selected = @intCast(number);
        }
        return self;
    }
    /// Closes the sample and retires the original config after commit/cancellation or app shutdown.
    pub fn destroy(self: *Chooser, allocator: std.mem.Allocator) void {
        if (self.sample_font) |font| c.TTF_CloseFont(font);
        self.original.deinit();
        allocator.destroy(self);
    }
    fn add(self: *Chooser, name: []const u8, style: []const u8, path: []const u8, spacing: c_int) void {
        if (spacing != c.FC_MONO and spacing != c.FC_DUAL) return;
        if (name.len == 0 or name.len >= 128 or !std.unicode.utf8ValidateSlice(name) or
            path.len == 0 or path.len >= path_limit or path[0] != '/' or !std.unicode.utf8ValidateSlice(path)) return;
        var index: usize = 0;
        while (index < self.count and !std.ascii.eqlIgnoreCase(self.families[index].name(), name)) : (index += 1) {}
        if (index == self.count) {
            if (self.count == family_limit) {
                self.truncated = true;
                return;
            }
            self.families[index] = .{};
            @memcpy(self.families[index].name_bytes[0..name.len], name);
            self.families[index].name_len = @intCast(name.len);
            self.count += 1;
        }
        var slot: usize = 0;
        var score: u8 = regularScore(style);
        if (std.ascii.eqlIgnoreCase(style, "Italic")) {
            slot = 1;
            score = 2;
        } else if (std.ascii.eqlIgnoreCase(style, "Oblique")) {
            slot = 1;
            score = 1;
        } else if (std.ascii.eqlIgnoreCase(style, "Bold")) {
            slot = 2;
            score = 2;
        } else if (std.ascii.eqlIgnoreCase(style, "Bold Italic")) {
            slot = 3;
            score = 2;
        } else if (std.ascii.eqlIgnoreCase(style, "Bold Oblique")) {
            slot = 3;
            score = 1;
        }
        const family = &self.families[index];
        if (score == 0 or score < family.scores[slot] or
            (score == family.scores[slot] and std.mem.order(u8, path, family.path(slot)) != .lt)) return;
        @memcpy(family.paths[slot][0..path.len], path);
        family.lengths[slot] = @intCast(path.len);
        family.scores[slot] = score;
    }
    fn load(self: *Chooser) !void {
        if (c.FcInit() == 0) return error.Fontconfig;
        const query = c.FcPatternCreate() orelse return error.FontPattern;
        defer c.FcPatternDestroy(query);
        const objects = c.FcObjectSetCreate() orelse return error.FontPattern;
        defer c.FcObjectSetDestroy(objects);
        for ([_][*:0]const u8{ c.FC_FAMILY, c.FC_STYLE, c.FC_FILE, c.FC_SPACING }) |name| {
            if (c.FcObjectSetAdd(objects, name) == 0) return error.FontPattern;
        }
        const found = c.FcFontList(null, query, objects) orelse return error.FontCatalogue;
        defer c.FcFontSetDestroy(found);
        if (found.*.nfont < 0 or found.*.nfont > 16 * 1024) return error.FontCatalogueLimit;
        for (0..@as(usize, @intCast(found.*.nfont))) |i| {
            const font = found.*.fonts[i];
            var name: [*c]u8 = null;
            var style: [*c]u8 = null;
            var path: [*c]u8 = null;
            var spacing: c_int = 0;
            if (c.FcPatternGetString(font, c.FC_FAMILY, 0, &name) != c.FcResultMatch or name == null or
                c.FcPatternGetString(font, c.FC_STYLE, 0, &style) != c.FcResultMatch or style == null or
                c.FcPatternGetString(font, c.FC_FILE, 0, &path) != c.FcResultMatch or path == null or
                c.FcPatternGetInteger(font, c.FC_SPACING, 0, &spacing) != c.FcResultMatch) continue;
            self.add(std.mem.span(name), std.mem.span(style), std.mem.span(path), spacing);
        }
        var count: u16 = 0;
        for (self.families[0..self.count]) |family| if (family.lengths[0] != 0) {
            self.families[count] = family;
            count += 1;
        };
        self.count = count;
        std.mem.sort(Family, self.families[0..self.count], {}, less);
        if (self.count == 0) return error.FontMissing;
    }
    /// Strong case-insensitive substrings precede fuzzy subsequences in alphabetic family order.
    pub fn refresh(self: *Chooser) void {
        self.result_count = 0;
        const query = self.query[0..self.query_len];
        for (0..2) |pass| for (self.families[0..self.count], 0..) |*family, index| {
            const strong = contains(family.name(), query);
            if ((pass == 0 and strong) or (pass == 1 and !strong and subsequence(family.name(), query))) {
                self.results[self.result_count] = @intCast(index);
                self.result_count += 1;
            }
        };
        self.selected = @min(self.selected, self.result_count -| 1);
    }
    /// Adds complete UTF-8 query text within the fixed byte budget.
    pub fn append(self: *Chooser, text: []const u8) !void {
        if (text.len > self.query.len - 1 - self.query_len) return error.FontQueryLimit;
        if (!std.unicode.utf8ValidateSlice(text) or std.mem.indexOfScalar(u8, text, 0) != null) return error.InvalidFontQuery;
        @memcpy(self.query[self.query_len..][0..text.len], text);
        self.query_len += @intCast(text.len);
        self.selected = 0;
        self.refresh();
    }
    /// Removes one complete query scalar.
    pub fn backspace(self: *Chooser) void {
        if (self.query_len == 0) return;
        self.query_len -= 1;
        while (self.query_len != 0 and self.query[self.query_len] & 0xc0 == 0x80) self.query_len -= 1;
        self.selected = 0;
        self.refresh();
    }
    /// Moves within the exact result set without wrapping.
    pub fn move(self: *Chooser, delta: i16) void {
        self.selected = @intCast(std.math.clamp(@as(i32, self.selected) + delta, 0, self.result_count -| 1));
    }
    /// Borrows an owned name for one validated result row.
    pub fn label(self: *const Chooser, result: u16) error{InvalidFontSelection}![]const u8 {
        if (result >= self.result_count) return error.InvalidFontSelection;
        return self.families[self.results[result]].name();
    }
    /// Borrows the exact owned regular path for the currently selected result.
    pub fn regularPath(self: *const Chooser) error{InvalidFontSelection}![]const u8 {
        if (self.selected >= self.result_count) return error.InvalidFontSelection;
        return self.families[self.results[self.selected]].path(0);
    }
    /// Builds an owned exact four-face candidate while preserving the original fallback recipe.
    pub fn candidate(self: *const Chooser, allocator: std.mem.Allocator, io: std.Io) !config.Config {
        if (self.selected >= self.result_count) return error.InvalidFontSelection;
        const family = &self.families[self.results[self.selected]];
        var value = self.original.value;
        value.font.regular = family.path(0);
        value.font.italic = family.path(1);
        value.font.bold = family.path(2);
        value.font.bold_italic = family.path(3);
        return config.Config.fromValue(allocator, io, value);
    }
    /// Owns one sample font independently of the terminal transaction and rescales it for the display.
    pub fn sample(self: *Chooser, scale: f32) !?*c.TTF_Font {
        if (self.selected >= self.result_count) return null;
        const index = self.results[self.selected];
        if (self.sample_index != index) {
            const family = &self.families[index];
            var path: [path_limit:0]u8 = undefined;
            @memcpy(path[0..family.lengths[0]], family.path(0));
            path[family.lengths[0]] = 0;
            const font = c.TTF_OpenFont(&path, 22 * scale) orelse return error.TTF;
            if (self.sample_font) |old| c.TTF_CloseFont(old);
            self.sample_font = font;
            self.sample_index = index;
            self.sample_scale = scale;
        }
        if (self.sample_scale != scale) {
            if (!c.TTF_SetFontSize(self.sample_font.?, 22 * scale)) return error.TTF;
            self.sample_scale = scale;
        }
        return self.sample_font;
    }
};

fn regularScore(style: []const u8) u8 {
    if (std.ascii.eqlIgnoreCase(style, "Regular")) return 4;
    for ([_][]const u8{ "Italic", "Oblique", "Bold", "Black" }) |word| if (contains(style, word)) return 0;
    if (contains(style, "Regular")) return 3;
    for ([_][]const u8{ "Medium", "Book", "Retina" }) |word| if (contains(style, word)) return 2;
    return 1;
}
fn contains(name: []const u8, query: []const u8) bool {
    if (query.len > name.len) return false;
    for (0..name.len - query.len + 1) |i| if (std.ascii.eqlIgnoreCase(name[i..][0..query.len], query)) return true;
    return false;
}
fn subsequence(name: []const u8, query: []const u8) bool {
    var i: usize = 0;
    for (name) |byte| if (i < query.len and std.ascii.toLower(byte) == std.ascii.toLower(query[i])) {
        i += 1;
    };
    return i == query.len;
}
fn less(_: void, left: Family, right: Family) bool {
    return std.ascii.orderIgnoreCase(left.name(), right.name()) == .lt;
}

test "terminal-family catalogue owns exact styles and ranks substring before fuzzy matches" {
    const a = std.testing.allocator;
    const io = std.testing.io;
    const font = try std.Io.Dir.cwd().realPathFileAlloc(io, @import("test_fonts").primary_font, a);
    defer a.free(font);
    var current = config.Config.defaults(a);
    defer current.deinit();
    const chooser = try a.create(Chooser);
    defer a.destroy(chooser);
    chooser.* = .{ .original = try config.Config.fromValue(a, io, current.value) };
    defer chooser.original.deinit();
    chooser.add("Zulu Mono", "Regular", "/fonts/zulu.ttf", c.FC_MONO);
    chooser.add("Alpha Mono", "Bold Italic", font, c.FC_DUAL);
    chooser.add("Alpha Mono", "Book", "/fonts/alpha-book.ttf", c.FC_DUAL);
    chooser.add("Alpha Mono", "Regular", font, c.FC_DUAL);
    chooser.add("Alpha Mono", "Oblique", "/fonts/alpha-oblique.ttf", c.FC_DUAL);
    chooser.add("Alpha Mono", "Italic", font, c.FC_DUAL);
    chooser.add("Proportional", "Regular", "/fonts/proportional.ttf", 0);
    chooser.add("JetBrains Mono", "Regular", "/fonts/jetbrains.ttf", c.FC_MONO);
    std.mem.sort(Family, chooser.families[0..chooser.count], {}, less);
    chooser.refresh();
    try std.testing.expectEqual(@as(u16, 3), chooser.count);
    try std.testing.expectEqualStrings("Alpha Mono", try chooser.label(0));
    var candidate = try chooser.candidate(a, io);
    defer candidate.deinit();
    try std.testing.expectEqualStrings(font, candidate.value.font.regular);
    try std.testing.expectEqualStrings(font, candidate.value.font.italic);
    try std.testing.expectEqualStrings(font, candidate.value.font.bold_italic);
    try chooser.append("jm");
    try std.testing.expectEqual(@as(u16, 1), chooser.result_count);
    try std.testing.expectEqualStrings("JetBrains Mono", try chooser.label(0));
    chooser.query_len = 0;
    try chooser.append("Mono");
    try std.testing.expectEqual(@as(u16, 3), chooser.result_count);
    chooser.move(300);
    try std.testing.expectEqual(@as(u16, 2), chooser.selected);
    chooser.move(-300);
    try std.testing.expectEqual(@as(u16, 0), chooser.selected);
    chooser.query_len = 0;
    try chooser.append("中");
    chooser.backspace();
    try std.testing.expectEqual(@as(u8, 0), chooser.query_len);
    try std.testing.expectError(error.InvalidFontQuery, chooser.append("\xff"));
    var full: [128]u8 = @splat('x');
    try std.testing.expectError(error.FontQueryLimit, chooser.append(&full));
    try chooser.append("no installed result");
    try std.testing.expectError(error.InvalidFontSelection, chooser.candidate(a, io));
}

fn candidateOwnershipProof(a: std.mem.Allocator) !void {
    const io = std.testing.io;
    const font = try std.Io.Dir.cwd().realPathFileAlloc(io, @import("test_fonts").primary_font, a);
    defer a.free(font);
    const chooser = try a.create(Chooser);
    defer a.destroy(chooser);
    var original = config.Config.defaults(a);
    original.value.font.fallback = font;
    original.value.font.secondary_fallback = font;
    chooser.* = .{ .original = try config.Config.fromValue(a, io, original.value) };
    defer chooser.original.deinit();
    const path = try a.dupe(u8, font);
    defer a.free(path);
    chooser.add("Owned Mono", "Regular", path, c.FC_MONO);
    @memset(path, 'x');
    chooser.refresh();
    var candidate = try chooser.candidate(a, io);
    defer candidate.deinit();
    @memset(chooser.families[0].paths[0][0..chooser.families[0].lengths[0]], 'y');
    try std.testing.expectEqualStrings(font, candidate.value.font.regular);
    try std.testing.expectEqualStrings(font, candidate.value.font.fallback);
    try std.testing.expectEqualStrings(font, candidate.value.font.secondary_fallback);
}
test "font recipe candidates own catalogue strings and survive every partial allocation failure" {
    try candidateOwnershipProof(std.testing.allocator);
    try std.testing.checkAllAllocationFailures(std.testing.allocator, candidateOwnershipProof, .{});
}
test "font catalogue and query bounds reject overlong paths without inventing a selection" {
    const a = std.testing.allocator;
    const chooser = try a.create(Chooser);
    defer a.destroy(chooser);
    chooser.* = .{ .original = config.Config.defaults(a) };
    defer chooser.original.deinit();
    var path: [512]u8 = @splat('x');
    path[0] = '/';
    chooser.add("Too long", "Regular", &path, c.FC_MONO);
    try std.testing.expectEqual(@as(u16, 0), chooser.count);
    for (0..family_limit) |number| {
        var name: [32]u8 = undefined;
        chooser.add(try std.fmt.bufPrint(&name, "Mono {d}", .{number}), "Regular", "/font.ttf", c.FC_MONO);
    }
    chooser.add("Overflow", "Regular", "/font.ttf", c.FC_MONO);
    try std.testing.expectEqual(@as(u16, family_limit), chooser.count);
    try std.testing.expect(chooser.truncated);
    chooser.add("Mono 0", "Bold", "/font-bold.ttf", c.FC_MONO);
    try std.testing.expectEqualStrings("/font-bold.ttf", chooser.families[0].path(2));
    chooser.refresh();
    try std.testing.expectEqual(@as(u16, family_limit), chooser.result_count);
    try chooser.append("No result");
    chooser.move(100);
    try std.testing.expectEqual(@as(u16, 0), chooser.selected);
    try std.testing.expectError(error.InvalidFontSelection, chooser.regularPath());
}
