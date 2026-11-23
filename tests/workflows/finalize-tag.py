#!/usr/bin/env python3
"""Checks that every workflow step that runs scripts/finalize.sh sets TAG in its env. Without TAG, finalize.sh takes the only draft
release layers-* and fails when there are several (Layers finalize, run 45144164837: "Expected exactly one draft release layers-*,
found 2"). TAG may be empty (finalize.sh then takes the only draft), but it must be passed, so that the input tag of the run is used.
Usage: finalize-tag.py workflow.yml...   Standard library only: a step is the block from its "- " line to the next line at the same or
a smaller indentation."""
import re, sys


def steps(lines):
    """(first line number, lines) of each list item under a "steps:" key."""
    i = 0
    while i < len(lines):
        m = re.match(r'^(\s*)steps:\s*$', lines[i])
        if not m:
            i += 1
            continue
        base = len(m.group(1))
        i += 1
        while i < len(lines):
            line = lines[i]
            indent = len(line) - len(line.lstrip())
            if line.strip() and indent <= base:
                break
            if re.match(r'^\s*- ', line):
                start, item_indent = i, indent
                i += 1
                while i < len(lines) and (not lines[i].strip() or len(lines[i]) - len(lines[i].lstrip()) > item_indent):
                    i += 1
                yield start + 1, lines[start:i]
            else:
                i += 1


def main():
    problems, count = [], 0
    for path in sys.argv[1:]:
        with open(path, encoding='utf-8') as f:
            lines = f.read().splitlines()
        for number, step in steps(lines):
            code = [l for l in step if not l.lstrip().startswith('#')]
            if not any('scripts/finalize.sh' in l for l in code):
                continue
            count += 1
            if not any(re.match(r'^\s+TAG:\s*\S', l) for l in code):
                problems.append('%s:%d: the step runs scripts/finalize.sh without TAG in its env' % (path, number))
    print('%d step(s) run scripts/finalize.sh' % count)
    if not count:
        problems.append('no step runs scripts/finalize.sh; the check finds nothing')
    if problems:
        sys.exit('\n'.join(problems))
    print('every one of them passes TAG')


if __name__ == '__main__':
    main()
