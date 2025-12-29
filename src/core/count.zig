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
/// Fast path for ASCII, uses custom decoder for multibyte to handle malformed sequences correctly
pub fn countBufferUnicode(buf: []const u8, in_word_start: bool) CountState {
    var counts = Counts{ .bytes = buf.len };
    var in_word = in_word_start;
    var i: usize = 0;

    while (i < buf.len) {
        const byte = buf[i];

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
            i += 1;
            continue;
        }

        // Multibyte: decode with proper malformed sequence handling
        // Each malformed byte should be treated as a single replacement character (non-whitespace)
        const decode_result = locale.decodeUtf8(buf[i..]);
        counts.chars += 1;

        const is_space = locale.isUnicodeWhitespace(decode_result.codepoint);
        if (is_space) {
            in_word = false;
        } else if (!in_word) {
            in_word = true;
            counts.words += 1;
        }
        i += decode_result.len;
    }

    return .{ .counts = counts, .in_word = in_word };
}

/// Count only lines and bytes (faster - no word boundary tracking)
/// Uses SIMD when available for ~3x speedup on newline counting
pub fn countLinesBytes(buf: []const u8) struct { lines: u64, bytes: u64 } {
    return .{ .lines = countNewlines(buf), .bytes = buf.len };
}

/// SIMD-accelerated newline counting with scalar fallback
fn countNewlines(data: []const u8) u64 {
    const VecLen = std.simd.suggestVectorLength(u8) orelse return countNewlinesScalar(data);
    const Vec = @Vector(VecLen, u8);

    var count: u64 = 0;
    var i: usize = 0;

    // SIMD loop - process VecLen bytes at a time
    while (i + VecLen <= data.len) : (i += VecLen) {
        const chunk: Vec = data[i..][0..VecLen].*;
        const newlines: Vec = @splat('\n');
        const matches = chunk == newlines;
        count += std.simd.countTrues(matches);
    }

    // Scalar tail for remaining bytes
    while (i < data.len) : (i += 1) {
        if (data[i] == '\n') count += 1;
    }

    return count;
}

fn countNewlinesScalar(data: []const u8) u64 {
    var count: u64 = 0;
    for (data) |byte| {
        if (byte == '\n') count += 1;
    }
    return count;
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

test "countLinesBytes basic" {
    const result = countLinesBytes("hello\nworld\nfoo\n");
    try std.testing.expectEqual(@as(u64, 3), result.lines);
    try std.testing.expectEqual(@as(u64, 16), result.bytes);
}

test "countLinesBytes empty" {
    const result = countLinesBytes("");
    try std.testing.expectEqual(@as(u64, 0), result.lines);
    try std.testing.expectEqual(@as(u64, 0), result.bytes);
}

test "countLinesBytes no newlines" {
    const result = countLinesBytes("hello world");
    try std.testing.expectEqual(@as(u64, 0), result.lines);
    try std.testing.expectEqual(@as(u64, 11), result.bytes);
}

test "countLinesBytes large buffer" {
    // Test with buffer larger than typical SIMD vector (16-64 bytes)
    const buf = "a\n" ** 100; // 200 bytes, 100 newlines
    const result = countLinesBytes(buf);
    try std.testing.expectEqual(@as(u64, 100), result.lines);
    try std.testing.expectEqual(@as(u64, 200), result.bytes);
}

test "countNewlinesScalar matches SIMD" {
    // Verify scalar fallback matches SIMD result
    const data = "hello\nworld\nfoo\nbar\nbaz\n";
    const simd_result = countNewlines(data);
    const scalar_result = countNewlinesScalar(data);
    try std.testing.expectEqual(simd_result, scalar_result);
}

test "malformed UTF-8 - lead byte followed by space" {
    // C0 20 C1 20 - each lead byte followed by space should be 2 words each
    // (lead byte = word, space = separator)
    const buf = "\xc0 \xc1 ";
    const result = countBufferUnicode(buf, false);
    try std.testing.expectEqual(@as(u64, 2), result.counts.words);
}

test "malformed UTF-8 - multiple lead bytes with spaces (GNU wc behavior)" {
    // Each malformed lead byte is a non-whitespace character (replacement char)
    // Pattern: C0 SP C1 SP C2 SP ... = each pair is "word separator"
    const buf = "\xc0 \xc1 \xc2 \xc3 \xc4 \xc5 \xc6 \xc7 \xc8 \xc9 \xca \xcb \xcc \xcd ";
    const result = countBufferUnicode(buf, false);
    try std.testing.expectEqual(@as(u64, 14), result.counts.words);
}

// decodeUtf8 tests are in locale.zig
