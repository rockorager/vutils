# POSIX wc Conformance

Based on [POSIX.1-2017 wc specification](https://pubs.opengroup.org/onlinepubs/9699919799/utilities/wc.html).

## Run Tests

```bash
# From repo root
./tests/posix/wc_test.sh
```

## POSIX Requirements Summary

### Options
| Option | Description | Status |
|--------|-------------|--------|
| `-c` | Write byte count | ✅ Implemented |
| `-l` | Write newline count | ✅ Implemented |
| `-m` | Write character count | ❌ #433 |
| `-w` | Write word count | ✅ Implemented |

**Note:** `-c` and `-m` are mutually exclusive per POSIX synopsis `[-c|-m]`.

### Output Format

POSIX format: `"%d %d %d %s\n"` for `<lines> <words> <bytes/chars> <filename>`

| Requirement | Status |
|-------------|--------|
| Output order: lines, words, bytes | ✅ |
| Per-file output with filename | ❌ #434 |
| "total" line only when >1 file | ❌ #434 |
| No filename for stdin (no operand) | ✅ |

### Standard Input

| Requirement | Status |
|-------------|--------|
| No file operand → read stdin | ✅ |
| `-` operand means stdin | ❌ #435 |
| `-` mixed with files | ❌ #435 |

### Word Definition

POSIX: "non-zero-length string of characters delimited by white space"

| Requirement | Status |
|-------------|--------|
| Space separates words | ✅ |
| Tab separates words | ✅ |
| Newline separates words | ✅ |
| Multiple whitespace = one boundary | ✅ |
| LC_CTYPE determines whitespace | ✅ |

### Exit Status

| Requirement | Status |
|-------------|--------|
| 0 on success | ✅ |
| >0 on error | ❌ #436 |
| Error messages to stderr | ❌ #436 |
| Continue processing after error | ❌ #436 |

### LC_CTYPE Locale Handling

| Requirement | Status |
|-------------|--------|
| UTF-8 locale: Unicode whitespace | ✅ |
| C locale: ASCII whitespace | ✅ |
| -m respects locale for char count | ❌ #433 |

## Related Tasks

- **#433**: Add `-m` option (character count)
- **#434**: Per-file output with total only when >1 file
- **#435**: Support `-` for stdin
- **#436**: Error handling (exit codes, stderr messages)

## Reference Implementations

- **busybox wc**: Minimal POSIX-compliant (Linux CI)
- **GNU wc**: Extended features, POSIX-compatible
- **BSD wc**: macOS `/usr/bin/wc`
