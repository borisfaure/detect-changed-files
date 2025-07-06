const std = @import("std");
const Yaml = @import("yaml").Yaml;
const Unicode = @import("unicode.zig");
const match = @import("match.zig");
const PathComponent = match.PathComponent;
const MatchPath = match.MatchPath;
const DiffFiles = @import("diff.zig").DiffFiles;

/// Represents the structure of changed-files.yaml
/// Each key maps to a list of file patterns
pub const ChangedFilesConfig = struct {
    map: std.StringHashMap([]const MatchPath),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ChangedFilesConfig {
        return ChangedFilesConfig{
            .map = std.StringHashMap([]const MatchPath).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ChangedFilesConfig) void {
        var it = self.map.iterator();
        while (it.next()) |entry| {
            for (entry.value_ptr.*) |pattern| {
                pattern.deinit();
            }
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
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

    pub fn checkPatterns(
        self: *ChangedFilesConfig,
        allocator: std.mem.Allocator,
        diff_files: DiffFiles,
    ) !GroupsMatched {
        var groups = try GroupsMatched.initFromConfig(allocator, self);
        errdefer groups.deinit();

        for (diff_files.list) |filepath| {
            var it = self.map.iterator();
            while (it.next()) |entry| {
                // Skip if the group is already matched
                if (groups.get(entry.key_ptr.*).?)
                    continue;

                const patterns = entry.value_ptr.*;
                for (patterns) |pattern| {
                    if (pattern.isMatch(allocator, filepath)) {
                        try groups.put(entry.key_ptr.*, true);
                        break;
                    }
                }
            }
        }

        return groups;
    }
};

pub const GroupsMatched = struct {
    groups: std.StringHashMap(bool),
    allocator: std.mem.Allocator,

    pub fn initFromConfig(
        allocator: std.mem.Allocator,
        config: *ChangedFilesConfig,
    ) !GroupsMatched {
        var groups = std.StringHashMap(bool).init(allocator);
        errdefer groups.deinit();
        // Populate the groups based on the config
        var it = config.map.iterator();
        while (it.next()) |entry| {
            const key = try allocator.dupe(u8, entry.key_ptr.*);
            std.debug.assert(!groups.contains(key));
            try groups.put(key, false);
        }
        return GroupsMatched{
            .groups = groups,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *GroupsMatched) void {
        var it = self.groups.iterator();
        while (it.next()) |entry| {
            const key = entry.key_ptr.*;
            // Free the key, which was duplicated in initFromConfig
            self.allocator.free(key);
        }
        self.groups.deinit();
    }

    pub fn get(self: *GroupsMatched, key: []const u8) ?bool {
        return self.groups.get(key);
    }
    pub fn put(self: *GroupsMatched, key: []const u8, value: bool) !void {
        try self.groups.put(key, value);
    }

    // Convert the groups to a JSON object for serialization
    pub fn toJsonObject(self: *GroupsMatched) !std.json.ObjectMap {
        var json_obj = std.json.ObjectMap.init(self.allocator);
        errdefer json_obj.deinit();

        var it = self.groups.iterator();
        while (it.next()) |entry| {
            const key = entry.key_ptr.*;
            const value = entry.value_ptr.*;

            // Create a JSON value for the boolean
            const json_value = std.json.Value{ .bool = value };

            // Add to the JSON object
            try json_obj.put(key, json_value);
        }

        return json_obj;
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
    defer config.deinit();

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

test "checkPatterns - basic functionality" {
    const allocator = std.testing.allocator;
    const test_yaml =
        \\key1:
        \\  - 'a/**/c.zig'
        \\  - 'd/?/f.zig'
        \\key2:
        \\  - '**/*.c'
        \\  - '**/*.zig'
        \\  - '**/*.h'
        \\key3:
        \\  - '**/*.rs'
    ;

    var config = ChangedFilesConfig.fromSlice(allocator, test_yaml) catch |err| {
        std.debug.print("checkPatterns parse error: {}\n", .{err});
        return err;
    };
    defer config.deinit();

    var diff_files = DiffFiles.init(allocator);
    defer diff_files.deinit();

    // Simulate a diff with only a file that match key1 and key2, and 2 files
    // that do not match
    var lines = std.ArrayList(MatchPath).init(allocator);
    defer lines.deinit();
    try lines.append(
        try MatchPath.initU8(allocator, "foo/bar"),
    );
    try lines.append(
        try MatchPath.initU8(allocator, "a/b/c.zig"),
    );
    try lines.append(
        try MatchPath.initU8(allocator, "build.zig.zon"),
    );
    diff_files.list = try lines.toOwnedSlice();

    var groups = try config.checkPatterns(allocator, diff_files);
    defer groups.deinit();

    // Check if the groups were matched correctly
    try std.testing.expect(groups.get("key1").?);
    try std.testing.expect(groups.get("key2").?);
    try std.testing.expect(!groups.get("key3").?);
}
