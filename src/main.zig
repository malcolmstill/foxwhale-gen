const std = @import("std");
const xml2 = @cImport({
    @cDefine("LIBXML_READER_ENABLED", {});
    @cInclude("libxml/xmlreader.h");
});

pub fn main() !void {
    const reader = xml2.xmlReaderForFile("wayland.xml", null, 0) orelse return error.ReaderFailed;
    defer xml2.xmlFreeTextReader(reader);

    // Process the file
    while (xml2.xmlTextReaderRead(reader) == 1) {
        processNode(reader);
    }

    // Cleanup function for the XML library
    xml2.xmlCleanupParser();
}

fn processNode(reader: *xml2.xmlTextReader) void {
    const name_ptr = xml2.xmlTextReaderConstName(reader);
    const name = if (name_ptr) |ptr| std.mem.span(ptr) else "<unknown>";

    std.debug.print("Element: {s}\n", .{name});

    // Check if the node has attributes
    if (xml2.xmlTextReaderHasAttributes(reader) != 0) {
        // Successfully moved to the first attribute
        if (xml2.xmlTextReaderMoveToFirstAttribute(reader) == 1) {
            // Process each attribute
            while (true) {
                // Print attribute name and value
                const attr_name_ptr = xml2.xmlTextReaderConstName(reader);
                const attr_name = if (attr_name_ptr) |ptr| std.mem.span(ptr) else "<unknown>";
                const attr_value_ptr = xml2.xmlTextReaderConstValue(reader);
                const attr_value = if (attr_value_ptr) |ptr| std.mem.span(ptr) else "<no value>";
                std.debug.print("  Attribute: {s}='{s}'\n", .{ attr_name, attr_value });

                // Attempt to move to the next attribute; break if unsuccessful
                if (xml2.xmlTextReaderMoveToNextAttribute(reader) != 1) {
                    break;
                }
            }

            // After processing attributes, move back to the element node
            _ = xml2.xmlTextReaderMoveToElement(reader);
        }
    }

    if (xml2.xmlTextReaderHasValue(reader) != 0) {
        const value_ptr = xml2.xmlTextReaderConstValue(reader);
        const value = if (value_ptr) |ptr| std.mem.span(ptr) else "";
        std.debug.print("Value: {s}", .{value});
    }
}
