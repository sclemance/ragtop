#!/bin/bash
# Ragtop's own catalogs (i18n/<code>/{shell,cli,menu}.json): every key the
# code asks for is in English, every language carries exactly English's keys
# with the same placeholders and plural forms, and the English menu catalog
# is the menu rows the code writes. A missing key shows as the key itself on
# screen, and a dropped %1 loses a value, so neither reaches a release.
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

make_sandbox "$old_omarchy"

check() {
  out=$(catalog_check "$1" 2>&1) || true
}

catalog_check() {
  /usr/bin/python3 - "$repo" "$1" <<'PY'
import json, os, re, sys
repo, what = sys.argv[1:]
i18n = os.path.join(repo, "i18n")
problems = []

def load(code, name):
    path = os.path.join(i18n, code, name)
    try:
        return json.load(open(path, encoding="utf-8"))
    except FileNotFoundError:
        return None
    except ValueError as e:
        problems.append(f"{code}/{name}: not JSON: {e}")
        return {}

def tokens(text):
    return sorted(set(re.findall(r"%\d+", text))) if isinstance(text, str) else None

# The plural forms each language's pluralForm() can ask for; every language
# Ragtop has so far picks between one and other.
FORMS = {}
def forms(code):
    return FORMS.get(code, ("one", "other"))

if what == "used":
    # Literal keys in the code: t("key" in QML, t key in the scripts, the
    # tour's titles and the wizard's steps, which are keys held as data.
    shell = load("en", "shell.json") or {}
    cli = load("en", "cli.json") or {}
    for f in sorted(os.listdir(repo)):
        path = os.path.join(repo, f)
        if not os.path.isfile(path):
            continue
        text = open(path, encoding="utf-8", errors="replace").read()
        if f.endswith(".qml"):
            keys = re.findall(r'\bt[n]?\("([a-zA-Z][\w.-]*)"', text)
            keys += re.findall(r'title: "(tour\.[\w.-]+)"', text)
            keys += re.findall(r'"(setup\.step\.[\w-]+)"', text)
            keys += re.findall(r'label: "(picker\.[\w-]+)"', text)
            # The setup wizard's lists hold keys, translated where shown.
            keys += re.findall(r'(?:need|label|detail): "(setup\.[\w.-]+)"', text)
            for k in keys:
                # A key put together at run time, "trouble." + name: its full
                # forms are English's own, which parity holds languages to.
                if k.endswith("."):
                    continue
                if k not in shell:
                    problems.append(f"{f}: {k} is not in en/shell.json")
        elif f in ("ragtop", "install.sh", "overlay-clones.sh", "setup-check.sh", "setup-apply.sh"):
            for k in re.findall(r'(?:\$\(|\btell |^\s*|\|\| )t "?([a-zA-Z][\w.-]*[\w])"?(?=[ "\n)])', text, re.M):
                if k not in cli:
                    problems.append(f"{f}: {k} is not in en/cli.json")
elif what == "parity":
    for code in sorted(os.listdir(i18n)):
        if code == "en" or not os.path.isdir(os.path.join(i18n, code)):
            continue
        for name in ("shell.json", "cli.json", "menu.json"):
            en, tr = load("en", name), load(code, name)
            if tr is None:
                problems.append(f"{code}/{name} is missing")
                continue
            for k in sorted(set(en) - set(tr)):
                problems.append(f"{code}/{name}: no {k}")
            for k in sorted(set(tr) - set(en)):
                problems.append(f"{code}/{name}: {k} is not an English key")
            for k in sorted(set(en) & set(tr)):
                a, b = en[k], tr[k]
                if name == "menu.json":
                    a, b = a.get("label", ""), b.get("label", "") if isinstance(b, dict) else ""
                if isinstance(a, dict) != isinstance(b, dict):
                    problems.append(f"{code}/{name}: {k} is plural in one and not the other")
                elif isinstance(b, dict):
                    # Every form the language asks for, each with English's
                    # placeholders: a form may leave out the count ("un mot")
                    # but never lose or invent anything else.
                    want = tokens(a.get("other"))
                    for form in forms(code):
                        got = tokens(b.get(form))
                        if not b.get(form):
                            problems.append(f"{code}/{name}: {k} has no {form} form")
                        elif got != want and not (form != "other" and set(want) - set(got) == {"%1"} and set(got) < set(want)):
                            problems.append(f"{code}/{name}: {k}.{form} has placeholders {got}, English {want}")
                elif tokens(a) != tokens(b):
                    problems.append(f"{code}/{name}: {k} has placeholders {tokens(b)}, English {tokens(a)}")
                elif not b:
                    problems.append(f"{code}/{name}: {k} is empty")
print("\n".join(problems))
sys.exit(1 if problems else 0)
PY
}

every_key_used_is_english() {
  check used
  [[ -z $out ]] || fail "$out"
}

every_language_matches_english() {
  check parity
  [[ -z $out ]] || fail "$out"
}

the_menu_catalog_is_the_menu() {
  local now
  now=$(bash "$repo/menu-block.sh" english)
  [[ $now == "$(cat "$repo/i18n/en/menu.json")" ]] \
    || fail "i18n/en/menu.json is not what menu-block.sh writes: run menu-block.sh english > i18n/en/menu.json"
}

# The installer and scripts say nothing in English when another language is
# set and has the string, and fall back to English when it does not.
the_scripts_follow_the_language() {
  local home="$sandbox/home"
  mkdir -p "$home/.config/omarchy" "$sandbox/lang/i18n/en" "$sandbox/lang/i18n/xx"
  cp "$repo/i18n.sh" "$sandbox/lang/"
  printf '{"a": "one %%1", "b": "two"}\n' >"$sandbox/lang/i18n/en/cli.json"
  printf '{"a": "un %%1"}\n' >"$sandbox/lang/i18n/xx/cli.json"
  printf 'xx\n' >"$home/.config/omarchy/language"
  out=$(HOME="$home" XDG_CONFIG_HOME= bash -c 'repo="$1"; source "$repo/i18n.sh"; t a 5; t b; t c' _ "$sandbox/lang")
  assert_equal "$out" $'un 5\ntwo\nc' "a translation, English for what it lacks, the key for neither"
}

run_test "i18n: every key the code asks for is in English" every_key_used_is_english
run_test "i18n: every language has English's keys, placeholders and plurals" every_language_matches_english
run_test "i18n: the English menu catalog is the menu rows the code writes" the_menu_catalog_is_the_menu
run_test "i18n: the scripts speak the language set, English where it has nothing" the_scripts_follow_the_language
finish
