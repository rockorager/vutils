# GNU Compatibility Quirks

This document lists intentional deviations from GNU coreutils behavior.

vutils aims for **full GNU coreutils compatibility** where possible.

---

## wc

### Current Status: ✅ Fully Compatible

vutils wc matches GNU wc behavior for:
- Unicode whitespace handling (Zs category splits words)
- Line counting (newline characters only)
- Byte counting
- Word boundary detection

### Not Yet Implemented

The following GNU wc features are not yet implemented:

| Feature | GNU Option | Status |
|---------|------------|--------|
| Character count | `-m` | ❌ Not implemented |
| Max line length | `-L` | ❌ Not implemented |
| Read files from stdin | `--files0-from` | ❌ Not implemented |

---

## Verification

Run the comparison script to see current differences:
```bash
./tests/compare_to_gnu.sh
```

Note: Requires GNU coreutils installed (`brew install coreutils` on macOS).
