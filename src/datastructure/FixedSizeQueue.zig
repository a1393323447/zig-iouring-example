const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn FixedSizeQueue(comptime T: type, comptime SIZE: usize)  type {
    return struct {
        head: usize,
        tail: usize,
        size: usize,
        data: [SIZE]T,

        const Self = @This();

        pub fn init() Self {
            return Self {
                .head = 0,
                .tail = 0,
                .size = 0,
                .data = undefined,
            };
        }

        pub fn enqueue(self: *Self, item: T) !void {
            if (self.is_full()) {
                return error.overflow;
            }
            self.data[self.tail] = item;
            self.tail = (self.tail + 1) % SIZE;
            self.size += 1;
        }

        pub fn dequeue(self: *Self) ?T {
            if (self.is_empty()) {
                return null;
            }
            const item = self.data[self.head];
            self.head = (self.head + 1) % SIZE;
            self.size -= 1;
            return item;
        }

        pub fn is_full(self: *const Self) bool {
            return self.size == SIZE;
        }

        pub fn is_empty(self: *const Self) bool {
            return self.size == 0;
        }
    };
}