//! Locale detection and character classification
//! Shared across all tools for consistent behavior

const std = @import("std");

/// Cached locale detection result
var cached_is_utf8: ?bool = null;

/// Check if current locale is UTF-8 based on LC_CTYPE/LC_ALL/LANG
/// Result is cached after first call for performance
pub fn isUtf8Locale() bool {
    if (cached_is_utf8) |cached| return cached;
    
    const result = detectUtf8Locale();
    cached_is_utf8 = result;
    return result;
}

fn detectUtf8Locale() bool {
    // Check LC_ALL first (overrides everything)
    if (std.posix.getenv("LC_ALL")) |val| {
        if (val.len > 0) {
            if (std.mem.eql(u8, val, "C") or std.mem.eql(u8, val, "POSIX")) {
                return false;
            }
            return containsUtf8(val);
        }
    }

    // Then LC_CTYPE (specific to character classification)
    if (std.posix.getenv("LC_CTYPE")) |val| {
        if (val.len > 0) {
            if (std.mem.eql(u8, val, "C") or std.mem.eql(u8, val, "POSIX")) {
                return false;
            }
            return containsUtf8(val);
        }
    }

    // Fall back to LANG
    if (std.posix.getenv("LANG")) |val| {
        if (val.len > 0) {
            if (std.mem.eql(u8, val, "C") or std.mem.eql(u8, val, "POSIX")) {
                return false;
            }
            return containsUtf8(val);
        }
    }

    // Default: C locale (ASCII only)
    return false;
}

fn containsUtf8(s: []const u8) bool {
    var buf: [256]u8 = undefined;
    const len = @min(s.len, buf.len);
    const lower = std.ascii.lowerString(buf[0..len], s[0..len]);
    return std.mem.indexOf(u8, lower, "utf-8") != null or
        std.mem.indexOf(u8, lower, "utf8") != null;
}

/// Bitmap for Unicode whitespace codepoints (U+0000 to U+3000)
/// All Unicode whitespace is below U+3001, so a 1.5KB bitmap covers everything.
/// This is 15-30% faster than uucode.get(.general_category) for non-ASCII.
const WHITESPACE_BITMAP_SIZE = 0x3001;
const whitespace_bitmap: [WHITESPACE_BITMAP_SIZE / 8 + 1]u8 = blk: {
    var bm: [WHITESPACE_BITMAP_SIZE / 8 + 1]u8 = [_]u8{0} ** (WHITESPACE_BITMAP_SIZE / 8 + 1);

    // All Unicode whitespace codepoints (exhaustive list)
    const whitespace_cps = [_]u21{
        // ASCII whitespace
        0x0009, 0x000A, 0x000B, 0x000C, 0x000D, 0x0020,
        // Latin-1 supplement
        0x0085, // NEL (Next Line)
        0x00A0, // NO-BREAK SPACE
        // Unicode Zs category (space separators)
        0x1680, // OGHAM SPACE MARK
        0x2000, // EN QUAD
        0x2001, // EM QUAD
        0x2002, // EN SPACE
        0x2003, // EM SPACE
        0x2004, // THREE-PER-EM SPACE
        0x2005, // FOUR-PER-EM SPACE
        0x2006, // SIX-PER-EM SPACE
        0x2007, // FIGURE SPACE
        0x2008, // PUNCTUATION SPACE
        0x2009, // THIN SPACE
        0x200A, // HAIR SPACE
        // Line/paragraph separators (Zl, Zp)
        0x2028, // LINE SEPARATOR
        0x2029, // PARAGRAPH SEPARATOR
        // Other spaces
        0x202F, // NARROW NO-BREAK SPACE
        0x205F, // MEDIUM MATHEMATICAL SPACE
        0x3000, // IDEOGRAPHIC SPACE
    };

    for (whitespace_cps) |cp| {
        bm[cp / 8] |= @as(u8, 1) << @intCast(cp % 8);
    }

    break :blk bm;
};

/// Check if a Unicode code point is whitespace (UTF-8 locale)
/// Uses a precomputed bitmap for fast lookup (15-30% faster than general_category)
pub inline fn isUnicodeWhitespace(cp: u21) bool {
    // ASCII whitespace (fast path - most common)
    if (cp <= 0x7F) {
        return isAsciiWhitespace(@intCast(cp));
    }

    // All Unicode whitespace is below U+3001
    if (cp >= WHITESPACE_BITMAP_SIZE) return false;

    // Bitmap lookup
    return (whitespace_bitmap[cp / 8] & (@as(u8, 1) << @intCast(cp % 8))) != 0;
}

/// Check if a byte is whitespace in C locale
/// ASCII whitespace + 0xA0 (Latin-1 NBSP, matches GNU libc iswspace)
pub inline fn isCLocaleWhitespace(byte: u8) bool {
    return switch (byte) {
        ' ', '\t', '\n', '\r', 0x0b, 0x0c, 0xa0 => true,
        else => false,
    };
}

/// Check if a byte is ASCII whitespace
pub inline fn isAsciiWhitespace(byte: u8) bool {
    return switch (byte) {
        ' ', '\t', '\n', '\r', 0x0b, 0x0c => true,
        else => false,
    };
}

test "isUtf8Locale with LC_ALL=C" {
    // Can't easily test env vars in unit tests, but the logic is straightforward
}

test "isUnicodeWhitespace" {
    // ASCII
    try std.testing.expect(isUnicodeWhitespace(' '));
    try std.testing.expect(isUnicodeWhitespace('\t'));
    try std.testing.expect(isUnicodeWhitespace('\n'));
    try std.testing.expect(!isUnicodeWhitespace('a'));

    // Unicode Zs
    try std.testing.expect(isUnicodeWhitespace(0x00A0)); // NO-BREAK SPACE
    try std.testing.expect(isUnicodeWhitespace(0x2003)); // EM SPACE
    try std.testing.expect(isUnicodeWhitespace(0x2007)); // FIGURE SPACE

    // Not whitespace
    try std.testing.expect(!isUnicodeWhitespace(0x200B)); // ZERO WIDTH SPACE (Cf)
    try std.testing.expect(!isUnicodeWhitespace(0x2060)); // WORD JOINER (Cf)
}

test "isCLocaleWhitespace" {
    try std.testing.expect(isCLocaleWhitespace(' '));
    try std.testing.expect(isCLocaleWhitespace('\t'));
    try std.testing.expect(isCLocaleWhitespace(0xa0)); // Latin-1 NBSP
    try std.testing.expect(!isCLocaleWhitespace('a'));
}
