#!/usr/bin/python3
"""Prepare approved overlay changes offscreen and publish them in a short batch.

Called under overlay-clones.sh's mutation lock. Refresh preserves clone IDs
and shell configuration. Selection changes update the configuration once.
Omarchy's plugin watcher can coalesce publication within its 150 ms debounce.
"""
import ctypes
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import sys
import tempfile
import copy


def signature(directory):
    """Include every path and byte, including manifests ignored by patch hashes."""
    directory = Path(directory)
    if directory.is_symlink() or not directory.is_dir():
        raise ValueError(f"Not an ordinary clone directory: {directory}")
    digest = hashlib.sha256()
    for path in sorted(directory.rglob("*")):
        mode = path.lstat().st_mode
        if not (stat.S_ISREG(mode) or stat.S_ISDIR(mode)):
            raise ValueError(f"Unexpected file type in clone: {path}")
        digest.update(os.fsencode(path.relative_to(directory)))
        digest.update(b"\0" + str(mode).encode() + b"\0")
        if stat.S_ISREG(mode):
            digest.update(hashlib.sha256(path.read_bytes()).digest())
    return digest.hexdigest()


def stage(builtin, live, staged):
    builtin, live, staged = map(Path, (builtin, live, staged))
    before = signature(live) if live.exists() or live.is_symlink() else None
    manifest = json.loads((builtin / "manifest.json").read_text())
    source_id = "omarchy." + builtin.name
    if manifest.get("id") != source_id or manifest.get("omarchy", {}).get("clonePaths"):
        raise ValueError(f"Unsupported built-in clone manifest: {builtin}")
    # Same manifest transformation as Omarchy's clone command. Only these
    # already approved built-ins are supplied by overlay-clones.sh.
    manifest["id"] = live.name
    manifest["name"] = "My " + manifest.get("name", source_id)
    if isinstance(manifest.get("barWidget"), dict):
        manifest["barWidget"]["displayName"] = manifest["name"]
    manifest.setdefault("omarchy", {})["clonedFrom"] = source_id
    shutil.copytree(builtin, staged)
    (staged / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return {"live": str(live), "staged": str(staged), "before": before,
            "operation": "replace" if before is not None else "add"}


def rename_pair(first, second, flags):
    # Linux renameat2 exchanges directories without a moment where the live
    # path is absent. Do not fall back to remove-then-copy on unsupported FSs.
    libc = ctypes.CDLL(None, use_errno=True)
    rename = libc.renameat2
    rename.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
    rename.restype = ctypes.c_int
    if rename(-100, os.fsencode(first), -100, os.fsencode(second), flags):
        error = ctypes.get_errno()
        raise OSError(error, os.strerror(error), str(first))


def exchange(first, second):
    rename_pair(first, second, 2)


def move_new(first, second):
    rename_pair(first, second, 1)  # RENAME_NOREPLACE


def configured(config, records):
    """Mirror Omarchy's clone enable/restore semantics for our six overlays."""
    config = copy.deepcopy(config)
    if not isinstance(config, dict) or config.get("version") != 1:
        raise ValueError("Unsupported shell configuration version")
    bar = config.setdefault("bar", {}).setdefault("layout", {})
    for section in ("left", "center", "right"):
        bar.setdefault(section, [])
        if not isinstance(bar[section], list):
            raise ValueError("Invalid bar layout")
    plugins = config.setdefault("plugins", [])
    disabled = config.setdefault("disabledPlugins", [])
    restores = config.setdefault("cloneSourceRestores", [])
    if not all(isinstance(value, list) for value in (plugins, disabled, restores)):
        raise ValueError("Invalid plugin configuration")
    def entry_id(entry):
        return entry.get("id") if isinstance(entry, dict) else entry
    for record in records:
        operation = record.get("operation", "replace")
        if operation == "replace":
            continue
        clone = Path(record["live"]).name
        source = "omarchy." + clone.rsplit(".", 1)[1]
        if operation == "add":
            manifest = json.loads(Path(record["staged"], "manifest.json").read_text())
            if clone in disabled:
                disabled.remove(clone)
            present = any(entry_id(e) == clone for entries in (bar[s] for s in ("left", "center", "right")) for e in entries) or any(entry_id(e) == clone for e in plugins)
            if not present and "bar-widget" in manifest["kinds"]:
                found = False
                for entries in (bar[s] for s in ("left", "center", "right")):
                    for index, entry in enumerate(entries):
                        if entry_id(entry) == source:
                            entries[index] = dict(entry, id=clone) if isinstance(entry, dict) else {"id": clone}
                            found = True
                            break
                    if found:
                        break
                if not found:
                    section = manifest.get("barWidget", {}).get("defaultSection", "center")
                    if section not in bar:
                        raise ValueError("Invalid default bar section")
                    anchor = {"left": "omarchy.workspaces", "center": "omarchy.weather", "right": "omarchy.tray"}[section]
                    at = next((i + 1 for i, e in enumerate(bar[section]) if entry_id(e) == anchor), len(bar[section]))
                    bar[section].insert(at, {"id": clone})
            elif not present:
                plugins.append({"id": clone})
            if source not in disabled:
                disabled.append(source)
                if clone not in restores:
                    restores.append(clone)
        elif operation == "remove":
            has_bar = any(entry_id(e) == clone for entries in (bar[s] for s in ("left", "center", "right")) for e in entries)
            for section in ("left", "center", "right"):
                entries = bar[section]
                if has_bar:
                    entries = [e for e in entries if entry_id(e) != source]
                    entries = [dict(e, id=source) if isinstance(e, dict) and e.get("id") == clone else {"id": source} if e == clone else e for e in entries]
                    bar[section] = entries
            plugins[:] = [e for e in plugins if entry_id(e) != clone]
            if clone in restores and source in disabled:
                disabled.remove(source)
            restores[:] = [e for e in restores if e != clone]
            disabled[:] = [e for e in disabled if e != clone]
        else:
            raise ValueError("Unknown overlay operation")
    for key in ("disabledPlugins", "cloneSourceRestores"):
        if not config[key]:
            del config[key]
    return config


def apply(records, config_path, defaults_path):
    """Publish additions/removals and one config write, rolling back errors."""
    if not records:
        return
    config_path = Path(config_path)
    if config_path.is_symlink():
        raise ValueError("Refusing to replace a symlinked shell configuration")
    before = config_path.read_bytes() if config_path.exists() else None
    original = json.loads(before if before is not None else Path(defaults_path).read_bytes())
    updated = configured(original, records)
    if len({r["live"] for r in records}) != len(records):
        raise ValueError("Duplicate overlay operation")
    for r in records:
        live, staged = Path(r["live"]), Path(r["staged"])
        current = signature(live) if live.exists() or live.is_symlink() else None
        if current != r["before"]:
            raise ValueError(f"Clone changed while preparing: {live}")
        if r["operation"] == "add":
            if not (staged / ".ragtop-base").is_file():
                raise ValueError(f"Unpatched clone: {staged}")
            signature(staged)
        elif r["operation"] == "remove" and staged.exists():
            raise ValueError(f"Backup already exists: {staged}")
    config_path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".ragtop-shell.", dir=config_path.parent)
    temporary = Path(temporary)
    with os.fdopen(fd, "w") as out:
        json.dump(updated, out, indent=2, ensure_ascii=False)
        out.write("\n")
        out.flush()
        os.fsync(out.fileno())
    os.chmod(temporary, stat.S_IMODE(config_path.stat().st_mode) if before is not None else 0o600)
    completed = []
    cleanup = False
    config_written = False
    try:
        if (config_path.read_bytes() if config_path.exists() else None) != before:
            raise ValueError("Shell settings changed while preparing; retry")
        for r in records:
            if r["operation"] == "add":
                move_new(r["staged"], r["live"])
            else:
                move_new(r["live"], r["staged"])
            completed.append(r)
        if before is None:
            move_new(temporary, config_path)
        else:
            exchange(temporary, config_path)
        config_written = True
        if before is not None and temporary.read_bytes() != before:
            raise ValueError("Shell settings changed during publication; retry")
        for r in records:
            if r["operation"] == "remove" and signature(r["staged"]) != r["before"]:
                raise ValueError("Clone changed during removal")
    except Exception:
        if config_written:
            if before is None:
                move_new(config_path, temporary)
            else:
                exchange(temporary, config_path)
        for r in reversed(completed):
            if r["operation"] == "add":
                move_new(r["live"], r["staged"])
            else:
                move_new(r["staged"], r["live"])
        cleanup = True
        raise
    else:
        cleanup = True
    finally:
        if cleanup:
            temporary.unlink(missing_ok=True)


def publish(records):
    if len({r["live"] for r in records}) != len(records):
        raise ValueError("Duplicate overlay in publication batch")
    for record in records:
        if signature(record["live"]) != record["before"]:
            raise ValueError(f"Clone changed while preparing: {record['live']}")
        staged = Path(record["staged"])
        if not (staged / ".ragtop-base").is_file():
            raise ValueError(f"Replacement was not patched: {staged}")
        signature(staged)  # Also reject symlinks and special files in replacements.
    completed = []
    try:
        for record in records:
            exchange(record["live"], record["staged"])
            completed.append(record)
        # Catch external edits racing preparation/publication. Old copies
        # now live at the staging paths and remain available as backups.
        for record in completed:
            if signature(record["staged"]) != record["before"]:
                raise ValueError(f"Clone edited during publication: {record['live']}")
    except Exception:
        for record in reversed(completed):
            exchange(record["live"], record["staged"])
        raise


def main():
    if sys.argv[1] == "stage" and len(sys.argv) == 5:
        print(json.dumps(stage(*sys.argv[2:])))
    elif sys.argv[1] == "remove" and len(sys.argv) == 4:
        print(json.dumps({"live": sys.argv[2], "staged": sys.argv[3],
                          "before": signature(sys.argv[2]), "operation": "remove"}))
    elif sys.argv[1] == "apply":
        apply([json.loads(arg) for arg in sys.argv[4:]], sys.argv[2], sys.argv[3])
    elif sys.argv[1] == "publish":
        publish([json.loads(arg) for arg in sys.argv[2:]])
    else:
        raise ValueError("Usage: overlay-publish.py stage <builtin> <live> <staged> | publish <records...>")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, AttributeError) as error:
        sys.exit(f"Overlay batch not published: {error}")
