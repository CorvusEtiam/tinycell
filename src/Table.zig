const std = @import("std");
const utils = @import("./utils.zig");
const cells = @import("./cell.types.zig");
const AppError = @import("./main.zig").AppError;

pub const TableSpan = struct {
    rows: usize = 0,
    cols: usize = 0,
};

const Self = @This();

allocator: std.mem.Allocator = undefined,
size: TableSpan = .{},
data: std.ArrayList(cells.Cell) = undefined,

pub fn dump(self: *Self) void {
    var col: usize = 0;
    var row: usize = 0;
    var cell_index: usize = 0;
    while (row < self.size.rows) : ({
        row += 1;
    }) {
        col = 0;
        while (col < self.size.cols) : ({
            col += 1;
            cell_index += 1;
        }) {
            const cell: cells.Cell = self.data.items[cell_index];
            switch (cell.as) {
                cells.CellContent.value => |val| switch (val) {
                    cells.CellValue.empty => {
                        std.debug.print("| Empty() ", .{});
                    },
                    cells.CellValue.boolean => {
                        std.debug.print("| Boolean({any}) ", .{val.boolean});
                    },
                    cells.CellValue.string => {
                        std.debug.print("| String({s}) ", .{val.string});
                    },
                    cells.CellValue.numeric => {
                        std.debug.print("| Num({d}) ", .{val.numeric});
                    },
                    cells.CellValue.err => {
                        std.debug.print("| Err ", .{});
                    },
                },
                cells.CellContent.expr => {
                    std.debug.print("| Expr() ", .{});
                },
            }
        }
        std.debug.print("|\n", .{});
    }
}

pub fn deinit(self: *Self) void {
    for (self.data.items) |cell| {
        switch (cell.as) {
            cells.CellContent.expr => |expr| {
                utils.deinitExpressions(expr.expr, self.allocator);
            },
            else => continue,
        }
    }
    self.data.deinit();
}

pub fn cellAt(self: *Self, at: cells.CellIndex) AppError!*cells.Cell {
    if (at.row >= self.size.rows or at.col >= self.size.cols) {
        return error.AppError.outOfBoundAccess;
    }
    return &self.data.items[at.row * self.size.cols + at.col];
}
