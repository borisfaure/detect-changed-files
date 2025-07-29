const std = @import("std");
const assert = std.debug.assert;
const io = std.io;
const Yaml = @import("yaml").Yaml;
const config_zig = @import("config.zig");
const Config = config_zig.ChangedFilesConfig;
const match = @import("match.zig");
const DiffFiles = @import("diff.zig").DiffFiles;
const build_options = @import("build_options");

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

fn printHelp() void {
    const help_text =
        \\detect-changed-files v{s} - Analyze changed files and categorize them based on patterns
        \\
        \\USAGE:
        \\    detect_changed_files [OPTIONS] <config.yaml>
        \\
        \\ARGS:
        \\    <config.yaml>    Path to the YAML configuration file
        \\
        \\OPTIONS:
        \\    -h, --help       Print this help message
        \\
        \\DESCRIPTION:
        \\    This tool reads changed file paths from stdin (typically the output of
        \\    'git diff --name-only') and categorizes them based on patterns defined
        \\    in the YAML configuration file.
        \\
        \\    The tool outputs JSON to stdout with boolean values indicating which
        \\    groups have matching files.
        \\
        \\EXAMPLES:
        \\    # Basic usage
        \\    git diff --name-only | detect_changed_files config.yaml
        \\
        \\    # Check staged changes
        \\    git diff --name-only --cached | detect_changed_files config.yaml
        \\
        \\    # Check changes between commits
        \\    git diff --name-only HEAD~1 HEAD | detect_changed_files config.yaml
        \\
        \\CONFIGURATION:
        \\    The configuration file is a YAML file where each key represents a group
        \\    name, and the value is a list of file patterns. Patterns use glob-style
        \\    syntax:
        \\
        \\    - * matches any sequence of characters except /
        \\    - ? matches any single character except /
        \\    - ** matches zero or more path components (directories)
        \\
        \\OUTPUT:
        \\    JSON object with group names as keys and boolean values indicating
        \\    whether any files matched that group's patterns.
        \\
    ;
    const stderr = std.io.getStdErr().writer();
    stderr.print(help_text, .{build_options.version}) catch {};
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Check for help flags
    if (args.len == 2) {
        const first_arg = args[1];
        if (std.mem.eql(u8, first_arg, "-h") or std.mem.eql(u8, first_arg, "--help")) {
            printHelp();
            return;
        }
    } else if (args.len < 2) {
        const stderr = std.io.getStdErr().writer();
        stderr.print("Error: No configuration file specified\n", .{}) catch {};
        stderr.print("Use -h or --help for usage information\n", .{}) catch {};
        return error.NoPathArgument;
    } else {
        // Too many arguments
        const stderr = std.io.getStdErr().writer();
        stderr.print("Error: Too many arguments\n", .{}) catch {};
        stderr.print("Use -h or --help for usage information\n", .{}) catch {};
        return error.TooManyArguments;
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
