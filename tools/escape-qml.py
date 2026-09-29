#!/usr/bin/env python3
# Rewrites any non-ASCII character in the given files as a \u escape, so icon
# glyphs survive editors and tools that mangle private-use codepoints.
#   tools/escape-qml.py Widget.qml components/*.qml
import sys
def esc(ch):
    cp = ord(ch)
    if cp < 128:
        return ch
    if cp > 0xFFFF:
        v = cp - 0x10000
        return "\\u%04X\\u%04X" % (0xD800 + (v >> 10), 0xDC00 + (v & 0x3FF))
    return "\\u%04x" % cp
for path in sys.argv[1:]:
    text = open(path, encoding="utf-8").read()
    fixed = "".join(esc(ch) for ch in text)
    if fixed != text:
        open(path, "w", encoding="utf-8").write(fixed)
        print("escaped", path)
