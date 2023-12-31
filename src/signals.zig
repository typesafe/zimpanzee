const std = @import("std");

pub fn on_sig_int(comptime callback: fn () void) !void {
    const internal_handler = struct {
        fn internal_handler(sig: c_int) callconv(.C) void {
            _ = sig;
            //assert(sig == os.SIG.INT);
            callback();
        }
    }.internal_handler;
    const act = std.os.Sigaction{
        .handler = .{ .handler = internal_handler },
        .mask = std.os.empty_sigset,
        .flags = 0,
    };

    try std.os.sigaction(std.os.SIG.INT, &act, null);
}
