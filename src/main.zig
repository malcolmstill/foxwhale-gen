const std = @import("std");
const xml2 = @cImport({
    @cInclude("libxml/parser.h");
    @cInclude("libxml/tree.h");
});

pub fn main() !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var node_list = NodeList.init(arena);
    defer node_list.deinit();

    xml2.xmlInitParser();
    defer xml2.xmlCleanupParser();

    // Parse the XML file
    const doc = xml2.xmlReadFile("wayland.xml", null, 0) orelse return error.ReaderFailed;
    defer xml2.xmlFreeDoc(doc);

    const root_element = xml2.xmlDocGetRootElement(doc);

    try processNode(arena, &node_list, root_element);

    const wayland = try processProtocols(arena, &node_list);

    std.debug.print("{any}\n", .{wayland});

    // std.debug.print("{s}", .{part_1});
    // for (node_list.nodes.items) |node| {
    //     switch (node) {
    //         .interface_begin => |i| std.debug.print("  {s}: type = ?void,\n", .{i.name}),
    //         else => continue,
    //     }
    // }
    // std.debug.print("{s}", .{part_2});

    // for (node_list.nodes.items) |node| {
    //     switch (node) {
    //         .interface_begin => |i| {
    //             std.debug.print("    pub const {s} = struct {{\n", .{i.name});
    //             std.debug.print("      wire: *Wire,\n", .{});
    //             std.debug.print("      id: u32,\n", .{});
    //             std.debug.print("      version: u32,\n", .{});
    //             std.debug.print("      resource: ResourceMap.{s},\n", .{i.name});
    //             std.debug.print("\n", .{});
    //             std.debug.print("      const Self = @This();\n", .{});
    //         },
    //         .interface_end => |_| std.debug.print("    }};\n", .{}),
    //         .event_begin => |ev| std.debug.print("      pub fn send{s}() !void {{\n", .{ev.name}),
    //         .event_end => |_| std.debug.print("      }}\n", .{}),
    //         else => continue,
    //     }
    // }

    // std.debug.print("{s}", .{part_3});
}

fn processProtocols(allocator: std.mem.Allocator, node_list: *NodeList) !Wayland {
    var wayland = Wayland.init(allocator);

    var i: usize = 0;
    var start: usize = 0;
    var protocol_name: []const u8 = "";
    const nodes = node_list.nodes.items;
    for (nodes) |node| {
        defer i += 1;
        switch (node) {
            .protocol_begin => |p| {
                protocol_name = p.name;
                start = i;
            },
            .protocol_end => {
                const protocol = try processProtocol(allocator, nodes[start..i], protocol_name);
                try wayland.protocols.append(protocol);
            },
            else => continue,
        }
    }

    return wayland;
}

fn processProtocol(allocator: std.mem.Allocator, nodes: []Node, name: []const u8) !Protocol {
    var protocol = Protocol.init(allocator, name);

    var index: usize = 0;
    var start: usize = 0;
    var interface_name: []const u8 = "";
    for (nodes) |node| {
        defer index += 1;
        switch (node) {
            .interface_begin => |i| {
                interface_name = i.name;
                start = index;
            },
            .interface_end => {
                const interface = try processInterface(allocator, nodes[start..index], interface_name);
                try protocol.interfaces.append(interface);
            },
            else => continue,
        }
    }

    return protocol;
}

fn processInterface(allocator: std.mem.Allocator, nodes: []Node, interface_name: []const u8) !Interface {
    var interface = Interface.init(allocator, interface_name);

    var index: usize = 0;
    var start: usize = 0;
    var name: []const u8 = "";
    for (nodes) |node| {
        defer index += 1;
        switch (node) {
            .enum_begin => |_| start = index,
            .enum_end => {
                const e_begin = nodes[start].enum_begin;
                const @"enum" = try processEnum(allocator, nodes[start..index], e_begin.name, e_begin.bitfield);
                try interface.enums.append(@"enum");
            },
            .request_begin => |r| {
                name = r.name;
                start = index;
            },
            .request_end => {
                const request = try processRequest(allocator, nodes[start..index], name);
                try interface.requests.append(request);
            },
            .event_begin => |e| {
                name = e.name;
                start = index;
            },
            .event_end => {
                const event = try processEvent(allocator, nodes[start..index], name);
                try interface.events.append(event);
            },
            else => continue,
        }
    }

    return interface;
}

fn processRequest(allocator: std.mem.Allocator, nodes: []Node, request_name: []const u8) !Request {
    var request = Request.init(allocator, request_name);

    var index: usize = 0;
    for (nodes) |node| {
        defer index += 1;
        switch (node) {
            .arg_begin => |a| {
                const arg: Arg = .{ .name = a.name, .type = a.type };
                try request.args.append(arg);
            },
            else => continue,
        }
    }

    return request;
}

fn processEvent(allocator: std.mem.Allocator, nodes: []Node, event_name: []const u8) !Event {
    var event = Event.init(allocator, event_name);

    var index: usize = 0;
    for (nodes) |node| {
        defer index += 1;
        switch (node) {
            .arg_begin => |a| {
                const arg: Arg = .{ .name = a.name, .type = a.type };
                try event.args.append(arg);
            },
            else => continue,
        }
    }

    return event;
}

fn processEnum(allocator: std.mem.Allocator, nodes: []Node, enum_name: []const u8, bitmap: bool) !Enum {
    var @"enum" = Enum.init(allocator, enum_name, bitmap);

    var index: usize = 0;
    for (nodes) |node| {
        defer index += 1;
        switch (node) {
            .entry_begin => |e| {
                const entry: Entry = .{ .name = e.name, .value = e.value };
                try @"enum".entries.append(entry);
            },
            .entry_end => {},
            else => continue,
        }
    }

    return @"enum";
}

const part_1 =
    \\const std = @import("std");
    \\const builtin = @import("builtin");
    \\const WireFn = @import("wire.zig").Wire;
    \\
    \\const fn Wayland(comptime ResourceMap: struct {
    \\
;
const part_2 =
    \\}) type {
    \\  return struct {
    \\    pub const Wire = WireFn(WlMessage);
    \\
;
const part_3 =
    \\  };
    \\}
    \\
;
// const walyand_struct = "const fn Wayland(comptime ResourceMap: struct {{ {s} }}) type {{ return struct {{ {s} }}; }}";

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

    pub fn format(arg_type: ArgType, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        switch (arg_type) {
            .int => try writer.print("int", .{}),
            .uint => try writer.print("uint", .{}),
            .fd => try writer.print("fd", .{}),
            .new_id => try writer.print("new_id", .{}),
            .object => try writer.print("object", .{}),
            .string => try writer.print("string", .{}),
            .fixed => try writer.print("fixed", .{}),
            .array => try writer.print("array", .{}),
        }
    }
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

const Wayland = struct {
    protocols: std.ArrayList(Protocol),

    pub fn init(allocator: std.mem.Allocator) Wayland {
        return .{ .protocols = std.ArrayList(Protocol).init(allocator) };
    }

    pub fn format(wayland: Wayland, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        for (wayland.protocols.items) |protocol| {
            try writer.print("{any}\n", .{protocol});
        }
    }
};

const Protocol = struct {
    name: []const u8,
    interfaces: std.ArrayList(Interface),

    pub fn init(allocator: std.mem.Allocator, name: []const u8) Protocol {
        return .{ .name = name, .interfaces = std.ArrayList(Interface).init(allocator) };
    }

    pub fn format(protocol: Protocol, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("protocol \"{s}\":\n", .{protocol.name});
        for (protocol.interfaces.items) |interface| {
            try writer.print("{any}\n", .{interface});
        }
    }
};

const Interface = struct {
    name: []const u8,
    enums: std.ArrayList(Enum),
    requests: std.ArrayList(Request),
    events: std.ArrayList(Event),

    pub fn init(allocator: std.mem.Allocator, name: []const u8) Interface {
        return .{
            .name = name,
            .enums = std.ArrayList(Enum).init(allocator),
            .requests = std.ArrayList(Request).init(allocator),
            .events = std.ArrayList(Event).init(allocator),
        };
    }

    pub fn format(interface: Interface, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("  interface \"{s}\":\n", .{interface.name});
        for (interface.enums.items) |@"enum"| {
            try writer.print("{any}\n", .{@"enum"});
        }
        for (interface.requests.items) |request| {
            try writer.print("{any}\n", .{request});
        }
        for (interface.events.items) |event| {
            try writer.print("{any}\n", .{event});
        }
    }
};

const Request = struct {
    name: []const u8,
    args: std.ArrayList(Arg),

    pub fn init(allocator: std.mem.Allocator, name: []const u8) Request {
        return .{
            .name = name,
            .args = std.ArrayList(Arg).init(allocator),
        };
    }

    pub fn format(request: Request, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("    request \"{s}\":\n", .{request.name});
        for (request.args.items) |arg| {
            try writer.print("{any}\n", .{arg});
        }
    }
};

const Event = struct {
    name: []const u8,
    args: std.ArrayList(Arg),

    pub fn init(allocator: std.mem.Allocator, name: []const u8) Event {
        return .{
            .name = name,
            .args = std.ArrayList(Arg).init(allocator),
        };
    }

    pub fn format(event: Event, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("    event \"{s}\":\n", .{event.name});
        for (event.args.items) |arg| {
            try writer.print("{any}\n", .{arg});
        }
    }
};

const Enum = struct {
    name: []const u8,
    bitmap: bool,
    entries: std.ArrayList(Entry),

    pub fn init(allocator: std.mem.Allocator, name: []const u8, bitmap: bool) Enum {
        return .{
            .name = name,
            .bitmap = bitmap,
            .entries = std.ArrayList(Entry).init(allocator),
        };
    }

    pub fn format(@"enum": Enum, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("    enum {s}:\n", .{@"enum".name});
        for (@"enum".entries.items) |entry| {
            try writer.print("{any}\n", .{entry});
        }
    }
};

const Arg = struct {
    name: []const u8,
    type: ArgType,

    pub fn format(arg: Arg, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("      arg \"{s}\" {any}", .{ arg.name, arg.type });
    }
};

const Entry = struct {
    name: []const u8,
    value: u32,

    pub fn format(entry: Entry, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("      entry \"{s}\" {}", .{ entry.name, entry.value });
    }
};
