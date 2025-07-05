const std = @import("std");

// Function to convert UTF-8 string to []const u21 at comptime
pub fn u8ToU21Comptime(comptime utf8_str: []const u8) []const u21 {
    const utf8_view = std.unicode.Utf8View.init(utf8_str) catch unreachable;

    // Count the number of codepoints first
    comptime var count: usize = 0;
    {
        var iter = utf8_view.iterator();
        while (iter.nextCodepoint()) |_| {
            count += 1;
        }
    }

    // Create a const global array that persists at runtime
    const result = blk: {
        var temp: [count]u21 = undefined;
        var i: usize = 0;
        var iter = utf8_view.iterator();
        while (iter.nextCodepoint()) |codepoint| {
            temp[i] = codepoint;
            i += 1;
        }
        break :blk temp;
    };

    return &result;
}
