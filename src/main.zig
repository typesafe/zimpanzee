const std = @import("std");
const repl = @import("./repl.zig");
const signals = @import("./signals.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var r = repl.Repl.init(gpa.allocator());

    try signals.on_sig_int(exit);

    try r.run();
}

fn exit() void {
    std.debug.print("\nExiting...\n", .{});
    std.posix.exit(1);
}

test {
    std.testing.refAllDeclsRecursive(@This());
}
