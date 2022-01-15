const std = @import("std");
const Tokenizer = @import("./Tokenizer.zig");

// literal -> number | 'FALSE' | 'TRUE'
// primary -> literal | '(' expr ')'
// unary -> '-' unary | primary
// factor -> unary (('*' | '/') unary)*
// term   -> factor (('+'|'-') factor)*
// comparison -> term (('>'|'>='|'<='|'<') term)*
// equality -> comparison ('<>'|'==' comparison)*

pub const ExprType = enum(u8) { numeric = 0, boolean, string, ident, binary_op, unary_op, group };

pub const BinOpExpr = struct {
    lhs: ?*Expr = null,
    operand: Tokenizer.TokType = .ident,
    rhs: ?*Expr = null,
};

pub const UnOpExpr = struct {
    operand: Tokenizer.TokType = .ident,
    rhs: ?*Expr = null,
};

pub const Expr = union(ExprType) {
    numeric: f64,
    boolean: bool,
    string: []const u8,
    ident: []const u8, // those can be cell references, function names and so on,
    binary_op: BinOpExpr,
    unary_op: UnOpExpr,
    group: *Expr,
};

const Token = Tokenizer.Token;

pub const Parser = struct {
    const Self = @This();

    alloc: std.mem.Allocator,
    tokenizer: Tokenizer,
    current_token: ?Token = null,

    pub fn init(expr: []const u8, alloc: std.mem.Allocator) Parser {
        return Parser{
            .alloc = alloc,
            .tokenizer = Tokenizer{ .alloc = alloc, .content = expr },
        };
    }
    // A1<>B2
    fn matchToken(self: *Self, types: []const Tokenizer.TokType) bool {
        if (self.current_token == null) return false;
        const current_token_type = self.current_token.?.token_type;
        for (types) |tok_type| {
            if (current_token_type == tok_type) {
                return true;
            }
        }
        return false;
    }

    pub fn advanceToken(self: *Self) void {
        self.current_token = self.tokenizer.nextToken();
    }

    fn newBinaryOp(self: *Self, lhs: *Expr, op: Tokenizer.TokType, rhs: *Expr) *Expr {
        var tmp = self.alloc.create(Expr) catch unreachable;
        tmp.* = Expr{ .binary_op = .{
            .lhs = lhs,
            .operand = op,
            .rhs = rhs,
        } };
        return tmp;
    }

    pub fn parse(self: *Self) *Expr {
        return self.parseEquality();
    }

    fn parseEquality(self: *Self) *Expr {
        var expr = self.parseComparison();
        while (self.matchToken(&.{ .eq, .neq })) {
            var rhs = self.parseComparison();
            expr = self.newBinaryOp(expr, self.current_token.?.token_type, rhs);
        }
        return expr;
    }

    fn parseComparison(self: *Self) *Expr {
        var expr: *Expr = self.parseTerm();
        while (self.matchToken(&.{ .gt, .gte, .lt, .lte })) {
            var rhs = self.parseTerm();
            expr = self.newBinaryOp(expr, self.current_token.?.token_type, rhs);
        }
        return expr;
    }

    fn parseTerm(self: *Self) *Expr {
        var expr = self.parseFactor();
        while (self.matchToken(&.{ .plus, .minus })) {
            var rhs = self.parseFactor();
            expr = self.newBinaryOp(expr, self.current_token.?.token_type, rhs);
        }

        return expr;
    }

    fn parseFactor(self: *Self) *Expr {
        var expr = self.parseUnary();
        while (self.matchToken(&.{ .slash, .mul })) {
            var rhs = self.parseUnary();
            expr = self.newBinaryOp(expr, self.current_token.?.token_type, rhs);
        }

        return expr;
    }

    fn parseUnary(self: *Self) *Expr {
        if (self.matchToken(&.{.minus})) {
            var operator = self.current_token.?.token_type;
            self.advanceToken();
            var rhs = self.parseUnary();
            var expr_tmp = self.alloc.create(Expr) catch unreachable;

            expr_tmp.* = Expr{ .unary_op = .{ .operand = operator, .rhs = rhs } };
            return expr_tmp;
        }

        return self.parsePrimary();
    }

    fn parsePrimary(self: *Self) *Expr {
        var primary_expr = self.alloc.create(Expr) catch unreachable;
        primary_expr.* = prim: {
            break :prim switch (self.current_token.?.token_type) {
                .false_ => Expr{ .boolean = false },
                .true_ => Expr{ .boolean = true },
                .ident => Expr{ .ident = self.current_token.?.content },
                .lparen => {
                    var expr = self.parse();
                    self.advanceToken();
                    if (!self.matchToken(&.{.rparen})) {
                        std.debug.panic("Expected ')' token", .{});
                        break :prim Expr { .ident = self.current_token.?.content };
                    } else {
                        break :prim Expr{ .group = expr };
                    }
                },
                else => unreachable,
            };
        };
        return primary_expr;
    }
};

pub fn printExpressionTree(expr: *Expr) void {
    switch (expr.*) {
        Expr.binary_op => {
            printExpressionTree(expr.binary_op.lhs.?);
            std.debug.print(" Op<{s}> ", .{@tagName(expr.binary_op.operand)});
            printExpressionTree(expr.binary_op.rhs.?);
        },
        Expr.unary_op => {
            std.debug.print(" Op<{s}> ", .{@tagName(expr.unary_op.operand)});
            printExpressionTree(expr.unary_op.rhs.?);
        },
        Expr.boolean => {
            std.debug.print("Bool<{any}>\n", .{expr.boolean});
        },
        Expr.ident => {
            std.debug.print("Ident<{s}>\n", .{expr.ident});
        },
        Expr.string => {
            std.debug.print("Str<{s}>\n", .{expr.string});
        },
        Expr.numeric => {
            std.debug.print("Num<{d}>\n", .{expr.numeric});
        },
        Expr.group => {
            std.debug.print("Group<\n", .{});
            printExpressionTree(expr.group);
            std.debug.print(">", .{});
        },
    }
}
