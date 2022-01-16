pub const TokType = enum {
    ident,
    plus,
    minus,
    mul,
    slash,
    lparen,
    rparen,
    eq, // ==
    gt, // >
    gte, // >=
    lt, // <
    lte, // <=
    neq, // <>
    false_, // FALSE
    true_, // TRUE
};

pub const Token = struct {
    content: []const u8 = undefined,
    token_type: TokType,

    pub inline fn operator(tok: TokType) Token {
        return .{ .token_type = tok };
    }
    pub inline fn ident(content: []const u8) Token {
        return .{ .token_type = .ident, .content = content };
    }
};
