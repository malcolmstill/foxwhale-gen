const std = @import("std");
const xml2 = @cImport({
    @cDefine("LIBXML_READER_ENABLED", {});
    @cInclude("libxml/xmlreader.h");
});

pub fn main() !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var nodes = NodeList.init(arena);
    defer nodes.deinit();

    const reader = xml2.xmlReaderForFile("wayland.xml", null, 0) orelse return error.ReaderFailed;
    defer xml2.xmlFreeTextReader(reader);

    // Process the file
    while (xml2.xmlTextReaderRead(reader) == 1) {
        try processNode(arena, &nodes, reader);
    }

    // Cleanup function for the XML library
    xml2.xmlCleanupParser();

    std.debug.print("{any}", .{nodes});
}

const NodeList = struct {
    nodes: std.ArrayList(Node),

    fn init(allocator: std.mem.Allocator) NodeList {
        return .{ .nodes = std.ArrayList(Node).init(allocator) };
    }

    fn deinit(node_list: *NodeList) void {
        node_list.nodes.deinit();
    }

    fn append(node_list: *NodeList, node: Node) !void {
        try node_list.nodes.append(node);
    }

    pub fn format(node_list: NodeList, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        var indent: i32 = -1;
        for (node_list.nodes.items) |node| {
            const ind = getIndent(node);
            if (ind == 0) indent += 1;
            if (ind > 0) indent += ind;
            defer {
                if (ind < 0) indent += ind;
                if (ind == 0) indent -= 1;
            }

            for (0..@intCast(indent)) |_| {
                try writer.print("  ", .{});
            }

            try writer.print("{any}\n", .{node});
        }
    }
};

const prelude =
    \\const std = @import("std");
    \\const builtin = @import("builtin");
    \\const WireFn = @import("wire.zig").Wire;
;

fn getIndent(node: Node) i32 {
    return switch (node) {
        .protocol_begin,
        .copyright_begin,
        .interface_begin,
        .description_begin,
        .event_begin,
        .request_begin,
        .enum_begin,
        => 1,
        .protocol_end,
        .copyright_end,
        .interface_end,
        .description_end,
        .event_end,
        .request_end,
        .enum_end,
        => -1,
        .arg,
        .entry,
        => 0,
    };
}

const walyand_struct = "const fn Wayland(comptime ResourceMap: struct {{ {s} }}) type {{ return struct {{ {s} }}; }}";

const NodeEnum = enum(u8) {
    protocol_begin,
    protocol_end,
    copyright_begin,
    copyright_end,
    interface_begin,
    interface_end,
    description_begin,
    description_end,
    event_begin,
    event_end,
    request_begin,
    request_end,
    enum_begin,
    enum_end,
    arg,
    entry,
};

const Node = union(NodeEnum) {
    protocol_begin: struct {
        name: []const u8 = "",
    },
    protocol_end: struct {},
    copyright_begin: struct {},
    copyright_end: struct {},
    interface_begin: struct {
        name: []const u8 = "",
        version: u32 = 0,
    },
    interface_end: struct {},
    description_begin: struct { summary: []const u8 },
    description_end: struct {},
    event_begin: struct { name: []const u8 },
    event_end: struct {},
    request_begin: struct { name: []const u8 },
    request_end: struct {},
    enum_begin: struct {},
    enum_end: struct {},
    arg: struct {},
    entry: struct {},

    pub fn format(node: Node, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        switch (node) {
            .protocol_begin => |n| try writer.print("<protocol name=\"{s}\">", .{n.name}),
            .protocol_end => |_| try writer.print("</protocol>", .{}),
            .copyright_begin => |_| try writer.print("<copyright>", .{}),
            .copyright_end => |_| try writer.print("</copyright>", .{}),
            .interface_begin => |n| try writer.print("<interface name=\"{s}\" version={}>", .{ n.name, n.version }),
            .interface_end => |_| try writer.print("</interface>", .{}),
            .description_begin => |n| try writer.print("<description summary=\"{s}\" >", .{n.summary}),
            .description_end => |_| try writer.print("</description>", .{}),
            .event_begin => |n| try writer.print("<event name=\"{s}\">", .{n.name}),
            .event_end => |_| try writer.print("</event>", .{}),
            .request_begin => |n| try writer.print("<request name=\"{s}\">", .{n.name}),
            .request_end => |_| try writer.print("</request>", .{}),
            .enum_begin => |_| try writer.print("<enum>", .{}),
            .enum_end => |_| try writer.print("</enum>", .{}),
            .arg => |_| try writer.print("<arg>", .{}),
            .entry => |_| try writer.print("<entry>", .{}),
        }
    }
};

fn processNode(allocator: std.mem.Allocator, nodes: *NodeList, reader: *xml2.xmlTextReader) !void {
    const tag_ptr = xml2.xmlTextReaderConstName(reader);
    const tag = if (tag_ptr) |ptr| std.mem.span(ptr) else "";

    const node_type = xml2.xmlTextReaderNodeType(reader);

    if (node_type == xml2.XML_READER_TYPE_ELEMENT) {
        if (std.mem.eql(u8, tag, "protocol")) {
            try nodes.append(.{ .protocol_begin = .{ .name = "" } });
        } else if (std.mem.eql(u8, tag, "copyright")) {
            try nodes.append(.{ .copyright_begin = .{} });
        } else if (std.mem.eql(u8, tag, "interface")) {
            try nodes.append(.{ .interface_begin = .{ .name = "" } });
        } else if (std.mem.eql(u8, tag, "description")) {
            try nodes.append(.{ .description_begin = .{ .summary = "" } });
        } else if (std.mem.eql(u8, tag, "event")) {
            try nodes.append(.{ .event_begin = .{ .name = "" } });
        } else if (std.mem.eql(u8, tag, "request")) {
            try nodes.append(.{ .request_begin = .{ .name = "" } });
        } else if (std.mem.eql(u8, tag, "arg")) {
            try nodes.append(.{ .arg = .{} });
        } else if (std.mem.eql(u8, tag, "enum")) {
            try nodes.append(.{ .enum_begin = .{} });
        } else if (std.mem.eql(u8, tag, "entry")) {
            try nodes.append(.{ .entry = .{} });
        } else {
            std.debug.panic("Unexpected tag: {s}", .{tag});
        }
    }
    if (node_type == xml2.XML_READER_TYPE_END_ELEMENT) {
        if (std.mem.eql(u8, tag, "protocol")) {
            try nodes.append(.{ .protocol_end = .{} });
        } else if (std.mem.eql(u8, tag, "copyright")) {
            try nodes.append(.{ .copyright_end = .{} });
        } else if (std.mem.eql(u8, tag, "interface")) {
            try nodes.append(.{ .interface_end = .{} });
        } else if (std.mem.eql(u8, tag, "description")) {
            try nodes.append(.{ .description_end = .{} });
        } else if (std.mem.eql(u8, tag, "event")) {
            try nodes.append(.{ .event_end = .{} });
        } else if (std.mem.eql(u8, tag, "request")) {
            try nodes.append(.{ .request_end = .{} });
        } else if (std.mem.eql(u8, tag, "enum")) {
            try nodes.append(.{ .enum_end = .{} });
        } else {
            std.debug.panic("Unexpected tag: {s}", .{tag});
        }
    }

    std.debug.assert(nodes.nodes.items.len > 0);
    const latest_node = &nodes.nodes.items[nodes.nodes.items.len - 1];

    if (xml2.xmlTextReaderHasAttributes(reader) != 0) {
        // Successfully moved to the first attribute
        if (xml2.xmlTextReaderMoveToFirstAttribute(reader) == 1) {
            // Process each attribute
            while (true) {
                // Print attribute name and value
                const attr_name_ptr = xml2.xmlTextReaderConstName(reader);
                const attr_name = if (attr_name_ptr) |ptr| std.mem.span(ptr) else unreachable;
                const attr_value_ptr = xml2.xmlTextReaderConstValue(reader);
                const attr_value = if (attr_value_ptr) |ptr| std.mem.span(ptr) else unreachable;

                const arena_attr_value = try allocator.alloc(u8, attr_value.len);
                std.mem.copyForwards(u8, arena_attr_value, attr_value);

                switch (latest_node.*) {
                    inline else => |*n| inline for (std.meta.fields(@TypeOf(n.*))) |field| {
                        if (std.mem.eql(u8, field.name, attr_name)) {
                            switch (@typeInfo(field.type)) {
                                .Int => @field(n, field.name) = try std.fmt.parseInt(u32, arena_attr_value, 10),
                                else => @field(n, field.name) = arena_attr_value,
                            }
                        }
                    },
                }

                // Attempt to move to the next attribute; break if unsuccessful
                if (xml2.xmlTextReaderMoveToNextAttribute(reader) != 1) {
                    break;
                }
            }

            // After processing attributes, move back to the element node
            _ = xml2.xmlTextReaderMoveToElement(reader);
        }
    }

    // if (xml2.xmlTextReaderHasValue(reader) != 0) {
    //     const value_ptr = xml2.xmlTextReaderConstValue(reader);
    //     const value = if (value_ptr) |ptr| std.mem.span(ptr) else "";
    //     // std.debug.print("Value: {s}", .{value});
    // }
}
