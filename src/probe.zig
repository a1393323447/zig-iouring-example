const std = @import("std");
const linux = std.os.linux;

const IOUringOp = enum(u8) {
    NOP = 0,
    READV,
    WRITEV,
    FSYNC,
    READ_FIXED,
    WRITE_FIXED,
    POLL_ADD,
    POLL_REMOVE,
    SYNC_FILE_RANGE,
    SENDMSG,
    RECVMSG,
    TIMEOUT,
    TIMEOUT_REMOVE,
    ACCEPT,
    ASYNC_CANCEL,
    LINK_TIMEOUT,
    CONNECT,
    FALLOCATE,
    OPENAT,
    CLOSE,
    FILES_UPDATE,
    STATX,
    READ,
    WRITE,
    FADVISE,
    MADVISE,
    SEND,
    RECV,
    OPENAT2,
    EPOLL_CTL,
    SPLICE,
    PROVIDE_BUFFERS,
    REMOVE_BUFFERS,
    TEE,
    SHUTDOWN,
    RENAMEAT,
    UNLINKAT,
    MKDIRAT,
    SYMLINKAT,
    LINKAT,
    MSG_RING,
    FSETXATTR,
    SETXATTR,
    FGETXATTR,
    GETXATTR,
    SOCKET,
    URING_CMD,
    SEND_ZC,
    SENDMSG_ZC,
};

pub const io_uring_probe_op = extern struct {
    op: IOUringOp,

    resv: u8,

    /// IO_URING_OP_* flags
    flags: u16,

    resv2: u32,
};

pub const io_uring_probe = extern struct {
    /// last opcode supported
    last_op: IOUringOp,
    /// Number of io_uring_probe_op following
    ops_len: u8,

    resv: u16,
    resv2: [3]u32,
};

const IOUringProbeSet = extern struct {
    probe: io_uring_probe,
    ops: [OP_CNT]io_uring_probe_op,

    const OP_CNT = @typeInfo(IOUringOp).Enum.fields.len;

    const Self = @This();

    pub fn get() !Self {
        var probe_set = std.mem.zeroInit(Self, .{});
        var ring = try linux.IO_Uring.init(2, 0);
        defer ring.deinit();
        const res = linux.io_uring_register(ring.fd, linux.IORING_REGISTER.REGISTER_PROBE, &probe_set, OP_CNT);
        if (@bitCast(isize, res) < 0) {
            return error.get_probe_failed;
        }
        return probe_set;
    }

    pub fn supportedOps(self: *const Self) []const io_uring_probe_op {
        const last_op = @intCast(usize, @enumToInt(self.probe.last_op));
        return self.ops[0..(last_op + 1)];
    }
};

pub fn main() !void {
    const uname = std.os.uname();
    std.debug.print("You are running kernel version: {s}\n", .{uname.release});
    std.debug.print("This program won't work on kernel version earlier than 5.6\n", .{});
    const probe_set = try IOUringProbeSet.get();
    std.debug.print("Report of your kernel's list of supported io_uring operations:\n", .{});
    for (probe_set.ops) |probe_op| {
        std.debug.print("{s}: ", .{@tagName(probe_op.op)});
        if (probe_op.flags & linux.IO_URING_OP_SUPPORTED != 0) {
            std.debug.print("yes\n", .{});
        } else {
            std.debug.print("no\n", .{});
        }
    }

    std.debug.print("\nTo test supportedOps\n\n", .{});
    for (probe_set.supportedOps()) |probe_op| {
        std.debug.print("{s}: yes\n", .{@tagName(probe_op.op)});
    }
}