#!/bin/bash
# Run GNU coreutils test suite against vutils
# Based on uutils' approach: https://github.com/uutils/coreutils
#
# Usage:
#   ./tests/gnu/run-gnu-tests.sh          # Run all GNU tests
#   ./tests/gnu/run-gnu-tests.sh --wc     # Run wc tests only
#   ./tests/gnu/run-gnu-tests.sh --setup  # Just setup, don't run

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
GNU_DIR="$SCRIPT_DIR/coreutils"
VUTILS_BIN="$REPO_ROOT/zig-out/bin"

GNU_VERSION="v9.5"  # Match version uutils tests against

log() { echo -e "\033[0;32m[gnu-test]\033[0m $*"; }
error() { echo -e "\033[0;31m[error]\033[0m $*" >&2; }

# Parse args
RUN_WC_ONLY=false
SETUP_ONLY=false
for arg in "$@"; do
    case "$arg" in
        --wc) RUN_WC_ONLY=true ;;
        --setup) SETUP_ONLY=true ;;
    esac
done

# Check dependencies
check_deps() {
    local missing=""
    for cmd in autoconf automake makeinfo wget perl; do
        if ! command -v "$cmd" &>/dev/null; then
            missing="$missing $cmd"
        fi
    done
    
    if [ -n "$missing" ]; then
        error "Missing dependencies:$missing"
        echo ""
        echo "Install on macOS:  brew install autoconf automake texinfo wget"
        echo "Install on Ubuntu: sudo apt-get install autoconf automake texinfo wget autopoint gperf"
        exit 1
    fi
}

# Clone GNU coreutils if needed
setup_gnu() {
    check_deps
    
    if [ ! -d "$GNU_DIR" ]; then
        log "Cloning GNU coreutils $GNU_VERSION..."
        git clone --depth 1 --branch "$GNU_VERSION" \
            https://git.savannah.gnu.org/git/coreutils.git "$GNU_DIR"
    fi

    cd "$GNU_DIR"

    if [ ! -f "Makefile" ]; then
        log "Bootstrapping GNU coreutils..."
        ./bootstrap --skip-po

        log "Configuring..."
        # Use -O0 for fastest build since we discard GNU binaries
        CFLAGS="-pipe -O0" ./configure --quiet --disable-nls --disable-gcc-warnings
    fi

    if [ ! -f "src/getlimits" ]; then
        log "Building GNU coreutils (required for test infrastructure)..."
        make -j"$(nproc 2>/dev/null || sysctl -n hw.ncpu)"
    fi

    log "GNU coreutils ready at $GNU_DIR"
}

# Build vutils
build_vutils() {
    log "Building vutils..."
    cd "$REPO_ROOT"
    zig build -Doptimize=ReleaseSmall
    
    # Verify wc exists
    if [ ! -x "$VUTILS_BIN/vwc" ]; then
        error "vutils wc not found at $VUTILS_BIN/vwc"
        exit 1
    fi
}

# Run tests
run_tests() {
    cd "$GNU_DIR"
    
    # Create a bin directory with vutils binaries + GNU fallbacks
    local test_bin="$SCRIPT_DIR/test-bin"
    rm -rf "$test_bin"
    mkdir -p "$test_bin"
    
    # Link vutils tools
    ln -sf "$VUTILS_BIN/vwc" "$test_bin/wc"
    
    # Link GNU-built helpers and tools we don't implement yet
    for tool in $(./build-aux/gen-lists-of-programs.sh --list-progs 2>/dev/null || echo ""); do
        if [ ! -f "$test_bin/$tool" ]; then
            if [ -f "$GNU_DIR/src/$tool" ]; then
                ln -sf "$GNU_DIR/src/$tool" "$test_bin/"
            fi
        fi
    done
    
    # Ensure getlimits is available
    ln -sf "$GNU_DIR/src/getlimits" "$test_bin/" 2>/dev/null || true
    
    export PATH="$test_bin:$PATH"
    
    log "PATH includes: $test_bin"
    log "vutils wc: $(which wc)"
    
    # Ensure test directories exist
    mkdir -p "$GNU_DIR/tests/misc"
    
    # Determine which tests to run
    local tests=""
    if $RUN_WC_ONLY; then
        # Run wc tests using RUN_EXPENSIVE to enable all tests
        tests="TESTS='tests/misc/wc.pl tests/misc/wc-files0-from.pl tests/misc/wc-parallel.sh' RUN_EXPENSIVE_TESTS=yes"
    fi
    
    log "Running GNU tests..."
    
    # Run tests and capture output
    local results_file="$SCRIPT_DIR/test-results.log"
    # Use -k to continue on errors, capture exit code but don't fail
    eval make -k check $tests VERBOSE=yes 2>&1 | tee "$results_file" || true
    
    # Parse results
    parse_results "$results_file"
}

# Parse and summarize test results
parse_results() {
    local log_file="$1"
    local results_json="$SCRIPT_DIR/conformance.json"
    
    # Count results from automake test output (handle grep returning 1 on no matches)
    local pass=0 fail=0 skip=0 xfail=0 err=0
    if [ -f "$log_file" ]; then
        pass=$(grep -c "^PASS:" "$log_file" || true)
        fail=$(grep -c "^FAIL:" "$log_file" || true)
        skip=$(grep -c "^SKIP:" "$log_file" || true)
        xfail=$(grep -c "^XFAIL:" "$log_file" || true)
        err=$(grep -c "^ERROR:" "$log_file" || true)
    fi
    # Ensure numeric values
    pass=${pass:-0}
    fail=${fail:-0}
    skip=${skip:-0}
    xfail=${xfail:-0}
    err=${err:-0}
    
    local total=$((pass + fail + skip + xfail + err))
    local pct=0
    local denom=$((pass + fail + err))
    if [ "$denom" -gt 0 ]; then
        pct=$(echo "scale=2; $pass * 100 / $denom" | bc)
    fi
    
    echo ""
    log "═══════════════════════════════════════════════════════════"
    log " GNU Test Suite Results"
    log "═══════════════════════════════════════════════════════════"
    log ""
    log "  PASS:  $pass"
    log "  FAIL:  $fail"
    log "  SKIP:  $skip"
    log "  XFAIL: $xfail"
    log "  ERROR: $error"
    log ""
    log "  Conformance: ${pct}%"
    log ""
    
    # Save JSON for tracking
    cat > "$results_json" <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "git_commit": "$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo "unknown")",
  "pass": $pass,
  "fail": $fail,
  "skip": $skip,
  "xfail": $xfail,
  "error": $error,
  "total": $total,
  "conformance_pct": $pct
}
EOF
    
    log "Results saved to: $results_json"
    
    # List failures for debugging
    if [ "$fail" -gt 0 ] || [ "$error" -gt 0 ]; then
        echo ""
        log "Failed tests:"
        grep -E "^(FAIL|ERROR):" "$log_file" | head -20
    fi
}

# Main
main() {
    setup_gnu
    
    if $SETUP_ONLY; then
        log "Setup complete. Run without --setup to execute tests."
        exit 0
    fi
    
    build_vutils
    run_tests
    
    log "Done!"
}

main "$@"
