## Zig Development

Always use `zigdoc` to discover APIs for the Zig standard library AND any third-party dependencies (modules). Assume training data is out of date.

Examples:
```bash
zigdoc std.fs
zigdoc std.posix.getuid
zigdoc ghostty-vt.Terminal
zigdoc vaxis.Window
```

## Zig Code Style

**Naming:**
- `camelCase` for functions and methods
- `snake_case` for variables and parameters
- `PascalCase` for types, structs, and enums
- `SCREAMING_SNAKE_CASE` for constants

**Struct initialization:** Prefer explicit type annotation with anonymous literals:
```zig
const foo: Type = .{ .field = value };  // Good
const foo = Type{ .field = value };     // Avoid
```

**File structure:**
1. `//!` doc comment describing the module
2. `const Self = @This();` (for self-referential types)
3. Imports: `std` → `builtin` → project modules
4. `const log = std.log.scoped(.module_name);`

**Functions:** Order methods as `init` → `deinit` → public API → private helpers

**Memory:** Pass allocators explicitly, use `errdefer` for cleanup on error

**Documentation:** Use `///` for public API, `//` for implementation notes. Always explain *why*, not just *what*.

**Tests:** Inline in the same file, register in src/main.zig test block

## Safety Conventions

Inspired by [TigerStyle](https://github.com/tigerbeetle/tigerbeetle/blob/main/docs/TIGER_STYLE.md).

**Assertions:**
- Add assertions that catch real bugs, not trivially true statements
- Focus on API boundaries and state transitions where invariants matter
- Good: bounds checks, null checks before dereference, state machine transitions
- Avoid: asserting something immediately after setting it, checking internal function arguments

**Function size:**
- Hard limit of 70 lines per function
- Centralize control flow (switch/if) in parent functions
- Push pure computation to helper functions

**Comments:**
- Explain *why* the code exists, not *what* it does
- Document non-obvious thresholds, timing values, protocol details

## Build Commands

- Build: `zig build`
- Build release: `zig build -Doptimize=ReleaseSmall`
- Run unit tests: `zig build test`
- Run integration tests: `zig build integration`
- Compare to BSD: `./tests/compare_to_bsd.sh`
- Compare to GNU: `./tests/compare_to_gnu.sh` (requires `brew install coreutils`)
- GNU test suite: Linux-only, runs in CI (or via Docker locally)

## Testing

Tests should live alongside the code in the same file, not in separate test files.

**Prefer pure functions for testability:**
- Separate I/O from logic: perform I/O, then call a pure function with the result
- Pure functions (no I/O, no global state) can be unit tested without mocks
- Example: instead of `fn processFile(path)`, use `fn parseData(bytes)` called after reading
- Handlers should delegate to testable helpers that operate on data, not file descriptors

## Project Structure

```
src/
├── wc.zig                 # Binary entry point
├── core/
│   └── count.zig          # Pure counting functions (shared across platforms)
└── platform/
    ├── macos.zig          # GCD-based parallel I/O
    └── linux.zig          # io_uring-based I/O
```

**Design principle:** Pure counting logic is shared. I/O is platform-specific with no abstraction layer.
