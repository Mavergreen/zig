const std = @import("std");

const workers = 4;
const rounds = 1000;

var mutex: std.Io.Mutex = .init;
var cond: std.Io.Condition = .init;
var count: u32 = 0;
var done: u32 = 0;
var flag: std.atomic.Value(u32) = .init(0);

fn worker(io: std.Io) void {
    for (0..rounds) |_| {
        mutex.lockUncancelable(io);
        count += 1;
        mutex.unlock(io);
    }
    mutex.lockUncancelable(io);
    done += 1;
    mutex.unlock(io);
    cond.signal(io);
}

fn waker(io: std.Io) void {
    flag.store(1, .release);
    io.futexWake(u32, &flag.raw, 1);
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var threads: [workers]std.Thread = undefined;
    for (&threads) |*t| t.* = try std.Thread.spawn(.{}, worker, .{io});
    try mutex.lock(io);
    while (done < workers) try cond.wait(io, &mutex);
    mutex.unlock(io);
    for (threads) |t| t.join();
    if (count != workers * rounds) return error.LostUpdates;

    const w = try std.Thread.spawn(.{}, waker, .{io});
    while (flag.load(.acquire) == 0) try io.futexWait(u32, &flag.raw, 0);
    w.join();
    try std.Io.File.stdout().writeStreamingAll(io, "sync ok\n");
}
