#!/usr/bin/env python3
"""Static checks for GDScript that Godot will not give us from a headless run.

The project builds with warnings promoted to errors, and `--editor --quit`
catches that whole class at load. It does not catch everything: a standalone
ternary is reported by `GDScript::reload` only in a real windowed session, so
the first anyone hears of it is a warning on someone's screen. Neither
`--check-only --script` (which cannot resolve the autoloads) nor the editor
pass sees it. This does.

It also carries a few checks for faults the editor pass *does* catch but only
after a two minute load: an integer division promoted to an error, a local that
shadows a class member, a local declared twice in one block, and a `static` left
dangling by an edit. Each of those cost a full test run to find. Catching them
here costs a second.

The editor pass remains authoritative. This is the fast half of it.

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


# `a.size() / 2` is an integer division and the project promotes that warning to
# an error. Only the literal-divisor shape is looked for, because without types
# there is no telling `a / b` apart from a float one -- and this shape is the one
# that keeps happening: a count divided by a constant to get a mean or a third.
# The accessors that return an int. `length()` is deliberately absent:
# `String.length()` is an int and `Vector3.length()` is not, and a check
# that cries wolf on every vector is a check people turn off.
INT_ACC = r"size|get_width|get_height|get_child_count|get_surface_count"
INT_DIV = re.compile(
    r"(?:\.(?:" + INT_ACC + r")\(\)|\blen\([^()]*\))\s*/\s*[0-9]+(?![0-9.])")

CLASS_VAR = re.compile(r"^(?:@\w+\s+)*(?:static\s+)?var\s+(\w+)")
FUNC_DEF = re.compile(r"^(?:static\s+)?func\s+(\w+)")
LOCAL_VAR = re.compile(r"(?:^|[^.\w])var\s+(\w+)")


def _code(line):
    """The line with any trailing comment and string bodies removed."""
    out = []
    quote = ""
    prev = ""
    for ch in line:
        if quote:
            if ch == quote and prev != "\\":
                quote = ""
            prev = ch
            continue
        if ch in "\"'":
            quote = ch
            out.append(" ")
        elif ch == "#":
            break
        else:
            out.append(ch)
        prev = ch
    return "".join(out)


def _indent(line):
    return len(line) - len(line.lstrip("\t "))


def structure(path):
    """Integer divisions, shadowed and redeclared locals, and dangling `static`."""
    out = []
    lines = open(path, encoding="utf-8").read().split("\n")
    members = set()
    for line in lines:
        if _indent(line) == 0:
            m = CLASS_VAR.match(_code(line))
            if m:
                members.add(m.group(1))
    # One pass per function body, so a name may repeat between functions.
    locals_here = {}
    inner = False
    in_shader = False
    for n, line in enumerate(lines, 1):
        code = _code(line)
        stripped = line.strip()
        if stripped.startswith("const ") and stripped.endswith('"""'):
            in_shader = True
            continue
        if in_shader:
            if stripped == '"""':
                in_shader = False
            continue
        if not stripped:
            continue
        if code.strip() == "static":
            out.append((n, "a `static` with nothing after it on the line",
                        stripped))
        # `@warning_ignore("integer_division")` is the engine's own way of
        # saying the remainder is meant to go, so it is this one's too --
        # whether it sits on the line or on the one above it.
        # Looked for over the few lines above, not just the one: a wrapped
        # expression puts the division several lines below its annotation.
        prev = " ".join(lines[max(0, n - 4):n - 1])
        waived = "integer_division" in stripped or "integer_division" in prev
        if INT_DIV.search(code) and not waived:
            out.append((n, "integer division — the decimal part is discarded; "
                        "say so with @warning_ignore(\"integer_division\") "
                        "if it is meant", stripped))
        if _indent(line) == 0:
            # A declaration at the top of the file is the class's own, not a
            # local shadowing it, and an inner class carries its members one
            # level in -- those are not locals either.
            locals_here = {}
            inner = code.strip().startswith("class ")
            continue
        if inner and _indent(line) <= 1:
            continue
        # Leaving a block retires the names declared in it. Checked on every
        # line, not only on the ones that declare something: two `if` arms of
        # the same `match` may each declare `var res`, and what says they are
        # different blocks is the `if` between them, which declares nothing.
        for k in list(locals_here):
            if _indent(line) <= locals_here[k][0] - 1:
                locals_here[k] = (locals_here[k][0], True)
        m = LOCAL_VAR.search(code)
        if not m:
            continue
        name = m.group(1)
        ind = _indent(line)
        if name in members:
            out.append((n, "`%s` shadows a variable of the same name on the "
                        "class" % name, stripped))
        seen = locals_here.get(name)
        # Declared twice with nothing less indented between them: the same
        # block, which Godot rejects. A lower indent in between means the two
        # are in sibling branches, where it is allowed.
        if seen is not None and seen[0] == ind and not seen[1]:
            out.append((n, "`%s` is declared twice in this block" % name,
                        stripped))
        locals_here[name] = (ind, False)
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
            rel = os.path.relpath(path, ROOT)
            for n, text in check(path):
                print("%s:%d  standalone ternary — the value is discarded" % (rel, n))
                print("        %s" % text)
                faults += 1
            for n, why, text in structure(path):
                print("%s:%d  %s" % (rel, n, why))
                print("        %s" % text)
                faults += 1
    print("[lint] %d files scanned, %d fault(s)" % (scanned, faults))
    return 1 if faults else 0


if __name__ == "__main__":
    sys.exit(main())
