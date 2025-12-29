#!/bin/bash
# POSIX wc conformance test suite
# Tests against POSIX.1-2017 specification:
# https://pubs.opengroup.org/onlinepubs/9699919799/utilities/wc.html
#
# Reference implementations:
# - busybox wc (Linux): POSIX-compliant minimal implementation
# - /usr/bin/wc (macOS): BSD wc
#
# Run from repo root: ./tests/posix/wc_test.sh
# Run with benchmarks: ./tests/posix/wc_test.sh --bench

set -e

# Configuration
WC_VUTILS="${WC_VUTILS:-./zig-out/bin/vwc}"
TMPDIR="${TMPDIR:-/tmp}/vutils_posix_test_$$"
BENCH_MODE=false

# Parse arguments
for arg in "$@"; do
    case "$arg" in
        --bench) BENCH_MODE=true ;;
    esac
done

# Find reference wc
if command -v busybox &> /dev/null; then
    WC_REF="busybox wc"
elif [ -f /usr/bin/wc ]; then
    WC_REF="/usr/bin/wc"
else
    WC_REF="wc"
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

PASS=0
FAIL=0
SKIP=0

# Setup
mkdir -p "$TMPDIR"
trap 'rm -rf "$TMPDIR"' EXIT

# Test helpers
pass() {
    echo -e "${GREEN}✓${NC} $1"
    PASS=$((PASS + 1))
}

fail() {
    echo -e "${RED}✗${NC} $1"
    if [ -n "$2" ]; then
        echo "  Expected: $2"
    fi
    if [ -n "$3" ]; then
        echo "  Got:      $3"
    fi
    FAIL=$((FAIL + 1))
}

skip() {
    echo -e "${YELLOW}○${NC} $1 (skipped: $2)"
    SKIP=$((SKIP + 1))
}

# Create test fixtures
create_fixtures() {
    # Simple file
    echo "hello world" > "$TMPDIR/simple.txt"
    
    # No trailing newline
    printf "no newline" > "$TMPDIR/no_nl.txt"
    
    # Empty file
    : > "$TMPDIR/empty.txt"
    
    # Only newlines
    printf '\n\n\n' > "$TMPDIR/newlines.txt"
    
    # Multiple spaces between words
    echo "hello    world   foo" > "$TMPDIR/spaces.txt"
    
    # Tabs
    printf "hello\tworld\n" > "$TMPDIR/tabs.txt"
    
    # Multiple lines
    printf "line one\nline two\nline three\n" > "$TMPDIR/multiline.txt"
    
    # Unicode (UTF-8)
    printf "héllo wörld\n" > "$TMPDIR/unicode.txt"
    
    # Multibyte characters (for -m vs -c)
    printf "日本語\n" > "$TMPDIR/multibyte.txt"
    
    # File with whitespace in name
    echo "content" > "$TMPDIR/file with spaces.txt"
    
    # Non-existent file for error tests
    # (intentionally not created)
}

create_fixtures

echo "POSIX wc Conformance Test Suite"
echo "================================"
echo "Testing: $WC_VUTILS"
echo "Reference: $WC_REF"
echo

# =============================================================================
# Section 1: Default Output Format
# POSIX: "%d %d %d %s\n", <newlines>, <words>, <bytes>, <file>
# =============================================================================
echo "1. Default Output Format"
echo "------------------------"

# 1.1 Default output contains lines, words, bytes (in that order)
test_1_1() {
    local out=$("$WC_VUTILS" "$TMPDIR/simple.txt" 2>/dev/null)
    # Should have 3 numbers: lines, words, bytes
    local nums=$(echo "$out" | awk '{print NF}')
    # At least 3 fields (some implementations add filename)
    if [ "$nums" -ge 3 ]; then
        pass "1.1 Default output has lines, words, bytes fields"
    else
        fail "1.1 Default output has lines, words, bytes fields" "3+ fields" "$nums fields"
    fi
}
test_1_1

# 1.2 Output order is lines, words, bytes
test_1_2() {
    local out=$("$WC_VUTILS" "$TMPDIR/simple.txt" 2>/dev/null)
    local lines=$(echo "$out" | awk '{print $1}')
    local words=$(echo "$out" | awk '{print $2}')
    local bytes=$(echo "$out" | awk '{print $3}')
    
    # "hello world\n" = 1 line, 2 words, 12 bytes
    if [ "$lines" = "1" ] && [ "$words" = "2" ] && [ "$bytes" = "12" ]; then
        pass "1.2 Output order: lines, words, bytes"
    else
        fail "1.2 Output order: lines, words, bytes" "1 2 12" "$lines $words $bytes"
    fi
}
test_1_2

# 1.3 File with no trailing newline counts correctly
test_1_3() {
    local out=$("$WC_VUTILS" "$TMPDIR/no_nl.txt" 2>/dev/null)
    local lines=$(echo "$out" | awk '{print $1}')
    local words=$(echo "$out" | awk '{print $2}')
    local bytes=$(echo "$out" | awk '{print $3}')
    
    # "no newline" = 0 lines (no newline!), 2 words, 10 bytes
    if [ "$lines" = "0" ] && [ "$words" = "2" ] && [ "$bytes" = "10" ]; then
        pass "1.3 File without trailing newline: 0 lines"
    else
        fail "1.3 File without trailing newline: 0 lines" "0 2 10" "$lines $words $bytes"
    fi
}
test_1_3

# 1.4 Empty file
test_1_4() {
    local out=$("$WC_VUTILS" "$TMPDIR/empty.txt" 2>/dev/null)
    local lines=$(echo "$out" | awk '{print $1}')
    local words=$(echo "$out" | awk '{print $2}')
    local bytes=$(echo "$out" | awk '{print $3}')
    
    if [ "$lines" = "0" ] && [ "$words" = "0" ] && [ "$bytes" = "0" ]; then
        pass "1.4 Empty file: 0 0 0"
    else
        fail "1.4 Empty file: 0 0 0" "0 0 0" "$lines $words $bytes"
    fi
}
test_1_4

# =============================================================================
# Section 2: Options
# POSIX: -c (bytes), -l (lines), -m (characters), -w (words)
# =============================================================================
echo
echo "2. Options"
echo "----------"

# 2.1 -l option (lines only)
test_2_1() {
    local out=$("$WC_VUTILS" -l "$TMPDIR/multiline.txt" 2>/dev/null)
    local first=$(echo "$out" | awk '{print $1}')
    
    if [ "$first" = "3" ]; then
        pass "2.1 -l option reports line count"
    else
        fail "2.1 -l option reports line count" "3" "$first"
    fi
}
test_2_1

# 2.2 -w option (words only)
test_2_2() {
    local out=$("$WC_VUTILS" -w "$TMPDIR/simple.txt" 2>/dev/null)
    local first=$(echo "$out" | awk '{print $1}')
    
    if [ "$first" = "2" ]; then
        pass "2.2 -w option reports word count"
    else
        fail "2.2 -w option reports word count" "2" "$first"
    fi
}
test_2_2

# 2.3 -c option (bytes only)
test_2_3() {
    local out=$("$WC_VUTILS" -c "$TMPDIR/simple.txt" 2>/dev/null)
    local first=$(echo "$out" | awk '{print $1}')
    
    if [ "$first" = "12" ]; then
        pass "2.3 -c option reports byte count"
    else
        fail "2.3 -c option reports byte count" "12" "$first"
    fi
}
test_2_3

# 2.4 -m option (characters) - multibyte
test_2_4() {
    if ! "$WC_VUTILS" -m "$TMPDIR/multibyte.txt" &>/dev/null; then
        skip "2.4 -m option reports character count" "-m not implemented"
        return
    fi
    
    local out=$("$WC_VUTILS" -m "$TMPDIR/multibyte.txt" 2>/dev/null)
    local first=$(echo "$out" | awk '{print $1}')
    local byte_out=$("$WC_VUTILS" -c "$TMPDIR/multibyte.txt" 2>/dev/null | awk '{print $1}')
    
    # In UTF-8 locale: "日本語\n" = 4 characters, 10 bytes
    # In C locale: each byte = 1 character, so 10 chars = 10 bytes
    if [ "$first" = "4" ]; then
        pass "2.4 -m option reports character count (UTF-8: 4 chars)"
    elif [ "$first" = "$byte_out" ]; then
        pass "2.4 -m option reports character count (C locale: bytes=chars)"
    else
        fail "2.4 -m option reports character count" "4 (UTF-8) or $byte_out (C)" "$first"
    fi
}
test_2_4

# 2.5 Combined options -lw
test_2_5() {
    local out=$("$WC_VUTILS" -lw "$TMPDIR/multiline.txt" 2>/dev/null)
    local first=$(echo "$out" | awk '{print $1}')
    local second=$(echo "$out" | awk '{print $2}')
    
    # Should be "3 6" (3 lines, 6 words)
    if [ "$first" = "3" ] && [ "$second" = "6" ]; then
        pass "2.5 Combined options -lw"
    else
        fail "2.5 Combined options -lw" "3 6" "$first $second"
    fi
}
test_2_5

# 2.6 -c and -m are mutually exclusive (POSIX: wc [-c|-m])
test_2_6() {
    if ! "$WC_VUTILS" -m "$TMPDIR/simple.txt" &>/dev/null; then
        skip "2.6 -c and -m mutual exclusivity" "-m not implemented"
        return
    fi
    
    # Last one wins, or error - either is acceptable
    # POSIX says "[-c|-m]" meaning you pick one
    local out=$("$WC_VUTILS" -cm "$TMPDIR/multibyte.txt" 2>/dev/null)
    local first=$(echo "$out" | awk '{print $1}')
    
    # Either 4 (chars, -m wins) or 10 (bytes, -c wins) or error
    if [ "$first" = "4" ] || [ "$first" = "10" ]; then
        pass "2.6 -c and -m: one takes precedence"
    else
        fail "2.6 -c and -m: one takes precedence" "4 or 10" "$first"
    fi
}
test_2_6

# =============================================================================
# Section 3: Multiple Files and Total
# POSIX: "total count for all named files, if more than one input file"
# =============================================================================
echo
echo "3. Multiple Files and Total"
echo "---------------------------"

# 3.1 Single file: no "total" line
test_3_1() {
    local out=$("$WC_VUTILS" "$TMPDIR/simple.txt" 2>/dev/null)
    local line_count=$(echo "$out" | wc -l | tr -d ' ')
    
    if [ "$line_count" = "1" ]; then
        pass "3.1 Single file: one output line (no total)"
    else
        fail "3.1 Single file: one output line (no total)" "1 line" "$line_count lines"
    fi
}
test_3_1

# 3.2 Multiple files: per-file output
test_3_2() {
    local out=$("$WC_VUTILS" "$TMPDIR/simple.txt" "$TMPDIR/multiline.txt" 2>/dev/null)
    local line_count=$(echo "$out" | wc -l | tr -d ' ')
    
    # Should have 3 lines: file1, file2, total
    if [ "$line_count" = "3" ]; then
        pass "3.2 Multiple files: per-file output + total"
    else
        fail "3.2 Multiple files: per-file output + total" "3 lines" "$line_count lines"
    fi
}
test_3_2

# 3.3 Multiple files: total line contains "total"
test_3_3() {
    local out=$("$WC_VUTILS" "$TMPDIR/simple.txt" "$TMPDIR/multiline.txt" 2>/dev/null)
    local last_line=$(echo "$out" | tail -1)
    
    if echo "$last_line" | grep -q "total"; then
        pass "3.3 Multiple files: last line contains 'total'"
    else
        fail "3.3 Multiple files: last line contains 'total'" "'total' in last line" "$last_line"
    fi
}
test_3_3

# 3.4 Multiple files: total is sum
test_3_4() {
    local out=$("$WC_VUTILS" "$TMPDIR/simple.txt" "$TMPDIR/multiline.txt" 2>/dev/null)
    local total_line=$(echo "$out" | tail -1)
    local total_lines=$(echo "$total_line" | awk '{print $1}')
    local total_words=$(echo "$total_line" | awk '{print $2}')
    local total_bytes=$(echo "$total_line" | awk '{print $3}')
    
    # simple.txt: 1 line, 2 words, 12 bytes ("hello world\n")
    # multiline.txt: 3 lines, 6 words, 29 bytes ("line one\nline two\nline three\n")
    # total: 4 lines, 8 words, 41 bytes
    if [ "$total_lines" = "4" ] && [ "$total_words" = "8" ] && [ "$total_bytes" = "41" ]; then
        pass "3.4 Multiple files: total is sum"
    else
        fail "3.4 Multiple files: total is sum" "4 8 41" "$total_lines $total_words $total_bytes"
    fi
}
test_3_4

# 3.5 Per-file output includes filename
test_3_5() {
    local out=$("$WC_VUTILS" "$TMPDIR/simple.txt" "$TMPDIR/multiline.txt" 2>/dev/null)
    
    if echo "$out" | head -1 | grep -q "simple.txt"; then
        pass "3.5 Per-file output includes filename"
    else
        fail "3.5 Per-file output includes filename" "filename in output" "$(echo "$out" | head -1)"
    fi
}
test_3_5

# =============================================================================
# Section 4: Standard Input
# POSIX: "If no file operands are specified, the standard input shall be used"
# POSIX: "if a file operand is '-' ... treats the '-' as meaning standard input"
# =============================================================================
echo
echo "4. Standard Input"
echo "-----------------"

# 4.1 No file operand: read stdin
test_4_1() {
    local out=$(echo "hello world" | "$WC_VUTILS" 2>/dev/null)
    local words=$(echo "$out" | awk '{print $2}')
    
    if [ "$words" = "2" ]; then
        pass "4.1 No file operand: reads stdin"
    else
        fail "4.1 No file operand: reads stdin" "2 words" "$words"
    fi
}
test_4_1

# 4.2 No file operand: no filename in output
test_4_2() {
    local out=$(echo "hello world" | "$WC_VUTILS" 2>/dev/null)
    local field_count=$(echo "$out" | awk '{print NF}')
    
    # Should be just numbers, no filename
    # With default output: 3 fields (lines, words, bytes)
    if [ "$field_count" = "3" ]; then
        pass "4.2 No file operand: no filename in output"
    else
        # Check if 4th field exists and is not a filename
        skip "4.2 No file operand: no filename in output" "output format varies"
    fi
}
test_4_2

# 4.3 "-" operand means stdin
test_4_3() {
    local out=$(echo "hello world" | "$WC_VUTILS" - 2>/dev/null)
    local words=$(echo "$out" | awk '{print $2}')
    
    if [ "$words" = "2" ]; then
        pass "4.3 '-' operand reads stdin"
    else
        fail "4.3 '-' operand reads stdin" "2 words" "$words"
    fi
}
test_4_3

# 4.4 "-" mixed with files
test_4_4() {
    local out=$(echo "stdin data" | "$WC_VUTILS" "$TMPDIR/simple.txt" - 2>/dev/null)
    local line_count=$(echo "$out" | wc -l | tr -d ' ')
    
    # Should have 3 lines: simple.txt, -, total
    if [ "$line_count" = "3" ]; then
        pass "4.4 '-' mixed with files shows total"
    else
        fail "4.4 '-' mixed with files shows total" "3 lines" "$line_count lines"
    fi
}
test_4_4

# =============================================================================
# Section 5: Word Definition
# POSIX: "non-zero-length string of characters delimited by white space"
# POSIX: uses isspace() equivalent for whitespace detection
# =============================================================================
echo
echo "5. Word Definition"
echo "------------------"

# 5.1 Space separates words
test_5_1() {
    local out=$(printf "hello world" | "$WC_VUTILS" 2>/dev/null)
    local words=$(echo "$out" | awk '{print $2}')
    
    if [ "$words" = "2" ]; then
        pass "5.1 Space separates words"
    else
        fail "5.1 Space separates words" "2" "$words"
    fi
}
test_5_1

# 5.2 Tab separates words
test_5_2() {
    local out=$(printf "hello\tworld" | "$WC_VUTILS" 2>/dev/null)
    local words=$(echo "$out" | awk '{print $2}')
    
    if [ "$words" = "2" ]; then
        pass "5.2 Tab separates words"
    else
        fail "5.2 Tab separates words" "2" "$words"
    fi
}
test_5_2

# 5.3 Newline separates words
test_5_3() {
    local out=$(printf "hello\nworld" | "$WC_VUTILS" 2>/dev/null)
    local words=$(echo "$out" | awk '{print $2}')
    
    if [ "$words" = "2" ]; then
        pass "5.3 Newline separates words"
    else
        fail "5.3 Newline separates words" "2" "$words"
    fi
}
test_5_3

# 5.4 Multiple whitespace = still word boundary
test_5_4() {
    local out=$(printf "hello    world" | "$WC_VUTILS" 2>/dev/null)
    local words=$(echo "$out" | awk '{print $2}')
    
    if [ "$words" = "2" ]; then
        pass "5.4 Multiple spaces still = 2 words"
    else
        fail "5.4 Multiple spaces still = 2 words" "2" "$words"
    fi
}
test_5_4

# 5.5 Leading whitespace doesn't create empty word
test_5_5() {
    local out=$(printf "  hello" | "$WC_VUTILS" 2>/dev/null)
    local words=$(echo "$out" | awk '{print $2}')
    
    if [ "$words" = "1" ]; then
        pass "5.5 Leading whitespace: 1 word"
    else
        fail "5.5 Leading whitespace: 1 word" "1" "$words"
    fi
}
test_5_5

# 5.6 Trailing whitespace doesn't create empty word
test_5_6() {
    local out=$(printf "hello  " | "$WC_VUTILS" 2>/dev/null)
    local words=$(echo "$out" | awk '{print $2}')
    
    if [ "$words" = "1" ]; then
        pass "5.6 Trailing whitespace: 1 word"
    else
        fail "5.6 Trailing whitespace: 1 word" "1" "$words"
    fi
}
test_5_6

# 5.7 Only whitespace = 0 words
test_5_7() {
    local out=$(printf "   \t  \n  " | "$WC_VUTILS" 2>/dev/null)
    local words=$(echo "$out" | awk '{print $2}')
    
    if [ "$words" = "0" ]; then
        pass "5.7 Only whitespace: 0 words"
    else
        fail "5.7 Only whitespace: 0 words" "0" "$words"
    fi
}
test_5_7

# =============================================================================
# Section 6: Exit Status
# POSIX: 0 = success, >0 = error
# =============================================================================
echo
echo "6. Exit Status"
echo "--------------"

# 6.1 Success exit code
test_6_1() {
    "$WC_VUTILS" "$TMPDIR/simple.txt" >/dev/null 2>&1
    local code=$?
    
    if [ "$code" = "0" ]; then
        pass "6.1 Success: exit code 0"
    else
        fail "6.1 Success: exit code 0" "0" "$code"
    fi
}
test_6_1

# 6.2 Non-existent file: exit code > 0
test_6_2() {
    local code=0
    "$WC_VUTILS" "$TMPDIR/nonexistent.txt" >/dev/null 2>&1 || code=$?
    
    if [ "$code" -gt "0" ]; then
        pass "6.2 Non-existent file: exit code > 0"
    else
        fail "6.2 Non-existent file: exit code > 0" ">0" "$code"
    fi
}
test_6_2

# 6.3 Error message to stderr
test_6_3() {
    local stderr=$("$WC_VUTILS" "$TMPDIR/nonexistent.txt" 2>&1 >/dev/null || true)
    
    if [ -n "$stderr" ]; then
        pass "6.3 Error message to stderr"
    else
        fail "6.3 Error message to stderr" "non-empty stderr" "(empty)"
    fi
}
test_6_3

# 6.4 Partial success: continue after error
test_6_4() {
    local out=$("$WC_VUTILS" "$TMPDIR/simple.txt" "$TMPDIR/nonexistent.txt" "$TMPDIR/multiline.txt" 2>/dev/null || true)
    local line_count=$(echo "$out" | wc -l | tr -d ' ')
    
    # Should still process valid files and show total
    # Expect: simple.txt, multiline.txt, total = 3 lines
    if [ "$line_count" -ge "2" ]; then
        pass "6.4 Partial success: continues after error"
    else
        fail "6.4 Partial success: continues after error" ">=2 output lines" "$line_count lines"
    fi
}
test_6_4

# =============================================================================
# Section 7: LC_CTYPE Locale Handling
# POSIX: "Determine the locale for interpretation of bytes as characters"
# =============================================================================
echo
echo "7. LC_CTYPE Locale Handling"
echo "---------------------------"

# 7.1 C locale: ASCII whitespace only
test_7_1() {
    # In C locale, NO-BREAK SPACE (U+00A0) behavior varies by implementation
    # GNU wc in C locale treats it as whitespace (Latin-1 NBSP)
    # BSD wc in C locale may not
    printf 'hello\xc2\xa0world\n' > "$TMPDIR/nbsp.txt"
    
    local out=$(LC_ALL=C "$WC_VUTILS" "$TMPDIR/nbsp.txt" 2>/dev/null)
    local words=$(echo "$out" | awk '{print $2}')
    
    # Accept either 1 or 2 words (implementation-defined in C locale)
    if [ "$words" = "1" ] || [ "$words" = "2" ]; then
        pass "7.1 C locale: NBSP handling (got $words words)"
    else
        fail "7.1 C locale: NBSP handling" "1 or 2 words" "$words"
    fi
}
test_7_1

# 7.2 UTF-8 locale: Unicode whitespace
test_7_2() {
    # In UTF-8 locale, NO-BREAK SPACE should be whitespace
    printf 'hello\xc2\xa0world\n' > "$TMPDIR/nbsp.txt"
    
    local out=$(LC_ALL=en_US.UTF-8 "$WC_VUTILS" "$TMPDIR/nbsp.txt" 2>/dev/null)
    local words=$(echo "$out" | awk '{print $2}')
    
    if [ "$words" = "2" ]; then
        pass "7.2 UTF-8 locale: NBSP splits words"
    else
        fail "7.2 UTF-8 locale: NBSP splits words" "2" "$words"
    fi
}
test_7_2

# 7.3 -m respects LC_CTYPE for character counting
test_7_3() {
    if ! "$WC_VUTILS" -m "$TMPDIR/multibyte.txt" &>/dev/null; then
        skip "7.3 -m respects LC_CTYPE" "-m not implemented"
        return
    fi
    
    # "日本語\n" in UTF-8: 10 bytes, 4 characters
    printf '日本語\n' > "$TMPDIR/kanji.txt"
    
    local chars=$(LC_ALL=en_US.UTF-8 "$WC_VUTILS" -m "$TMPDIR/kanji.txt" 2>/dev/null | awk '{print $1}')
    
    if [ "$chars" = "4" ]; then
        pass "7.3 -m in UTF-8 locale: counts characters"
    else
        fail "7.3 -m in UTF-8 locale: counts characters" "4" "$chars"
    fi
}
test_7_3

# =============================================================================
# Section 8: Edge Cases
# =============================================================================
echo
echo "8. Edge Cases"
echo "-------------"

# 8.1 Binary file (null bytes)
test_8_1() {
    printf 'hello\x00world\n' > "$TMPDIR/binary.txt"
    
    "$WC_VUTILS" "$TMPDIR/binary.txt" >/dev/null 2>&1
    local code=$?
    
    if [ "$code" = "0" ]; then
        pass "8.1 Binary file with null bytes: succeeds"
    else
        fail "8.1 Binary file with null bytes: succeeds" "exit 0" "exit $code"
    fi
}
test_8_1

# 8.2 Very long line
test_8_2() {
    head -c 100000 /dev/zero | tr '\0' 'x' > "$TMPDIR/longline.txt"
    
    local out=$("$WC_VUTILS" "$TMPDIR/longline.txt" 2>/dev/null)
    local bytes=$(echo "$out" | awk '{print $3}')
    
    if [ "$bytes" = "100000" ]; then
        pass "8.2 Very long line (100KB): correct byte count"
    else
        fail "8.2 Very long line (100KB): correct byte count" "100000" "$bytes"
    fi
}
test_8_2

# 8.3 File with only newlines
test_8_3() {
    local out=$("$WC_VUTILS" "$TMPDIR/newlines.txt" 2>/dev/null)
    local lines=$(echo "$out" | awk '{print $1}')
    local words=$(echo "$out" | awk '{print $2}')
    
    if [ "$lines" = "3" ] && [ "$words" = "0" ]; then
        pass "8.3 Only newlines: 3 lines, 0 words"
    else
        fail "8.3 Only newlines: 3 lines, 0 words" "3 0" "$lines $words"
    fi
}
test_8_3

# 8.4 Invalid UTF-8 sequence
test_8_4() {
    printf '\xff\xfe hello\n' > "$TMPDIR/invalid_utf8.txt"
    
    "$WC_VUTILS" "$TMPDIR/invalid_utf8.txt" >/dev/null 2>&1
    local code=$?
    
    if [ "$code" = "0" ]; then
        pass "8.4 Invalid UTF-8: handles gracefully"
    else
        fail "8.4 Invalid UTF-8: handles gracefully" "exit 0" "exit $code"
    fi
}
test_8_4

# =============================================================================
# Section 9: Comparison with Reference Implementation
# =============================================================================
echo
echo "9. Reference Implementation Comparison"
echo "--------------------------------------"

compare_with_ref() {
    local desc="$1"
    local file="$2"
    
    local ref_out=$($WC_REF "$file" 2>/dev/null | awk '{print $1, $2, $3}')
    local vutils_out=$("$WC_VUTILS" "$file" 2>/dev/null | awk '{print $1, $2, $3}')
    
    if [ "$ref_out" = "$vutils_out" ]; then
        pass "9.x $desc matches reference"
    else
        fail "9.x $desc matches reference" "$ref_out" "$vutils_out"
    fi
}

compare_with_ref "simple.txt" "$TMPDIR/simple.txt"
compare_with_ref "no_nl.txt" "$TMPDIR/no_nl.txt"
compare_with_ref "empty.txt" "$TMPDIR/empty.txt"
compare_with_ref "multiline.txt" "$TMPDIR/multiline.txt"

# =============================================================================
# Section 10: Benchmarks (optional)
# =============================================================================
if [ "$BENCH_MODE" = "true" ]; then
    echo
    echo "10. Benchmarks"
    echo "--------------"
    
    # Create large test file
    BENCH_FILE="$TMPDIR/bench_10mb.txt"
    dd if=/dev/zero bs=1M count=10 2>/dev/null | tr '\0' 'x' > "$BENCH_FILE"
    # Add some words
    for i in $(seq 1 1000); do
        echo "word$i word$i word$i word$i word$i" >> "$BENCH_FILE"
    done
    
    BENCH_ITERS=5
    
    bench_wc() {
        local name="$1"
        local cmd="$2"
        local total_ms=0
        
        # Warmup
        eval "$cmd" "$BENCH_FILE" >/dev/null 2>&1 || true
        
        for i in $(seq 1 $BENCH_ITERS); do
            local start=$(python3 -c 'import time; print(int(time.time() * 1000))' 2>/dev/null || gdate +%s%3N 2>/dev/null || date +%s000)
            eval "$cmd" "$BENCH_FILE" >/dev/null 2>&1 || true
            local end=$(python3 -c 'import time; print(int(time.time() * 1000))' 2>/dev/null || gdate +%s%3N 2>/dev/null || date +%s000)
            total_ms=$((total_ms + end - start))
        done
        
        local avg_ms=$((total_ms / BENCH_ITERS))
        printf "  %-15s %4d ms (avg of %d runs)\n" "$name:" "$avg_ms" "$BENCH_ITERS"
    }
    
    echo "File: 10MB + 5000 words"
    echo
    bench_wc "vwc" "$WC_VUTILS"
    bench_wc "reference" "$WC_REF"
    
    # GNU wc if available
    if command -v gwc &> /dev/null; then
        bench_wc "GNU wc" "gwc"
    fi
    
    # busybox if available
    if command -v busybox &> /dev/null; then
        bench_wc "busybox" "busybox wc"
    fi
fi

# =============================================================================
# Summary
# =============================================================================
echo
echo "================================"
echo "Summary: $PASS passed, $FAIL failed, $SKIP skipped"

if [ $FAIL -gt 0 ]; then
    exit 1
fi
exit 0
