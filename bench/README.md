# Benchmarking Infrastructure

Track performance across commits, platforms, and binaries.

## Quick Start

```bash
# Run benchmarks
./bench/benchmark.sh

# Run and save to history
./bench/benchmark.sh --save

# Benchmark specific binary
./bench/benchmark.sh wc
```

## Output

Results are stored as JSON Lines in `bench/data/`:
- `wc_darwin.jsonl` - wc benchmarks on macOS
- `wc_linux.jsonl` - wc benchmarks on Linux

Each line is a complete benchmark result:
```json
{
  "binary": "wc",
  "platform": "darwin",
  "arch": "arm64",
  "timestamp": "2025-01-15T10:30:00Z",
  "git_commit": "abc1234",
  "git_branch": "main",
  "test_config": {
    "num_files": 50,
    "total_mb": 66,
    "warmup_runs": 2,
    "bench_runs": 5
  },
  "results": {
    "vutils_ms": 65,
    "bsd_ms": 94,
    "gnu_ms": 91,
    "speedup_vs_bsd": 1.45,
    "speedup_vs_gnu": 1.40
  }
}
```

## CI Integration

Add to your CI workflow:
```yaml
- name: Benchmark
  run: ./bench/benchmark.sh --save

- name: Upload results
  uses: actions/upload-artifact@v4
  with:
    name: benchmarks-${{ runner.os }}
    path: bench/data/*.jsonl
```

## Analyzing Results

Query history with jq:
```bash
# Latest result
tail -1 bench/data/wc_darwin.jsonl | jq .

# Performance trend over last 10 commits
tail -10 bench/data/wc_darwin.jsonl | jq -r '[.git_commit, .results.vutils_ms] | @tsv'

# Find regressions (>10% slower)
cat bench/data/wc_darwin.jsonl | jq -s '
  [., .[1:]] | transpose | 
  map(select(.[1].results.vutils_ms > .[0].results.vutils_ms * 1.1)) |
  .[].git_commit
'
```

## Dependencies

- `jq` - JSON processing (for summary output)
- `bc` - Calculator (for speedup calculations)
- `gwc` - GNU wc for comparison (optional, `brew install coreutils`)
- uutils wc - Rust coreutils (`brew install --force uutils-coreutils`)
- `busybox` - busybox wc for comparison (Linux only)
