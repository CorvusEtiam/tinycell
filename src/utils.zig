const std = @import("std");
const Expr = @import("./expression_parser.zig").Expr;

fn printExpressionTreeHelper(expr: *Expr, level: usize) void {
    const output = std.io.getStdErr().writer();
    switch (expr.*) {
        Expr.binary_op => {
            _ = output.writeByteNTimes(' ', level) catch unreachable;
            std.debug.print("BinOp<{s}> [\n", .{@tagName(expr.binary_op.operand)});
            printExpressionTreeHelper(expr.binary_op.lhs.?, level + 1);
            printExpressionTreeHelper(expr.binary_op.rhs.?, level + 1);
            _ = output.writeByteNTimes(' ', level)  catch unreachable;
            std.debug.print("]\n", .{});
        },
        Expr.unary_op => {
            _ = output.writeByteNTimes(' ', level)  catch unreachable;
            std.debug.print("UnOp<{s}> [\n", .{@tagName(expr.unary_op.operand)});
            printExpressionTreeHelper(expr.unary_op.rhs.?, level + 1);
            _ = output.writeByteNTimes(' ', level)  catch unreachable;
            std.debug.print("]\n", .{});
        },
        Expr.boolean => {
            _ = output.writeByteNTimes(' ', level + 1)  catch unreachable;
            std.debug.print("Bool<{any}>", .{expr.boolean});
        },
        Expr.ident => {
            _ = output.writeByteNTimes(' ', level + 1)  catch unreachable;
            std.debug.print("Ident<{s}>", .{expr.ident});
        },
        Expr.string => {
            _ = output.writeByteNTimes(' ', level + 1)  catch unreachable;
            std.debug.print("Str<{s}>", .{expr.string});
        },
        Expr.numeric => {
            _ = output.writeByteNTimes(' ', level + 1)  catch unreachable;
            std.debug.print("Num<{d}>", .{expr.numeric});
        },
        Expr.group => {
            _ = output.writeByteNTimes(' ', level)  catch unreachable;
            std.debug.print("Group [", .{});
            printExpressionTree(expr.group);
            _ = output.writeByteNTimes(' ', level)  catch unreachable;
            std.debug.print("]", .{});
            
        },
        Expr.ref => {
            std.debug.print("Ref<{d}:{d}:{d}>\n", .{ expr.ref.column, expr.ref.row, expr.ref.ref_flag });
        },
        Expr.err => {
            std.debug.print("Err<>\n", .{ });
        },
    }
}

pub fn printExpressionTree(expr: *Expr) void {
    printExpressionTreeHelper(expr, 1);
}

pub fn deinitExpressions(expr: *Expr, alloc: std.mem.Allocator) void {
    switch (expr.*) {
        Expr.binary_op => {
            deinitExpressions(expr.binary_op.lhs.?, alloc);
            deinitExpressions(expr.binary_op.rhs.?, alloc);
        },
        Expr.unary_op => {
            deinitExpressions(expr.unary_op.rhs.?, alloc);
        },
        Expr.ident => {
            alloc.free(expr.ident);
        },
        Expr.string => {
            alloc.free(expr.string);
        },
        Expr.group => {
            deinitExpressions(expr.group, alloc);
        },
        else => return,
    }
}



const MiB: comptime_int = 1024 * 1024;

pub fn readWholeFile(path: []const u8, alloc: std.mem.Allocator) ![]const u8 {
    var csv_raw_file = try std.fs.cwd().openFile(path, .{});
    defer csv_raw_file.close();
    var csv_reader = std.io.bufferedReader(csv_raw_file.reader()).reader();
    // swap this with dynamic check of file size and alloc just enough space for it
    return try csv_reader.readAllAlloc(alloc, 1 * MiB);
}

pub const CommandOptions = struct {
    input_file_path: []const u8 = undefined,

    pub fn parse(alloc: std.mem.Allocator) anyerror!CommandOptions {
        var args = try std.process.argsWithAllocator(alloc);
        defer args.deinit();
        _ = args.skip(); // skip program name
        var file = try args.next(alloc) orelse unreachable;
        return CommandOptions { .input_file_path = file };
    }

    pub fn deinit(self: *CommandOptions, alloc: std.mem.Allocator) void {
        alloc.free(self.input_file_path);
    }
};
