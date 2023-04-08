const utils = @import("utils.zig");
const std = @import("std");
const linux = std.os.linux;

const TEMP_FILE_NAME = "/tmp/io_uring_test.txt";
const STR = "Hello, io_uring!\n";

fn link_operations(ring: *linux.IO_Uring) !void {
    const O = linux.O;
    const fd = try utils.open(TEMP_FILE_NAME, O.RDWR | O.TRUNC | O.CREAT, 0o644);
    
    const w_sqe = try ring.write(0, fd, STR, 0);
    w_sqe.flags |= linux.IOSQE_IO_LINK;
    
    var buf = std.mem.zeroes([32]u8);
    const r_sqe = try ring.read(0, fd, .{.buffer = &buf}, 0);
    r_sqe.flags |= linux.IOSQE_IO_LINK;

    _ = try ring.close(0, fd);

    _  = try ring.submit_and_wait(3);

    try std.io.getStdOut().writeAll(&buf);
}

pub fn main() !void {
    var ring = try linux.IO_Uring.init(4, 0);
    defer ring.deinit();
    
    try link_operations(&ring);
}