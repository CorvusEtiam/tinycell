const std = @import("std");
const Tokenizer = @import("./Tokenizer.zig");
const typedefs = @import("./types.zig");


const Token = Tokenizer.Token;

const ExprIndex = typedefs.ExprIndex;
const CellIndex = typedefs.CellIndex;
const Expr      = typedefs.Expr;
const ExprList = std.ArrayList(Expr);

pub const Parser = struct {
    const ExprIndexWrapper = struct {
        index: ExprIndex,
        ptr: *Expr
    };
    
    const Self = @This();

    store: *std.ArrayList(Expr) = undefined,
    tokenizer: Tokenizer,
    current_token: ?Token = null,

    pub fn init(expr: []const u8, store: *ExprList, alloc: std.mem.Allocator) Parser {
        return Parser{
            .store = store,
            .tokenizer = Tokenizer{ .alloc = alloc, .content = expr },
        };
    }

    pub fn createExpr(self: *Self) ExprIndexWrapper {
        self.store.append(Expr { .boolean = false }) catch unreachable;
        const last_index = self.store.items.len - 1;
        return .{ .index = last_index, .ptr = &self.store.items[last_index] };
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


    fn newBinaryOp(self: *Self, lhs: ExprIndex, op: Tokenizer.TokType, rhs: ExprIndex) ExprIndex {
        var tmp = self.createExpr();
        tmp.ptr.* = Expr { .binary_op = .{
            .lhs = lhs,
            .operand = op,
            .rhs = rhs,
        } };
        return tmp.index;
    }

    pub fn parse(self: *Self) ExprIndex {
        self.current_token = self.tokenizer.nextToken();
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

    fn parseUnary(self: *Self) ExprIndex {
        if (self.matchToken(&.{.minus})) {
            var operator = self.advanceToken(); 
            var rhs = self.parseUnary();
            var expr = self.createExpr();
            
            expr.ptr.* = Expr{ .unary_op = .{ .operand = operator.?.token_type, .rhs = rhs } };
            return expr.index;
        }

        return self.parsePrimary();
    }

    fn parsePrimary(self: *Self) ExprIndex {
        if ( self.current_token == null ) std.debug.panic("End of input", .{});
        var primary_expr = self.createExpr();
        
        primary_expr.ptr.* = prim: {
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
                        var row = std.fmt.parseInt(u32, potential_ref[1..], 10) catch {
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

        return primary_expr.index;
    }
};

