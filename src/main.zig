const std = @import("std");
const assert = std.debug.assert;
const io = std.io;
const Yaml = @import("yaml").Yaml;

pub const std_options = std.Options{
    // Set the log level to info
    .log_level = .info,

    // Define logFn to override the std implementation
    .logFn = myLogFn,
};

pub fn myLogFn(
    comptime level: std.log.Level,
    comptime scope: @Type(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    // Ignore all non-error logging from sources other than
    // .my_project, .nice_library and the default
    const scope_prefix = "(" ++ switch (scope) {
        .my_project, .nice_library, std.log.default_log_scope => @tagName(scope),
        else => if (@intFromEnum(level) <= @intFromEnum(std.log.Level.err))
            @tagName(scope)
        else
            return,
    } ++ "): ";

    const prefix = "[" ++ comptime level.asText() ++ "] " ++ scope_prefix;

    // Print the message to stderr, silently ignoring any errors
    std.debug.lockStdErr();
    defer std.debug.unlockStdErr();
    const stderr = std.io.getStdErr().writer();
    nosuspend stderr.print(prefix ++ format ++ "\n", args) catch return;
}

/// Represents the structure of changed-files.yaml
/// Each key maps to a list of file patterns
pub const ChangedFilesConfig = struct {
    map: std.StringHashMap([]const []const u8),

    pub fn init(allocator: std.mem.Allocator) ChangedFilesConfig {
        return ChangedFilesConfig{
            .map = std.StringHashMap([]const []const u8).init(allocator),
        };
    }

    pub fn deinit(self: *ChangedFilesConfig, allocator: std.mem.Allocator) void {
        var it = self.map.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            for (entry.value_ptr.*) |pattern| {
                allocator.free(pattern);
            }
            allocator.free(entry.value_ptr.*);
        }
        self.map.deinit();
        allocator.destroy(self);
    }

    pub fn put(self: *ChangedFilesConfig, key: []const u8, value: []const []const u8) !void {
        try self.map.put(key, value);
    }
    pub fn get(self: *ChangedFilesConfig, key: []const u8) ?[]const []const u8 {
        return self.map.get(key);
    }
    pub fn count(self: *ChangedFilesConfig) usize {
        return self.map.count();
    }
    pub fn iterator(self: *ChangedFilesConfig) std.StringHashMap([]const []const u8).Iterator {
        return self.map.iterator();
    }
};

/// Parse YAML content and return a pointer to a ChangedFilesConfig
fn parseChangedFilesConfig(allocator: std.mem.Allocator, yaml_content: []const u8) !*ChangedFilesConfig {
    var yaml: Yaml = .{ .source = yaml_content };
    defer yaml.deinit(allocator);

    try yaml.load(allocator);
    if (yaml.docs.items.len == 0) {
        // treat empty as empty config
        const result = try allocator.create(ChangedFilesConfig);
        result.* = ChangedFilesConfig.init(allocator);
        return result;
    }
    const root = yaml.docs.items[0];
    if (root != .map) return error.TypeMismatch;
    const map = root.map;

    const result = try allocator.create(ChangedFilesConfig);
    result.* = ChangedFilesConfig.init(allocator);

    var it = map.iterator();
    while (it.next()) |entry| {
        const key = entry.key_ptr.*;
        const value = entry.value_ptr.*;
        if (value != .list) return error.TypeMismatch;
        const list = value.list;
        var patterns = try allocator.alloc([]const u8, list.len);
        for (list, 0..) |item, i| {
            if (item != .string) return error.TypeMismatch;
            // duplicate the string to ensure it is owned by the allocator
            patterns[i] = try allocator.dupe(u8, item.string);
        }
        // duplicate the key to ensure it is owned by the allocator
        const duped_key = try allocator.dupe(u8, key);
        try result.put(duped_key, patterns);
    }
    return result;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        return error.NoPathArgument;
    }

    const yml_location = args[1];

    const yaml_path = try std.fs.cwd().realpathAlloc(
        allocator,
        yml_location,
    );
    defer allocator.free(yaml_path);

    const file = try std.fs.cwd().openFile(yaml_path, .{});
    defer file.close();

    const source = try file.readToEndAlloc(allocator, std.math.maxInt(u32));
    defer allocator.free(source);

    const changes = try parseChangedFilesConfig(allocator, source);
    defer changes.*.deinit(allocator);
    // print number of elements in changes
    std.debug.print("Number of elements in changes: {}\n", .{changes.count()});

    // print all keys in changes
    var it = changes.iterator();
    while (it.next()) |entry| {
        std.debug.print("Key: {s}\n", .{entry.key_ptr.*});
    }
}

/// This imports the separate module containing `root.zig`. Take a look in `build.zig` for details.
const lib = @import("detect_changed_files_lib");

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

    const config = parseChangedFilesConfig(std.testing.allocator, test_yaml) catch |err| {
        std.debug.print("basic functionality parse error: {}\n", .{err});
        return err;
    };
    defer config.*.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), config.*.count());

    // Test key1
    const key1_patterns = config.*.get("key1").?;
    try std.testing.expectEqual(@as(usize, 2), key1_patterns.len);
    try std.testing.expectEqualStrings("pattern1", key1_patterns[0]);
    try std.testing.expectEqualStrings("pattern2", key1_patterns[1]);

    // Test key2
    const key2_patterns = config.*.get("key2").?;
    try std.testing.expectEqual(@as(usize, 3), key2_patterns.len);
    try std.testing.expectEqualStrings("pattern3", key2_patterns[0]);
    try std.testing.expectEqualStrings("pattern4", key2_patterns[1]);
    try std.testing.expectEqualStrings("pattern5", key2_patterns[2]);
}
