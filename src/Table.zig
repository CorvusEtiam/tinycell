const std = @import("std");
const utils = @import("./utils.zig");
const typedefs = @import("./types.zig");
const AppError = @import("./main.zig").AppError;
const parser = @import("./expression_parser.zig");

const Expr  = typedefs.Expr;
const Cell  = typedefs.Cell;
const CellValue  = typedefs.CellValue;
const CellContent = typedefs.CellContent; 
const CellIndex = typedefs.CellIndex;


pub const TableSpan = struct {
    rows: u32 = 0,
    cols: u32 = 0,
};

const Self = @This();

allocator: std.mem.Allocator = undefined,
size: TableSpan = .{},
expr_list: std.ArrayList(Expr) = undefined,
data: std.ArrayList(Cell) = undefined,

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
            const cell: Cell = self.data.items[cell_index];
            switch (cell.as) {
                CellContent.value => |val| switch (val) {
                    CellValue.empty => {
                        std.debug.print("| Empty() ", .{});
                    },
                    CellValue.boolean => {
                        std.debug.print("| Boolean({any}) ", .{val.boolean});
                    },
                    CellValue.string => {
                        std.debug.print("| String({s}) ", .{val.string});
                    },
                    CellValue.numeric => {
                        std.debug.print("| Num({d}) ", .{val.numeric});
                    },
                    CellValue.err => {
                        std.debug.print("| Err ", .{});
                    },
                },
                CellContent.expr => | expr | {
                    switch ( expr.value ) {
                        .numeric => std.debug.print("| Expr({d})", .{ expr.value.numeric }),
                        .string => std.debug.print("| Expr({s})", .{ expr.value.string }),
                        .err => std.debug.print("| Err ", .{ }),
                        else => std.debug.print("| Expr({any})", .{ expr.value }),
                    }
                    // std.debug.print("| Expr({any}) ", .{ expr.value });
                },
            }
        }
        std.debug.print("|\n", .{});
    }
}

pub fn deinit(self: *Self) void {
    self.expr_list.deinit();
    self.data.deinit();
}

pub fn cellAt(self: *Self, at: CellIndex) AppError!*Cell {
    if (at.row >= self.size.rows or at.column >= self.size.cols) {
        return error.outOfBoundAccess;
    }
    return &self.data.items[at.row * self.size.cols + at.column];
}
