#!/usr/bin/env python3
"""Check SwiftUI memberwise-init call sites against declaration order.

WHY THIS EXISTS

Swift synthesizes a struct's memberwise `init` with parameters in *declaration*
order, so a call's argument labels must appear in that same order. Adding a
property at the *end* of a struct and passing it in the *middle* of a call is a
compile error:

    Incorrect argument labels in call
    (have 'points:metric:accessibilityTitle:average:valueLabel:',
     expected 'points:metric:average:compact:valueLabel:...:accessibilityTitle:')

That is a real error this repo shipped to CI, and CI is a macOS runner billed at
10x. This script catches that class of mistake on Linux, where there is no Swift
compiler, for free.

USAGE

    python3 scripts/check_memberwise_order.py            # checks the defaults
    python3 scripts/check_memberwise_order.py Foo Bar    # checks named structs

Exits non-zero on a mismatch, printing the call and the declaration order.

SCOPE AND LIMITS

This is a regex-based reader, not a Swift parser. It understands the shapes this
codebase actually uses and will be confused by anything exotic. It is therefore
**not wired into CI** — a heuristic should not be able to block a merge, and CI
has a real compiler. Run it before pushing; treat a failure as a real problem
and a pass as encouraging rather than conclusive.
"""
import re, sys, pathlib

ROOT = pathlib.Path('.')
SRC = [p for d in ('Shared','FuelTracker','FuelTrackerWatch','FuelTrackerTests')
       for p in ROOT.joinpath(d).rglob('*.swift')]

def stored_properties(body: str):
    props, depth = [], 0
    for line in body.splitlines():
        stripped = line.strip()
        # only top-level (4-space) declarations count as stored properties
        m = re.match(r'^\s{4}(let|var)\s+([A-Za-z_]\w*)\s*(:[^=\{]*)?(=|$)', line)
        opens = line.count('{') - line.count('}')
        if depth == 0 and m:
            rest = line.split(m.group(2),1)[1]
            # computed properties have a `{` before any `=`
            if '{' in rest.split('=')[0]:
                depth += opens
                continue
            props.append(m.group(2))
        depth += opens
        if depth < 0: depth = 0
    return props

def struct_bodies(text):
    out = {}
    for m in re.finditer(r'^(?:public )?struct (\w+)[^{]*\{', text, re.M):
        name, start = m.group(1), m.end()
        depth, i = 1, start
        while i < len(text) and depth:
            if text[i] == '{': depth += 1
            elif text[i] == '}': depth -= 1
            i += 1
        out[name] = text[start:i]
    return out

decls = {}
for p in SRC:
    for name, body in struct_bodies(p.read_text()).items():
        decls.setdefault(name, stored_properties(body))

TARGETS = sys.argv[1:] or ['MetricLineChart', 'MonthlyBarChart']
failures = 0
for p in SRC:
    text = p.read_text()
    for target in TARGETS:
        for m in re.finditer(re.escape(target) + r'\(', text):
            i, depth, start = m.end(), 1, m.end()
            while i < len(text) and depth:
                if text[i] == '(': depth += 1
                elif text[i] == ')': depth -= 1
                i += 1
            call = text[start:i-1]
            # top-level labels only
            labels, d = [], 0
            for tok in re.finditer(r'[(\[{]|[)\]}]|([A-Za-z_]\w*)\s*:', call):
                t = tok.group(0)
                if t in '([{': d += 1
                elif t in ')]}': d -= 1
                elif d == 0 and tok.group(1): labels.append(tok.group(1))
            order = decls.get(target, [])
            pos, ok = -1, True
            for lab in labels:
                if lab not in order: ok = False; break
                idx = order.index(lab)
                if idx <= pos: ok = False; break
                pos = idx
            line_no = text[:m.start()].count('\n') + 1
            if not ok:
                failures += 1
                print(f"  MISMATCH {p}:{line_no}\n    call  : {':'.join(labels)}:\n    decl  : {':'.join(order)}:")
            else:
                print(f"  ok {p}:{line_no}  {':'.join(labels)}:")

print()
for t in TARGETS:
    print(f"declaration order — {t}: {':'.join(decls.get(t,[]))}:")
print()
print("FAILURES:", failures)
sys.exit(1 if failures else 0)
