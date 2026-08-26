#!/usr/bin/env python3
"""Static checks for GDScript that Godot will not give us from a headless run.

The project builds with warnings promoted to errors, and `--editor --quit`
catches that whole class at load. It does not catch everything: a standalone
ternary is reported by `GDScript::reload` only in a real windowed session, so
the first anyone hears of it is a warning on someone's screen. Neither
`--check-only --script` (which cannot resolve the autoloads) nor the editor
pass sees it. This does.

Run:  python3 tools/lint_gd.py
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# A statement is a discarded ternary when its `if`/`else` sit at bracket depth
# zero. Inside brackets they belong to somebody else's expression --
# `print("a" if b else "c")` is a perfectly good line -- and that distinction is
# the whole check. Testing whether the line merely *starts* with a call, which
# was the first attempt, throws the real fault away with the false ones.
STARTS = re.compile(r"^\s*(return|var|const|elif|if|while|for|assert|await|match)\b")
ASSIGN = re.compile(r"(^|[^=!<>])=([^=]|$)|[-+*/|&%]=")


def _top_level_ternary(line):
    """True when this line's value is a ternary and nothing consumes it."""
    depth = 0
    quote = ""
    prev = ""
    saw_if = False
    for i, ch in enumerate(line):
        if quote:
            if ch == quote and prev != "\\":
                quote = ""
            prev = ch
            continue
        if ch in "\"'":
            quote = ch
        elif ch == "#":
            break
        elif ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        elif depth == 0 and ch == "i" and line[i:i + 3] == "if " and (
                i > 0 and line[i - 1] == " "):
            saw_if = True
        elif depth == 0 and ch == "e" and line[i:i + 5] == "else " and (
                i > 0 and line[i - 1] == " ") and saw_if:
            return True
        prev = ch
    return False


def _depth_delta(line):
    """Net change in bracket depth, ignoring brackets inside strings."""
    depth = 0
    quote = ""
    prev = ""
    for ch in line:
        if quote:
            if ch == quote and prev != "\\":
                quote = ""
        elif ch in "\"'":
            quote = ch
        elif ch == "#":
            break
        elif ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        prev = ch
    return depth


def check(path):
    out = []
    with open(path, encoding="utf-8") as fh:
        in_shader = False
        depth = 0
        cont = False
        for n, raw in enumerate(fh, 1):
            line = raw.rstrip("\n")
            stripped = line.strip()
            # embedded shader source is not GDScript
            if stripped.startswith(('const SKY_SHADER', 'const FOG_SHADER',
                                    'const GROUND_SHADER')):
                in_shader = True
                continue
            if in_shader:
                if stripped == '"""':
                    in_shader = False
                continue
            if not stripped or stripped.startswith("#"):
                continue
            # A line inside an unclosed bracket, or following one that ended in
            # a backslash, is the middle of somebody else's expression and its
            # value is very much not discarded. Without this the check reports
            # every wrapped argument list in the project: 38 of them.
            inside = depth > 0 or cont
            was_depth = depth
            depth += _depth_delta(line)
            cont = line.endswith("\\")
            if inside or was_depth > 0:
                continue
            if STARTS.match(line) or ASSIGN.search(line):
                continue
            if _top_level_ternary(line):
                out.append((n, stripped))
    return out


def main():
    faults = 0
    scanned = 0
    for base, _dirs, files in os.walk(os.path.join(ROOT, "scripts")):
        for f in sorted(files):
            if not f.endswith(".gd"):
                continue
            path = os.path.join(base, f)
            scanned += 1
            for n, text in check(path):
                rel = os.path.relpath(path, ROOT)
                print("%s:%d  standalone ternary — the value is discarded" % (rel, n))
                print("        %s" % text)
                faults += 1
    print("[lint] %d files scanned, %d fault(s)" % (scanned, faults))
    return 1 if faults else 0


if __name__ == "__main__":
    sys.exit(main())
