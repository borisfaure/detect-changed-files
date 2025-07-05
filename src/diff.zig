// Get the list of files from stdin
// They are the output of `git diff --name-only`

const std = @import("std");
const MatchPath = @import("match.zig").MatchPath;

pub const DiffFiles = struct {
    list: []const *MatchPath,

    pub fn init() DiffFiles {
        return DiffFiles{
            .list = &.{},
        };
    }

    pub fn deinit(self: *DiffFiles, allocator: std.mem.Allocator) void {
        for (self.list) |item| {
            MatchPath.destroy(item, allocator);
        }
        allocator.free(self.list);
    }

    pub fn fromStdIn(
        allocator: std.mem.Allocator,
    ) !DiffFiles {
        const stdin = std.io.getStdIn();
        var buf = std.io.bufferedReader(stdin.reader());

        // Get the Reader interface from BufferedReader
        var r = buf.reader();

        var lines = std.ArrayList(*MatchPath).init(allocator);
        defer lines.deinit();

        // Read until a newline or EOF
        var buf_msg: [4096]u8 = undefined;
        while (try r.readUntilDelimiterOrEof(&buf_msg, '\n')) |str| {
            const trimmed = std.mem.trim(u8, str, " \t\r\n");
            if (trimmed.len == 0) continue; // Skip empty lines

            // Allocate a new MatchPath for each line read
            var match_path = try MatchPath.createInitU8(
                allocator,
                trimmed,
            );
            lines.append(match_path) catch |err| {
                // If we fail to append, deinit the match_path
                match_path.deinit(allocator);
                return err;
            };
        }

        return DiffFiles{
            .list = try lines.toOwnedSlice(),
        };
    }
};
