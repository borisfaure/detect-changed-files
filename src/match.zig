// match.zig
// Do pattern matching on strings
const std = @import("std");
const Allocator = std.mem.Allocator;
const unicode_zig = @import("unicode.zig");
const u8ToU21Comptime = unicode_zig.u8ToU21Comptime;
const u8ToU21 = unicode_zig.u8ToU21;

pub const PathComponent = struct {
    str: []const u21,

    fn isDoubleStar(self: PathComponent) bool {
        return self.str.len == 2 and self.str[0] == '*' and self.str[1] == '*';
    }

    pub fn init(allocator: Allocator, str: []const u21) !PathComponent {
        return PathComponent{
            .str = try allocator.dupe(u21, str),
        };
    }
    pub fn createInit(allocator: Allocator, str: []const u8) !*PathComponent {
        const self = try allocator.create(PathComponent);
        self.* = PathComponent.init(allocator, try u8ToU21(allocator, str)) catch |err| {
            allocator.destroy(self);
            return err;
        };
        return self;
    }

    pub fn deinit(self: PathComponent, allocator: Allocator) void {
        allocator.free(self.str);
    }
    pub fn destroy(self: *PathComponent, allocator: Allocator) void {
        self.deinit(allocator);
        allocator.destroy(self);
    }
};

pub const MatchPath = struct {
    components: []PathComponent,

    pub fn init(allocator: Allocator, path: []const u21) !MatchPath {
        const components = try splitPathComponents(allocator, path);
        return MatchPath{
            .components = components,
        };
    }

    pub fn initU8(allocator: Allocator, path: []const u8) !MatchPath {
        const path_u21 = try u8ToU21(allocator, path);
        defer allocator.free(path_u21);
        return MatchPath.init(allocator, path_u21);
    }

    pub fn createInitU8(allocator: Allocator, path: []const u8) !*MatchPath {
        const self = try allocator.create(MatchPath);
        self.* = MatchPath.initU8(allocator, path) catch |err| {
            allocator.destroy(self);
            return err;
        };
        return self;
    }

    pub fn deinit(self: MatchPath, allocator: Allocator) void {
        for (self.components) |*comp| {
            comp.deinit(allocator);
        }
        allocator.free(self.components);
    }
    pub fn destroy(self: *MatchPath, allocator: Allocator) void {
        self.deinit(allocator);
        allocator.destroy(self);
    }
};

// Split a string into path components
fn splitPathComponents(allocator: Allocator, path: []const u21) ![]PathComponent {
    var components = std.ArrayList(PathComponent).init(allocator);
    defer components.deinit();

    var start: usize = 0;
    var i: usize = 0;
    for (path) |c| {
        if (c == '/') {
            if (i > start) {
                const comp = try PathComponent.init(allocator, path[start..i]);
                try components.append(comp);
            }
            start = i + 1; // skip the '/'
        }
        i += 1;
    }
    // Add last component if not empty
    if (start < path.len) {
        const comp = try PathComponent.init(allocator, path[start..]);
        try components.append(comp);
    }

    return components.toOwnedSlice();
}

fn matchPatternComponent(allocator: Allocator, pattern: []const u21, text: []const u21) !bool {
    // Create memoization table
    var memo = std.AutoHashMap(usize, bool).init(allocator);
    defer memo.deinit();

    return matchRecursiveMemo(pattern, text, 0, 0, &memo);
}

fn matchRecursiveMemo(pattern: []const u21, text: []const u21, p_idx: usize, t_idx: usize, memo: *std.AutoHashMap(usize, bool)) !bool {
    // Create unique key for this state
    const key = p_idx * 10000 + t_idx;

    // Check memoization
    if (memo.get(key)) |result| return result;

    // Base cases
    if (p_idx == pattern.len) {
        const result = t_idx == text.len;
        try memo.put(key, result);
        return result;
    }

    if (t_idx == text.len) {
        // If we're at end of text, pattern must be all * from here
        var result = true;
        for (pattern[p_idx..]) |c| {
            if (c != '*') {
                result = false;
                break;
            }
        }
        try memo.put(key, result);
        return result;
    }

    var match_result = false;
    switch (pattern[p_idx]) {
        '*' => {
            // Try matching 0, 1, 2, ... characters
            var i: usize = 0;
            while (t_idx + i <= text.len) : (i += 1) {
                if (try matchRecursiveMemo(pattern, text, p_idx + 1, t_idx + i, memo)) {
                    match_result = true;
                    break;
                }
            }
        },
        '?' => {
            // Match exactly one character
            match_result = try matchRecursiveMemo(pattern, text, p_idx + 1, t_idx + 1, memo);
        },
        else => {
            // Exact character match
            if (t_idx < text.len and pattern[p_idx] == text[t_idx]) {
                match_result = try matchRecursiveMemo(pattern, text, p_idx + 1, t_idx + 1, memo);
            }
        },
    }

    try memo.put(key, match_result);
    return match_result;
}

fn testMatchPatternComponent(comptime pattern: []const u8, comptime text: []const u8) !bool {
    const allocator = std.testing.allocator;
    const pattern_u21 = comptime u8ToU21Comptime(pattern);
    const text_u21 = comptime u8ToU21Comptime(text);
    return matchPatternComponent(allocator, pattern_u21, text_u21);
}
test "Component: multiple star wildcards" {
    try std.testing.expect(try testMatchPatternComponent("a*b*c", "a123b456c"));
    try std.testing.expect(try testMatchPatternComponent("a*b*c", "abc"));
    try std.testing.expect(!try testMatchPatternComponent("a*b*c", "a123b456c789"));
    try std.testing.expect(!try testMatchPatternComponent("a*b*c", "a123d456c")); // missing 'b'
    try std.testing.expect(!try testMatchPatternComponent("a*b*c", "a123b")); // missing 'c'
    try std.testing.expect(try testMatchPatternComponent("*", "anything"));
    try std.testing.expect(try testMatchPatternComponent("a*", "a"));
    try std.testing.expect(try testMatchPatternComponent("*a", "a"));
    try std.testing.expect(try testMatchPatternComponent("a*b*", "ab"));
}
test "Component: ? wildcard" {
    try std.testing.expect(try testMatchPatternComponent("a?b", "a1b"));
    try std.testing.expect(!try testMatchPatternComponent("a?b", "ab")); // '?' does not match empty
    try std.testing.expect(!try testMatchPatternComponent("a?b", "abx")); // too long
    try std.testing.expect(try testMatchPatternComponent("a?b", "acb"));
    try std.testing.expect(try testMatchPatternComponent("a?b?", "a1b2"));
    try std.testing.expect(!try testMatchPatternComponent("a?b?", "a1b"));
    try std.testing.expect(!try testMatchPatternComponent("a?b?", "a1b2c")); // too long
}
test "Component: exact match" {
    try std.testing.expect(try testMatchPatternComponent("abc", "abc"));
    try std.testing.expect(!try testMatchPatternComponent("abc", "abcd")); // too long
    try std.testing.expect(!try testMatchPatternComponent("abc", "ab")); // too short
    try std.testing.expect(!try testMatchPatternComponent("abc", "abx")); // wrong character
    try std.testing.expect(try testMatchPatternComponent("a?c", "abc")); // '?' matches 'b'
}
test "Component: complex patterns" {
    try std.testing.expect(try testMatchPatternComponent("a*b?c", "a123b4c"));
    try std.testing.expect(!try testMatchPatternComponent("a*b?c", "a123b456c"));
    try std.testing.expect(try testMatchPatternComponent("a*b?c?d*", "a123b4c7d89"));
    try std.testing.expect(!try testMatchPatternComponent("a*b?c", "a123b456c789"));
    try std.testing.expect(!try testMatchPatternComponent("a*b?c", "a123d456c")); // missing 'b'
    try std.testing.expect(!try testMatchPatternComponent("a*b?c", "a123b")); // missing 'c'
    try std.testing.expect(try testMatchPatternComponent("a*b?c*", "a123b4c56"));
    try std.testing.expect(!try testMatchPatternComponent("a*b?c*", "a123b456d789")); // wrong character
}

test "Split path components" {
    const allocator = std.testing.allocator;
    const path = comptime u8ToU21Comptime("ab/cd/ef/gh/ij");
    const components = try splitPathComponents(allocator, path);
    defer {
        for (components) |*comp| {
            comp.deinit(allocator);
        }
        allocator.free(components);
    }

    try std.testing.expectEqual(components.len, 5);
}
