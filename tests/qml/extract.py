"""Copies named members of a QML file's root, as written, into a test
harness: extract.py <source.qml> <shell.qml.in> <out>. Taken from the real
file every run, so the test follows the code rather than a copy of it.

The template names what it wants on a line of its own,
  // FROM SOURCE: name name ...
(as many such lines as it likes), and the members go where that first line
was. A member is a line indented two spaces that declares one of the names
(a property, a function, an on-handler, or a Timer by its id), with every
line after it indented further, and the closing brace back at two spaces."""
import re
import sys

DECLARES = re.compile(r"^  (?:readonly )?(?:property \S+ (\w+)\b|function (\w+)\(|(on\w+):)")


def members(lines, names):
    found = {}
    i = 0
    while i < len(lines):
        line = lines[i]
        name = None
        m = DECLARES.match(line)
        if m:
            name = next(g for g in m.groups() if g)
        elif line == "  Timer {" and i + 1 < len(lines):
            t = re.match(r"^    id: (\w+)$", lines[i + 1])
            name = t.group(1) if t else None
        if name not in names:
            i += 1
            continue
        j = i + 1
        while j < len(lines):
            nxt = lines[j]
            if nxt.strip() == "":
                k = j
                while k < len(lines) and lines[k].strip() == "":
                    k += 1
                if k < len(lines) and len(lines[k]) - len(lines[k].lstrip()) > 2:
                    j = k
                    continue
                break
            indent = len(nxt) - len(nxt.lstrip())
            if indent > 2:
                j += 1
                continue
            if indent == 2 and nxt.strip().startswith("}"):
                j += 1
            break
        found[name] = "\n".join(lines[i:j])
        i = j
    return found


def main():
    source, template, out = sys.argv[1:]
    text = open(template, encoding="utf-8").read()
    wanted = re.findall(r"^  // FROM SOURCE: (.*)\n", text, re.M)
    names = [n for line in wanted for n in line.split()]
    found = members(open(source, encoding="utf-8").read().split("\n"), names)
    missing = [n for n in names if n not in found]
    if missing:
        sys.exit("not found in " + source + ": " + ", ".join(missing))
    first = True
    def place(_):
        nonlocal first
        if not first:
            return ""
        first = False
        return "\n".join(found[n] for n in names) + "\n"
    text = re.sub(r"^  // FROM SOURCE: .*\n", place, text, flags=re.M)
    open(out, "w", encoding="utf-8").write(text)


main()
