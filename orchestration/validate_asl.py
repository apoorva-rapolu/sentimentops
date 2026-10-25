#!/usr/bin/env python3
"""Offline sanity check for the Step Functions definition (no AWS needed).

Checks: valid JSON, StartAt exists, every Next/Default/Catch target exists,
every state is reachable, Task/Pass states have a Next or End, and the only
${...} placeholder is ${lambda_function_name} (filled in by Terraform).

    python orchestration/validate_asl.py [path]
"""
import json
import re
import sys
from pathlib import Path

path = Path(sys.argv[1] if len(sys.argv) > 1 else "orchestration/state_machine.asl.json")
text = path.read_text(encoding="utf-8")
errors = []

try:
    sm = json.loads(text)
except json.JSONDecodeError as exc:
    sys.exit(f"INVALID JSON in {path}: {exc}")

unknown = set(re.findall(r"\$\{(\w+)\}", text)) - {"lambda_function_name"}
if unknown:
    errors.append(f"unexpected template placeholders: {sorted(unknown)}")

states = sm.get("States", {})
if sm.get("StartAt") not in states:
    errors.append(f"StartAt {sm.get('StartAt')!r} is not a state")


def targets(node):
    out = []
    if "Next" in node:
        out.append(node["Next"])
    if "Default" in node:
        out.append(node["Default"])
    out += [c["Next"] for c in node.get("Choices", []) if "Next" in c]
    out += [c["Next"] for c in node.get("Catch", [])]
    return out


for name, node in states.items():
    kind = node.get("Type")
    if kind in ("Task", "Pass", "Wait") and "Next" not in node and not node.get("End"):
        errors.append(f"{name}: {kind} state has neither Next nor End")
    for t in targets(node):
        if t not in states:
            errors.append(f"{name}: points to missing state {t!r}")

seen, stack = set(), [sm.get("StartAt")]
while stack:
    cur = stack.pop()
    if cur in seen or cur not in states:
        continue
    seen.add(cur)
    stack += targets(states[cur])
for name in sorted(set(states) - seen):
    errors.append(f"{name}: unreachable")

if errors:
    print("\n".join(f"ERROR: {e}" for e in errors))
    sys.exit(1)
print(f"OK: {len(states)} states, all reachable, all targets exist ({path})")
