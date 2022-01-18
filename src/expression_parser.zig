const std = @import("std");
const Tokenizer = @import("./Tokenizer.zig");

// literal -> number | 'FALSE' | 'TRUE'
// primary -> literal | '(' expr ')'
// unary -> '-' unary | primary
// factor -> unary (('*' | '/') unary)*
// term   -> factor (('+'|'-') factor)*
// comparison -> term (('>'|'>='|'<='|'<') term)*
// equality -> comparison ('<>'|'==' comparison)*

pub const ExprType = enum(u8) { numeric = 0, boolean, string, ident, binary_op, unary_op, group, err, ref };

pub const BinOpExpr = struct {
    lhs: ?*Expr = null,
    operand: Tokenizer.TokType = .ident,
    rhs: ?*Expr = null,
};

pub const UnOpExpr = struct {
    operand: Tokenizer.TokType = .ident,
    rhs: ?*Expr = null,
};



pub const CellIndex = struct {
    pub const ADDR_ABS_BOTH = 0b11;
    pub const ADDR_ABS_ROW = 0b10;
    pub const ADDR_ABS_COL = 0b01;
    pub const ADDR_ABS_NONE = 0b00;

    row: u64 = 0,
    column: u32 = 0,
    ref_flag: u2 = ADDR_ABS_NONE,
};

// 64+32+2 => u8

pub const Expr = union(ExprType) {
    numeric: f64,
    boolean: bool,
    string: []const u8,
    ident: []const u8, // those can be cell references, function names and so on,
    binary_op: BinOpExpr,
    unary_op: UnOpExpr,
    group: *Expr,
    err: []const u8,
    ref: CellIndex,
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

    pub fn advanceToken(self: *Self) ?Token {
        const current = self.current_token;
        self.current_token = self.tokenizer.nextToken();
        return current;
    }

    pub fn expectToken(self: *Self, token_type: Tokenizer.TokType) bool {
        if ( self.current_token ) | token | {
            return token.token_type == token_type;
        } else {
            return false;
        }
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
        self.current_token = self.tokenizer.nextToken();
        return self.parseEquality();
    }

    fn parseEquality(self: *Self) *Expr {
        var expr = self.parseComparison();
        while (self.matchToken(&.{ .eq, .neq })) {
            var operator = self.advanceToken();
            var rhs = self.parseComparison();
            expr = self.newBinaryOp(expr, operator.?.token_type, rhs);

        }
        return expr;
    }

    fn parseComparison(self: *Self) *Expr {
        var expr: *Expr = self.parseTerm();
        while (self.matchToken(&.{ .gt, .gte, .lt, .lte })) {
            var operator = self.advanceToken();
            var rhs = self.parseTerm();
            expr = self.newBinaryOp(expr, operator.?.token_type, rhs);

        }
        return expr;
    }

    fn parseTerm(self: *Self) *Expr {
        var expr = self.parseFactor(); 
        while (self.matchToken(&.{ .plus, .minus })) {
            var operator = self.advanceToken();
            var rhs = self.parseFactor();
            expr = self.newBinaryOp(expr, operator.?.token_type, rhs);
        }
        return expr;
    }

    fn parseFactor(self: *Self) *Expr {
        var expr = self.parseUnary(); 
        while (self.matchToken(&.{ .slash, .mul })) {
            var operator = self.advanceToken();
            var rhs = self.parseUnary();
            expr = self.newBinaryOp(expr, operator.?.token_type, rhs);
        }

        return expr;
    }

    fn parseUnary(self: *Self) *Expr {
        if (self.matchToken(&.{.minus})) {
            var operator = self.advanceToken(); 
            var rhs = self.parseUnary();
            var expr_tmp = self.alloc.create(Expr) catch unreachable;

            expr_tmp.* = Expr{ .unary_op = .{ .operand = operator.?.token_type, .rhs = rhs } };
            return expr_tmp;
        }

        return self.parsePrimary();
    }

    fn parsePrimary(self: *Self) *Expr {
        if ( self.current_token == null ) std.debug.panic("End of input", .{});
        var primary_expr = self.alloc.create(Expr) catch unreachable;
        primary_expr.* = prim: {
            break :prim switch (self.current_token.?.token_type) {
                .false_ => Expr{ .boolean = false },
                .true_ => Expr{ .boolean = true },
                .ident => {
                    var num = std.fmt.parseFloat(f64, self.current_token.?.content) catch {
                        // identify cell ref -- letter* digit*
                        // cell ref -- starts with capital letters?
                        const potential_ref = self.current_token.?.content;
                        var col: u32 = 0;
                        if ( std.ascii.isUpper(potential_ref[0]) ) {
                            col = @as(u32, potential_ref[0] - 'A');
                        } else {
                        } 
                        var row = std.fmt.parseInt(u64, potential_ref[1..], 10) catch {
                            break :prim Expr{ .ident = self.current_token.?.content }; 
                        };
                        break :prim Expr { .ref = .{ .row = row, .column = col } };
                    };
                    break :prim Expr { .numeric = num };
                },
                .lparen => {
                    var expr = self.parse(); // skip lparen token, advance start parsing
                    std.debug.assert( self.current_token != null );
                    if (!self.expectToken(.rparen)) {
                        std.debug.panic("Expected ')' token", .{});
                        break :prim Expr { .err = {} };
                    } else {
                        break :prim Expr{ .group = expr };
                    }
                },
                else => unreachable,
            };
        };

        _ = self.advanceToken(); // load next token 

        return primary_expr;
    }
};

