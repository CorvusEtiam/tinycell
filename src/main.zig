const std = @import("std");
const expressions = @import("./expression_parser.zig");

const MiB: comptime_int = 1024 * 1024;

pub const CellType = enum(u8) { empty = 0, numeric, expr, boolean, string };

pub const CellContent = union(CellType) {
    numeric: f64,
    expr: expressions.Expr,
    boolean: bool,
    string: []const u8,
    empty: void,
};

// cell.content.expr

pub const Cell = struct {
    const Self = @This();
    as: CellContent = .{ .empty = {} },
};

pub const TableSize = struct {
    rows: usize = 0,
    cols: usize = 0,
};

pub const Table = struct {
    const Self = @This();

    allocator: std.mem.Allocator = undefined,
    size: TableSize = .{},
    data: std.ArrayList(Cell) = undefined,

    pub fn printTypes(self: *const Self) void {
        // print each row
        var col_index: usize = 0;
        var index: usize = 0;
        while (index < self.data.items.len) {
            const active = std.meta.activeTag(self.data.items[index].as);
            std.debug.print("|{s}", .{ @tagName(active) });
            index += 1;
            col_index += 1;
            if (col_index == self.size.cols) {
                col_index = 0;
                std.debug.print("|\n", .{});
            }
        }
    }

    pub fn print(self: *Self) void {
        var col: usize = 0;
        var row: usize = 0;
        var cell_index: usize = 0;
        while ( row < self.size.rows ) : ({ row += 1; }) {
            col = 0;
            while ( col < self.size.cols ) : ({ col += 1; cell_index += 1; }) {
                const cell = self.data.items[cell_index];
                switch ( cell.as ) {
                    .empty => { std.debug.print("| Empty() ", .{ }); },
                    .boolean => { std.debug.print("| Boolean({any}) ", .{  cell.as.boolean }); },
                    .string => { std.debug.print("| String({s}) ", .{ cell.as.string }); },
                    .numeric => { std.debug.print("| Num({d}) ", .{  cell.as.numeric }); },
                    .expr => { std.debug.print("| Expr() ", .{  }); },
                } 
            }
            std.debug.print("|\n", .{ });
        }
    }

    pub fn deinit(self: *Self) void {
        self.data.deinit();
    }
};

pub const AppError = error{ParseExprError};


pub fn parseCellFromString(str: []const u8, alloc: std.mem.Allocator) Cell {
    var trimmed = std.mem.trim(u8, str, " ");
    if ( str.len == 0 ) {
        return Cell { .as = .{ .empty = {} } };
    } else if (trimmed[0] == '=') {
        var text = alloc.dupe(u8, trimmed[1..]) catch unreachable;
        return Cell{ .as = .{ .expr = expressions.Expr { .string = text } } };
    } else if ( std.mem.eql(u8, trimmed, "TRUE") or std.mem.eql(u8, trimmed, "FALSE") ) {
        return Cell{ .as = .{ .boolean = (trimmed[0] == 'T') } };        
    } else {
        if (std.fmt.parseFloat(f64, trimmed)) |value| {
            return Cell{ .as = .{ .numeric = value } };
        } else |_| {
            return Cell{ .as = .{ .string = str } };
        }
    }
}

pub fn readWholeFile(path: []const u8, alloc: std.mem.Allocator) ![]const u8 {
    var csv_raw_file = try std.fs.cwd().openFile(path, .{});
    defer csv_raw_file.close();
    var csv_reader = std.io.bufferedReader(csv_raw_file.reader()).reader();
    // swap this with dynamic check of file size and alloc just enough space for it
    return try csv_reader.readAllAlloc(alloc, 1 * MiB);
}

pub fn calculateTableSize(table: []const u8) TableSize {
    var row_iterator = std.mem.tokenize(u8, table, "\r\n");
    var max_column_count: usize = 0;

    var row_index: usize = 0;
    while (row_iterator.next()) |row| {
        var cell_count: usize = std.mem.count(u8, row, "\t") + 1;

        if (cell_count > max_column_count) {
            max_column_count = cell_count;
        }
        row_index += 1;
    }
    return .{ .rows = row_index, .cols = max_column_count };
}

pub fn parseTableFromTSV(table: []const u8, size: TableSize, alloc: std.mem.Allocator) !Table {
    var result_data = try std.ArrayList(Cell).initCapacity(alloc, size.cols * size.rows);
    try result_data.resize(size.cols * size.rows);

    var row_index: usize = 0;
    var col_index: usize = 0;
    var row_iter = std.mem.tokenize(u8, table, "\r\n");
    while (row_iter.next()) |row| {
        var cell_iter = std.mem.tokenize(u8, row, "\t");
        while (cell_iter.next()) |cell| {
            std.debug.print("Row x Col => {d} x {d}\n", .{ row_index, col_index });
            result_data.items[row_index * size.cols + col_index] = parseCellFromString(std.mem.trim(u8, cell, " "), alloc);
            col_index += 1;
        }
        if ( col_index < size.cols ) {
            while ( col_index < size.cols ) : ({ col_index += 1; }) {
                result_data.items[row_index * size.cols + col_index] = Cell { };
            }
        }
        col_index = 0;
        row_index += 1;
    }

    return Table{
        .data = result_data,
        .size = size,
        .allocator = alloc,
    };
}

const Tokenizer = @import("./Tokenizer.zig");

pub fn main() anyerror!void {
    var tokenizer = Tokenizer { .alloc = std.testing.allocator, .content = "A1+A2" };
    while ( tokenizer.nextToken() ) | t | {
        std.debug.print("Token: {s}", .{ @tagName(t.token_type) });
        if ( t.token_type == .ident ) {
            std.debug.print(" -> {s}\n", .{ t.content });
        } else {
            std.debug.print("\n", .{});
        }
    }
    var parser = expressions.Parser.init("A1+A2+A3+(D4*C15)", std.testing.allocator);
    var expr = parser.parse();
    expressions.printExpressionTree(expr);

    return;
}


pub fn main1() anyerror!void {
    // load whole csv file from args
    // we need: filename
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    defer {
        _ = gpa.deinit();
    }
    var input_file_path: []const u8 = undefined;
    defer allocator.free(input_file_path);

    {
        var args = try std.process.argsWithAllocator(allocator);
        _ = args.skip(); // skip program name
        input_file_path = try args.next(allocator) orelse unreachable;
        defer args.deinit();
    }

    std.log.info("File passed: {s}", .{input_file_path});
    var csv_content: []const u8 = readWholeFile(input_file_path, allocator) catch {
        std.log.err("There was error while loading file. Check if file exist", .{});
        std.log.err("Load from path: {s}", .{input_file_path});
        return;
    };
    defer allocator.free(csv_content);

    const table_size = calculateTableSize(csv_content);
    std.debug.print("Table size: {d}x{d}\n", .{ table_size.rows, table_size.cols });

    // replace with something little more space efficient

    var table = try parseTableFromTSV(csv_content, table_size, gpa.allocator());
    defer table.deinit();
    table.printTypes();
    std.debug.print("="**80 ++ "\n", .{});
    table.print();
}
