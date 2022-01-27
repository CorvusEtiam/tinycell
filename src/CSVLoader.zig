const std = @import("std");
const utils = @import("./utils.zig");
const typedef = @import("./types.zig");
const expressions = @import("./expression_parser.zig");
const tbls = @import("./Table.zig");
const Table = tbls;
const Cell = typedef.Cell;
const Expr = typedef.Expr;

alloc: std.mem.Allocator,

const Self = @This();

pub fn loadFile(alloc: std.mem.Allocator, path: []const u8) !Table {
    var self = Self { .alloc = alloc };
    var content = try utils.readWholeFile(path, alloc);
    defer alloc.free(content);
    
    var size = self.calculateTableSize(content);
    var table =  self.parseTableFromTSV(content, size);
    return table;
}

fn parseCellFromString(self: *const Self, str: []const u8, expr_list: *std.ArrayList(Expr)) Cell {
    var trimmed = std.mem.trim(u8, str, " ");
    if (str.len == 0) {
        return Cell{};
    } else if (trimmed[0] == '=') {
        var parser = expressions.Parser.init(trimmed[1..], expr_list, self.alloc);
        return Cell{ .as = .{ .expr = .{ .expr = parser.parse() } } };
    } else if (std.mem.eql(u8, trimmed, "TRUE") or std.mem.eql(u8, trimmed, "FALSE")) {
        return Cell{ .as = .{ .value = .{ .boolean = (trimmed[0] == 'T') } } };
    } else {
        if (std.fmt.parseFloat(f64, trimmed)) |value| {
            return Cell.fromValue(.{ .numeric = value });
        } else |_| {
             
            var copy = self.alloc.dupe(u8, str) catch unreachable;
            return Cell.fromValue(.{ .string = copy });
        }
    }
}

fn calculateTableSize(_: *const Self, table: []const u8) tbls.TableSpan {
    var row_iterator = std.mem.tokenize(u8, table, "\r\n");
    const separator: u8 = sep: {
        if ( std.mem.startsWith(u8, table, "sep=") ) {
            _ = row_iterator.next();
            break :sep table[4];
        } else {
            break :sep '|';
        }
    };

    var max_column_count: u32 = 0;
    var row_index: u32 = 0;
    while (row_iterator.next()) |row| {
        var cell_count: u32 = @intCast(u32, std.mem.count(u8, row, &.{ separator }) + 1);

        if (cell_count > max_column_count) {
            max_column_count = cell_count;
        }
        row_index += 1;
    }
    return .{ .rows = row_index, .cols = max_column_count };
}

fn parseTableFromTSV(self: *Self, table: []const u8, size: tbls.TableSpan) !Table {
    var result_data = try std.ArrayList(Cell).initCapacity(self.alloc, size.cols * size.rows);
    try result_data.resize(size.cols * size.rows);
    var expr_list = std.ArrayList(Expr).init(self.alloc);

    var row_index: usize = 0;
    var col_index: usize = 0;
    var row_iter = std.mem.tokenize(u8, table, "\r\n");
    const separator: u8 = sep: {
        if ( std.mem.startsWith(u8, table, "sep=") ) {
            _ = row_iter.next();
            break :sep table[4];
        } else {
            break :sep '|';
        }
    };

    
    while (row_iter.next()) |row| {
        var cell_iter = std.mem.tokenize(u8, row, &.{ separator });
        while (cell_iter.next()) |cell| {
            result_data.items[row_index * size.cols + col_index] = self.parseCellFromString(std.mem.trim(u8, cell, " "), &expr_list);
            col_index += 1;
        }
        if (col_index < size.cols) {
            while (col_index < size.cols) : ({
                col_index += 1;
            }) {
                result_data.items[row_index * size.cols + col_index] = Cell{};
            }
        }
        col_index = 0;
        row_index += 1;
    }

    return Table{
        .data = result_data,
        .expr_list = expr_list,
        .size = size,
        .allocator = self.alloc,
    };
}
