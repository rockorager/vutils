//! Pure counting functions - shared across all platforms
//! No I/O, no allocations, no syscalls

const std = @import("std");
const uucode = @import("uucode");

pub const Counts = struct {
    lines: u64 = 0,
    words: u64 = 0,
    bytes: u64 = 0,

    pub fn add(self: Counts, other: Counts) Counts {
        return .{
            .lines = self.lines + other.lines,
            .words = self.words + other.words,
            .bytes = self.bytes + other.bytes,
        };
    }
};

/// Check if a Unicode code point is whitespace
/// Follows Unicode semantics: Zs (Space_Separator) + line/paragraph separators
fn isUnicodeWhitespace(cp: u21) bool {
    // ASCII whitespace (fast path)
    if (cp <= 0x7F) {
        return switch (@as(u8, @intCast(cp))) {
            ' ', '\t', '\n', '\r', 0x0b, 0x0c => true,
            else => false,
        };
    }

    // Unicode whitespace: general_category == separator_space (Zs)
    // This includes NO-BREAK SPACE, EM SPACE, FIGURE SPACE, etc.
    const gc = uucode.get(.general_category, cp);
    if (gc == .separator_space) return true;

    // Line/paragraph separators (Zl, Zp categories)
    return cp == 0x0085 or // NEL (Next Line) - Cc but treated as line break
        cp == 0x2028 or // LINE SEPARATOR (Zl)
        cp == 0x2029; // PARAGRAPH SEPARATOR (Zp)
}

/// Count lines, words, bytes in a buffer (ASCII fast path)
pub fn countBuffer(buf: []const u8) Counts {
    return countBufferWithState(buf, false).counts;
}

pub const CountState = struct {
    counts: Counts,
    in_word: bool,
};

/// Count with word boundary state for streaming (ASCII fast path)
pub fn countBufferWithState(buf: []const u8, in_word_start: bool) CountState {
    var counts = Counts{ .bytes = buf.len };
    var in_word = in_word_start;

    for (buf) |byte| {
        if (byte == '\n') counts.lines += 1;

        // ASCII whitespace only - fast path
        const is_space = switch (byte) {
            ' ', '\t', '\n', '\r', 0x0b, 0x0c => true,
            else => false,
        };

        if (is_space) {
            in_word = false;
        } else if (!in_word) {
            in_word = true;
            counts.words += 1;
        }
    }

    return .{ .counts = counts, .in_word = in_word };
}

/// Count with full Unicode whitespace support
/// Handles invalid UTF-8 gracefully (treats invalid bytes as non-whitespace)
pub fn countBufferUnicode(buf: []const u8, in_word_start: bool) CountState {
    var counts = Counts{ .bytes = buf.len };
    var in_word = in_word_start;
    var i: usize = 0;

    while (i < buf.len) {
        const byte = buf[i];

        // Count newlines
        if (byte == '\n') counts.lines += 1;

        // Try to decode UTF-8
        const cp_len = std.unicode.utf8ByteSequenceLength(byte) catch {
            // Invalid start byte - treat as non-whitespace, skip 1 byte
            if (!in_word) {
                in_word = true;
                counts.words += 1;
            }
            i += 1;
            continue;
        };

        if (i + cp_len > buf.len) {
            // Truncated sequence at end of buffer - treat as non-whitespace
            if (!in_word) {
                in_word = true;
                counts.words += 1;
            }
            i += 1;
            continue;
        }

        const cp = std.unicode.utf8Decode(buf[i..][0..cp_len]) catch {
            // Invalid UTF-8 sequence - treat as non-whitespace
            if (!in_word) {
                in_word = true;
                counts.words += 1;
            }
            i += 1;
            continue;
        };

        const is_space = isUnicodeWhitespace(cp);

        if (is_space) {
            in_word = false;
        } else if (!in_word) {
            in_word = true;
            counts.words += 1;
        }

        i += cp_len;
    }

    return .{ .counts = counts, .in_word = in_word };
}

/// Count only lines and bytes (faster - no word boundary tracking)
pub fn countLinesBytes(buf: []const u8) struct { lines: u64, bytes: u64 } {
    var lines: u64 = 0;

    for (buf) |byte| {
        if (byte == '\n') lines += 1;
    }

    return .{ .lines = lines, .bytes = buf.len };
}

test "countBuffer basic" {
    const result = countBuffer("hello world\nfoo bar\n");
    try std.testing.expectEqual(@as(u64, 2), result.lines);
    try std.testing.expectEqual(@as(u64, 4), result.words);
    try std.testing.expectEqual(@as(u64, 20), result.bytes);
}

test "countBuffer empty" {
    const result = countBuffer("");
    try std.testing.expectEqual(@as(u64, 0), result.lines);
    try std.testing.expectEqual(@as(u64, 0), result.words);
    try std.testing.expectEqual(@as(u64, 0), result.bytes);
}

test "streaming word boundary" {
    // "hello " split as "hel" + "lo "
    const s1 = countBufferWithState("hel", false);
    const s2 = countBufferWithState("lo ", s1.in_word);

    try std.testing.expectEqual(@as(u64, 1), s1.counts.words + s2.counts.words);
}

test "unicode whitespace - NO-BREAK SPACE" {
    // U+00A0 NO-BREAK SPACE should be treated as whitespace
    const buf = "hello\xc2\xa0world"; // "hello<NBSP>world"
    const result = countBufferUnicode(buf, false);
    try std.testing.expectEqual(@as(u64, 2), result.counts.words);
}

test "unicode whitespace - EM SPACE" {
    // U+2003 EM SPACE should be treated as whitespace
    const buf = "hello\xe2\x80\x83world"; // "hello<EM SPACE>world"
    const result = countBufferUnicode(buf, false);
    try std.testing.expectEqual(@as(u64, 2), result.counts.words);
}

test "unicode whitespace - ZERO WIDTH SPACE" {
    // U+200B ZERO WIDTH SPACE is NOT whitespace (it's Cf, not Zs)
    // BSD wc does NOT treat this as a word separator
    const buf = "hello\xe2\x80\x8bworld"; // "hello<ZWSP>world"
    const result = countBufferUnicode(buf, false);
    try std.testing.expectEqual(@as(u64, 1), result.counts.words);
}

test "check general_category for special spaces" {
    // NO-BREAK SPACE - should be Zs (separator_space)
    try std.testing.expectEqual(uucode.types.GeneralCategory.separator_space, uucode.get(.general_category, 0x00A0));

    // FIGURE SPACE - should be Zs
    try std.testing.expectEqual(uucode.types.GeneralCategory.separator_space, uucode.get(.general_category, 0x2007));

    // NARROW NO-BREAK SPACE - should be Zs
    try std.testing.expectEqual(uucode.types.GeneralCategory.separator_space, uucode.get(.general_category, 0x202F));

    // WORD JOINER - should be Cf (format), NOT Zs
    try std.testing.expectEqual(uucode.types.GeneralCategory.other_format, uucode.get(.general_category, 0x2060));

    // ZERO WIDTH SPACE - should be Cf (format), NOT Zs
    try std.testing.expectEqual(uucode.types.GeneralCategory.other_format, uucode.get(.general_category, 0x200B));
}
