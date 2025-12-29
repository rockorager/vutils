#!/bin/bash
# Test vutils wc output against expected values
# Run from repo root: ./tests/compare_to_gnu.sh

set -e

# vutils uses consistent Unicode whitespace across all platforms.
# This matches macOS libc behavior and Unicode Zs category.
# Note: glibc (Linux) iswspace() differs - we intentionally diverge for consistency.
if [ -z "$LC_ALL" ]; then
    export LC_ALL=en_US.UTF-8
fi

# Detect if we're in C/POSIX locale (no Unicode whitespace)
IS_C_LOCALE=0
if [ "$LC_ALL" = "C" ] || [ "$LC_ALL" = "POSIX" ]; then
    IS_C_LOCALE=1
fi

WC_VUTILS="./zig-out/bin/vwc"

PASS=0
FAIL=0

# Compare against expected values (not system wc)
check() {
    local desc="$1"
    local expected="$2"
    shift 2
    local files=("$@")
    
    local vutils_out=$($WC_VUTILS "${files[@]}" 2>/dev/null | tail -1)
    local vutils_nums=$(echo "$vutils_out" | awk '{print $1, $2, $3}')
    
    if [ "$vutils_nums" = "$expected" ]; then
        echo "✓ $desc"
        PASS=$((PASS + 1))
    else
        echo "✗ $desc"
        echo "  expected: $expected"
        echo "  got:      $vutils_nums"
        FAIL=$((FAIL + 1))
    fi
}

echo "Testing vutils wc against expected values..."
echo

# Test fixtures with known expected values
# In C locale, Unicode whitespace is NOT recognized, so word counts differ
if [ "$IS_C_LOCALE" = "1" ]; then
    check "lorem_ipsum.txt" "13 109 772" tests/fixtures/lorem_ipsum.txt
    check "UTF_8_weirdchars.txt" "25 91 513" tests/fixtures/UTF_8_weirdchars.txt
    check "UTF_8_test.txt" "303 2183 23025" tests/fixtures/UTF_8_test.txt
else
    check "lorem_ipsum.txt" "13 109 772" tests/fixtures/lorem_ipsum.txt
    check "UTF_8_weirdchars.txt" "25 89 513" tests/fixtures/UTF_8_weirdchars.txt
    check "UTF_8_test.txt" "303 2178 23025" tests/fixtures/UTF_8_test.txt
fi

# Create Unicode test files
mkdir -p /tmp/vutils_test

# NO-BREAK SPACE (U+00A0) - splits words in UTF-8, but recognized in C locale too (Latin-1)
printf 'hello\xc2\xa0world\n' > /tmp/vutils_test/nbsp.txt
check "NO-BREAK SPACE splits words" "1 2 13" /tmp/vutils_test/nbsp.txt

# EM SPACE (U+2003) - splits words in UTF-8 locale only
printf 'hello\xe2\x80\x83world\n' > /tmp/vutils_test/emspace.txt
if [ "$IS_C_LOCALE" = "1" ]; then
    check "EM SPACE (C locale - no split)" "1 1 14" /tmp/vutils_test/emspace.txt
else
    check "EM SPACE splits words" "1 2 14" /tmp/vutils_test/emspace.txt
fi

# ZERO WIDTH SPACE (U+200B) - should NOT split (not in Zs category)
printf 'hello\xe2\x80\x8bworld\n' > /tmp/vutils_test/zwsp.txt
check "ZERO WIDTH SPACE does NOT split" "1 1 14" /tmp/vutils_test/zwsp.txt

# Multiple files
if [ "$IS_C_LOCALE" = "1" ]; then
    check "multiple files" "38 200 1285" tests/fixtures/lorem_ipsum.txt tests/fixtures/UTF_8_weirdchars.txt
else
    check "multiple files" "38 198 1285" tests/fixtures/lorem_ipsum.txt tests/fixtures/UTF_8_weirdchars.txt
fi

rm -rf /tmp/vutils_test

echo
echo "Results: $PASS passed, $FAIL failed"

if [ $FAIL -gt 0 ]; then
    exit 1
fi
