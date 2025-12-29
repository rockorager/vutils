# vutils

Fast, platform-optimized coreutils in Zig.

[![Dashboard](https://img.shields.io/badge/dashboard-live-brightgreen)](https://rockorager.github.io/vutils/)
[![GNU Conformance](https://img.shields.io/badge/GNU%20tests-tracking-blue)](#gnu-test-conformance)

## Features

- **2-3x faster** than GNU/BSD coreutils
- **~124 KB** multicall binary (vs busybox ~1MB)
- **Full Unicode** whitespace support (GNU-compatible)
- **Platform-optimized** I/O (GCD on macOS, io_uring on Linux)

## Installation

```bash
zig build -Doptimize=ReleaseFast
export PATH="$PWD/zig-out/bin:$PATH"

# Use as:
vutils wc file.txt    # or
vwc file.txt          # or  
wc file.txt           # (symlink)
```

## Implemented Tools

| Tool | Status | Notes |
|------|--------|-------|
| `wc` | ✅ | 2-3x faster, full Unicode support |

More coming soon. Goal: full GNU coreutils compatibility.

## Performance

Benchmarked on 50 files × 1MB (50MB total):

| Tool | Time | vs vutils |
|------|------|-----------|
| **vutils** | 33ms | — |
| BSD wc | 80ms | 2.4x slower |
| GNU wc | 120ms | 3.6x slower |
| uutils | 117ms | 3.5x slower |

See the [live dashboard](https://rockorager.github.io/vutils/) for current benchmarks.

## GNU Test Conformance

We track compatibility against the GNU coreutils test suite. Tests run automatically in CI on Linux.

Results are published to the [dashboard](https://rockorager.github.io/vutils/).

## Architecture

```
src/
├── main.zig           # Multicall dispatcher
├── wc.zig             # wc implementation
├── core/
│   └── count.zig      # Pure counting functions (shared)
└── platform/
    ├── macos.zig      # GCD parallel I/O
    └── linux.zig      # io_uring I/O (WIP)
```

**Design:** Pure logic is shared. I/O is uncompromisingly platform-specific.

## Build & Test

```bash
zig build                        # Debug build
zig build -Doptimize=ReleaseFast # Release build
zig build test                   # Unit tests
zig build integration            # Integration tests

# Compare against other implementations (macOS/Linux)
./tests/compare_to_gnu.sh        # Requires: brew install coreutils
./tests/compare_to_bsd.sh        # macOS only

# Benchmarks
./bench/benchmark.sh
```

### GNU Test Suite

The full GNU coreutils test suite runs in CI on Linux. To run locally:

```bash
# Linux only (or via Docker)
./tests/gnu/run-gnu-tests.sh --wc

# On macOS, use Docker:
docker run --rm -v "$(pwd)":/vutils -w /vutils ubuntu:22.04 bash -c "
  apt-get update && apt-get install -y build-essential autoconf automake texinfo gperf autopoint wget git && \
  ./tests/gnu/run-gnu-tests.sh --setup
"
```

## Why It's Fast

1. **Parallelism** — GCD `dispatch_apply` on macOS spreads files across cores
2. **Larger buffers** — 128KB vs BSD's 64KB = fewer syscalls  
3. **Fast Unicode** — [uucode](https://github.com/jacobsandlund/uucode) 3-stage tables beat libc's `iswspace()`
4. **No abstraction tax** — Platform-specific I/O, no portability layer

## Compatibility

We match GNU coreutils behavior (the de facto standard).

- [QUIRKS_GNU.md](QUIRKS_GNU.md) — Deviations from GNU
- [QUIRKS_BSD.md](QUIRKS_BSD.md) — Deviations from BSD

## License

MIT
