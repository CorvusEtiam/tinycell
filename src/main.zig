const std = @import("std");
const utils = @import("./utils.zig");
const loader = @import("./CSVLoader.zig");
const evaluateTable = @import("./expression_eval.zig").evaluateTable;

pub const AppError = error{ parseError, parseExprError, outOfBoundAccess, wrongType, circularDependency };

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{ }){};
    var allocator = gpa.allocator();
    defer {
        _ = gpa.deinit();
    }

    var command_options = utils.CommandOptions.parse(allocator, .{ .input_file_path = "data/expr.csv" }) catch {
        std.debug.panic("Unhandled error in command options", .{});
    };
    defer command_options.deinit();
        
    var table = loader.loadFile(allocator, command_options.input_file_path) catch {
        std.log.err("There was error while loading file. Check if file exist", .{});
        std.log.err("Load from path: {s}", .{command_options.input_file_path});
        return;
    };

    defer table.deinit();

    evaluateTable(&table);
    // table.dum();
    // std.debug.print("\n{s}\n", .{ "="**80 });
    try utils.printSliceAsTable(allocator, table.data.items, table.size);
}
