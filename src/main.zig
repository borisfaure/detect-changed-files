const std = @import("std");
const assert = std.debug.assert;
const io = std.io;
const Yaml = @import("yaml").Yaml;
const config_zig = @import("config.zig");
const Config = config_zig.ChangedFilesConfig;
const match = @import("match.zig");
const DiffFiles = @import("diff.zig").DiffFiles;

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
    defer config.deinit();

    var diff_files = try DiffFiles.fromStdIn(allocator);
    defer diff_files.deinit();

    var groups = config.checkPatterns(allocator, diff_files) catch |err| {
        std.debug.print("Error checking patterns: {}\n", .{err});
        return err;
    };
    defer groups.deinit();

    const json_options = std.json.StringifyOptions{ .whitespace = .indent_2 };

    // Convert groups to JSON object for serialization
    var json_obj = try groups.toJsonObject();
    defer json_obj.deinit();

    // Create a JSON Value from the object map
    const json_value = std.json.Value{ .object = json_obj };

    const output_writer = std.io.getStdOut().writer();
    try std.json.stringify(json_value, json_options, output_writer);
}
