const std = @import("std");
const xml2 = @cImport({
    @cInclude("libxml/parser.h");
    @cInclude("libxml/tree.h");
});

pub fn main() !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    // const args = try std.process.argsAlloc(arena);

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

    // const outfile = try std.fs.cwd().createFile(output, .{});
    // defer outfile.close();

    var writer = std.io.getStdOut().writer();

    // const output: []const u8 = args[1];

    try writer.print("{s}", .{part_1});
    for (wayland.protocols.items) |protocol| {
        for (protocol.interfaces.items) |interface| {
            try writer.print("  {s}: type = ?void,\n", .{interface.name});
        }
    }
    try writer.print("{s}", .{part_2});

    for (wayland.protocols.items) |protocol| {
        for (protocol.interfaces.items) |interface| {
            try writer.print("/// {s}\n", .{interface.name});
            try emitDoc(writer, interface.summary, interface.description);
            try writer.print("    pub const {s} = struct {{\n", .{try dotToCamel(arena, interface.name)});
            try writer.print("      wire: *Wire,\n", .{});
            try writer.print("      id: u32,\n", .{});
            try writer.print("      version: u32,\n", .{});
            try writer.print("      resource: ResourceMap.{s},\n", .{interface.name});
            try writer.print("\n", .{});
            try writer.print("      const Self = @This();\n\n", .{});

            try writer.print("      pub fn init(id: u32, wire: *Wire, version: u32, resource: ResourceMap.{s}) Self {{\n", .{interface.name});
            try writer.print("        return Self{{\n", .{});
            try writer.print("          .id = id,\n", .{});
            try writer.print("          .wire = wire,\n", .{});
            try writer.print("          .version = version,\n", .{});
            try writer.print("          .resource = resource,\n", .{});
            try writer.print("        }};\n", .{});
            try writer.print("      }}\n", .{});

            // Enums
            // ============================================
            for (interface.enums.items) |@"enum"| {
                // try writer.print("      pub const {s} = enum(u8) {{\n", .{try snakeToCamel(arena, @"enum".name)});
                // for (@"enum".entries)
                // try writer.print("      }};\n\n", .{});
                try @"enum".emit(arena, writer);
            }

            // Requests
            // ============================================
            try writer.print("      pub fn readMessage(self: *Self, comptime Client: type, objects: anytype, comptime field: []const u8, opcode: u16) !Message {{\n", .{});
            // try writer.print("        use(self, Client, objects, field);\n", .{});
            try writer.print(" if (builtin.mode == .Debug and builtin.mode == .ReleaseFast) std.log.info(\"{{any}}, {{s}} {{s}}\", .{{ &objects, &field, Client }});", .{});
            try writer.print("        switch(opcode) {{\n", .{});
            for (interface.requests.items) |request| {
                try writer.print("          // {s}\n", .{request.name});
                try writer.print("          {} => {{\n", .{request.index});
                for (request.args.items) |arg| {
                    // try writer.print("            const {s} = {s},\n", .{ arg.name,  });
                    try arg.genNext(arena, writer);
                }
                try writer.print("            return Message {{\n", .{});
                try writer.print("              .{s} = {s}Message {{\n", .{ request.name, try snakeToCamel(arena, request.name) });
                try writer.print("                .{s} = self.*,\n", .{interface.name});
                for (request.args.items) |arg| {
                    try writer.print("                .{s} = {s},\n", .{ arg.name, arg.name });
                }
                try writer.print("              }},\n", .{});
                try writer.print("            }};\n", .{});
                try writer.print("          }},\n", .{});
            }
            try writer.print("          else => {{\n", .{});
            try writer.print("            return error.UnknownOpcode;\n", .{});
            try writer.print("          }},\n", .{});
            try writer.print("        }}\n", .{});
            try writer.print("      }}\n\n", .{});

            try writer.print("      const MessageType = enum(u8) {{\n", .{});
            for (interface.requests.items) |request| {
                try writer.print("        {s},\n", .{request.name});
            }
            try writer.print("      }};\n\n", .{});

            try writer.print("      pub const Message = union(MessageType) {{\n", .{});
            for (interface.requests.items) |request| {
                try emitDoc(writer, request.summary, request.description);
                try writer.print("        {s}: {s}Message,\n", .{ request.name, try snakeToCamel(arena, request.name) });
            }
            try writer.print("      }};\n\n", .{});

            for (interface.requests.items) |request| {
                try emitDoc(writer, request.summary, request.description);
                try writer.print("      const {s}Message = struct {{\n", .{try snakeToCamel(arena, request.name)});
                try writer.print("        {s}: {s},\n", .{ interface.name, try snakeToCamel(arena, interface.name) });
                for (request.args.items) |arg| {
                    try writer.print("/// {s}\n", .{arg.summary});
                    try arg.genMessageType(arena, writer);
                }
                try writer.print("      }};\n\n", .{});
            }

            // Events
            // ============================================
            for (interface.events.items) |event| {
                // FIXME: emit doc
                try emitDoc(writer, event.summary, event.description);
                try writer.print("      pub fn send{s}(self: Self", .{try dotToCamel(arena, event.name)});
                for (event.args.items) |arg| {
                    try writer.print(", {s}: {s}", .{ arg.name, try arg.type.zigType(arena) });
                }
                try writer.print(") !void {{\n", .{});
                try writer.print("        try self.wire.startWrite();\n", .{});

                for (event.args.items) |a| {
                    const arg: Arg = a;
                    try arg.genPut(writer);
                }

                try writer.print("        try self.wire.finishWrite(self.id, {});\n", .{event.index});
                try writer.print("      }}\n\n", .{});
            }
            try writer.print("    }};\n\n", .{});
        }
    }

    try writer.print("pub const WlInterfaceType = enum(u8) {{\n", .{});
    for (wayland.protocols.items) |protocol| {
        for (protocol.interfaces.items) |interface| {
            try writer.print("{s},\n", .{interface.name});
        }
    }
    try writer.print("}};\n\n", .{});

    try writer.print("pub const WlMessage = union(WlInterfaceType) {{\n", .{});
    for (wayland.protocols.items) |protocol| {
        for (protocol.interfaces.items) |interface| {
            try writer.print("{s}: {s}.Message,\n", .{ interface.name, try snakeToCamel(arena, interface.name) });
        }
    }
    try writer.print("}};\n\n", .{});

    try writer.print("pub const WlObject = union(WlInterfaceType) {{\n", .{});
    for (wayland.protocols.items) |protocol| {
        for (protocol.interfaces.items) |interface| {
            try writer.print("{s}: {s},\n", .{ interface.name, try snakeToCamel(arena, interface.name) });
        }
    }

    // fn readMessage
    try writer.print("\npub fn readMessage(self: *WlObject, comptime Client: type, objects: anytype, comptime field: []const u8, opcode: u16) !WlMessage {{\n", .{});
    try writer.print("return switch (self.*) {{\n", .{});
    for (wayland.protocols.items) |protocol| {
        for (protocol.interfaces.items) |interface| {
            try writer.print(".{s} => |*o| WlMessage {{ .{s} = try o.readMessage(Client, objects, field, opcode) }},\n", .{ interface.name, try snakeToCamel(arena, interface.name) });
        }
    }
    try writer.print("}};\n\n", .{});
    try writer.print("}}\n\n", .{});

    // fn id
    try writer.print("\npub fn id(self: WlObject) u32 {{\n", .{});
    try writer.print("return switch (self) {{\n", .{});
    for (wayland.protocols.items) |protocol| {
        for (protocol.interfaces.items) |interface| {
            try writer.print(".{s} => |o| o.id,\n", .{interface.name});
        }
    }
    try writer.print("}};\n\n", .{});
    try writer.print("}}\n\n", .{});

    try writer.print("}};\n\n", .{});

    try writer.print("{s}", .{part_3});

    try writer.print("fn use(self: anytype, client: anytype, objects: anytype, field: anytype) void {{", .{});
    try writer.print("_ = self;", .{});
    try writer.print("_ = client;", .{});
    try writer.print("_ = objects;", .{});
    try writer.print("_ = field;", .{});
    try writer.print("}}", .{});
}

pub fn dotToCamel(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    const dot_count = std.mem.count(u8, input, ".");

    if (dot_count == 0) {
        return try snakeToCamel(allocator, input);
    } else if (dot_count == 1) {
        var it = std.mem.split(u8, input, ".");
        const first = try snakeToCamel(allocator, it.next() orelse unreachable);
        const second = try snakeToCamel(allocator, it.next() orelse unreachable);

        return try std.mem.join(allocator, ".", &.{ first, second });
    } else {
        unreachable;
    }
}

pub fn snakeToCamel(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var it = std.mem.split(u8, input, "_");

    var underscore_count: usize = 0;
    for (input) |c| {
        if (c != '_') continue;

        underscore_count += 1;
    }

    var out = try allocator.alloc(u8, input.len - underscore_count);

    var index: usize = 0;
    while (it.next()) |part| {
        defer index += part.len;

        std.mem.copyForwards(u8, out[index .. index + part.len], part);
        out[index] -= 32;
    }

    return out;
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
    var request_number: usize = 0;
    var event_number: usize = 0;
    for (nodes) |node| {
        defer index += 1;
        switch (node) {
            .description_begin => |d| {
                if (index == 1) {
                    interface.summary = d.summary;
                    interface.description = d.description;
                }
            },
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
                const request = try processRequest(allocator, nodes[start..index], name, request_number);
                try interface.requests.append(request);
                request_number += 1;
            },
            .event_begin => |e| {
                name = e.name;
                start = index;
            },
            .event_end => {
                const event = try processEvent(allocator, nodes[start..index], name, event_number);
                try interface.events.append(event);
                event_number += 1;
            },
            else => continue,
        }
    }

    return interface;
}

fn processRequest(allocator: std.mem.Allocator, nodes: []Node, request_name: []const u8, request_number: usize) !Request {
    var request = Request.init(allocator, request_name, request_number);

    var index: usize = 0;
    for (nodes) |node| {
        defer index += 1;
        switch (node) {
            .description_begin => |d| {
                if (index == 1) {
                    request.summary = d.summary;
                    request.description = d.description;
                }
            },
            .arg_begin => |a| {
                const arg: Arg = .{ .name = a.name, .type = a.type };
                try request.args.append(arg);
            },
            else => continue,
        }
    }

    return request;
}

fn processEvent(allocator: std.mem.Allocator, nodes: []Node, event_name: []const u8, event_number: usize) !Event {
    var event = Event.init(allocator, event_name, event_number);

    var index: usize = 0;
    for (nodes) |node| {
        defer index += 1;
        switch (node) {
            .description_begin => |d| {
                if (index == 1) {
                    event.summary = d.summary;
                    event.description = d.description;
                }
            },
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
    \\pub fn Wayland(comptime ResourceMap: struct {
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
    object: struct { interface: ?[]const u8 = null, @"allow-null": bool = false },
    string: struct { @"allow-null": bool = false },
    fixed: struct {},
    array: struct {},

    pub fn zigType(arg_type: ArgType, allocator: std.mem.Allocator) ![]const u8 {
        return switch (arg_type) {
            .int => |o| if (o.@"enum") |e| try dotToCamel(allocator, e) else "i32",
            .uint => |o| if (o.@"enum") |e| try dotToCamel(allocator, e) else "u32",
            .fd => "i32",
            .new_id => "u32",
            .object => |o| if (o.interface) |i| try dotToCamel(allocator, i) else "u32",
            .string => "[]const u8",
            .fixed => "f32",
            .array => "[]u8",
        };
    }

    pub fn genMessageType(arg_type: ArgType, allocator: std.mem.Allocator, writer: anytype, name: []const u8) !void {
        switch (arg_type) {
            .int => |o| if (o.@"enum") |_| {
                try writer.print("{s}: i32,\n", .{name});
            } else {
                try writer.print("{s}: i32,\n", .{name});
            },
            .uint => |o| if (o.@"enum") |_| {
                try writer.print("{s}: u32,\n", .{name});
            } else {
                try writer.print("{s}: u32,\n", .{name});
            },
            .fd => try writer.print("{s}: i32,\n", .{name}),
            .new_id => try writer.print("{s}: u32,\n", .{name}),
            .object => |o| {
                if (o.interface) |iface| {
                    if (o.@"allow-null" == false) {
                        try writer.print("{s}: {s},\n", .{ name, try snakeToCamel(allocator, iface) });
                    } else {
                        try writer.print("{s}: ?{s},\n", .{ name, try snakeToCamel(allocator, iface) });
                    }
                } else {
                    try writer.print("{s}: u32,\n", .{name});
                }
            },
            .string => try writer.print("{s}: []u8,\n", .{name}),
            .fixed => try writer.print("{s}: f32,\n", .{name}),
            .array => try writer.print("{s}: []u8,\n", .{name}),
        }
    }

    pub fn genNext(arg_type: ArgType, allocator: std.mem.Allocator, writer: anytype, name: []const u8) !void {
        try writer.print("            ", .{});
        return switch (arg_type) {
            .int => |o| if (o.@"enum") |_| {
                try writer.print("const {s}: i32 = try self.wire.nextI32();\n", .{name});
            } else {
                try writer.print("const {s}: i32 = try self.wire.nextI32();\n", .{name});
            },
            .uint => |o| if (o.@"enum") |_| {
                try writer.print("const {s}: u32 = try self.wire.nextU32();\n", .{name});
            } else {
                try writer.print("const {s}: u32 = try self.wire.nextU32();\n", .{name});
            },
            .fd => try writer.print("const {s}: i32 = try self.wire.nextFd();\n", .{name}),
            .new_id => try writer.print("const {s}: u32 = try self.wire.nextU32();\n", .{name}),
            .object => |o| {
                if (o.interface) |iface| {
                    if (o.@"allow-null" == false) {
                        try writer.print("const {s}: {s} = if (@call(.auto, @field(Client, field), .{{objects, try self.wire.nextU32()}})) |obj| switch (obj) {{ .{s} => |o| o, else => return error.MismtachObjectTypes, }} else return error.ExpectedObject;\n", .{ name, try snakeToCamel(allocator, iface), iface });
                    } else {
                        try writer.print("const {s}: ?{s} = if (@call(.auto, @field(Client, field), .{{objects, try self.wire.nextU32()}})) |obj| switch (obj) {{ .{s} => |o| o, else => return error.MismtachObjectTypes, }} else null;\n", .{ name, try snakeToCamel(allocator, iface), iface });
                    }
                } else {
                    try writer.print("const {s} = try self.wire.nextU32();\n", .{name}); // TODO: We can make send args typesafe
                }
            },
            .string => try writer.print("const {s}: []u8 = try self.wire.nextString();\n", .{name}),
            .fixed => try writer.print("const {s} = try self.wire.nextFixed();\n", .{name}),
            .array => try writer.print("const {s} = try self.wire.nextArray();\n", .{name}),
        };
    }

    pub fn genPut(arg_type: ArgType, writer: anytype, name: []const u8) !void {
        try writer.print("        try self.wire.", .{});

        return switch (arg_type) {
            .int => |o| if (o.@"enum") |_| {
                try writer.print("putI32(@intFromEnum({s})); // enum\n", .{name});
            } else {
                try writer.print("putI32({s});\n", .{name});
            },
            .uint => |o| if (o.@"enum") |_| {
                try writer.print("putU32(@intFromEnum({s})); // enum\n", .{name});
            } else {
                try writer.print("putU32({s});\n", .{name});
            },
            .fd => try writer.print("putFd({s});\n", .{name}),
            .new_id => try writer.print("putU32({s});\n", .{name}),
            .object => try writer.print("putU32({s});\n", .{name}), // TODO: We can make send args typesafe
            .string => try writer.print("putString({s});\n", .{name}),
            .fixed => try writer.print("putFixed({s});\n", .{name}),
            .array => try writer.print("putArray({s});\n", .{name}),
        };
    }

    pub fn format(arg_type: ArgType, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        switch (arg_type) {
            .int => try writer.print("int", .{}),
            .uint => try writer.print("uint", .{}),
            .fd => try writer.print("fd", .{}),
            .new_id => try writer.print("new_id", .{}),
            .object => |o| {
                try writer.print("object (allow-null = {}", .{o.allow_null});
                if (o.interface) |i| {
                    try writer.print("interface = {s}", .{i});
                }
                try writer.print(")", .{});
            },
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
    description_begin: struct { summary: []const u8 = "", description: []const u8 = "" },
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
            .arg_begin => |n| try writer.print("<arg name=\"{s}\" type=\"{any}\" summary=\"{s}\">", .{
                n.name,
                n.type,
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

        if (std.mem.eql(u8, tag, "description")) {
            const content = std.mem.span(xml2.xmlNodeGetContent(cur_node));
            latest_node.description_begin.description = content;
        }

        var attr = cur_node.*.properties;
        while (attr != null) {
            const attr_name = std.mem.span(attr.*.name);
            const attr_value = std.mem.span(attr.*.children.*.content);

            const arena_attr_value = try allocator.alloc(u8, attr_value.len);
            std.mem.copyForwards(u8, arena_attr_value, attr_value);

            switch (latest_node.*) {
                .arg_begin => |*n| inline for (std.meta.fields(@TypeOf(n.*))) |_| {
                    if (std.mem.eql(u8, attr_name, "name")) {
                        n.name = attr_value;
                    } else if (std.mem.eql(u8, attr_name, "summary")) {
                        n.summary = arena_attr_value;
                    } else if (std.mem.eql(u8, attr_name, "type")) {
                        inline for (std.meta.fields(ArgType)) |union_field| {
                            if (std.mem.eql(u8, union_field.name, attr_value)) {
                                n.type = @unionInit(ArgType, union_field.name, .{});
                            }
                        }
                    } else {
                        inline for (std.meta.fields(ArgType)) |union_field| {
                            if (std.mem.eql(u8, union_field.name, @tagName(std.meta.activeTag(n.type)))) {
                                inline for (std.meta.fields(union_field.type)) |union_specific_field| {
                                    if (std.mem.eql(u8, attr_name, union_specific_field.name)) {
                                        switch (@typeInfo(union_specific_field.type)) {
                                            .Bool => @field(@field(n.type, union_field.name), union_specific_field.name) = std.mem.eql(u8, arena_attr_value, "true"),
                                            else => @field(@field(n.type, union_field.name), union_specific_field.name) = arena_attr_value,
                                        }
                                    }
                                }
                            }
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
        return .{
            .name = name,
            .interfaces = std.ArrayList(Interface).init(allocator),
        };
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
    summary: ?[]const u8 = null,
    description: []const u8 = "",
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
    summary: ?[]const u8 = null,
    description: []const u8 = "",
    index: usize,
    args: std.ArrayList(Arg),

    pub fn init(allocator: std.mem.Allocator, name: []const u8, index: usize) Request {
        return .{
            .name = name,
            .index = index,
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
    summary: ?[]const u8 = null,
    description: []const u8 = "",
    index: usize,
    args: std.ArrayList(Arg),

    pub fn init(allocator: std.mem.Allocator, name: []const u8, index: usize) Event {
        return .{
            .name = name,
            .index = index,
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

    pub fn emit(@"enum": Enum, allocator: std.mem.Allocator, writer: anytype) !void {
        if (@"enum".bitmap) {
            const count = @"enum".entries.items.len - 1;
            try writer.print("      pub const {s} = packed struct(u32) {{ // bitfield\n", .{try snakeToCamel(allocator, @"enum".name)});
            for (@"enum".entries.items) |entry| {
                if (entry.value == 0) continue;
                try writer.print("        @\"{s}\": bool = false,\n", .{entry.name});
            }
            try writer.print("        _padding: u{} = 0,\n", .{32 - count});
            try writer.print("      }};\n\n", .{});
        } else {
            try writer.print("      pub const {s} = enum(u32) {{\n", .{try snakeToCamel(allocator, @"enum".name)});
            for (@"enum".entries.items) |entry| {
                try writer.print("        @\"{s}\" = {},\n", .{ entry.name, entry.value });
            }
            try writer.print("      }};\n\n", .{});
        }
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
    summary: []const u8 = "",
    type: ArgType,

    pub fn genMessageType(arg: Arg, allocator: std.mem.Allocator, writer: anytype) !void {
        try arg.type.genMessageType(allocator, writer, arg.name);
    }

    pub fn genNext(arg: Arg, allocator: std.mem.Allocator, writer: anytype) !void {
        try arg.type.genNext(allocator, writer, arg.name);
    }

    pub fn genPut(arg: Arg, writer: anytype) !void {
        try arg.type.genPut(writer, arg.name);
    }

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

fn emitDoc(writer: anytype, summary: ?[]const u8, doc: []const u8) !void {
    if (summary) |s| try writer.print("/// {s}\n", .{s});
    var it = std.mem.split(u8, doc, "\n");
    while (it.next()) |line| {
        try writer.print("/// {s}\n", .{std.mem.trim(u8, line, " \t")});
    }
}
