const std = @import("std");
const Expr = @import("./types.zig").Expr;
const ExprIndex = @import("./types.zig").ExprIndex;


fn printExpressionTreeHelper(ex: []const Expr, expr_index: ExprIndex, level: usize) void {
    const output = std.io.getStdErr().writer();
    const expr = ex[expr_index];
    switch (expr) {
        Expr.binary_op => {
            _ = output.writeByteNTimes(' ', level) catch unreachable;
            std.debug.print("BinOp<{s}> [\n", .{@tagName(expr.binary_op.operand)});
            printExpressionTreeHelper(ex, expr.binary_op.lhs, level + 1);
            printExpressionTreeHelper(ex, expr.binary_op.rhs, level + 1);
            _ = output.writeByteNTimes(' ', level)  catch unreachable;
            std.debug.print("]\n", .{});
        },
        Expr.unary_op => {
            _ = output.writeByteNTimes(' ', level)  catch unreachable;
            std.debug.print("UnOp<{s}> [\n", .{@tagName(expr.unary_op.operand)});
            printExpressionTreeHelper(ex, expr.unary_op.rhs, level + 1);
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
            printExpressionTree(ex, expr.group);
            _ = output.writeByteNTimes(' ', level)  catch unreachable;
            std.debug.print("]", .{});
            
        },
        Expr.ref => {
            std.debug.print("Ref<{d}:{d}\n", .{ expr.ref.column, expr.ref.row });
        },
        Expr.err => {
            std.debug.print("Err<>\n", .{ });
        },
    }
}

pub fn printExpressionTree(exp: []const Expr, start: ExprIndex) void {
    printExpressionTreeHelper(exp, start, 1);
}

pub fn deinitExpressions(expr: *Expr, alloc: std.mem.Allocator) void {
    switch (expr.*) {
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

    pub fn parse(alloc: std.mem.Allocator, comptime defaults: anytype) anyerror!CommandOptions {
        var args = try std.process.argsWithAllocator(alloc);
        defer args.deinit();
        _ = args.skip(); // skip program name
        
        if ( args.next(alloc) ) | arg_or_err | {
            var file = try arg_or_err;
            return CommandOptions { .input_file_path = file };
        } else {
            var file = try alloc.dupe(u8, @field(defaults, "input_file_path"));
            return CommandOptions { .input_file_path = file };
        }
       // const file: ?[]const u8 = (args.next(alloc) orelse null);
    }

    pub fn deinit(self: *CommandOptions, alloc: std.mem.Allocator) void {
        alloc.free(self.input_file_path);
    }
};
