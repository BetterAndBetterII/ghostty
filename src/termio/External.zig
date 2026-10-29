//! External I/O (Jarvis fork): the terminal's program runs somewhere else.
//! There is no pty and no process here. What the terminal writes (encoded
//! keys, mouse reports, replies to queries) goes to a callback the host sends
//! on; what the host receives (the remote terminal's output) is fed in with
//! `ghostty_surface_io_feed`, the way the exec backend's read thread feeds a
//! pty's output. A new grid size goes to another callback, so the host can
//! resize the remote terminal.
const External = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const renderer = @import("../renderer.zig");
const terminal = @import("../terminal/main.zig");
const termio = @import("../termio.zig");
const ProcessInfo = @import("../pty.zig").ProcessInfo;

/// Bytes the terminal writes, for the host to send to the remote program.
pub const WriteFn = *const fn (?*anyopaque, [*]const u8, usize) callconv(.c) void;

/// The terminal's new size in cells and pixels.
pub const ResizeFn = *const fn (?*anyopaque, u16, u16, u32, u32) callconv(.c) void;

pub const Config = struct {
    userdata: ?*anyopaque,
    write: WriteFn,
    resize: ?ResizeFn = null,
};

config: Config,

pub fn init(config: Config) External {
    return .{ .config = config };
}

pub fn deinit(self: *External) void {
    _ = self;
}

pub fn initTerminal(self: *External, t: *terminal.Terminal) void {
    _ = self;
    _ = t;
}

pub fn threadEnter(
    self: *External,
    alloc: Allocator,
    io: *termio.Termio,
    td: *termio.Termio.ThreadData,
) !void {
    _ = self;
    _ = alloc;
    _ = io;
    td.backend = .{ .external = .{} };
}

pub fn threadExit(self: *External, td: *termio.Termio.ThreadData) void {
    _ = self;
    _ = td;
}

pub fn focusGained(
    self: *External,
    td: *termio.Termio.ThreadData,
    focused: bool,
) !void {
    _ = self;
    _ = td;
    _ = focused;
}

pub fn resize(
    self: *External,
    grid_size: renderer.GridSize,
    screen_size: renderer.ScreenSize,
) !void {
    const cb = self.config.resize orelse return;
    cb(
        self.config.userdata,
        @intCast(grid_size.columns),
        @intCast(grid_size.rows),
        screen_size.width,
        screen_size.height,
    );
}

pub fn queueWrite(
    self: *External,
    alloc: Allocator,
    td: *termio.Termio.ThreadData,
    data: []const u8,
    linefeed: bool,
) !void {
    _ = td;
    if (!linefeed) {
        self.config.write(self.config.userdata, data.ptr, data.len);
        return;
    }

    // Linefeed mode: \r goes out as \r\n (what the exec backend does too).
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(alloc);
    for (data) |ch| {
        try out.append(alloc, ch);
        if (ch == '\r') try out.append(alloc, '\n');
    }
    self.config.write(self.config.userdata, out.items.ptr, out.items.len);
}

pub fn childExitedAbnormally(
    self: *External,
    gpa: Allocator,
    t: *terminal.Terminal,
    exit_code: u32,
    runtime_ms: u64,
) !void {
    _ = self;
    _ = gpa;
    _ = t;
    _ = exit_code;
    _ = runtime_ms;
}

/// There is no local process to tell about.
pub fn getProcessInfo(self: *External, comptime info: ProcessInfo) ?ProcessInfo.Type(info) {
    _ = self;
    return null;
}

pub const ThreadData = struct {
    pub fn deinit(self: *ThreadData, alloc: Allocator) void {
        _ = self;
        _ = alloc;
    }
};
