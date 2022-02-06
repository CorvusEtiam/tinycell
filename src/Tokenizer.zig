const std = @import("std");
const tokdefs = @import("./token.zig");

pub const Token = tokdefs.Token;
pub const TokType = tokdefs.TokType;

const Self = @This();

alloc: std.mem.Allocator = undefined,
content: []const u8 = undefined,
cursor: usize = 0,

fn peek(self: *Self) u8 {
    if ( self.cursor == self.content.len ) {
        return 0;
    }
    return self.content[self.cursor];
}

fn consume(self: *Self) u8 {
    const r = self.content[self.cursor];
    self.cursor += 1;
    return r;
}

fn match(self: *Self, next_char: u8) bool {
    return ( self.peek() == next_char );
}

fn matchAndConsume(self: *Self, expected: u8) bool {
    if ( self.peek() == expected ) {
        self.cursor += 1;
        return true;
    } 
    return false;
}

pub const TokenizerError = error {
    unexpectedChar,
    unexpectedEndOfInput,
};

// FIXME: Graceful error handling
// maybe swap nextToken ?Token into !Token, and use error{ endOfInput, unexpectedChar };
pub fn nextToken(self: *Self) TokenizerError!?Token {
    // end of stream
    if (self.cursor >= self.content.len) return null;

    while (self.cursor < self.content.len and std.ascii.isBlank(self.content[self.cursor])) {
        self.cursor += 1;
    }

    const current = self.peek();
    self.cursor += 1;
    switch (current) {
        '>' => {
            if (self.match('=')) {
                self.cursor += 1;
                return Token.operator(.gte);
            } else {
                return Token.operator(.gt);
            }
        },
        '<' => {
            if (self.match('=')) {
                self.cursor += 1;
                return Token.operator(.lte);
            } else if (self.match('>')) {
                return Token.operator(.neq);
            } else {
                return Token.operator(.lt);
            }
        },
        '=' => {
            if (self.match('=')) {
                self.cursor += 1;
                return Token.operator(.eq);
            } else {
                return error.unexpectedChar;
            }
        },
        ':' => {
            if ( self.matchAndConsume('>') ) return Token.operator(.clone_w);
            if ( self.matchAndConsume('<') ) return Token.operator(.clone_e);
            if ( self.matchAndConsume('v') or self.matchAndConsume('V') ) return Token.operator(.clone_s);
            if ( self.matchAndConsume('^') ) return Token.operator(.clone_n);
            
            return error.unexpectedChar;
        },
        '(' => return Token.operator(.lparen),
        ')' => return Token.operator(.rparen),
        '+' => return Token.operator(.plus),
        '-' => return Token.operator(.minus),
        '*' => return Token.operator(.mul),
        '/' => return Token.operator(.slash),
        else => {
            if (std.mem.startsWith(u8, self.content[self.cursor..], "FALSE")) {
                self.cursor += 4;
                return Token.operator(.false_);
            } else if (std.mem.startsWith(u8, self.content[self.cursor..], "TRUE")) {
                self.cursor += 3;
                return Token.operator(.true_);
            }

            const start = self.cursor - 1;
            while (self.cursor < self.content.len and (std.ascii.isAlNum(self.peek()) or self.peek() == '_')) {
                self.cursor += 1;
            }
            var content = self.alloc.dupe(u8, self.content[start..self.cursor]) catch unreachable;
            return Token.ident(content);
        },
    }
}
