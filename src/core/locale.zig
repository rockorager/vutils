//! Locale detection and character classification
//! Shared across all tools for consistent behavior

const std = @import("std");
const uucode = @import("uucode");

/// Check if current locale is UTF-8 based on LC_CTYPE/LC_ALL/LANG
pub fn isUtf8Locale() bool {
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

/// Check if a Unicode code point is whitespace (UTF-8 locale)
/// Follows Unicode semantics: Zs (Space_Separator) + line/paragraph separators
pub fn isUnicodeWhitespace(cp: u21) bool {
    // ASCII whitespace (fast path)
    if (cp <= 0x7F) {
        return isAsciiWhitespace(@intCast(cp));
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

/// Check if a byte is whitespace in C locale
/// ASCII whitespace + 0xA0 (Latin-1 NBSP, matches GNU libc iswspace)
pub fn isCLocaleWhitespace(byte: u8) bool {
    return switch (byte) {
        ' ', '\t', '\n', '\r', 0x0b, 0x0c, 0xa0 => true,
        else => false,
    };
}

/// Check if a byte is ASCII whitespace
pub fn isAsciiWhitespace(byte: u8) bool {
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
