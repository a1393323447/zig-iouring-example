const std = @import("std");
const linux = std.os.linux;

/// Returns the size of the file whose open file descriptor is passed in.
/// Properly handles regular file and block devices as well. Pretty.
pub fn getFileSize(fd: linux.fd_t) !usize {
    var st: linux.Stat = std.mem.zeroes(linux.Stat);
    
    if (linux.fstat(fd, &st) < 0) {
        std.log.err("fstat\n", .{});
        return error.fstat_failed;
    }

    if (linux.S.ISBLK(st.mode)) {
        comptime var BLKGETSIZE64 = linux.IOCTL.IOR(0x12, 114, usize);
        var bytes: u64 = 0;
        if (linux.ioctl(fd, BLKGETSIZE64, @ptrToInt(&bytes)) != 0) {
            std.log.err("ioctl\n", .{});
            return error.ioctl_failed;
        }
        return @intCast(usize, bytes);
    } else if (linux.S.ISREG(st.mode)) {
        return @intCast(usize, st.size);
    }

    return error.unknown;
}

pub fn open(path: [*:0]const u8, flags: u32, perm: linux.mode_t) !linux.fd_t {
    const ufd = linux.open(path, flags, perm);
    const ifd = @bitCast(isize, ufd);
    if (ifd < 0) {
        return error.open_failed;
    }
    return @intCast(linux.fd_t, ifd);
}
