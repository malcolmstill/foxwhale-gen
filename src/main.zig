const std = @import("std");
const xml2 = @cImport({
    @cDefine("LIBXML_READER_ENABLED", "1");
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

    if (xml2.xmlTextReaderHasValue(reader) != 0) {
        const value_ptr = xml2.xmlTextReaderConstValue(reader);
        const value = if (value_ptr) |ptr| std.mem.span(ptr) else "<no value>";
        std.debug.print("  Value: {s}\n", .{value});
    }
}
