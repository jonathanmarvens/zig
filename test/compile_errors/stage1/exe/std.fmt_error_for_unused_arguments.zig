pub fn main() !void {
    @import("std").debug.print("{d} {d} {d} {d} {d}", .{1,2,3,4,5,6,7,8,9,10,11,12,13,14,15});
}

// std.fmt error for unused arguments
//
// ?:?:?: error: 10 unused arguments in '{d} {d} {d} {d} {d}'