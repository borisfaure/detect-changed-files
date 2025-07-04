const std = @import("std");
const assert = std.debug.assert;
const Yaml = @import("yaml").Yaml;
const io = std.io;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        return error.NoPathArgument;
    }

    const stdout = std.io.getStdOut().writer();

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

    var yaml: Yaml = .{ .source = source };
    defer yaml.deinit(allocator);

    yaml.load(allocator) catch |err| switch (err) {
        error.ParseFailure => {
            assert(yaml.parse_errors.errorMessageCount() > 0);
            yaml.parse_errors.renderToStdErr(.{ .ttyconf = std.io.tty.detectConfig(std.io.getStdErr()) });
            return error.ParseFailure;
        },
        else => return err,
    };

    try yaml.stringify(stdout);
}

/// This imports the separate module containing `root.zig`. Take a look in `build.zig` for details.
const lib = @import("detect_changed_files_lib");
