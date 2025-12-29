#!/bin/bash
# POSIX echo conformance test suite
# Tests against POSIX.1-2017 specification:
# https://pubs.opengroup.org/onlinepubs/9699919799/utilities/echo.html
#
# Key POSIX requirements:
# - Writes arguments separated by single spaces, followed by newline
# - No arguments: only newline is written
# - "--" shall be recognized as a string operand (NOT option terminator)
# - Implementations shall not support any options (but XSI defines -n behavior)
# - If first operand is -n or any operand contains backslash: implementation-defined
# - XSI systems: escape sequences recognized, -n treated as string
#
# Run from repo root: ./tests/posix/echo_test.sh

set -e

# Configuration
ECHO_VUTILS="${ECHO_VUTILS:-./zig-out/bin/vecho}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

PASS=0
FAIL=0
SKIP=0

pass() {
    echo -e "${GREEN}✓${NC} $1"
    PASS=$((PASS + 1))
}

fail() {
    echo -e "${RED}✗${NC} $1"
    if [ -n "$2" ]; then
        echo "  Expected: '$2'"
    fi
    if [ -n "$3" ]; then
        echo "  Got:      '$3'"
    fi
    FAIL=$((FAIL + 1))
}

skip() {
    echo -e "${YELLOW}○${NC} $1 (skipped: $2)"
    SKIP=$((SKIP + 1))
}

echo "POSIX echo Conformance Test Suite"
echo "=================================="
echo "Testing: $ECHO_VUTILS"
echo

# =============================================================================
# Section 1: Basic Output
# POSIX: "writes its arguments to standard output, followed by a <newline>"
# =============================================================================
echo "1. Basic Output"
echo "---------------"

# 1.1 Simple text output
test_1_1() {
    local out=$("$ECHO_VUTILS" "hello world")
    if [ "$out" = "hello world" ]; then
        pass "1.1 Simple text output"
    else
        fail "1.1 Simple text output" "hello world" "$out"
    fi
}
test_1_1

# 1.2 No arguments: only newline
test_1_2() {
    local out=$("$ECHO_VUTILS")
    if [ "$out" = "" ]; then
        pass "1.2 No arguments produces empty line"
    else
        fail "1.2 No arguments produces empty line" "(empty)" "$out"
    fi
}
test_1_2

# 1.3 Multiple arguments separated by single spaces
test_1_3() {
    local out=$("$ECHO_VUTILS" "hello" "world" "foo")
    if [ "$out" = "hello world foo" ]; then
        pass "1.3 Multiple arguments separated by spaces"
    else
        fail "1.3 Multiple arguments separated by spaces" "hello world foo" "$out"
    fi
}
test_1_3

# 1.4 Output followed by newline (verified by line count)
test_1_4() {
    local lines=$("$ECHO_VUTILS" "test" | wc -l | tr -d ' ')
    if [ "$lines" = "1" ]; then
        pass "1.4 Output followed by newline"
    else
        fail "1.4 Output followed by newline" "1 line" "$lines lines"
    fi
}
test_1_4

# =============================================================================
# Section 2: POSIX Special Cases
# =============================================================================
echo
echo "2. POSIX Special Cases"
echo "----------------------"

# 2.1 "--" treated as string operand (NOT option terminator)
test_2_1() {
    local out=$("$ECHO_VUTILS" "--")
    if [ "$out" = "--" ]; then
        pass "2.1 '--' treated as string operand"
    else
        fail "2.1 '--' treated as string operand" "--" "$out"
    fi
}
test_2_1

# 2.2 "--" followed by other args
test_2_2() {
    local out=$("$ECHO_VUTILS" "--" "hello")
    if [ "$out" = "-- hello" ]; then
        pass "2.2 '--' followed by args"
    else
        fail "2.2 '--' followed by args" "-- hello" "$out"
    fi
}
test_2_2

# 2.3 Single dash
test_2_3() {
    local out=$("$ECHO_VUTILS" "-")
    if [ "$out" = "-" ]; then
        pass "2.3 Single dash"
    else
        fail "2.3 Single dash" "-" "$out"
    fi
}
test_2_3

# 2.4 Exit status 0 on success
test_2_4() {
    "$ECHO_VUTILS" "test" >/dev/null 2>&1
    local code=$?
    if [ "$code" = "0" ]; then
        pass "2.4 Exit status 0 on success"
    else
        fail "2.4 Exit status 0 on success" "0" "$code"
    fi
}
test_2_4

# =============================================================================
# Section 3: XSI Extension: -n flag
# XSI: "if the first operand is -n, it shall be treated as a string"
# Note: GNU echo treats -n as "no newline" - we follow GNU behavior
# =============================================================================
echo
echo "3. -n Flag (GNU Behavior)"
echo "-------------------------"

# 3.1 -n suppresses trailing newline
test_3_1() {
    local out=$("$ECHO_VUTILS" -n "hello" | wc -c | tr -d ' ')
    if [ "$out" = "5" ]; then
        pass "3.1 -n suppresses trailing newline (5 bytes, not 6)"
    else
        fail "3.1 -n suppresses trailing newline" "5" "$out"
    fi
}
test_3_1

# 3.2 -n with multiple args
test_3_2() {
    local out=$("$ECHO_VUTILS" -n "hello" "world")
    if [ "$out" = "hello world" ]; then
        pass "3.2 -n with multiple arguments"
    else
        fail "3.2 -n with multiple arguments" "hello world" "$out"
    fi
}
test_3_2

# =============================================================================
# Section 4: XSI Extension: Escape Sequences (via -e)
# XSI defines: \a \b \c \f \n \r \t \v \\ \0num
# =============================================================================
echo
echo "4. Escape Sequences (via -e)"
echo "----------------------------"

# 4.1 \n - newline
test_4_1() {
    local lines=$("$ECHO_VUTILS" -e "hello\nworld" | wc -l | tr -d ' ')
    if [ "$lines" = "2" ]; then
        pass "4.1 \\n produces newline"
    else
        fail "4.1 \\n produces newline" "2 lines" "$lines lines"
    fi
}
test_4_1

# 4.2 \t - tab
test_4_2() {
    local out=$("$ECHO_VUTILS" -e "hello\tworld")
    local expected=$(printf "hello\tworld")
    if [ "$out" = "$expected" ]; then
        pass "4.2 \\t produces tab"
    else
        fail "4.2 \\t produces tab" "$expected" "$out"
    fi
}
test_4_2

# 4.3 \\ - backslash
test_4_3() {
    local out=$("$ECHO_VUTILS" -e "hello\\\\world")
    if [ "$out" = 'hello\world' ]; then
        pass "4.3 \\\\ produces backslash"
    else
        fail "4.3 \\\\ produces backslash" 'hello\world' "$out"
    fi
}
test_4_3

# 4.4 \r - carriage return
test_4_4() {
    local out=$("$ECHO_VUTILS" -e "hello\rworld" | cat -v)
    if [ "$out" = "hello^Mworld" ]; then
        pass "4.4 \\r produces carriage return"
    else
        fail "4.4 \\r produces carriage return" "hello^Mworld" "$out"
    fi
}
test_4_4

# 4.5 \a - alert (bell)
test_4_5() {
    local out=$("$ECHO_VUTILS" -e "hello\aworld" | cat -v)
    if [ "$out" = "hello^Gworld" ]; then
        pass "4.5 \\a produces alert (bell)"
    else
        fail "4.5 \\a produces alert (bell)" "hello^Gworld" "$out"
    fi
}
test_4_5

# 4.6 \b - backspace
test_4_6() {
    local out=$("$ECHO_VUTILS" -e "hello\bworld" | cat -v)
    if [ "$out" = "hello^Hworld" ]; then
        pass "4.6 \\b produces backspace"
    else
        fail "4.6 \\b produces backspace" "hello^Hworld" "$out"
    fi
}
test_4_6

# 4.7 \f - form feed
test_4_7() {
    local out=$("$ECHO_VUTILS" -e "hello\fworld" | cat -v)
    if [ "$out" = "hello^Lworld" ]; then
        pass "4.7 \\f produces form feed"
    else
        fail "4.7 \\f produces form feed" "hello^Lworld" "$out"
    fi
}
test_4_7

# 4.8 \v - vertical tab
test_4_8() {
    local out=$("$ECHO_VUTILS" -e "hello\vworld" | cat -v)
    if [ "$out" = "hello^Kworld" ]; then
        pass "4.8 \\v produces vertical tab"
    else
        fail "4.8 \\v produces vertical tab" "hello^Kworld" "$out"
    fi
}
test_4_8

# 4.9 \c - suppress output (POSIX XSI: all characters following \c are ignored)
test_4_9() {
    local out=$("$ECHO_VUTILS" -e "hello\cworld")
    if [ "$out" = "hello" ]; then
        pass "4.9 \\c suppresses remaining output"
    else
        fail "4.9 \\c suppresses remaining output" "hello" "$out"
    fi
}
test_4_9

# 4.10 \0num - octal
test_4_10() {
    local out=$("$ECHO_VUTILS" -e "hello\0101world")
    if [ "$out" = "helloAworld" ]; then
        pass "4.10 \\0num produces octal value (A=0101)"
    else
        fail "4.10 \\0num produces octal value" "helloAworld" "$out"
    fi
}
test_4_10

# =============================================================================
# Section 5: -E flag (disable escapes)
# =============================================================================
echo
echo "5. -E Flag (Disable Escapes)"
echo "----------------------------"

# 5.1 -E prevents escape interpretation
test_5_1() {
    local out=$("$ECHO_VUTILS" -E 'hello\nworld')
    if [ "$out" = 'hello\nworld' ]; then
        pass "5.1 -E prevents escape interpretation"
    else
        fail "5.1 -E prevents escape interpretation" 'hello\nworld' "$out"
    fi
}
test_5_1

# 5.2 Default behavior (no -e) does not interpret escapes
test_5_2() {
    local out=$("$ECHO_VUTILS" 'hello\nworld')
    if [ "$out" = 'hello\nworld' ]; then
        pass "5.2 Default: no escape interpretation"
    else
        fail "5.2 Default: no escape interpretation" 'hello\nworld' "$out"
    fi
}
test_5_2

# =============================================================================
# Section 6: Combined Flags
# =============================================================================
echo
echo "6. Combined Flags"
echo "-----------------"

# 6.1 -ne (no newline + escapes)
test_6_1() {
    local bytes=$("$ECHO_VUTILS" -ne "hello\nworld" | wc -c | tr -d ' ')
    # "hello" + newline + "world" = 5 + 1 + 5 = 11 bytes (no trailing newline)
    if [ "$bytes" = "11" ]; then
        pass "6.1 -ne combines both flags"
    else
        fail "6.1 -ne combines both flags" "11 bytes" "$bytes bytes"
    fi
}
test_6_1

# 6.2 -en (same as -ne)
test_6_2() {
    local bytes=$("$ECHO_VUTILS" -en "hello\nworld" | wc -c | tr -d ' ')
    if [ "$bytes" = "11" ]; then
        pass "6.2 -en same as -ne"
    else
        fail "6.2 -en same as -ne" "11 bytes" "$bytes bytes"
    fi
}
test_6_2

# 6.3 -eE (last wins: escapes disabled)
test_6_3() {
    local out=$("$ECHO_VUTILS" -eE 'hello\nworld')
    if [ "$out" = 'hello\nworld' ]; then
        pass "6.3 -eE: last flag wins (escapes disabled)"
    else
        fail "6.3 -eE: last flag wins" 'hello\nworld' "$out"
    fi
}
test_6_3

# 6.4 -Ee (last wins: escapes enabled)
test_6_4() {
    local lines=$("$ECHO_VUTILS" -Ee "hello\nworld" | wc -l | tr -d ' ')
    if [ "$lines" = "2" ]; then
        pass "6.4 -Ee: last flag wins (escapes enabled)"
    else
        fail "6.4 -Ee: last flag wins" "2 lines" "$lines lines"
    fi
}
test_6_4

# =============================================================================
# Section 7: Edge Cases
# =============================================================================
echo
echo "7. Edge Cases"
echo "-------------"

# 7.1 Invalid option character stops option parsing
test_7_1() {
    local out=$("$ECHO_VUTILS" "-abc")
    if [ "$out" = "-abc" ]; then
        pass "7.1 Invalid option char: treat as string"
    else
        fail "7.1 Invalid option char: treat as string" "-abc" "$out"
    fi
}
test_7_1

# 7.2 Empty string argument
test_7_2() {
    local out=$("$ECHO_VUTILS" "" "hello")
    if [ "$out" = " hello" ]; then
        pass "7.2 Empty string argument preserved"
    else
        fail "7.2 Empty string argument preserved" " hello" "$out"
    fi
}
test_7_2

# 7.3 Hex escape sequence
test_7_3() {
    local out=$("$ECHO_VUTILS" -e "hello\x41world")
    if [ "$out" = "helloAworld" ]; then
        pass "7.3 \\xHH hex escape"
    else
        fail "7.3 \\xHH hex escape" "helloAworld" "$out"
    fi
}
test_7_3

# 7.4 Escape at end of string
test_7_4() {
    local out=$("$ECHO_VUTILS" -e 'hello\')
    if [ "$out" = 'hello\' ]; then
        pass "7.4 Trailing backslash preserved"
    else
        fail "7.4 Trailing backslash preserved" 'hello\' "$out"
    fi
}
test_7_4

# 7.5 Unknown escape sequence
test_7_5() {
    local out=$("$ECHO_VUTILS" -e 'hello\zworld')
    if [ "$out" = 'hello\zworld' ]; then
        pass "7.5 Unknown escape preserved"
    else
        fail "7.5 Unknown escape preserved" 'hello\zworld' "$out"
    fi
}
test_7_5

# 7.6 \c suppresses newline too
test_7_6() {
    local bytes=$("$ECHO_VUTILS" -e "hello\c" | wc -c | tr -d ' ')
    if [ "$bytes" = "5" ]; then
        pass "7.6 \\c suppresses newline (5 bytes, not 6)"
    else
        fail "7.6 \\c suppresses newline" "5 bytes" "$bytes bytes"
    fi
}
test_7_6

# 7.7 Multiple \c has same effect
test_7_7() {
    local out=$("$ECHO_VUTILS" -e "abc\c" "def\c" "ghi")
    if [ "$out" = "abc" ]; then
        pass "7.7 \\c in first arg stops all output"
    else
        fail "7.7 \\c in first arg stops all output" "abc" "$out"
    fi
}
test_7_7

# =============================================================================
# Summary
# =============================================================================
echo
echo "=================================="
echo "Summary: $PASS passed, $FAIL failed, $SKIP skipped"

if [ $FAIL -gt 0 ]; then
    exit 1
fi
exit 0
