const std = @import("std");

const utils = @import("./utils.zig");
const Tokenizer = @import("./Tokenizer.zig");
const typedefs = @import("./types.zig");

const Token = Tokenizer.Token;

const ExprIndex = typedefs.ExprIndex;
const CellIndex = typedefs.CellIndex;
const Expr = typedefs.Expr;
const ExprList = std.ArrayList(Expr);

pub const Parser = struct {
    const Self = @This();

    store: *utils.ExprStore,
    alloc: std.mem.Allocator,
    tokenizer: Tokenizer,
    current_token: ?Token = null,

    pub fn init(expr: []const u8, store: *utils.ExprStore, alloc: std.mem.Allocator) Parser {
        return Parser{
            .alloc = alloc,
            .store = store,
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

    pub fn advanceToken(self: *Self) ?Token {
        const current = self.current_token;
        self.current_token = self.tryNextToken();
        return current;
    }

    pub fn expectToken(self: *Self, token_type: Tokenizer.TokType) bool {
        if (self.current_token) |token| {
            return token.token_type == token_type;
        } else {
            return false;
        }
    }

    fn newBinaryOp(self: *Self, lhs: ExprIndex, op: Tokenizer.TokType, rhs: ExprIndex) ExprIndex {
        const tmp = self.store.createExpression();
        tmp.expr.* = Expr{ .binary_op = .{
            .lhs = lhs,
            .operand = op,
            .rhs = rhs,
        } };
        return tmp.index;
    }

    fn newUnaryOp(self: *Self, operand: Tokenizer.TokType, rhs: ExprIndex) ExprIndex {
        const tmp = self.store.createExpression();
        tmp.expr.* = Expr{ .unary_op = .{ .operand = operand, .rhs = rhs } };
        return tmp.index;
    }

    fn tryNextToken(self: *Self) ?Token {
        if ( self.tokenizer.nextToken() ) | token_or_null | { 
            return token_or_null;
        } else | err | {
            if ( self.current_token ) | current | {
                std.log.err("Error spotted after token: {any}", .{ current });
            } else {
                std.log.err("Spotted token is null: {s}", .{ @errorName(err) });    
            }

            return null;
        }
    }

    pub fn parse(self: *Self) ExprIndex {
        self.current_token = self.tryNextToken();
        return self.parseEquality();
    }

    fn parseEquality(self: *Self) ExprIndex {
        var expr = self.parseComparison();
        while (self.matchToken(&.{ .eq, .neq })) {
            var operator = self.advanceToken();
            var rhs = self.parseComparison();
            expr = self.newBinaryOp(expr, operator.?.token_type, rhs);
        }
        return expr;
    }

    fn parseComparison(self: *Self) ExprIndex {
        var expr = self.parseTerm();
        while (self.matchToken(&.{ .gt, .gte, .lt, .lte })) {
            var operator = self.advanceToken();
            var rhs = self.parseTerm();
            expr = self.newBinaryOp(expr, operator.?.token_type, rhs);
        }
        return expr;
    }

    fn parseTerm(self: *Self) ExprIndex {
        var expr = self.parseFactor();
        while (self.matchToken(&.{ .plus, .minus })) {
            var operator = self.advanceToken();
            var rhs = self.parseFactor();
            expr = self.newBinaryOp(expr, operator.?.token_type, rhs);
        }
        return expr;
    }

    fn parseFactor(self: *Self) ExprIndex {
        var expr = self.parseUnary();
        while (self.matchToken(&.{ .slash, .mul })) {
            var operator = self.advanceToken();
            var rhs = self.parseUnary();
            expr = self.newBinaryOp(expr, operator.?.token_type, rhs);
        }

        return expr;
    }

    // unary -> '-' primary | primary | formula
    fn parseUnary(self: *Self) ExprIndex {
        if (self.matchToken(&.{.minus})) {
            var operator = self.advanceToken();
            var rhs = self.parseUnary();
            return self.newUnaryOp(operator.?.token_type, rhs);
        }
        // else if (self.matchToken(&.{.ident})) {
        // formula   -> ident '(' arguments? ')'
        //const formula_name = self.advanceToken();
        //const args = self.parseArguments();
        //self.store.items[expr] = Expr { .formula = .{ .name = formula_name, .arguments = args } };
        //}
        return self.parsePrimary();
    }

    // arguments -> expr (',' expr)*
    fn parseArguments(self: *Self) []ExprIndex {
        var args_list = std.ArrayList(ExprIndex).init(self.alloc);
        while (true) {
            if (self.matchToken(&.{.rparen})) {
                // end of argument list
                return args_list.toOwnedSlice();
            }
            var arg = self.parsePrimary();
            args_list.append(arg) catch unreachable;
        }

        return {};
    }

    fn parsePrimary(self: *Self) ExprIndex {
        if (self.current_token == null) std.debug.panic("End of input", .{});
        var primary_expr = self.store.createExpression();

        switch (self.current_token.?.token_type) {
            .clone_n => {
                primary_expr.expr.* = Expr{ .clone = .{ .direction = .north } };
            },
            .clone_s => {
                primary_expr.expr.* = Expr{ .clone = .{ .direction = .south } };
            },
            .clone_w => {
                primary_expr.expr.* = Expr{ .clone = .{ .direction = .west } };
            },
            .clone_e => {
                primary_expr.expr.* = Expr{ .clone = .{ .direction = .east } };
            },
            .false_ => {
                primary_expr.expr.* = Expr{ .boolean = false };
            },
            .true_ => {
                primary_expr.expr.* = Expr{ .boolean = true };
            },
            .ident => {
                std.debug.assert(self.current_token != null);
                var content = self.current_token.?.content;

                if (std.fmt.parseFloat(f64, content)) |num| {
                    primary_expr.expr.* = Expr{ .numeric = num };
                    self.tokenizer.alloc.free(content);
                    _ = self.advanceToken();
                    return primary_expr.index;
                } else |_| {}
                if (content.len > 1 and std.ascii.isUpper(content[0])) {
                    var col: u32 = @as(u32, content[0] - 'A');
                    if (std.fmt.parseInt(u32, content[1..], 10)) |row| {
                        primary_expr.expr.* = Expr{ .ref = .{ .row = row, .column = col } };
                        self.tokenizer.alloc.free(self.current_token.?.content);
                    } else |_| {
                        primary_expr.expr.* = Expr{ .ident = self.current_token.?.content };
                    }
                } else {
                    primary_expr.expr.* = Expr{ .ident = self.current_token.?.content };
                }
                return primary_expr.index;
            },
            .lparen => {
                var expr = self.parse(); // skip lparen token, advance start parsing
                std.debug.assert(self.current_token != null);
                if (!self.expectToken(.rparen)) {
                    std.debug.panic("Expected ')' token", .{});
                    primary_expr.expr.* = Expr{ .err = {} };
                } else {
                    // we invalidate pointers here.
                    // try to understand where?
                    self.store.store.items[primary_expr.index] = Expr{ .group = expr };
                }
            },
            else => unreachable,
        }

        _ = self.advanceToken();
        return primary_expr.index;
    }
};
