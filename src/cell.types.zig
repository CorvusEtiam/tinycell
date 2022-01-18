const expressions = @import("./expression_parser.zig");

pub const EvaluationState = enum { 
    notEvaluated,
    inProgress,
    evaluated
};

pub const CellValueType = enum {
    numeric, boolean, string, empty, err
};

pub const CellValue = union(CellValueType) {
    numeric: f64,
    boolean: bool,
    string: []const u8,
    empty: void,
    err: void,
};

pub const CellExpr = struct {
    expr: *expressions.Expr = undefined,
    state: EvaluationState = .notEvaluated,
    value: CellValue = .{ .empty = {} },
};

pub const CellContentType = enum(u1) { expr, value };

pub const CellContent = union(CellContentType) {
    expr:  CellExpr,
    value: CellValue,
};

pub const Cell = struct {
    as: CellContent = .{ .value = .{ .empty = {} } },

    pub inline fn fromExpression(expr: *expressions.Expr) Cell {
        return .{ .as = .{ .expr = CellExpr { .expr = expr } } };
    }
    
    pub inline fn fromValue(val: CellValue) Cell {
        return .{ .as = .{ .value = val } };
    }
};

// by default both: row and column are references and not absolute indexes
pub const CellIndex = struct {
    row: u32,
    col: u32,
};
