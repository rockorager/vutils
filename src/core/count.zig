//! Pure counting functions - shared across all platforms
//! No I/O, no allocations, no syscalls

const std = @import("std");
const locale = @import("locale");
const uucode = @import("uucode");

pub const Counts = struct {
    lines: u64 = 0,
    words: u64 = 0,
    bytes: u64 = 0,
    chars: u64 = 0,

    pub fn add(self: Counts, other: Counts) Counts {
        return .{
            .lines = self.lines + other.lines,
            .words = self.words + other.words,
            .bytes = self.bytes + other.bytes,
            .chars = self.chars + other.chars,
        };
    }
};

/// Count lines, words, bytes in a buffer (ASCII fast path)
pub fn countBuffer(buf: []const u8) Counts {
    return countBufferWithState(buf, false).counts;
}

/// Count respecting current locale (UTF-8 locale uses Unicode whitespace, otherwise ASCII)
pub fn countBufferLocale(buf: []const u8, in_word_start: bool) CountState {
    if (locale.isUtf8Locale()) {
        return countBufferUnicode(buf, in_word_start);
    } else {
        return countBufferWithState(buf, in_word_start);
    }
}

pub const CountState = struct {
    counts: Counts,
    in_word: bool,
};

/// What counts are needed - allows optimized code paths
pub const CountMode = enum {
    bytes_only,
    lines_only,
    lines_bytes,
    full,
};

/// Count with word boundary state for streaming (C locale - ASCII + Latin-1 NBSP)
pub fn countBufferWithState(buf: []const u8, in_word_start: bool) CountState {
    var counts = Counts{ .bytes = buf.len, .chars = buf.len };
    var in_word = in_word_start;

    for (buf) |byte| {
        counts.lines += @intFromBool(byte == '\n');
        const is_ws = switch (byte) {
            ' ', '\t', '\n', '\r', 0x0b, 0x0c, 0xa0 => true,
            else => false,
        };
        if (is_ws) {
            in_word = false;
        } else if (!in_word) {
            in_word = true;
            counts.words += 1;
        }
    }

    return .{ .counts = counts, .in_word = in_word };
}

/// Count with full Unicode whitespace support
/// Fast path for ASCII, falls back to uucode DFA decoder for multibyte
pub fn countBufferUnicode(buf: []const u8, in_word_start: bool) CountState {
    var counts = Counts{ .bytes = buf.len };
    var in_word = in_word_start;
    var iter = uucode.utf8.Iterator{ .bytes = buf, .i = 0 };

    while (iter.i < buf.len) {
        const byte = buf[iter.i];

        // ASCII fast path (most common case)
        if (byte < 0x80) {
            counts.chars += 1;
            counts.lines += @intFromBool(byte == '\n');
            const is_ws = switch (byte) {
                ' ', '\t', '\n', '\r', 0x0b, 0x0c => true,
                else => false,
            };
            if (is_ws) {
                in_word = false;
            } else if (!in_word) {
                in_word = true;
                counts.words += 1;
            }
            iter.i += 1;
            continue;
        }

        // Multibyte: use iterator (already positioned)
        if (iter.next()) |cp| {
            counts.chars += 1;

            const is_space = locale.isUnicodeWhitespace(cp);
            if (is_space) {
                in_word = false;
            } else if (!in_word) {
                in_word = true;
                counts.words += 1;
            }
        }
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

// Unicode general_category tests moved to locale.zig
