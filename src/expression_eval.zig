const std = @import("std");
const utils = @import("./utils.zig");
const Table = @import("./Table.zig");
const AppError = @import("./main.zig").AppError;

const typedefs = @import("./types.zig");

const Expr = typedefs.Expr;
const ExprIndex = typedefs.ExprIndex;
const CellValue = typedefs.CellValue;
const CellIndex = typedefs.CellIndex;

const Cell = typedefs.Cell;
const CellExpr = typedefs.CellExpr;

pub fn evaluateExpression(context: *Table, cell_index: CellIndex, ast_index: ExprIndex) AppError!CellValue {
    var ast_node: Expr = context.expr_list.items[ast_index];
    // std.log.info("Evaluate expression at index={d}", .{ ast_index });
    // utils.printExpressionTree(context.expr_list.items, ast_index);
    // std.log.info("Expression: {s}\n", .{ @tagName(std.meta.activeTag(ast_node)) } );
    switch (ast_node) {
        .err => return CellValue{ .err = {} },
        .ident => return CellValue{ .empty = {} },
        .string => return CellValue{ .string = ast_node.string },
        .binary_op => |bop| {
            var lhs = try evaluateExpression(context, cell_index, bop.lhs);
            var rhs = try evaluateExpression(context, cell_index, bop.rhs);
            switch (bop.operand) {
                .plus => {
                    if (lhs.isNumeric() and rhs.isNumeric()) {
                        return CellValue{ .numeric = lhs.numeric + rhs.numeric };
                    } else {
                        return error.wrongType;
                    }
                },
                .minus => {
                    if (lhs.isNumeric() and rhs.isNumeric()) {
                        return CellValue{ .numeric = lhs.numeric - rhs.numeric };
                    } else {
                        return error.wrongType;
                    }
                },
                .mul => {
                    if (lhs.isNumeric() and rhs.isNumeric()) {
                        return CellValue{ .numeric = lhs.numeric * rhs.numeric };
                    } else {
                        return error.wrongType;
                    }
                },
                .slash => {
                    if (lhs.isNumeric() and rhs.isNumeric()) {
                        return CellValue{ .numeric = lhs.numeric / rhs.numeric };
                    } else {
                        return error.wrongType;
                    }
                },
                else => return error.wrongType,
            }
        },
        .unary_op => |uop| {
            var rhs = try evaluateExpression(context, cell_index, uop.rhs);
            switch (uop.operand) {
                .plus => {
                    if (rhs.isNumeric()) {
                        return CellValue{ .numeric = rhs.numeric };
                    } else {
                        return error.wrongType;
                    }
                },
                .minus => {
                    if (rhs.isNumeric()) {
                        return CellValue{ .numeric = -rhs.numeric };
                    } else {
                        return error.wrongType;
                    }
                },
                else => return error.wrongType,
            }
        },
        .ref => |ref| {
            var cell = try context.cellAt(ref);
            return evaluateCell(context, cell);
        },
        .group => {
            return evaluateExpression(context, cell_index, ast_node.group);
        },
        .numeric => {
            return CellValue{ .numeric = ast_node.numeric };
        },
        .boolean => {
            return CellValue{ .boolean = ast_node.boolean };
        },
        .formula => {
            // TODO: Formula evaluation
            return CellValue{ .empty = {} };
        },
        .clone => | clone_expr | {
            const direction = clone_expr.direction;
            const new_index = try cell_index.offsetInDirection(direction.getOpposite());
            const new_index_cell = try context.cellAt(new_index);
            return evaluateCell(context, new_index_cell); 
        },
    }
}

pub fn evaluateClone(context: *Table, cell: *Cell, clone: typedefs.Clone) AppError!CellValue {
    _ = .{ context, cell, clone };
    return error.parseExprError;
}

pub fn evaluateCell(context: *Table, cell: *Cell) AppError!CellValue {
    if ( cell.getCellType() == .value ) {
        return cell.as.value;
    }
    var cell_expr: *CellExpr = &cell.as.expr;
    if (cell_expr.state == .inProgress) {
        std.log.err("Evaluate cell: R:{d} C:{d}\n", .{ cell.index.row, cell.index.column });
        std.log.err("Circular dependency detected", .{});
        utils.printExpressionTree(context.expr_list.items, cell_expr.expr);
        return error.circularDependency;
    }
    if (cell_expr.state == .notEvaluated) {
        cell_expr.state = .inProgress;
        const ast_expr_index = cell_expr.expr;
        var value = evaluateExpression(context, cell.index, ast_expr_index) catch CellValue{ .err = {} };
        cell_expr.state = .evaluated;
        return value;
    } else {
        return cell.as.expr.value;
    }
}

pub fn evaluateTable(table: *Table) void {
    for (table.data.items) |*cell| {
        if (cell.getCellType() == .expr and cell.as.expr.state != .evaluated) {
            var new_cell_value = evaluateCell(table, cell) catch CellValue{ .err = {} };
            cell.updateValue(new_cell_value);
        }
    }
}
