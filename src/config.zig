const std = @import("std");
const Yaml = @import("yaml").Yaml;
const Unicode = @import("unicode.zig");
const match = @import("match.zig");
const PathComponent = match.PathComponent;
const MatchPath = match.MatchPath;

/// Represents the structure of changed-files.yaml
/// Each key maps to a list of file patterns
pub const ChangedFilesConfig = struct {
    map: std.StringHashMap([]const MatchPath),

    pub fn init(allocator: std.mem.Allocator) ChangedFilesConfig {
        return ChangedFilesConfig{
            .map = std.StringHashMap([]const MatchPath).init(allocator),
        };
    }

    pub fn deinit(self: *ChangedFilesConfig, allocator: std.mem.Allocator) void {
        var it = self.map.iterator();
        while (it.next()) |entry| {
            for (entry.value_ptr.*) |pattern| {
                MatchPath.deinit(pattern, allocator);
            }
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        self.map.deinit();
    }

    pub fn put(self: *ChangedFilesConfig, key: []const u8, value: []const MatchPath) !void {
        try self.map.put(key, value);
    }
    pub fn get(self: *ChangedFilesConfig, key: []const u8) ?[]const MatchPath {
        return self.map.get(key);
    }
    pub fn count(self: ChangedFilesConfig) usize {
        return self.map.count();
    }
    pub fn fromSlice(
        allocator: std.mem.Allocator,
        slice: []const u8,
    ) !ChangedFilesConfig {
        var yaml: Yaml = .{ .source = slice };
        defer yaml.deinit(allocator);

        try yaml.load(allocator);
        if (yaml.docs.items.len == 0) {
            // treat empty as empty config
            return ChangedFilesConfig.init(allocator);
        }
        const root = yaml.docs.items[0];
        if (root != .map) return error.TypeMismatch;
        const map = root.map;

        var result = ChangedFilesConfig.init(allocator);

        var it = map.iterator();
        while (it.next()) |entry| {
            const key = entry.key_ptr.*;
            const value = entry.value_ptr.*;
            if (value != .list) return error.TypeMismatch;
            const list = value.list;
            var patterns = try allocator.alloc(MatchPath, list.len);
            for (list, 0..) |item, i| {
                if (item != .string) return error.TypeMismatch;
                // duplicate the string to ensure it is owned by the allocator
                patterns[i] = try MatchPath.initU8(allocator, item.string);
            }
            // duplicate the key to ensure it is owned by the allocator
            const duped_key = try allocator.dupe(u8, key);
            try (&result).put(duped_key, patterns);
        }
        return result;
    }

    pub fn fromFileLocation(
        allocator: std.mem.Allocator,
        yaml_location: []const u8,
    ) !ChangedFilesConfig {
        const yaml_path = try std.fs.cwd().realpathAlloc(allocator, yaml_location);
        defer allocator.free(yaml_path);

        const file = try std.fs.cwd().openFile(yaml_path, .{});
        defer file.close();
        const source = try file.readToEndAlloc(allocator, std.math.maxInt(u32));
        defer allocator.free(source);
        return ChangedFilesConfig.fromSlice(allocator, source);
    }
};

test "parseChangedFilesConfig - basic functionality" {
    const test_yaml =
        \\key1:
        \\  - pattern1
        \\  - pattern2
        \\key2:
        \\  - pattern3
        \\  - pattern4
        \\  - pattern5
    ;

    var config = ChangedFilesConfig.fromSlice(std.testing.allocator, test_yaml) catch |err| {
        std.debug.print("basic functionality parse error: {}\n", .{err});
        return err;
    };
    defer config.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), config.map.count());

    // Test key1
    const key1_patterns = config.get("key1").?;
    try std.testing.expectEqual(@as(usize, 2), key1_patterns.len);
    try std.testing.expectEqualSlices(u21, comptime Unicode.u8ToU21Comptime("pattern1"), key1_patterns[0].components[0].str);
    try std.testing.expectEqualSlices(u21, comptime Unicode.u8ToU21Comptime("pattern2"), key1_patterns[1].components[0].str);

    // Test key2
    const key2_patterns = config.get("key2").?;
    try std.testing.expectEqual(@as(usize, 3), key2_patterns.len);
    try std.testing.expectEqualSlices(u21, comptime Unicode.u8ToU21Comptime("pattern3"), key2_patterns[0].components[0].str);
    try std.testing.expectEqualSlices(u21, comptime Unicode.u8ToU21Comptime("pattern4"), key2_patterns[1].components[0].str);
    try std.testing.expectEqualSlices(u21, comptime Unicode.u8ToU21Comptime("pattern5"), key2_patterns[2].components[0].str);
}
