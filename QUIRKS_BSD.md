# BSD Compatibility Quirks

This document lists intentional deviations from BSD coreutils behavior.

vutils prioritizes **GNU coreutils compatibility** and **Unicode correctness** over BSD compatibility.

---

## wc

### Unicode Whitespace Handling

**Behavior difference:** vutils treats Unicode whitespace characters (Zs category) as word separators. BSD wc does not.

| Character | Code Point | vutils | BSD wc |
|-----------|------------|--------|--------|
| NO-BREAK SPACE | U+00A0 | splits words | does NOT split |
| EM SPACE | U+2003 | splits words | does NOT split |
| EN SPACE | U+2002 | splits words | does NOT split |
| FIGURE SPACE | U+2007 | splits words | does NOT split |
| THIN SPACE | U+2009 | splits words | does NOT split |
| NARROW NO-BREAK SPACE | U+202F | splits words | does NOT split |

**Example:**
```bash
# Input: "hello<NBSP>world\n" (where <NBSP> is U+00A0)
$ printf 'hello\xc2\xa0world\n' | /usr/bin/wc -w
       1

$ printf 'hello\xc2\xa0world\n' | vutils-wc -w
       2
```

**Rationale:** We follow Unicode semantics where all characters in the Space_Separator (Zs) general category are whitespace. This matches GNU wc behavior and is more correct for internationalized text.

### Characters That Do NOT Split Words (Correct in Both)

These format characters are correctly treated as non-whitespace by both vutils and BSD wc:

| Character | Code Point | Category | Behavior |
|-----------|------------|----------|----------|
| ZERO WIDTH SPACE | U+200B | Cf (Format) | does NOT split |
| WORD JOINER | U+2060 | Cf (Format) | does NOT split |
| ZERO WIDTH NO-BREAK SPACE | U+FEFF | Cf (Format) | does NOT split |

---

## Verification

Run the comparison script to see current differences:
```bash
./tests/compare_to_bsd.sh
```
