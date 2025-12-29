#!/bin/bash
# Benchmark vutils against GNU and BSD implementations
# Outputs JSON for tracking over time
#
# Usage:
#   ./bench/benchmark.sh              # Run all benchmarks
#   ./bench/benchmark.sh --save       # Run and append to history
#   ./bench/benchmark.sh wc           # Benchmark only wc

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
BENCH_DIR="$SCRIPT_DIR"
DATA_DIR="$BENCH_DIR/data"
FIXTURE_DIR="$BENCH_DIR/fixtures"

mkdir -p "$DATA_DIR" "$FIXTURE_DIR"

# Configuration
NUM_FILES=50
FILE_SIZE_MB=1
WARMUP_RUNS=2
BENCH_RUNS=5

# Detect platform
PLATFORM="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"

# Get git info
GIT_COMMIT="$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo "unknown")"
GIT_BRANCH="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")"
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Tool paths
WC_VUTILS="$REPO_ROOT/zig-out/bin/vwc"
WC_BSD="/usr/bin/wc"
WC_GNU="gwc"
# uutils: use full path to avoid conflicts with coreutils
WC_UUTILS="/opt/homebrew/opt/uutils-coreutils/libexec/uubin/wc"
WC_BUSYBOX="busybox" # busybox (Linux only)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# All logging goes to stderr so stdout is clean for JSON
log() { echo -e "${GREEN}[bench]${NC} $*" >&2; }
warn() { echo -e "${YELLOW}[warn]${NC} $*" >&2; }
error() { echo -e "${RED}[error]${NC} $*" >&2; }

# Generate test fixtures if needed
generate_fixtures() {
    local marker="$FIXTURE_DIR/.generated_${NUM_FILES}_${FILE_SIZE_MB}MB"
    
    if [ -f "$marker" ]; then
        log "Using cached fixtures ($NUM_FILES files × ${FILE_SIZE_MB}MB)"
        return
    fi
    
    log "Generating $NUM_FILES files × ${FILE_SIZE_MB}MB each..."
    rm -f "$FIXTURE_DIR"/bench_*.txt
    
    for i in $(seq 1 $NUM_FILES); do
        # Generate realistic text-like content
        dd if=/dev/urandom bs=1024 count=$((FILE_SIZE_MB * 1024)) 2>/dev/null | \
            LC_ALL=C tr -c 'a-zA-Z0-9 \n' ' ' | \
            fold -w 80 > "$FIXTURE_DIR/bench_$(printf '%03d' $i).txt"
    done
    
    touch "$marker"
    log "Generated $(du -sh "$FIXTURE_DIR" | cut -f1) of test data"
}

# Time a command in milliseconds (returns median of runs)
time_cmd() {
    local cmd="$1"
    local runs="$2"
    local times=()
    
    for i in $(seq 1 $runs); do
        # Use perl for sub-second timing (portable)
        local start_ms=$(perl -MTime::HiRes=time -e 'printf "%.0f", time * 1000')
        eval "$cmd" >/dev/null 2>&1
        local end_ms=$(perl -MTime::HiRes=time -e 'printf "%.0f", time * 1000')
        times+=( $((end_ms - start_ms)) )
    done
    
    # Sort and return median
    printf '%s\n' "${times[@]}" | sort -n | sed -n "$((runs / 2 + 1))p"
}

# Benchmark wc implementations
benchmark_wc() {
    log "Benchmarking wc..."
    
    local files=("$FIXTURE_DIR"/bench_*.txt)
    # macOS du doesn't have -b, use stat instead
    local total_bytes=0
    for f in "${files[@]}"; do
        total_bytes=$((total_bytes + $(stat -f%z "$f" 2>/dev/null || stat -c%s "$f" 2>/dev/null || echo 0)))
    done
    local total_mb=$((total_bytes / 1024 / 1024))
    
    # Warmup
    log "Warmup ($WARMUP_RUNS runs)..."
    for i in $(seq 1 $WARMUP_RUNS); do
        "$WC_VUTILS" "${files[@]}" >/dev/null 2>&1 || true
    done
    
    # Benchmark vutils
    log "Timing vutils wc ($BENCH_RUNS runs)..."
    local vutils_ms=$(time_cmd "\"$WC_VUTILS\" ${files[*]}" $BENCH_RUNS)
    
    # Benchmark BSD wc
    local bsd_ms="null"
    if [ -x "$WC_BSD" ]; then
        log "Timing BSD wc ($BENCH_RUNS runs)..."
        bsd_ms=$(time_cmd "\"$WC_BSD\" ${files[*]}" $BENCH_RUNS)
    fi
    
    # Benchmark GNU wc
    local gnu_ms="null"
    if command -v "$WC_GNU" &>/dev/null; then
        log "Timing GNU wc ($BENCH_RUNS runs)..."
        gnu_ms=$(time_cmd "\"$WC_GNU\" ${files[*]}" $BENCH_RUNS)
    fi
    
    # Benchmark uutils wc
    local uutils_ms="null"
    if [ -x "$WC_UUTILS" ]; then
        log "Timing uutils wc ($BENCH_RUNS runs)..."
        uutils_ms=$(time_cmd "\"$WC_UUTILS\" ${files[*]}" $BENCH_RUNS)
    fi
    
    # Benchmark busybox wc
    local busybox_ms="null"
    if command -v "$WC_BUSYBOX" &>/dev/null; then
        log "Timing busybox wc ($BENCH_RUNS runs)..."
        busybox_ms=$(time_cmd "\"$WC_BUSYBOX\" wc ${files[*]}" $BENCH_RUNS)
    fi
    
    # Calculate speedups
    local speedup_vs_bsd="null"
    local speedup_vs_gnu="null"
    local speedup_vs_uutils="null"
    local speedup_vs_busybox="null"
    if [ "$bsd_ms" != "null" ] && [ "$vutils_ms" -gt 0 ]; then
        speedup_vs_bsd=$(echo "scale=2; $bsd_ms / $vutils_ms" | bc)
    fi
    if [ "$gnu_ms" != "null" ] && [ "$vutils_ms" -gt 0 ]; then
        speedup_vs_gnu=$(echo "scale=2; $gnu_ms / $vutils_ms" | bc)
    fi
    if [ "$uutils_ms" != "null" ] && [ "$vutils_ms" -gt 0 ]; then
        speedup_vs_uutils=$(echo "scale=2; $uutils_ms / $vutils_ms" | bc)
    fi
    if [ "$busybox_ms" != "null" ] && [ "$vutils_ms" -gt 0 ]; then
        speedup_vs_busybox=$(echo "scale=2; $busybox_ms / $vutils_ms" | bc)
    fi
    
    # Output JSON to stdout
    cat <<EOF
{
  "binary": "wc",
  "platform": "$PLATFORM",
  "arch": "$ARCH",
  "timestamp": "$TIMESTAMP",
  "git_commit": "$GIT_COMMIT",
  "git_branch": "$GIT_BRANCH",
  "test_config": {
    "num_files": $NUM_FILES,
    "total_mb": $total_mb,
    "warmup_runs": $WARMUP_RUNS,
    "bench_runs": $BENCH_RUNS
  },
  "results": {
    "vutils_ms": $vutils_ms,
    "bsd_ms": $bsd_ms,
    "gnu_ms": $gnu_ms,
    "uutils_ms": $uutils_ms,
    "busybox_ms": $busybox_ms,
    "speedup_vs_bsd": $speedup_vs_bsd,
    "speedup_vs_gnu": $speedup_vs_gnu,
    "speedup_vs_uutils": $speedup_vs_uutils,
    "speedup_vs_busybox": $speedup_vs_busybox
  }
}
EOF
}

# Print human-readable summary
print_summary() {
    local json="$1"
    
    # Parse JSON values
    local binary=$(echo "$json" | jq -r '.binary // "unknown"')
    local vutils=$(echo "$json" | jq -r '.results.vutils_ms // 0')
    local bsd=$(echo "$json" | jq -r '.results.bsd_ms // "null"')
    local gnu=$(echo "$json" | jq -r '.results.gnu_ms // "null"')
    local uutils=$(echo "$json" | jq -r '.results.uutils_ms // "null"')
    local busybox=$(echo "$json" | jq -r '.results.busybox_ms // "null"')
    local speedup_bsd=$(echo "$json" | jq -r '.results.speedup_vs_bsd // "null"')
    local speedup_gnu=$(echo "$json" | jq -r '.results.speedup_vs_gnu // "null"')
    local speedup_uutils=$(echo "$json" | jq -r '.results.speedup_vs_uutils // "null"')
    local speedup_busybox=$(echo "$json" | jq -r '.results.speedup_vs_busybox // "null"')
    local total_mb=$(echo "$json" | jq -r '.test_config.total_mb // 0')
    
    # Print to stderr
    {
        echo
        echo "═══════════════════════════════════════════════════════════"
        echo " Benchmark Results: $binary"
        echo " Platform: $PLATFORM/$ARCH | Commit: $GIT_COMMIT"
        echo "═══════════════════════════════════════════════════════════"
        echo
        
        printf "  %-12s %8s ms\n" "vutils:" "$vutils"
        [ "$bsd" != "null" ] && printf "  %-12s %8s ms  (vutils is %sx faster)\n" "BSD:" "$bsd" "$speedup_bsd"
        [ "$gnu" != "null" ] && printf "  %-12s %8s ms  (vutils is %sx faster)\n" "GNU:" "$gnu" "$speedup_gnu"
        [ "$uutils" != "null" ] && printf "  %-12s %8s ms  (vutils is %sx faster)\n" "uutils:" "$uutils" "$speedup_uutils"
        [ "$busybox" != "null" ] && printf "  %-12s %8s ms  (vutils is %sx faster)\n" "busybox:" "$busybox" "$speedup_busybox"
        echo
        
        if [ "$vutils" -gt 0 ]; then
            local throughput=$(echo "scale=1; $total_mb * 1000 / $vutils" | bc)
            printf "  Throughput: %s MB/s\n" "$throughput"
        fi
        echo
    } >&2
}

# Save result to history
save_result() {
    local json="$1"
    local binary=$(echo "$json" | jq -r '.binary')
    local history_file="$DATA_DIR/${binary}_${PLATFORM}.jsonl"
    
    # Compact JSON to single line
    echo "$json" | jq -c . >> "$history_file"
    log "Saved to $history_file"
}

# Benchmark binary sizes
benchmark_size() {
    log "Benchmarking binary sizes..."
    
    # Build ReleaseSmall for size comparison
    log "Building ReleaseSmall..."
    (cd "$REPO_ROOT" && zig build -Doptimize=ReleaseSmall) || {
        error "ReleaseSmall build failed"
        return 1
    }
    
    local vutils_size=$(file_size "$REPO_ROOT/zig-out/bin/vutils")
    local busybox_size=$(file_size "$(command -v busybox 2>/dev/null || echo /dev/null)")
    
    # Output JSON
    cat <<EOF
{
  "type": "size",
  "platform": "$PLATFORM",
  "arch": "$ARCH",
  "timestamp": "$TIMESTAMP",
  "git_commit": "$GIT_COMMIT",
  "git_branch": "$GIT_BRANCH",
  "sizes_bytes": {
    "vutils": $vutils_size,
    "busybox": $busybox_size
  }
}
EOF
}

print_size_summary() {
    local json="$1"
    
    local vutils=$(echo "$json" | jq -r '.sizes_bytes.vutils // 0')
    local busybox=$(echo "$json" | jq -r '.sizes_bytes.busybox // 0')
    
    {
        echo
        echo "═══════════════════════════════════════════════════════════"
        echo " Binary Size (ReleaseSmall)"
        echo " Platform: $PLATFORM/$ARCH | Commit: $GIT_COMMIT"
        echo "═══════════════════════════════════════════════════════════"
        echo
        printf "  %-12s %10s\n" "vutils:" "$(numfmt_kb $vutils)"
        [ "$busybox" -gt 0 ] && printf "  %-12s %10s  (vutils is %sx larger)\n" "busybox:" "$(numfmt_kb $busybox)" "$(echo "scale=1; $vutils / $busybox" | bc)"
        echo
    } >&2
}

# Get file size (cross-platform)
file_size() {
    local file="$1"
    if [ ! -f "$file" ]; then
        echo 0
        return
    fi
    # macOS uses -f%z, Linux uses -c%s
    stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo 0
}

numfmt_kb() {
    local bytes=$1
    if [ "$bytes" -gt 1048576 ]; then
        echo "$(echo "scale=1; $bytes / 1048576" | bc) MB"
    elif [ "$bytes" -gt 1024 ]; then
        echo "$(echo "scale=0; $bytes / 1024" | bc) KB"
    else
        echo "$bytes B"
    fi
}

# Main
main() {
    local save=false
    local what="all"
    
    for arg in "$@"; do
        case "$arg" in
            --save) save=true ;;
            wc) what="wc" ;;
            size) what="size" ;;
        esac
    done
    
    case "$what" in
        size)
            local result=$(benchmark_size)
            print_size_summary "$result"
            ;;
        wc)
            # Build first
            log "Building release binary..."
            (cd "$REPO_ROOT" && zig build -Doptimize=ReleaseFast) || {
                error "Build failed"
                exit 1
            }
            generate_fixtures
            local result=$(benchmark_wc)
            print_summary "$result"
            if $save; then
                save_result "$result"
            fi
            ;;
        all)
            # Speed benchmark
            log "Building release binary..."
            (cd "$REPO_ROOT" && zig build -Doptimize=ReleaseFast) || {
                error "Build failed"
                exit 1
            }
            generate_fixtures
            local speed_result=$(benchmark_wc)
            print_summary "$speed_result"
            if $save; then
                save_result "$speed_result"
            fi
            
            # Size benchmark
            local size_result=$(benchmark_size)
            print_size_summary "$size_result"
            ;;
    esac
}

main "$@"
