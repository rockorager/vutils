#!/bin/bash
# Compare vutils wc output against GNU wc (gwc)
# Requires: brew install coreutils
# Run from repo root: ./tests/compare_to_gnu.sh

set -e

# vutils respects LC_CTYPE: UTF-8 locale uses Unicode whitespace, C locale uses ASCII.
# Default to UTF-8 if no locale is set, so both GNU and vutils use Unicode semantics.
if [ -z "$LC_ALL" ]; then
    export LC_ALL=en_US.UTF-8
fi

WC_VUTILS="./zig-out/bin/vwc"

# Find GNU wc: gwc on macOS, wc on Linux
if command -v gwc &> /dev/null; then
    WC_GNU="gwc"
elif [ "$(uname)" = "Linux" ]; then
    WC_GNU="wc"
else
    echo "GNU wc not found. Install with: brew install coreutils"
    exit 1
fi

PASS=0
FAIL=0

compare() {
    local desc="$1"
    shift
    local files=("$@")
    
    local gnu_out=$($WC_GNU "${files[@]}" 2>/dev/null | tail -1)
    local vutils_out=$($WC_VUTILS "${files[@]}" 2>/dev/null)
    
    local gnu_nums=$(echo "$gnu_out" | awk '{print $1, $2, $3}')
    local vutils_nums=$(echo "$vutils_out" | awk '{print $1, $2, $3}')
    
    if [ "$gnu_nums" = "$vutils_nums" ]; then
        echo "✓ $desc"
        PASS=$((PASS + 1))
    else
        echo "✗ $desc"
        echo "  GNU:    $gnu_nums"
        echo "  vutils: $vutils_nums"
        FAIL=$((FAIL + 1))
    fi
}

echo "Comparing vutils wc against GNU wc..."
echo

# Test fixtures
if [ -f tests/fixtures/lorem_ipsum.txt ]; then
    compare "lorem_ipsum.txt" tests/fixtures/lorem_ipsum.txt
fi

if [ -f tests/fixtures/UTF_8_weirdchars.txt ]; then
    compare "UTF_8_weirdchars.txt (Unicode whitespace)" tests/fixtures/UTF_8_weirdchars.txt
fi

if [ -f tests/fixtures/UTF_8_test.txt ]; then
    compare "UTF_8_test.txt" tests/fixtures/UTF_8_test.txt
fi

# Create Unicode test files
mkdir -p /tmp/vutils_test

# NO-BREAK SPACE (U+00A0)
printf 'hello\xc2\xa0world\n' > /tmp/vutils_test/nbsp.txt
compare "NO-BREAK SPACE splits words" /tmp/vutils_test/nbsp.txt

# EM SPACE (U+2003)
printf 'hello\xe2\x80\x83world\n' > /tmp/vutils_test/emspace.txt
compare "EM SPACE splits words" /tmp/vutils_test/emspace.txt

# ZERO WIDTH SPACE (U+200B) - should NOT split
printf 'hello\xe2\x80\x8bworld\n' > /tmp/vutils_test/zwsp.txt
compare "ZERO WIDTH SPACE does NOT split" /tmp/vutils_test/zwsp.txt

# Multiple files
compare "multiple files" tests/fixtures/lorem_ipsum.txt tests/fixtures/UTF_8_weirdchars.txt

rm -rf /tmp/vutils_test

echo
echo "Results: $PASS passed, $FAIL failed"

if [ $FAIL -gt 0 ]; then
    exit 1
fi
