#!/bin/bash
# Compare vutils wc output against BSD wc
# Run from repo root: ./tests/compare_to_bsd.sh

set -e

WC_VUTILS="./zig-out/bin/vwc"
WC_BSD="/usr/bin/wc"

PASS=0
FAIL=0

compare() {
    local desc="$1"
    shift
    local files=("$@")
    
    # Get counts from both
    local bsd_out=$($WC_BSD "${files[@]}" 2>/dev/null | tail -1)
    local vutils_out=$($WC_VUTILS "${files[@]}" 2>/dev/null)
    
    # Extract just the numbers (ignore filenames and "total")
    local bsd_nums=$(echo "$bsd_out" | awk '{print $1, $2, $3}')
    local vutils_nums=$(echo "$vutils_out" | awk '{print $1, $2, $3}')
    
    if [ "$bsd_nums" = "$vutils_nums" ]; then
        echo "✓ $desc"
        PASS=$((PASS + 1))
    else
        echo "✗ $desc"
        echo "  BSD:    $bsd_nums"
        echo "  vutils: $vutils_nums"
        FAIL=$((FAIL + 1))
    fi
}

echo "Comparing vutils wc against BSD wc..."
echo

# Create test files
mkdir -p /tmp/vutils_test
echo "hello world" > /tmp/vutils_test/simple.txt
echo -n "no newline" > /tmp/vutils_test/no_nl.txt
printf '\n\n\n' > /tmp/vutils_test/newlines.txt
dd if=/dev/zero bs=1M count=10 2>/dev/null | tr '\0' 'x' > /tmp/vutils_test/large.txt
echo "line with    multiple   spaces" > /tmp/vutils_test/spaces.txt

compare "simple file" /tmp/vutils_test/simple.txt
compare "no trailing newline" /tmp/vutils_test/no_nl.txt
compare "only newlines" /tmp/vutils_test/newlines.txt
compare "large file (10MB)" /tmp/vutils_test/large.txt
compare "multiple spaces" /tmp/vutils_test/spaces.txt
compare "multiple files" /tmp/vutils_test/simple.txt /tmp/vutils_test/spaces.txt

# Test with real files if they exist
if [ -f tests/fixtures/lorem_ipsum.txt ]; then
    compare "lorem_ipsum.txt" tests/fixtures/lorem_ipsum.txt
fi

# Cleanup
rm -rf /tmp/vutils_test

echo
echo "Results: $PASS passed, $FAIL failed"

if [ $FAIL -gt 0 ]; then
    exit 1
fi
