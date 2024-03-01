const std = @import("std");
const xml2 = @cImport({
    @cInclude("libxml/parser.h");
    @cInclude("libxml/tree.h");
});

pub fn main() !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var nodes = NodeList.init(arena);
    defer nodes.deinit();

    xml2.xmlInitParser();
    defer xml2.xmlCleanupParser();

    // Parse the XML file
    const doc = xml2.xmlReadFile("wayland.xml", null, 0) orelse return error.ReaderFailed;
    defer xml2.xmlFreeDoc(doc);

    const root_element = xml2.xmlDocGetRootElement(doc);

    try processNode(arena, &nodes, root_element);

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
            if (isOpen(node)) indent += 2;
            defer {
                if (!isOpen(node)) indent -= 2;
            }

            for (0..@intCast(indent)) |_| {
                try writer.print(" ", .{});
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

fn isOpen(node: Node) bool {
    return switch (node) {
        .protocol_begin,
        .copyright_begin,
        .interface_begin,
        .description_begin,
        .event_begin,
        .request_begin,
        .enum_begin,
        .arg_begin,
        .entry_begin,
        => true,
        .protocol_end,
        .copyright_end,
        .interface_end,
        .description_end,
        .event_end,
        .request_end,
        .enum_end,
        .arg_end,
        .entry_end,
        => false,
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
    arg_begin,
    entry_begin,
    arg_end,
    entry_end,
};

const ArgTypeTag = enum(u8) {
    int,
    uint,
    fd,
    new_id,
    object,
    string,
    fixed,
    array,
};

const ArgType = union(ArgTypeTag) {
    int: struct { @"enum": ?[]const u8 = null },
    uint: struct { @"enum": ?[]const u8 = null },
    fd: struct {},
    new_id: struct { interface: ?[]const u8 = null },
    object: struct { interface: ?[]const u8 = null, allow_null: bool = false },
    string: struct { allow_null: bool = false },
    fixed: struct {},
    array: struct {},
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
    description_begin: struct { summary: []const u8 = "" },
    description_end: struct {},
    event_begin: struct { name: []const u8 = "", since: u32 = 0 },
    event_end: struct {},
    request_begin: struct { name: []const u8 = "", since: u32 = 0 },
    request_end: struct {},
    enum_begin: struct { name: []const u8 = "", bitfield: bool = false },
    enum_end: struct {},
    arg_begin: struct {
        name: []const u8 = "",
        summary: []const u8 = "",
        type: ArgType = .{ .int = .{} },
    },
    entry_begin: struct {
        name: []const u8 = "",
        value: u32 = 0,
        summary: []const u8 = "",
    },
    arg_end: struct {},
    entry_end: struct {},

    pub fn format(node: Node, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        switch (node) {
            .protocol_begin => |n| try writer.print("<protocol name=\"{s}\">", .{n.name}),
            .protocol_end => |_| try writer.print("</protocol>", .{}),
            .copyright_begin => |_| try writer.print("<copyright>", .{}),
            .copyright_end => |_| try writer.print("</copyright>", .{}),
            .interface_begin => |n| try writer.print("<interface name=\"{s}\" version={}>", .{ n.name, n.version }),
            .interface_end => |_| try writer.print("</interface>", .{}),
            .description_begin => |n| try writer.print("<description summary=\"{s}\">", .{n.summary}),
            .description_end => |_| try writer.print("</description>", .{}),
            .event_begin => |n| try writer.print("<event name=\"{s}\" since={}>", .{ n.name, n.since }),
            .event_end => |_| try writer.print("</event>", .{}),
            .request_begin => |n| try writer.print("<request name=\"{s}\" since={}>", .{ n.name, n.since }),
            .request_end => |_| try writer.print("</request>", .{}),
            .enum_begin => |n| try writer.print("<enum name=\"{s}\" bitfield={}>", .{ n.name, n.bitfield }),
            .enum_end => |_| try writer.print("</enum>", .{}),
            .arg_begin => |n| try writer.print("<arg name=\"{s}\" type=\"{s}\" summary=\"{s}\">", .{
                n.name,
                @tagName(n.type),
                n.summary,
            }),
            .arg_end => |_| try writer.print("</arg>", .{}),
            .entry_begin => |n| try writer.print("<entry name=\"{s}\" value={} summary=\"{s}\">", .{ n.name, n.value, n.summary }),
            .entry_end => |_| try writer.print("</entry>", .{}),
        }
    }
};

fn processNode(allocator: std.mem.Allocator, node_list: *NodeList, maybe_parent_node: ?*xml2.xmlNode) !void {
    var maybe_cur_node: ?*xml2.xmlNode = maybe_parent_node;

    while (maybe_cur_node) |node| {
        const cur_node: *xml2.xmlNode = node;
        defer maybe_cur_node = cur_node.*.next;

        if (cur_node.type != xml2.XML_ELEMENT_NODE) continue;

        const tag = std.mem.span(cur_node.name);

        try node_list.append(tagToOpening(tag));

        std.debug.assert(node_list.nodes.items.len > 0);

        const latest_node = &node_list.nodes.items[node_list.nodes.items.len - 1];

        var attr = cur_node.*.properties;
        while (attr != null) {
            const attr_name = std.mem.span(attr.*.name);
            const attr_value = std.mem.span(attr.*.children.*.content);

            const arena_attr_value = try allocator.alloc(u8, attr_value.len);
            std.mem.copyForwards(u8, arena_attr_value, attr_value);

            switch (latest_node.*) {
                .arg_begin => |*n| inline for (std.meta.fields(@TypeOf(n.*))) |field| {
                    if (std.mem.eql(u8, field.name, attr_name)) {
                        switch (@typeInfo(field.type)) {
                            .Int => @field(n, field.name) = if (std.mem.startsWith(u8, arena_attr_value, "0x"))
                                try std.fmt.parseInt(u32, arena_attr_value[2..], 16)
                            else
                                try std.fmt.parseInt(u32, arena_attr_value, 10),
                            .Bool => @field(n, field.name) = std.mem.eql(u8, arena_attr_value, "true"),
                            .Union => {
                                inline for (std.meta.fields(ArgType)) |union_field| {
                                    if (std.mem.eql(u8, union_field.name, attr_value)) {
                                        @field(n, field.name) = @unionInit(ArgType, union_field.name, .{});
                                    }
                                }
                            },
                            else => @field(n, field.name) = arena_attr_value,
                        }
                    }
                },
                inline else => |*n| inline for (std.meta.fields(@TypeOf(n.*))) |field| {
                    if (std.mem.eql(u8, field.name, attr_name)) {
                        switch (@typeInfo(field.type)) {
                            .Int => @field(n, field.name) = if (std.mem.startsWith(u8, arena_attr_value, "0x"))
                                try std.fmt.parseInt(u32, arena_attr_value[2..], 16)
                            else
                                try std.fmt.parseInt(u32, arena_attr_value, 10),
                            .Bool => @field(n, field.name) = std.mem.eql(u8, arena_attr_value, "true"),
                            else => @field(n, field.name) = arena_attr_value,
                        }
                    }
                },
            }

            attr = attr.*.next;
        }

        try processNode(allocator, node_list, cur_node.children);

        try node_list.append(tagToClosing(tag));
    }
}

fn tagToOpening(tag: []const u8) Node {
    if (std.mem.eql(u8, tag, "protocol")) {
        return .{ .protocol_begin = .{} };
    } else if (std.mem.eql(u8, tag, "copyright")) {
        return .{ .copyright_begin = .{} };
    } else if (std.mem.eql(u8, tag, "interface")) {
        return .{ .interface_begin = .{} };
    } else if (std.mem.eql(u8, tag, "description")) {
        return .{ .description_begin = .{} };
    } else if (std.mem.eql(u8, tag, "event")) {
        return .{ .event_begin = .{} };
    } else if (std.mem.eql(u8, tag, "request")) {
        return .{ .request_begin = .{} };
    } else if (std.mem.eql(u8, tag, "enum")) {
        return .{ .enum_begin = .{} };
    } else if (std.mem.eql(u8, tag, "arg")) {
        return .{ .arg_begin = .{} };
    } else if (std.mem.eql(u8, tag, "entry")) {
        return .{ .entry_begin = .{} };
    } else {
        std.debug.panic("Unexpected tag: {s}", .{tag});
    }
}

fn tagToClosing(tag: []const u8) Node {
    if (std.mem.eql(u8, tag, "protocol")) {
        return .{ .protocol_end = .{} };
    } else if (std.mem.eql(u8, tag, "copyright")) {
        return .{ .copyright_end = .{} };
    } else if (std.mem.eql(u8, tag, "interface")) {
        return .{ .interface_end = .{} };
    } else if (std.mem.eql(u8, tag, "description")) {
        return .{ .description_end = .{} };
    } else if (std.mem.eql(u8, tag, "event")) {
        return .{ .event_end = .{} };
    } else if (std.mem.eql(u8, tag, "request")) {
        return .{ .request_end = .{} };
    } else if (std.mem.eql(u8, tag, "enum")) {
        return .{ .enum_end = .{} };
    } else if (std.mem.eql(u8, tag, "arg")) {
        return .{ .arg_end = .{} };
    } else if (std.mem.eql(u8, tag, "entry")) {
        return .{ .entry_end = .{} };
    } else {
        std.debug.panic("Unexpected tag: {s}", .{tag});
    }
}
