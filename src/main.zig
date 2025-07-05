const std = @import("std");
const assert = std.debug.assert;
const io = std.io;
const Yaml = @import("yaml").Yaml;
const Config = @import("config.zig").ChangedFilesConfig;
const match = @import("match.zig");

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
    var config = try Config.fromFileLocation(allocator, yml_location);
    defer config.deinit(allocator);

    // print number of elements in changes
    std.debug.print("Number of elements in changes: {}\n", .{config.count()});

    // print all keys in changes
    var it = config.iterator();
    while (it.next()) |entry| {
        std.debug.print("Key: {s}\n", .{entry.key_ptr.*});
    }
}

/// This imports the separate module containing `root.zig`. Take a look in `build.zig` for details.
const lib = @import("detect_changed_files_lib");
