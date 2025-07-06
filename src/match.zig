// match.zig
// Do pattern matching on strings
const std = @import("std");
const Allocator = std.mem.Allocator;
const unicode_zig = @import("unicode.zig");
const u8ToU21Comptime = unicode_zig.u8ToU21Comptime;
const u8ToU21 = unicode_zig.u8ToU21;

// PATTERN FORMAT
//  - The slash "/" is used as the directory separator. Patterns must not
//    start with a slash.
//  - An asterisk "*" matches anything except a slash. The character "?"
//    matches any one character except "/".
//  - Two consecutive asterisks ("**") in patterns match against many
//    successive path components

pub const PathComponent = struct {
    str: []const u21,
    allocator: Allocator,

    fn isDoubleStar(self: PathComponent) bool {
        return self.str.len == 2 and self.str[0] == '*' and self.str[1] == '*';
    }

    pub fn init(allocator: Allocator, str: []const u21) !PathComponent {
        return PathComponent{
            .str = try allocator.dupe(u21, str),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: PathComponent) void {
        self.allocator.free(self.str);
    }
};

pub const MatchPath = struct {
    components: []PathComponent,
    allocator: Allocator,

    pub fn init(allocator: Allocator, path: []const u21) !MatchPath {
        const components = try splitPathComponents(allocator, path);
        return MatchPath{
            .components = components,
            .allocator = allocator,
        };
    }

    pub fn initU8(allocator: Allocator, path: []const u8) !MatchPath {
        const path_u21 = try u8ToU21(allocator, path);
        defer allocator.free(path_u21);
        return MatchPath.init(allocator, path_u21);
    }

    pub fn deinit(self: MatchPath) void {
        for (self.components) |*comp| {
            comp.deinit();
        }
        self.allocator.free(self.components);
    }

    // Check if the path matches the given text
    // self is the pattern, text is the string to match against
    pub fn isMatch(self: MatchPath, allocator: Allocator, text: MatchPath) bool {

        // If the pattern has no components, it matches only if text is empty
        if (self.components.len == 0) return text.components.len == 0;

        // index in self.components
        var pattern_idx: usize = 0;
        // index in text.components
        var text_idx: usize = 0;

        var is_double_star: bool = false;
        // Iterate through both components
        while (pattern_idx < self.components.len and text_idx < text.components.len) {
            const pattern_comp = self.components[pattern_idx];
            const text_comp = text.components[text_idx];

            // If the pattern component is a double star, it matches anything
            if (pattern_comp.isDoubleStar()) {
                is_double_star = true;
                if (pattern_idx + 1 == self.components.len) {
                    // If this is the last pattern component, it matches everything
                    return true;
                }
                pattern_idx += 1; // Move to the next pattern component
                text_idx += 1; // Move to the next text component
                continue;
            }

            if (matchPatternComponent(
                allocator,
                pattern_comp.str,
                text_comp.str,
            ) catch |err| {
                std.debug.print("Error matching pattern component: {}\n", .{err});
                return false;
            } == false) {
                // If the current components do not match, check if we had a double star
                if (is_double_star) {
                    // If we had a double star, we can skip this text component
                    text_idx += 1;
                    continue;
                }
                // Otherwise, the match fails
                return false;
            } else {
                // There is a match!
                // Reset double star flag
                is_double_star = false;

                // Move to the next components in both
                pattern_idx += 1;
                text_idx += 1;
                continue;
            }
        }
        if ((pattern_idx < self.components.len) or (text_idx < text.components.len)) {
            // If we still have pattern or text components left, it means we didn't match all components
            return false;
        }
        // If we reached here, all components matched
        return true;
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
            comp.deinit();
        }
        allocator.free(components);
    }

    try std.testing.expectEqual(components.len, 5);
}

test "MatchPath: pattern == text" {
    const allocator = std.testing.allocator;

    const pattern = try MatchPath.initU8(allocator, "ab/cd/ef.zig");
    defer pattern.deinit();

    const text = try MatchPath.initU8(allocator, "ab/cd/ef.zig");
    defer text.deinit();
    try std.testing.expect(pattern.isMatch(allocator, text));

    const nope = try MatchPath.initU8(allocator, "ab/cd/ef.ghi");
    defer nope.deinit();
    try std.testing.expect(!pattern.isMatch(allocator, nope));
}

test "MatchPath: leading **" {
    const allocator = std.testing.allocator;

    const pattern = try MatchPath.initU8(allocator, "**/ef.zig");
    defer pattern.deinit();

    const single = try MatchPath.initU8(allocator, "foo/ef.zig");
    defer single.deinit();
    try std.testing.expect(pattern.isMatch(allocator, single));

    const multiple = try MatchPath.initU8(allocator, "ab/cd/ef.zig");
    defer multiple.deinit();
    try std.testing.expect(pattern.isMatch(allocator, multiple));

    const nope = try MatchPath.initU8(allocator, "ef.zig");
    defer nope.deinit();
    try std.testing.expect(!pattern.isMatch(allocator, nope));
}

test "MatchPath: trailing **" {
    const allocator = std.testing.allocator;

    const pattern = try MatchPath.initU8(allocator, "ab/cd/**");
    defer pattern.deinit();

    const single = try MatchPath.initU8(allocator, "ab/cd/ef.zig");
    defer single.deinit();
    try std.testing.expect(pattern.isMatch(allocator, single));

    const multiple = try MatchPath.initU8(allocator, "ab/cd/ef/gh.zig");
    defer multiple.deinit();
    try std.testing.expect(pattern.isMatch(allocator, multiple));

    const nope = try MatchPath.initU8(allocator, "ab/cd");
    defer nope.deinit();
    try std.testing.expect(!pattern.isMatch(allocator, nope));
}

test "MatchPath: ** in the middle" {
    const allocator = std.testing.allocator;

    const pattern = try MatchPath.initU8(allocator, "ab/**/cd/ef.zig");
    defer pattern.deinit();

    const single = try MatchPath.initU8(allocator, "ab/foo/cd/ef.zig");
    defer single.deinit();
    try std.testing.expect(pattern.isMatch(allocator, single));

    const multiple = try MatchPath.initU8(allocator, "ab/foo/bar/cd/ef.zig");
    defer multiple.deinit();
    try std.testing.expect(pattern.isMatch(allocator, multiple));

    const nope = try MatchPath.initU8(allocator, "ab/cd/ef.zig");
    defer nope.deinit();
    try std.testing.expect(!pattern.isMatch(allocator, nope));
}

test "MatchPath: complex pattern with ** and ?" {
    const allocator = std.testing.allocator;

    const pattern = try MatchPath.initU8(allocator, "ab/cd/**/e?f/gh.zig");
    defer pattern.deinit();

    const single = try MatchPath.initU8(allocator, "ab/cd/foo/e3f/gh.zig");
    defer single.deinit();
    try std.testing.expect(pattern.isMatch(allocator, single));

    const nope = try MatchPath.initU8(allocator, "ab/cd/foo/e33f/gh.zig");
    defer nope.deinit();
    try std.testing.expect(!pattern.isMatch(allocator, nope));
}

test "MatchPath: double **" {
    const allocator = std.testing.allocator;

    const pattern = try MatchPath.initU8(allocator, "ab/**/cd/**/ef.zig");
    defer pattern.deinit();

    const single = try MatchPath.initU8(allocator, "ab/foo/cd/bar/ef.zig");
    defer single.deinit();
    try std.testing.expect(pattern.isMatch(allocator, single));

    const multiple = try MatchPath.initU8(allocator, "ab/foo/cd/bar/baz/ef.zig");
    defer multiple.deinit();
    try std.testing.expect(pattern.isMatch(allocator, multiple));

    const nope = try MatchPath.initU8(allocator, "ab/cd/ef.zig");
    defer nope.deinit();
    try std.testing.expect(!pattern.isMatch(allocator, nope));
}

test "MatchPath: with utf-8 strings" {
    const allocator = std.testing.allocator;

    // Test with UTF-8 strings
    const pattern = try MatchPath.initU8(allocator, "ab/**/e⚡f/g?h/ij.zig");
    defer pattern.deinit();

    const text = try MatchPath.initU8(allocator, "ab/⚡/e⚡f/g⚡h/ij.zig");
    defer text.deinit();
    try std.testing.expect(pattern.isMatch(allocator, text));
}
