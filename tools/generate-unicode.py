#!/usr/bin/env python3
"""Build unicode.json, the long-tail fallback behind the curated symbols.

Adapted from generate-unicode.py in EFrMG/omarchy-unicode-picker,
Copyright (c) 2026 EFrMG, MIT license (see LICENSE-unicode-picker): every named, assigned code
point from Python's unicodedata, minus CJK ideographs (no English keyword to
search by) and invisible or combining characters. Entries are {e, k} with k
the lowercase name plus "u+XXXX".

The names are Unicode Data Files (Unicode Character Database), redistributed
under the Unicode License; see LICENSE-unicode at the repository root.
"""
import json, unicodedata, sys

SKIP_NAMES = ("CJK UNIFIED IDEOGRAPH", "CJK COMPATIBILITY IDEOGRAPH")
SKIP_CATEGORIES = {"Cf", "Zs", "Zl", "Zp", "Mn", "Mc", "Me"}

out = []
for cp in range(0x20, 0x110000):
    if 0xD800 <= cp <= 0xDFFF:
        continue
    ch = chr(cp)
    try:
        name = unicodedata.name(ch)
    except ValueError:
        continue
    if any(s in name for s in SKIP_NAMES) or unicodedata.category(ch) in SKIP_CATEGORIES:
        continue
    out.append({"e": ch, "k": name.lower() + " u+%04x" % cp})

dst = sys.argv[1] if len(sys.argv) > 1 else "unicode.json"
with open(dst, "w", encoding="utf-8") as f:
    f.write(json.dumps(out, ensure_ascii=False, separators=(",", ":")))
print(len(out), "entries ->", dst, "unicodedata", unicodedata.unidata_version)
