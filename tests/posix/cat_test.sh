#!/bin/bash
# POSIX cat conformance test suite
# Tests against POSIX.1-2017 specification:
# https://pubs.opengroup.org/onlinepubs/9699919799/utilities/cat.html
#
# Run from repo root: ./tests/posix/cat_test.sh

set -e

# Configuration
CAT_VUTILS="${CAT_VUTILS:-./zig-out/bin/vcat}"
TMPDIR="${TMPDIR:-/tmp}/vutils_cat_test_$$"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

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
    echo "hello world" > "$TMPDIR/simple.txt"
    printf "no newline" > "$TMPDIR/no_nl.txt"
    : > "$TMPDIR/empty.txt"
    printf "line1\nline2\nline3\n" > "$TMPDIR/multiline.txt"
    printf "日本語\n" > "$TMPDIR/unicode.txt"
    echo "file1 content" > "$TMPDIR/file1.txt"
    echo "file2 content" > "$TMPDIR/file2.txt"
    echo "file3 content" > "$TMPDIR/file3.txt"
    # Binary-ish content
    printf '\x00\x01\x02\x03' > "$TMPDIR/binary.bin"
}

create_fixtures

echo "POSIX cat Conformance Test Suite"
echo "================================="
echo "Testing: $CAT_VUTILS"
echo

# =============================================================================
# Section 1: Basic File Reading
# POSIX: "read files in sequence and write their contents to standard output"
# =============================================================================
echo "1. Basic File Reading"
echo "---------------------"

# Test: Single file
result=$("$CAT_VUTILS" "$TMPDIR/simple.txt")
expected="hello world"
if [ "$result" = "$expected" ]; then
    pass "single file"
else
    fail "single file" "$expected" "$result"
fi

# Test: Empty file
result=$("$CAT_VUTILS" "$TMPDIR/empty.txt")
if [ -z "$result" ]; then
    pass "empty file"
else
    fail "empty file" "(empty)" "$result"
fi

# Test: File without trailing newline
result=$("$CAT_VUTILS" "$TMPDIR/no_nl.txt")
expected="no newline"
if [ "$result" = "$expected" ]; then
    pass "file without trailing newline"
else
    fail "file without trailing newline" "$expected" "$result"
fi

# Test: Multiline file
result=$("$CAT_VUTILS" "$TMPDIR/multiline.txt")
expected=$'line1\nline2\nline3'
if [ "$result" = "$expected" ]; then
    pass "multiline file"
else
    fail "multiline file" "$expected" "$result"
fi

# Test: Unicode content preserved
result=$("$CAT_VUTILS" "$TMPDIR/unicode.txt")
expected="日本語"
if [ "$result" = "$expected" ]; then
    pass "unicode content preserved"
else
    fail "unicode content preserved" "$expected" "$result"
fi

# Test: Binary content preserved
result=$("$CAT_VUTILS" "$TMPDIR/binary.bin" | xxd -p)
expected="00010203"
if [ "$result" = "$expected" ]; then
    pass "binary content preserved"
else
    fail "binary content preserved" "$expected" "$result"
fi

echo

# =============================================================================
# Section 2: Multiple Files
# POSIX: "read files in sequence... in the same sequence"
# =============================================================================
echo "2. Multiple Files (Concatenation)"
echo "----------------------------------"

# Test: Two files concatenated
result=$("$CAT_VUTILS" "$TMPDIR/file1.txt" "$TMPDIR/file2.txt")
expected=$'file1 content\nfile2 content'
if [ "$result" = "$expected" ]; then
    pass "two files concatenated"
else
    fail "two files concatenated" "$expected" "$result"
fi

# Test: Three files concatenated
result=$("$CAT_VUTILS" "$TMPDIR/file1.txt" "$TMPDIR/file2.txt" "$TMPDIR/file3.txt")
expected=$'file1 content\nfile2 content\nfile3 content'
if [ "$result" = "$expected" ]; then
    pass "three files concatenated"
else
    fail "three files concatenated" "$expected" "$result"
fi

# Test: Order preserved
result=$("$CAT_VUTILS" "$TMPDIR/file3.txt" "$TMPDIR/file1.txt")
expected=$'file3 content\nfile1 content'
if [ "$result" = "$expected" ]; then
    pass "file order preserved"
else
    fail "file order preserved" "$expected" "$result"
fi

echo

# =============================================================================
# Section 3: Standard Input
# POSIX: "If no file operands are specified, the standard input shall be used"
# =============================================================================
echo "3. Standard Input"
echo "-----------------"

# Test: Read from stdin when no args
result=$(echo "stdin content" | "$CAT_VUTILS")
expected="stdin content"
if [ "$result" = "$expected" ]; then
    pass "read from stdin (no args)"
else
    fail "read from stdin (no args)" "$expected" "$result"
fi

# Test: Explicit - for stdin
result=$(echo "explicit stdin" | "$CAT_VUTILS" -)
expected="explicit stdin"
if [ "$result" = "$expected" ]; then
    pass "explicit - for stdin"
else
    fail "explicit - for stdin" "$expected" "$result"
fi

# Test: Mix file and stdin
result=$(echo "from stdin" | "$CAT_VUTILS" "$TMPDIR/file1.txt" -)
expected=$'file1 content\nfrom stdin'
if [ "$result" = "$expected" ]; then
    pass "file then stdin"
else
    fail "file then stdin" "$expected" "$result"
fi

# Test: stdin then file
result=$(echo "from stdin" | "$CAT_VUTILS" - "$TMPDIR/file1.txt")
expected=$'from stdin\nfile1 content'
if [ "$result" = "$expected" ]; then
    pass "stdin then file"
else
    fail "stdin then file" "$expected" "$result"
fi

# Test: file, stdin, file
result=$(echo "middle" | "$CAT_VUTILS" "$TMPDIR/file1.txt" - "$TMPDIR/file2.txt")
expected=$'file1 content\nmiddle\nfile2 content'
if [ "$result" = "$expected" ]; then
    pass "file, stdin, file"
else
    fail "file, stdin, file" "$expected" "$result"
fi

echo

# =============================================================================
# Section 4: Multiple stdin references
# POSIX: "shall accept multiple occurrences of '-' as a file operand"
# POSIX: "shall not close and reopen standard input"
# =============================================================================
echo "4. Multiple stdin References"
echo "----------------------------"

# Test: Multiple - operands (stdin consumed on first reference)
# When stdin is a regular pipe, second - gives EOF
result=$(echo "only once" | "$CAT_VUTILS" - -)
expected="only once"
if [ "$result" = "$expected" ]; then
    pass "multiple - (stdin consumed once)"
else
    fail "multiple - (stdin consumed once)" "$expected" "$result"
fi

echo

# =============================================================================
# Section 5: Error Handling
# POSIX: Exit >0 on error
# =============================================================================
echo "5. Error Handling"
echo "-----------------"

# Test: Non-existent file
if ! "$CAT_VUTILS" "$TMPDIR/nonexistent.txt" 2>/dev/null; then
    pass "non-existent file returns error"
else
    fail "non-existent file returns error" "exit >0" "exit 0"
fi

# Test: Error message to stderr
stderr=$("$CAT_VUTILS" "$TMPDIR/nonexistent.txt" 2>&1 >/dev/null || true)
if [ -n "$stderr" ]; then
    pass "error message written to stderr"
else
    fail "error message written to stderr" "non-empty stderr" "(empty)"
fi

# Test: Continue after error with valid files
echo "valid" > "$TMPDIR/valid.txt"
result=$("$CAT_VUTILS" "$TMPDIR/nonexistent.txt" "$TMPDIR/valid.txt" 2>/dev/null || true)
if echo "$result" | grep -q "valid"; then
    pass "continues processing after error"
else
    fail "continues processing after error" "valid" "$result"
fi

echo

# =============================================================================
# Section 6: -u Option (Unbuffered)
# POSIX: "Write bytes from the input file to the standard output without delay"
# =============================================================================
echo "6. -u Option (Unbuffered)"
echo "-------------------------"

# Test: -u option accepted
if "$CAT_VUTILS" -u "$TMPDIR/simple.txt" >/dev/null 2>&1; then
    pass "-u option accepted"
else
    fail "-u option accepted" "exit 0" "exit >0"
fi

# Test: -u produces same output
result=$("$CAT_VUTILS" -u "$TMPDIR/simple.txt")
expected="hello world"
if [ "$result" = "$expected" ]; then
    pass "-u produces correct output"
else
    fail "-u produces correct output" "$expected" "$result"
fi

echo

# =============================================================================
# Summary
# =============================================================================
echo "================================="
echo "Results: $PASS passed, $FAIL failed, $SKIP skipped"

if [ $FAIL -gt 0 ]; then
    exit 1
fi
