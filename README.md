# vutils

Fast, platform-optimized coreutils in Zig.

## Installation

```bash
zig build -Doptimize=ReleaseFast
# Creates: zig-out/bin/vutils, vwc, wc (symlinks)

# Add to PATH
export PATH="$PWD/zig-out/bin:$PATH"
```

Multicall binary: invoke as `vutils wc` or directly as `vwc`/`wc` via symlinks.

**Binary size (ReleaseSmall):** ~124 KB (vs busybox ~1MB with all applets)

## Why We're Faster

Benchmarked against macOS BSD `wc` and GNU `wc` on 50 files × 1.3MB each (66MB total):

| Tool | Wall Time | Speedup |
|------|-----------|---------|
| **vutils wc** | 65ms | **1.4x faster** |
| GNU wc | 91ms | baseline |
| BSD wc | 94ms | ~same |

With full Unicode whitespace support. Here's why we're still faster:

### 1. Parallelism via GCD `dispatch_apply`
BSD wc processes files sequentially. We use Grand Central Dispatch to 
spread work across all cores automatically:
```
Sequential: 50 files × 2ms each = 100ms
Parallel:   50 files ÷ 16 cores ≈ 6ms
```

### 2. Proper Unicode via uucode
We use [uucode](https://github.com/jacobsandlund/uucode) for fast Unicode 
property lookups (3-stage tables). This is faster than libc's `iswspace()`.

### 3. Larger read buffer
- BSD wc: 64KB (MAXBSIZE)
- vutils: 128KB

Fewer syscalls per file.

### 4. Correct Unicode semantics
We follow GNU wc / Unicode semantics:
- All Zs (Space_Separator) characters split words
- BSD wc has quirks where NBSP, FIGURE SPACE don't split words

## Architecture

```
src/
├── main.zig               # Multicall entry point (dispatches to tools)
├── wc.zig                 # wc tool implementation
├── core/
│   └── count.zig          # Pure functions (shared across platforms)
└── platform/
    ├── macos.zig          # GCD-based parallel I/O
    └── linux.zig          # io_uring-based I/O (WIP)
```

**Design principle:** Pure counting logic is shared. I/O is *uncompromising* 
and platform-specific—no abstraction layer, just the fastest path for each OS.

## macOS Implementation

Uses libdispatch (GCD):
- `dispatch_apply` for automatic work distribution
- `F_NOCACHE` for large files (bypass buffer cache)
- Direct `read()` syscalls with 128KB buffer

## Linux Implementation (WIP)

Will use io_uring for:
- Batched `openat` + `read` syscalls
- True async I/O with completion queue
- Zero-copy where possible

## Testing

macOS ships with **BSD coreutils** (FreeBSD-derived), not GNU.
The GNU coreutils test suite can be run against any implementation.

### Running GNU tests
```bash
# Clone GNU coreutils
git clone https://git.savannah.gnu.org/git/coreutils.git
cd coreutils
./bootstrap && ./configure && make

# Run wc tests against vutils (add vutils to PATH first)
make check TESTS=tests/misc/wc*.sh
```

### uutils compatibility
[uutils/coreutils](https://github.com/uutils/coreutils) (Rust) maintains 
GNU test suite compatibility tracking. We can use their test harness.

## Build & Test

```bash
zig build                           # Debug
zig build -Doptimize=ReleaseFast    # Release

# Tests
zig build test                      # Unit tests (core counting logic)
zig build integration               # Integration tests
./tests/compare_to_gnu.sh           # Compare against GNU wc
./tests/compare_to_bsd.sh           # Compare against BSD wc
./tests/gnu/run-gnu-tests.sh        # Run GNU test suite (requires deps)

# Run with timing
./zig-out/bin/wc -t *.txt
```

## POSIX Compliance

Goal: Match GNU coreutils behavior (the de facto standard).

Current status for `wc`:
- [x] `-l` line count
- [x] `-w` word count  
- [x] `-c` byte count
- [ ] `-m` character count (multibyte)
- [ ] `-L` max line length
- [ ] `--files0-from`
- [ ] Read from stdin (partial)

## Compatibility

We aim for GNU coreutils compatibility. See:
- [QUIRKS_GNU.md](QUIRKS_GNU.md) - Deviations from GNU behavior
- [QUIRKS_BSD.md](QUIRKS_BSD.md) - Deviations from BSD behavior

## Benchmarking

```bash
./bench/benchmark.sh           # Run benchmarks
./bench/benchmark.sh --save    # Save to history
```

Results are stored in `bench/data/` as JSON Lines for tracking over time.
See [bench/README.md](bench/README.md) for details.

## License

MIT
