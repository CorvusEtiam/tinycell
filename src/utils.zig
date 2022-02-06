const std = @import("std");
const typedef = @import("./types.zig");
const tbls = @import("./Table.zig");
const Expr = typedef.Expr;
const ExprIndex = typedef.ExprIndex;
const Cell = typedef.Cell;
const CellValue = typedef.CellValue;

const TableSpan = tbls.TableSpan;

fn printExpressionTreeHelper(ex: []const Expr, expr_index: ExprIndex, level: usize) void {
    const output = std.io.getStdErr().writer();
    const expr = ex[expr_index];
    switch (expr) {
        Expr.binary_op => {
            _ = output.writeByteNTimes(' ', level) catch unreachable;
            std.debug.print("BinOp<{s}> [\n", .{@tagName(expr.binary_op.operand)});
            printExpressionTreeHelper(ex, expr.binary_op.lhs, level + 1);
            printExpressionTreeHelper(ex, expr.binary_op.rhs, level + 1);
            _ = output.writeByteNTimes(' ', level) catch unreachable;
            std.debug.print("]\n", .{});
        },
        Expr.unary_op => {
            _ = output.writeByteNTimes(' ', level) catch unreachable;
            std.debug.print("UnOp<{s}> [\n", .{@tagName(expr.unary_op.operand)});
            printExpressionTreeHelper(ex, expr.unary_op.rhs, level + 1);
            _ = output.writeByteNTimes(' ', level) catch unreachable;
            std.debug.print("]\n", .{});
        },
        Expr.boolean => {
            _ = output.writeByteNTimes(' ', level + 1) catch unreachable;
            std.debug.print("Bool<{any}>", .{expr.boolean});
        },
        Expr.ident => {
            _ = output.writeByteNTimes(' ', level + 1) catch unreachable;
            std.debug.print("Ident<{s}>", .{expr.ident});
        },
        Expr.string => {
            _ = output.writeByteNTimes(' ', level + 1) catch unreachable;
            std.debug.print("Str<{s}>", .{expr.string});
        },
        Expr.numeric => {
            _ = output.writeByteNTimes(' ', level + 1) catch unreachable;
            std.debug.print("Num<{d}>", .{expr.numeric});
        },
        Expr.group => {
            _ = output.writeByteNTimes(' ', level) catch unreachable;
            std.debug.print("Group [", .{});
            printExpressionTree(ex, expr.group);
            _ = output.writeByteNTimes(' ', level) catch unreachable;
            std.debug.print("]", .{});
        },
        Expr.ref => {
            std.debug.print("Ref<{d}:{d}\n", .{ expr.ref.column, expr.ref.row });
        },
        Expr.err => {
            std.debug.print("Err<>\n", .{});
        },
        Expr.formula => |formula| {
            std.debug.print("Formula[{s}]<", .{formula.name});
            for (formula.arguments) |arg| {
                printExpressionTreeHelper(ex, arg, level + 1);
                std.debug.print("; ", .{});
            }
            std.debug.print(">", .{});
        },
        Expr.clone => |source_dir| {
            std.debug.print("Clone<in-dir={s}>\n", .{@tagName(source_dir.direction)});
        },
    }
}

pub fn printExpressionTree(exp: []const Expr, start: ExprIndex) void {
    printExpressionTreeHelper(exp, start, 1);
}

pub fn deinitExpressions(exp: []Expr, expr: *Expr, alloc: std.mem.Allocator) void {
    switch (expr.*) {
        Expr.ident => {
            alloc.free(expr.ident);
        },
        Expr.string => {
            alloc.free(expr.string);
        },
        Expr.group => {
            deinitExpressions(exp, &exp[expr.group], alloc);
        },
        else => return,
    }
}

const MiB: comptime_int = 1024 * 1024;


pub fn readWholeFile(path: []const u8, alloc: std.mem.Allocator) ![]const u8 {
    const real_path = try std.fs.realpathAlloc(alloc, path);
    defer alloc.free(real_path);
    var csv_raw_file = std.fs.openFileAbsolute(real_path, .{}) catch {
        std.log.err("Cannot open provided file: {s}", .{ real_path });
        std.log.err("FileNotFound", .{});
        unreachable;
    };
    defer csv_raw_file.close();
    var csv_reader = std.io.bufferedReader(csv_raw_file.reader()).reader();
    // swap this with dynamic check of file size and alloc just enough space for it
    return try csv_reader.readAllAlloc(alloc, 1 * MiB);
}

pub const CommandOptions = struct {
    alloc: std.mem.Allocator,
    input_file_path: []const u8 = undefined,

    pub fn parse(alloc: std.mem.Allocator, comptime defaults: anytype) anyerror!CommandOptions {
        var args = try std.process.argsWithAllocator(alloc);
        defer args.deinit();
        _ = args.skip(); // skip program name
        var file = args.next() orelse @field(defaults, "input_file_path");
        var copy = alloc.dupe(u8, file) catch @panic("Alloc error");
        
        return CommandOptions{
            .alloc = alloc,
            .input_file_path = copy,
        };
    }

    pub fn deinit(self: *CommandOptions) void {
        self.alloc.free(self.input_file_path);
    }
};

fn cellValueWidth(cell_value: CellValue) usize {
    var buf: [32]u8 = undefined;

    return switch (cell_value) {
        .numeric => blk: {
            const result = std.fmt.bufPrint(&buf, "{d:.2}", .{cell_value.numeric}) catch &buf;
            break :blk result.len;
        },
        .boolean => |boolean| if (boolean) @as(usize, 6) else @as(usize, 7),
        .string => |str| str.len + 2,
        .empty => @as(usize, 3),
        .err => @as(usize, 7),
    };
}

pub fn printCell(cell_value: CellValue, max_size: usize, writer: anytype) !void {
    switch (cell_value) {
        .err => {
            try writer.print("<err>", .{});
            _ = try writer.writeByteNTimes(' ', max_size - 5);
        },
        .boolean => |b| {
            if (b) {
                try writer.print("TRUE", .{});
                _ = try writer.writeByteNTimes(' ', max_size - 4);
            } else {
                try writer.print("FALSE", .{});
                _ = try writer.writeByteNTimes(' ', max_size - 5);
            }
        },
        .empty => {
            _ = try writer.writeByteNTimes(' ', max_size);
        },
        .string => |s| {
            if (s.len <= max_size) {
                _ = try writer.write(s);
                _ = try writer.writeByteNTimes(' ', max_size - s.len);
            } else {
                _ = try writer.write(s[0 .. max_size - 1]);
                _ = try writer.write("]");
            }
        },
        .numeric => |n| {
            var buf: [32]u8 = undefined;
            var result = try std.fmt.bufPrint(&buf, "{d:.2}", .{n});
            if (result.len <= max_size) {
                _ = try writer.write(result);
                _ = try writer.writeByteNTimes(' ', max_size - result.len);
            } else {
                _ = try writer.write("######");
                _ = try writer.writeByteNTimes('#', max_size - 6);
            }
        },
    }
}

pub fn printSliceAsTable(alloc: std.mem.Allocator, table_data: []Cell, dim: TableSpan) !void {
    var bufwriter = std.io.bufferedWriter(std.io.getStdOut().writer());
    var stdout = bufwriter.writer();
    // iterate over columns first computing their widths
    var widths = try alloc.alloc(usize, dim.cols);
    defer alloc.free(widths);

    {
        var y: usize = 0;
        var x: usize = 0;
        var max_column_width: usize = 0;
        while (x < dim.cols) : ({
            x += 1;
            y = 0;
        }) {
            max_column_width = 0;
            while (y < dim.rows) : ({
                y += 1;
            }) {
                const cell_width = cellValueWidth(table_data[y * dim.cols + x].getValue());
                max_column_width = if (cell_width > max_column_width) cell_width else max_column_width;
            }
            widths[x] = if (max_column_width > 32) 32 else max_column_width;
        }
    }

    {
        var y: usize = 0;
        var x: usize = 0;
        var index: usize = 0;
        while (y < dim.rows) : ({
            y += 1;
            x = 0;
        }) {
            while (x < dim.cols) : ({
                x += 1;
                index += 1;
            }) {
                _ = try stdout.write("| ");
                const final_value = table_data[index].getValue();
                try printCell(final_value, widths[x], &stdout);
                _ = try stdout.write(" ");
            }
            _ = try stdout.write(" |\n");
        }

        try bufwriter.flush();
    }
}

pub const ExprStore = struct {
    const Wrapper = struct {
        expr: *Expr,
        index: usize,
    };

    store: std.ArrayList(Expr),
    // we use create and not alloc because we are not deallocating this expr ourselves
    // This is just thin helper around ArrayList
    pub fn create(alloc: std.mem.Allocator) ExprStore {
        var list = std.ArrayList(Expr).init(alloc);
        return ExprStore{ .store = list };
    }

    pub fn createExpression(self: *ExprStore) Wrapper {
        self.store.append(Expr { .boolean = false }) catch {
            std.log.err("Alloc failed inside createExpression", .{});
            std.process.exit(1);
        };

        const index = self.store.items.len - 1;
        var wrapper = .{
            .expr = &self.store.items[index],
            .index = index,
        };

        return wrapper;
    }
};
