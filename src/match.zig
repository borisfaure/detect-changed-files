// match.zig
// Do pattern matching on strings
const std = @import("std");
const Allocator = std.mem.Allocator;
const u8ToU21Comptime = @import("unicode.zig").u8ToU21Comptime;

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
