#!/bin/bash
# Compare vutils echo output against GNU echo (gecho)
# Requires: brew install coreutils
# Run from repo root: ./tests/compare_echo_to_gnu.sh

set -e

ECHO_VUTILS="./zig-out/bin/vecho"

# Find GNU echo: gecho on macOS, /bin/echo on Linux (but we need GNU echo)
if command -v gecho &> /dev/null; then
    ECHO_GNU="gecho"
elif [ "$(uname)" = "Linux" ]; then
    ECHO_GNU="echo"
else
    echo "GNU echo not found. Install with: brew install coreutils"
    exit 1
fi

PASS=0
FAIL=0

compare() {
    local desc="$1"
    shift
    
    local gnu_out=$($ECHO_GNU "$@" 2>/dev/null || true)
    local vutils_out=$($ECHO_VUTILS "$@" 2>/dev/null || true)
    
    if [ "$gnu_out" = "$vutils_out" ]; then
        echo "✓ $desc"
        PASS=$((PASS + 1))
    else
        echo "✗ $desc"
        echo "  GNU:    '$gnu_out'"
        echo "  vutils: '$vutils_out'"
        FAIL=$((FAIL + 1))
    fi
}

echo "Comparing vutils echo against GNU echo..."
echo

# Basic tests
compare "simple text" "hello world"
compare "empty" ""
compare "multiple args" "hello" "world" "foo"

# -n flag (no newline)
compare "-n flag" -n "hello"
compare "-n with multiple args" -n "hello" "world"

# -e flag (escape sequences)
compare "-e newline" -e "hello\nworld"
compare "-e tab" -e "hello\tworld"
compare "-e backslash" -e "hello\\\\world"
compare "-e carriage return" -e "hello\rworld"
compare "-e bell" -e "hello\aworld"
compare "-e backspace" -e "hello\bworld"
compare "-e form feed" -e "hello\fworld"
compare "-e vertical tab" -e "hello\vworld"
compare "-e escape" -e "hello\eworld"
compare "-e hex" -e "hello\x41world"
compare "-e octal" -e "hello\0101world"

# -E flag (disable escapes, default)
compare "-E flag" -E "hello\nworld"

# Combined flags
compare "-ne flags" -ne "hello\nworld"
compare "-en flags" -en "hello\nworld"

# -- stops option parsing
compare "-- stops options" -- -n

# Edge cases
compare "dash only" "-"
compare "single char arg" "a"
compare "arg starting with dash" "-abc"

echo
echo "Results: $PASS passed, $FAIL failed"

if [ $FAIL -gt 0 ]; then
    exit 1
fi
