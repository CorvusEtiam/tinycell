const std = @import("std");
const TokType = @import("./Tokenizer.zig").TokType;
const AppError = @import("./main.zig").AppError;

pub const ExprIndex = usize;

// literal    ->  number | 'FALSE' | 'TRUE'
// primary    ->  literal | '(' expr ')'
// formula    ->  ident '(' primary (',' primary)* ')'
// unary      ->  formula | '-' unary | primary
// factor     ->  unary (('*' | '/') unary)*
// term       ->  factor (('+'|'-') factor)*
// comparison ->  term (('>'|'>='|'<='|'<') term)*
// equality   ->  comparison ('<>'|'==' comparison)*

pub const ExprType = enum(u8) {
    numeric = 0,
    boolean,
    string,
    ident,
    binary_op,
    unary_op,
    group,
    err,
    ref,
    formula,
    clone,
};

pub const BinOpExpr = struct {
    lhs: ExprIndex = 0,
    operand: TokType = .ident,
    rhs: ExprIndex = 0,
};

pub const UnOpExpr = struct {
    operand: TokType = .ident,
    rhs: ExprIndex = 0,
};

pub const Formula = struct {
    name: []const u8,
    arguments: []ExprIndex,
};

pub const Cardinal = enum {
    north,
    east,
    south,
    west,

    pub fn fromChar(char: u8) AppError!Cardinal {
        return switch (char) {
            '^' => .north,
            'v', 'V' => .south,
            '<' => .west,
            '>' => .east,
            else => error.parseError,
        };
    }
// =:>
    pub fn getOpposite(self: Cardinal) Cardinal {
        return switch (self) {
            .north => .south,
            .east => .west,
            .south => .north,
            .west => .east,
        };
    }
};

pub const Clone = struct {
    direction: Cardinal,
};

pub const Expr = union(ExprType) {
    numeric: f64,
    boolean: bool,
    string: []const u8,
    ident: []const u8, // those can be cell references, function names and so on,
    binary_op: BinOpExpr,
    unary_op: UnOpExpr,
    group: ExprIndex,
    err: []const u8,
    ref: CellIndex,
    formula: Formula,
    clone: Clone,
};

pub const EvaluationState = enum { notEvaluated, inProgress, evaluated };

pub const CellValueType = enum { numeric, boolean, string, empty, err };

pub const CellValue = union(CellValueType) {
    const Self = @This();
    numeric: f64,
    boolean: bool,
    string: []const u8,
    empty: void,
    err: void,

    pub fn isNumeric(self: Self) bool {
        return switch (self) {
            .numeric => true,
            else => false,
        };
    }
};

pub const CellExpr = struct {
    expr: ExprIndex = 0,
    state: EvaluationState = .notEvaluated,
    value: CellValue = .{ .empty = {} },
};

pub const CellContentType = enum {
    expr,
    value,
};

pub const CellContent = union(CellContentType) {
    expr: CellExpr,
    value: CellValue,
};

pub const Cell = struct {
    index: CellIndex,
    as: CellContent = .{ .value = .{ .empty = {} } },

    pub fn getValue(self: *Cell) CellValue {
        switch (self.as) {
            .expr => |expr| {
                if (expr.state == .evaluated) {
                    return expr.value;
                } else {
                    return CellValue{ .empty = {} };
                }
            },
            .value => {
                return self.as.value;
            },
        }
    }

    pub fn getCellType(self: Cell) CellContentType {
        return std.meta.activeTag(self.as);
    }

    pub inline fn fromExpression(index: CellIndex, expr: ExprIndex) Cell {
        return .{ .index = index, .as = .{ .expr = CellExpr{ .expr = expr } } };
    }

    pub inline fn fromValue(index: CellIndex, val: CellValue) Cell {
        return .{ .index = index, .as = .{ .value = val } };
    }

    pub inline fn fromEmpty(index: CellIndex) Cell {
        return .{ .index = index };
    }

    pub fn updateValue(self: *Cell, val: CellValue) void {
        switch (self.as) {
            .expr => {
                self.as.expr.value = val;
            },
            .value => {
                self.as.value = val;
            },
        }
    }
};

// by default both: row and column are references and not absolute indexes
pub const CellIndex = struct {
    row: u32 = 0,
    column: u32 = 0,

    pub fn offsetInDirection(self: CellIndex, dir: Cardinal) AppError!CellIndex {
        var copy = CellIndex{ .row = self.row, .column = self.column };
        switch (dir) {
            .north => {
                if (copy.row > 0) {
                    copy.row -= 1;
                } else {
                    return error.outOfBoundAccess;
                }
            },
            .west => {
                if (self.column > 0) {
                    copy.column -= 1;
                } else {
                    return error.outOfBoundAccess;
                }
            },
            .south => {
                copy.row += 1;
            },
            .east => {
                copy.column += 1;
            },
        }

        return copy;
    }
};
