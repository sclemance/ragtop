"""Copies named members of Service.qml's root, as written, into the typing
memory harness: extract.py <Service.qml> <shell.qml.in> <out>. Taken from the
real file every run, so the test follows the code rather than a copy of it.

A member is a line indented two spaces that declares one of NAMES (a
property, a function, an on-handler, or a Timer by its id), with every line
after it indented further, and the closing brace back at two spaces."""
import re
import sys

NAMES = [
    "fieldInfo", "fieldShown", "fieldHidden", "fieldReported", "fieldPending", "pendingTyped", "fieldPendingLimit",
    "secretField", "onSecretFieldChanged",
    "typingMemory", "fieldKnown", "keepAnything", "keepWord", "keepContext",
    "onKeepAnythingChanged", "onTypingMemoryChanged", "forgetField", "dropTyped",
    "typedTail", "typedCursor", "beforeCursor", "typedFromStart", "sentenceStart",
    "isWordChar", "noteTyped", "freshField", "freshFieldAt", "fieldGeneration",
    "predicting", "onPredictingChanged", "trackWord", "currentWord", "swipedWord", "autoSpaced", "hyphenJoined",
    "finished", "finishedFormsAsked", "setFinished", "joinFirst", "joinPair", "joinOffer",
    "asked", "formsAsked", "joinAsked", "termAsked", "nextAsked", "nextWords", "nextArrived",
    "sentContext", "contextNow", "updateContext", "wordsBefore", "backSpaceDownAt",
]

DECLARES = re.compile(r"^  (?:readonly )?(?:property \S+ (\w+)\b|function (\w+)\(|(on\w+):)")


def members(lines):
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
        if name not in NAMES:
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
    service, template, out = sys.argv[1:]
    found = members(open(service, encoding="utf-8").read().split("\n"))
    missing = [n for n in NAMES if n not in found]
    if missing:
        sys.exit("not found in Service.qml: " + ", ".join(missing))
    text = open(template, encoding="utf-8").read()
    text = text.replace("  // SERVICE MEMBERS\n", "\n".join(found[n] for n in NAMES) + "\n")
    open(out, "w", encoding="utf-8").write(text)


main()
