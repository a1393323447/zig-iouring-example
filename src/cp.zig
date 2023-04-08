const utils = @import("utils.zig");
const std = @import("std");
const linux = std.os.linux;
const Allocator = std.mem.Allocator;
const FixedSizeQueue = @import("datastructure/FixedSizeQueue.zig").FixedSizeQueue;

const QD = 16;
const BS: usize = 16 * 1024;

var infd: ?linux.fd_t = null;
var outfd: ?linux.fd_t = null;

const Mode = enum {
    Read,
    Write,
};

const IOData = struct {
    mode: Mode = .Write,
    offset: usize = 0,
    len: usize = 0,
    buf: []u8 = &[_]u8{},
};

fn queuePrep(ring: *linux.IO_Uring, data: *IOData) !void {
    switch (data.mode) {
        .Read => {
            const read_buf = linux.IO_Uring.ReadBuffer { .buffer = data.buf[0..data.len] };
            _ = try ring.read(@ptrToInt(data), infd.?, read_buf, 0);
        },
        .Write => {
           _ = try  ring.write(@ptrToInt(data), outfd.?, data.buf[0..data.len], 0);
        },
    }
}

fn copyFile(ring: *linux.IO_Uring, allocator: Allocator) !void {
    // first, we calculate the total blocks we need to submit
    // and name it total task because one task for one block
    const file_size: usize = try utils.getFileSize(infd.?);
    var total_task: usize = file_size / BS;
    if (file_size % BS != 0) {
        total_task += 1;
    }
    // then we init a io data array shared by read and write
    var io_datas = std.mem.zeroes([QD]IOData);
    // we have two queue
    // read_complete_queue contains the io data ptr that was used by read task
    // write_complete_queue contains the io data ptr that was used by write task
    var read_complete_queue = FixedSizeQueue(*IOData, QD).init();
    var write_complete_queue = FixedSizeQueue(*IOData, QD).init();
    // init the write_complete_queue
    for (0..QD) |i| {
        const data_ptr = &io_datas[i];
        io_datas[i].buf = try allocator.alloc(u8, BS);
        try write_complete_queue.enqueue(data_ptr);
    }
    // read_offset is current reading file offset
    var read_offset: usize = 0;
    var finished_task: usize = 0;
    // cqes just a array used by copy_cqes()
    var cqes: [QD]linux.io_uring_cqe = std.mem.zeroes([QD]linux.io_uring_cqe);

    while (finished_task < total_task) {
        // first we check if there are complete tasks
        var cqe_cnt: u32 = ring.cq_ready();
        // if we have no complete task
        if (cqe_cnt == 0) {
            //  we wait for a timeout to prevent busy empty loop
            std.time.sleep(1000 * 3);
            // and look up again
            cqe_cnt = ring.cq_ready();
        }
        // if we now have complete tasks
        if (cqe_cnt != 0) {
            // then we copy cqes
            const copy_cqe_cnt = try ring.copy_cqes(&cqes, cqe_cnt);
            const cnt = @intCast(usize, copy_cqe_cnt);
            for (cqes[0..cnt]) |cqe| {
                // we get the io date we regist in sqe
                const data_ptr = @intToPtr(*IOData, cqe.user_data);
                // then we enqueue this io data depend on its mode (Read/Write)
                switch (data_ptr.mode) {
                    .Read => try read_complete_queue.enqueue(data_ptr),
                    .Write => {
                        try write_complete_queue.enqueue(data_ptr);
                        finished_task += 1;
                    }
                }
            }
        }
        // if read_offset < file_size then we need to read file
        while (read_offset < file_size) {
            // we try to find a available io data from write_complete_queue
            if (write_complete_queue.dequeue()) |data_ptr| {
                // if we find one, we init it and prepare it
                data_ptr.offset = read_offset;
                const len = std.math.min(BS, file_size - read_offset);
                data_ptr.len = len;
                data_ptr.mode = .Read;

                try queuePrep(ring, data_ptr);

                read_offset += len;
            } else {
                // if we can't find any more, we break the loop
                break;
            }
        }

        // because the write is depend on the read, so we don't need to
        // record the write offset or init the io data, we just find a available 
        // io data from read_complete_queue and simply prepare
        while (read_complete_queue.dequeue()) |data_ptr| {
            data_ptr.mode = .Write;
            try queuePrep(ring, data_ptr);
        }

        // finally we submit all task we prepare
        _ = try ring.submit();
    }

    // release the bufs we allocated
    defer {
        for (io_datas) |io_data| {
            allocator.free(io_data.buf);
        }
    }
}

pub fn main() !void {
    var general_alloc = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = general_alloc.allocator();
    
    const args: [][:0]u8 = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    
    if (args.len < 3) {
        std.log.err("Usage: {s} [infile] [outfile]\n", .{
            args[0],         
        });
        return;
    }

    const infile = args[1];
    const outfile = args[2];

    infd = try utils.open(infile, linux.O.RDONLY, 0);
    outfd = try utils.open(outfile, linux.O.WRONLY | linux.O.CREAT | linux.O.TRUNC, 0o644);

    var ring = try linux.IO_Uring.init(QD, 0);
    defer ring.deinit();

    try copyFile(&ring, allocator);
}