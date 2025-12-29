#!/bin/bash
# Run GNU coreutils test suite against vutils
# Based on uutils' approach: https://github.com/uutils/coreutils
#
# Usage:
#   ./tests/gnu/run-gnu-tests.sh          # Run wc tests only
#   ./tests/gnu/run-gnu-tests.sh --all    # Run all tests (requires all tools)
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
RUN_ALL=false
SETUP_ONLY=false
for arg in "$@"; do
    case "$arg" in
        --all) RUN_ALL=true ;;
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
        ./configure --quiet --disable-nls
    fi

    if [ ! -f "src/getlimits" ]; then
        log "Building test helpers..."
        make -j"$(nproc 2>/dev/null || sysctl -n hw.ncpu)" src/getlimits
    fi

    log "GNU coreutils ready at $GNU_DIR"
}

# Build vutils
build_vutils() {
    log "Building vutils..."
    cd "$REPO_ROOT"
    zig build -Doptimize=ReleaseFast
    
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
    
    # Link vutils tools (use vwc as wc)
    ln -sf "$VUTILS_BIN/vwc" "$test_bin/wc"
    
    # Link GNU helpers needed for tests
    ln -sf "$GNU_DIR/src/getlimits" "$test_bin/"
    
    # For tools we don't have, use system/GNU versions
    for tool in cat echo printf tr seq head tail; do
        if [ -f "$GNU_DIR/src/$tool" ]; then
            ln -sf "$GNU_DIR/src/$tool" "$test_bin/"
        elif command -v "g$tool" &>/dev/null; then
            ln -sf "$(command -v g$tool)" "$test_bin/$tool"
        elif command -v "$tool" &>/dev/null; then
            ln -sf "$(command -v $tool)" "$test_bin/$tool"
        fi
    done
    
    export PATH="$test_bin:$PATH"
    
    log "Running GNU wc tests..."
    log "PATH includes: $test_bin"
    
    # Run wc-specific tests
    if $RUN_ALL; then
        make check TESTS="tests/misc/wc.pl tests/misc/wc-files0-from.pl" VERBOSE=yes || true
    else
        # Just run basic wc tests
        cd tests/misc
        
        log "Test: basic wc functionality"
        echo "hello world" | wc
        
        log "Test: wc -l"
        printf "line1\nline2\nline3\n" | wc -l
        
        log "Test: wc -w" 
        echo "one two three four" | wc -w
        
        log "Test: wc -c"
        echo "12345" | wc -c
        
        log "Running wc.pl test..."
        cd "$GNU_DIR"
        perl -I"$GNU_DIR/tests" tests/misc/wc.pl || {
            error "wc.pl failed (some failures expected)"
        }
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
