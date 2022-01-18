const std = @import("std");
const Expr = @import("./expression_parser.zig").Expr;
const Table = @import("./Table.zig");
// FIXME: currently eval will print to stdout
pub fn evalExpression(context: *Table, expr: *Expr) void {
    _ = expr;
    _ = context;
}