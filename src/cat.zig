const utils = @import("utils.zig");
const std = @import("std");
const linux = std.os.linux;

const QUEUE_DEPTH: u13 = 1;
const BLOCK_SZ: usize = 1024;

const FileInfo =  struct {
    file_sz: usize,
    iovecs: []std.os.iovec,
    allocator: std.mem.Allocator,

    const Self = @This();
    pub fn init(
        self: *Self,
        file_sz: usize,
        allocator: std.mem.Allocator, 
    ) !void {
        self.allocator = allocator;
        self.file_sz = file_sz;

        var blocks: usize = file_sz / BLOCK_SZ;
        const bytes_remaining = file_sz % BLOCK_SZ;        
        if (bytes_remaining != 0) {
            blocks += 1;
        }
        self.iovecs = try allocator.alloc(std.os.iovec, blocks);

        for (0..blocks) |i| {
            self.iovecs[i].iov_len = BLOCK_SZ;
            var buf = try allocator.alignedAlloc(u8, BLOCK_SZ, BLOCK_SZ);
            self.iovecs[i].iov_base = @ptrCast([*]u8, buf.ptr);
        } 
        if (bytes_remaining != 0) {
            const last = blocks - 1;
            self.iovecs[last].iov_len = bytes_remaining;
        }
    }

    pub fn deinit(self: *Self) void {
        for (self.iovecs) |iovec| {
            const ptr = iovec.iov_base;
            const orign = @alignCast(BLOCK_SZ, ptr);
            self.allocator.free(orign[0..BLOCK_SZ]);
        }
        self.allocator.free(self.iovecs);
    }
};

/// Wait for a completion to be available, fetch the data from
/// the readv operation and print it to console
fn getCompletionAndPrint(ring: *linux.IO_Uring) !void {
    const cqe:linux.io_uring_cqe = try ring.copy_cqe();
    if (cqe.res < 0) {
        std.log.err("Async readv failed.\n", .{});
        return error.readv_failed;
    }
    const fi = @intToPtr(*FileInfo, cqe.user_data);
    const buf = @ptrCast([]std.os.iovec_const, fi.iovecs);
    try std.io.getStdOut().writevAll(buf);

    fi.deinit();
}

/// Submit the readv request
fn submitReadRequest(
    file_path: [*:0]const u8, 
    ring: *linux.IO_Uring,
    allocator: std.mem.Allocator,
) !void {
    const fd = try utils.open(file_path, linux.O.RDONLY, 0);
    const file_sz = try utils.getFileSize(fd);
    var fi = try allocator.create(FileInfo);
    try fi.init(file_sz, allocator);
    
    const read_buf = linux.IO_Uring.ReadBuffer { .iovecs = fi.iovecs };
    _ = try ring.read(@ptrToInt(fi), fd, read_buf, 0);
    _ = try ring.submit();
}

pub fn main() !void {
    var general_alloc = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = general_alloc.allocator();
    
    const args: [][:0]u8 = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    
    if (args.len < 2) {
        std.log.err("Usage: {s} [file name] < [file name] ...>\n", .{
            args[0],         
        });
        return;
    }

    var ring = try linux.IO_Uring.init(QUEUE_DEPTH, 0);

    for (args[1..]) |arg| {
        std.log.info("Opening {s}\n", .{arg});
        try submitReadRequest(arg, &ring, allocator);
        try getCompletionAndPrint(&ring);
    }

    ring.deinit();
}
