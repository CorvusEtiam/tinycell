const std = @import("std");
const expressions = @import("./expression_parser.zig");
const evaluator = @import("./expression_eval.zig");
const utils = @import("./utils.zig");
const cells = @import("./types.zig");

const tbls = @import("./Table.zig");
const Table = tbls;
const Cell = cells.Cell;
const Expr = cells.Expr;
pub const AppError = error{ parseExprError, outOfBoundAccess, wrongType, circularDependency };

pub fn parseCellFromString(str: []const u8, alloc: std.mem.Allocator, expr_list: *std.ArrayList(Expr)) Cell {
    var trimmed = std.mem.trim(u8, str, " ");
    if (str.len == 0) {
        return Cell{};
    } else if (trimmed[0] == '=') {
        var parser = expressions.Parser.init(trimmed[1..], expr_list, alloc);
        return Cell{ .as = .{ .expr = .{ .expr = parser.parse() } } };
    } else if (std.mem.eql(u8, trimmed, "TRUE") or std.mem.eql(u8, trimmed, "FALSE")) {
        return Cell{ .as = .{ .value = .{ .boolean = (trimmed[0] == 'T') } } };
    } else {
        if (std.fmt.parseFloat(f64, trimmed)) |value| {
            return Cell.fromValue(.{ .numeric = value });
        } else |_| {
            return Cell.fromValue(.{ .string = str });
        }
    }
}

pub fn calculateTableSize(table: []const u8) tbls.TableSpan {
    var row_iterator = std.mem.tokenize(u8, table, "\r\n");
    var max_column_count: u32 = 0;

    var row_index: u32 = 0;
    while (row_iterator.next()) |row| {
        var cell_count: u32 = @intCast(u32, std.mem.count(u8, row, "\t") + 1);

        if (cell_count > max_column_count) {
            max_column_count = cell_count;
        }
        row_index += 1;
    }
    return .{ .rows = row_index, .cols = max_column_count };
}

pub fn parseTableFromTSV(table: []const u8, size: tbls.TableSpan, alloc: std.mem.Allocator) !Table {
    var result_data = try std.ArrayList(Cell).initCapacity(alloc, size.cols * size.rows);
    try result_data.resize(size.cols * size.rows);
    var expr_list = std.ArrayList(Expr).init(alloc);

    var row_index: usize = 0;
    var col_index: usize = 0;
    var row_iter = std.mem.tokenize(u8, table, "\r\n");
    while (row_iter.next()) |row| {
        var cell_iter = std.mem.tokenize(u8, row, "\t");
        while (cell_iter.next()) |cell| {
            std.debug.print("Row x Col => {d} x {d}\n", .{ row_index, col_index });
            result_data.items[row_index * size.cols + col_index] = parseCellFromString(std.mem.trim(u8, cell, " "), alloc, &expr_list);
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
        .allocator = alloc,
    };
}

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    // FIXME: Deallocate everything. Maybe store expressions in a single buffer like tsoding did?
    var command_options = utils.CommandOptions.parse(allocator, .{ .input_file_path = "data/input.csv" }) catch {
        std.debug.panic("Unhandled error in command options", .{});
    };

    std.log.info("Options passed: {s}", .{command_options.input_file_path});
    var csv_content: []const u8 = utils.readWholeFile(command_options.input_file_path, allocator) catch {
        std.log.err("There was error while loading file. Check if file exist", .{});
        std.log.err("Load from path: {s}", .{command_options.input_file_path});
        return;
    };
    // defer allocator.free(csv_content);

    const table_size = calculateTableSize(csv_content);
    std.debug.print("Table size: {d}x{d}\n", .{ table_size.rows, table_size.cols });

    var table = try parseTableFromTSV(csv_content, table_size, gpa.allocator());
    defer table.deinit();

    std.debug.print("=" ** 80 ++ "\n", .{});
    table.dump();
    std.debug.print("\n" ++ ("=" ** 80) ++ "\n", .{});
    evaluator.evaluateTable(&table);
    table.dump();
}
