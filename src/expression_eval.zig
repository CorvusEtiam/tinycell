const std = @import("std");
const utils = @import("./utils.zig");
const Table = @import("./Table.zig");
const AppError = @import("./main.zig").AppError;

const typedefs = @import("./types.zig");

const Expr  = typedefs.Expr;
const ExprIndex = typedefs.ExprIndex;
const CellValue = typedefs.CellValue;
const Cell  = typedefs.Cell;
const CellExpr  = typedefs.CellExpr;



pub fn evaluateExpression(context: *Table, ast_index: ExprIndex) AppError!CellValue {
    var ast_node: Expr = context.expr_list.items[ast_index];
    // std.log.info("Evaluate expression at index={d}", .{ ast_index });
    // utils.printExpressionTree(context.expr_list.items, ast_index);
    // std.log.info("Expression: {s}\n", .{ @tagName(std.meta.activeTag(ast_node)) } );
    switch (ast_node) {
        .err => return CellValue { .err = {} },
        .ident => return CellValue { .empty = { } },
        .string => return CellValue { .string = ast_node.string },
        .binary_op => |bop| {
            var lhs = try evaluateExpression(context, bop.lhs);
            var rhs = try evaluateExpression(context, bop.rhs);
            switch (bop.operand) {
                .plus => {
                    if (lhs.isNumeric() and rhs.isNumeric()) {
                        return CellValue { .numeric = lhs.numeric + rhs.numeric };
                    } else {
                        return error.wrongType;
                    }
                },
                .minus => {
                    if (lhs.isNumeric() and rhs.isNumeric()) {
                        return CellValue { .numeric = lhs.numeric - rhs.numeric };
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
            var rhs = try evaluateExpression(context, uop.rhs);
            switch (uop.operand) {
                .plus => {
                    if ( rhs.isNumeric() ) {
                        return CellValue{ .numeric = rhs.numeric };
                    } else {
                        return error.wrongType;
                    }
                },
                .minus => {
                    if ( rhs.isNumeric() ) {
                        return CellValue{ .numeric = -rhs.numeric };
                    } else {
                        return error.wrongType;
                    }
                },
                else => return error.wrongType,
            }
        },
        .ref => | ref | {
            var cell = try context.cellAt(ref);
            return evaluateCell(context, cell);
        },
        .group => {
            return evaluateExpression(context, ast_node.group);
        },
        .numeric => {
            return CellValue{ .numeric = ast_node.numeric };
        },
        .boolean => {
            return CellValue{ .boolean = ast_node.boolean };
        },
    }

    // string, numeric, boolean -> return copy
    // ident -> outside uop -> Error
    // ref -> cell address -> try to evaluate cell targeted by ref
    // binary_op -> operand_call(operand, left, right) -- contract OP(NUM, NUM)
    //    validate if both sides are numeric
    // uop -> operand_or_formula_call(operand, right);
    //    validate if types of evaluated args match required by function
    // group -> evaluateExpression(group.expr)
    // err -> return EvaluateError
}

pub fn evaluateCell(context: *Table, cell: *Cell) AppError!CellValue {
    
    //std.log.info("Evaluate cell at offset={d}, value={any}", .{ offset, cell });
    if (!cell.isExpr()) {
        return cell.as.value;
    }

    var cell_expr: *CellExpr = &cell.as.expr;
    if (cell_expr.state == .inProgress) {
        std.log.err("Circular dependency detected", .{});
        utils.printExpressionTree(context.expr_list.items, cell_expr.expr);
        return error.circularDependency;
    }

    if (cell_expr.state == .notEvaluated) {
        cell_expr.state = .inProgress;

        const ast_expr_index = cell_expr.expr;
//        std.log.info("Evaluate expression...", .{});
        var value = evaluateExpression(context, ast_expr_index) catch CellValue{ .err = {} };
        cell_expr.state = .evaluated;
        return value;
    } else {
        return cell.as.expr.
        value;
    }
}


pub fn evaluateTable(table: *Table) void {
    for ( table.data.items ) | *cell | {
        if ( cell.isExpr() ) {
//            std.debug.print("> Evaluating cell: {d}\n", .{index});
            var new_cell_value = evaluateCell(table, cell) catch CellValue { .err = { } };
            cell.updateValue(new_cell_value);
        }
    }
}







