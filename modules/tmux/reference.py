#!/usr/bin/env python3
"""Tmux reference data and terminal rendering. Standard library only; never eval shell text."""

import argparse
import gzip
import hashlib
import json
import os
import re
import shlex
import shutil
import string
import subprocess
import sys
import tempfile
import textwrap
from pathlib import Path

RESET = "\033[0m"
PALETTE = {
    "name": "38;5;81",
    "value": "38;5;150",
    "scope": "38;5;180",
    "key": "1;38;5;222",
    "changed": "1;38;5;215",
    "dim": "38;5;245",
    "title": "1;38;5;111",
    "flag": "38;5;176",
}
TOGGLES = set(os.environ.get("FZX_TOGGLES", "").split())
KEY_FORMAT = "#{key_table}\t#{key_string}\t#{key_repeat}\t#{key_note}\t#{key_command}"


def clean(value):
    return re.sub(
        r"[\x00-\x1f\x7f]",
        lambda m: {"\n": "\\n", "\t": "    ", "\r": "\\r"}.get(m[0], ""),
        str(value),
    )


def paint(value, role):
    code = os.environ.get("FZX_TMUX_COLOR_" + role.upper(), PALETTE[role])
    return (
        f"\033[{code}m{clean(value)}{RESET}"
        if re.fullmatch(r"[0-9;]+", code)
        else clean(value)
    )


def tmux(*args, optional=False):
    result = subprocess.run(
        ["tmux", *args], text=True, capture_output=True, check=False
    )
    if result.returncode and not optional:
        raise RuntimeError(result.stderr.strip() or "tmux command failed")
    return result.stdout if result.returncode == 0 else ""


def target(pane):
    return ["-t", pane] if pane else []


def cache_dir():
    return (
        Path(
            os.environ.get(
                "FZX_CACHE_DIR",
                str(
                    Path(os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache")))
                    / "fzx"
                ),
            )
        )
        / "tmux-reference"
    )


def cached(name, stamp, build):
    """An atomic cache per binary/manual version; simultaneous callbacks do not share temp files."""
    path = cache_dir() / (
        name + "-" + hashlib.sha256(stamp.encode()).hexdigest()[:20] + ".json"
    )
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        pass
    value = build()
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(
            mode="w", dir=path.parent, delete=False
        ) as stream:
            json.dump(value, stream)
        os.replace(stream.name, path)
    except OSError:
        pass
    return value


def manual():
    if not shutil.which("man"):
        return {"text": "", "variables": {}}
    located = subprocess.run(
        ["man", "-w", "tmux"], capture_output=True, text=True, check=False
    )
    path = (
        Path(located.stdout.strip().splitlines()[0]) if located.stdout.strip() else None
    )
    stamp = "v1:" + str(path)
    if path and path.exists():
        stamp += ":" + str(path.stat().st_mtime_ns)

    def build():
        env = os.environ | {"MANWIDTH": "120", "MANPAGER": "cat", "PAGER": "cat"}
        result = subprocess.run(
            ["man", "tmux"], env=env, capture_output=True, text=True, check=False
        )
        text = re.sub(r".\x08", "", result.stdout).expandtabs(8)
        variables = {}
        if path and path.exists():
            read = gzip.open if path.suffix == ".gz" else open
            with read(path, "rt", errors="replace") as stream:
                for line in stream:
                    if line.startswith('.It Li "') and " Ta " in line:
                        fields = re.findall(r'"([^"]*)"', line)
                        if len(fields) == 3 and re.fullmatch(
                            r"[a-z][a-z0-9_]+", fields[0]
                        ):
                            variables[fields[0]] = {
                                "alias": fields[1],
                                "description": fields[2].replace("\\-", "-"),
                            }
        return {"text": text, "variables": variables}

    return cached("manual", stamp, build)


def documentation(name):
    data = manual()
    if name in data["variables"]:
        return data["variables"][name]["description"]
    # Match definition headings, not incidental mentions in introductory paragraphs.
    base = re.sub(r"\[\d+\]$", "[]", name)
    match = re.search(
        r"^ {7}" + re.escape(base) + r"(?=\s|$).*$", data["text"], re.MULTILINE
    )
    if not match:
        return ""
    rest = data["text"][match.end() :]
    end = re.search(r"\n(?: {7}\S|[A-Z][A-Z ]+$)", rest, re.MULTILINE)
    block = rest[: end.start()] if end else rest
    return "\n\n".join(" ".join(p.split()) for p in block.split("\n\n") if p.strip())


def synopsis(text):
    return re.sub(r"\s+", " ", text).split(". ")[0][:100]


def syntax(value):
    """Highlight flags, format expressions, strings and punctuation without altering data."""
    pattern = r"#\{[^}]*\}|#\[[^]]*\]|(?<!\w)-[a-zA-Z][\w-]*|\([^)]*\)|\[[^]]*\]|\"[^\"]*\"|'[^']*'"
    result, end = "", 0
    for match in re.finditer(pattern, clean(value)):
        result += clean(value)[end : match.start()]
        role = (
            "name"
            if match[0].startswith("#{")
            else "value"
            if match[0][0] in "\"'"
            else "flag"
        )
        result += paint(match[0], role)
        end = match.end()
    return result + clean(value)[end:]


def row(identifier, display, metadata=None):
    # The first column is always plain, and metadata stays hidden from fzf's display/search.
    print(f"{identifier}\t{display}\t{json.dumps(metadata or {}, ensure_ascii=False)}")


def key_rows(raw):
    result = []
    for line in raw.splitlines():
        fields = line.split("\t", 4)
        if len(fields) == 5:
            table, key, repeat, note, command = fields
            result.append(
                {
                    "table": table,
                    "key": key,
                    "repeat": repeat == "1",
                    "note": note,
                    "command": command,
                }
            )
    return result


def read_keys():
    raw = tmux("list-keys", "-F", KEY_FORMAT, optional=True)
    if raw:
        return key_rows(raw)
    # Older tmux versions do not support list-keys -F.
    result = []
    for line in tmux("list-keys").splitlines():
        match = re.match(r"bind-key\s+(-r\s+)?-T\s+(\S+)\s+(\S+)\s+(.*)", line)
        if match:
            repeat, table, key, command = match.groups()
            result.append(
                {
                    "table": table,
                    "key": key.lstrip("\\"),
                    "repeat": bool(repeat),
                    "note": "",
                    "command": command,
                }
            )
    return result


def defaults():
    binary = shutil.which("tmux") or "tmux"
    stamp = "v2:" + binary + ":" + tmux("-V").strip()

    def build():
        # A unique socket and empty config; never a shared '_defaults' server.
        with tempfile.TemporaryDirectory(prefix="fzx-tmux-defaults-") as directory:
            socket = str(Path(directory) / "socket")
            try:
                raw = tmux(
                    "-S",
                    socket,
                    "-f",
                    "/dev/null",
                    "start-server",
                    ";",
                    "list-keys",
                    "-F",
                    KEY_FORMAT,
                    ";",
                    "kill-server",
                    optional=True,
                )
                if raw:
                    return key_rows(raw)
                raw = tmux(
                    "-S",
                    socket,
                    "-f",
                    "/dev/null",
                    "start-server",
                    ";",
                    "list-keys",
                    ";",
                    "kill-server",
                    optional=True,
                )
                result = []
                for line in raw.splitlines():
                    match = re.match(
                        r"bind-key\s+(-r\s+)?-T\s+(\S+)\s+(\S+)\s+(.*)", line
                    )
                    if match:
                        repeat, table, key, command = match.groups()
                        result.append(
                            {
                                "table": table,
                                "key": key.lstrip("\\"),
                                "repeat": bool(repeat),
                                "note": "",
                                "command": command,
                            }
                        )
                return result
            finally:
                tmux("-S", socket, "kill-server", optional=True)

    return cached("keys-defaults", stamp, build)


def keys(args):
    original = {(item["table"], item["key"]): item for item in defaults()}
    current = read_keys()
    tables = args.table.split(",") if args.table != "all" else []
    selected = [item for item in current if not tables or item["table"] in tables]
    if "unassigned" in TOGGLES:
        tables = tables or ["prefix"]
        candidates = list(string.ascii_letters + string.digits + string.punctuation)
        candidates += [
            prefix + ch for prefix in ("C-", "M-") for ch in string.ascii_lowercase
        ]
        candidates += [
            "Up",
            "Down",
            "Left",
            "Right",
            "Space",
            "Enter",
            "Escape",
            "Tab",
            "BSpace",
            "BTab",
            "DC",
            "End",
            "Home",
            "IC",
            "NPage",
            "PPage",
        ]
        candidates += [f"F{i}" for i in range(1, 13)]
        for table in tables:
            bound = {item["key"] for item in current if item["table"] == table}
            for key in candidates:
                if key not in bound:
                    row(
                        key,
                        paint(f"[{table}]", "scope")
                        + "  "
                        + paint(f"{key:16}", "key")
                        + paint("unassigned", "dim"),
                        {"table": table, "key": key, "unassigned": True},
                    )
        return
    for item in selected:
        default = original.get((item["table"], item["key"]))
        changed = default is None or any(
            item[k] != default[k] for k in ("command", "repeat")
        )
        if "changed" in TOGGLES and not changed:
            continue
        item |= {"default": default, "changed": changed}
        markers = ("*" if changed else " ") + ("+" if item["repeat"] else " ")
        label = paint(f"[{item['table']}]".ljust(16), "scope")
        note = paint(item["note"], "value") + "  " if item["note"] else ""
        display = f"{label} {paint(markers, 'changed')} {paint(item['key'].ljust(18), 'key')} {note}{syntax(item['command'])}"
        raw = (
            "bind-key "
            + ("-r " if item["repeat"] else "")
            + "-T "
            + shlex.quote(item["table"])
            + " "
            + shlex.quote(item["key"])
            + " "
            + item["command"]
        )
        row(raw, display, item)


SCOPES = {
    "server": ["-s"],
    "global-session": ["-g"],
    "global-window": ["-g", "-w"],
    "session": [],
    "window": ["-w"],
    "pane": ["-p"],
}


def parse_options(raw):
    return dict(
        line.split(" ", 1) if " " in line else (line, "")
        for line in raw.splitlines()
        if line
    )


def assignments(path):
    result = {}
    for line in Path(path).read_text().splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        match = re.match(r"^([@\w\[\]-]+)(?:\s*=\s*|\s+)(.*)$", line.strip())
        if match:
            result[match[1]] = unquote(match[2])
    return result


def option_data(args, hooks=False):
    if args.options_file:
        return {"file": assignments(args.options_file)}
    data = {}
    for scope, flags in SCOPES.items():
        if hooks and scope == "server":
            continue
        pane = target(args.pane) if scope in ("session", "window", "pane") else []
        command = "show-hooks" if hooks else "show-options"
        data[scope] = parse_options(tmux(command, *flags, *pane, optional=hooks))
    return data


def unquote(value):
    try:
        fields = shlex.split(value)
        return fields[0] if len(fields) == 1 else value
    except ValueError:
        return value


NAMED = {
    name: index
    for index, name in enumerate(
        ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"]
    )
}
ATTRS = {
    "bold": 1,
    "dim": 2,
    "italics": 3,
    "underscore": 4,
    "blink": 5,
    "reverse": 7,
    "hidden": 8,
    "strikethrough": 9,
    "overline": 53,
    "nobold": 22,
    "nodim": 22,
    "noitalics": 23,
    "nounderscore": 24,
    "noblink": 25,
    "noreverse": 27,
    "nohidden": 28,
    "nostrikethrough": 29,
}


def color(value, background=False):
    base = 48 if background else 38
    if value in ("default", "terminal"):
        return f"\033[{49 if background else 39}m"
    if re.fullmatch(r"#[0-9a-fA-F]{6}", value):
        channels = [int(value[i : i + 2], 16) for i in (1, 3, 5)]
        return f"\033[{base};2;" + ";".join(map(str, channels)) + "m"
    match = re.fullmatch(r"colou?r(\d+)", value)
    if match and int(match[1]) <= 255:
        return f"\033[{base};5;{int(match[1])}m"
    bright = value.startswith("bright")
    name = value[6:] if bright else value
    if name in NAMED:
        code = (100 if background else 90) if bright else (40 if background else 30)
        return f"\033[{code + NAMED[name]}m"
    return ""


def style(value):
    result = ""
    for part in re.split(r"[, ]+", unquote(value)):
        if part.startswith(("fg=", "bg=")):
            result += color(part[3:], part.startswith("bg="))
        elif part == "none":
            result += RESET
        elif part in ATTRS:
            result += f"\033[{ATTRS[part]}m"
    return result


def sample(value, base=""):
    result = style(base)
    pos = 0
    for match in re.finditer(r"#\[([^]]*)\]", value):
        result += clean(value[pos : match.start()])
        result += RESET + style(base) if match[1] == "default" else style(match[1])
        pos = match.end()
    return result + clean(value[pos:]) + RESET


def swatches(value):
    result = []
    for channel, shade in re.findall(r"\b(fg|bg)=([^, ]+)", value):
        ansi = color(shade)
        if ansi:
            result.append(paint(channel + " ", "dim") + ansi + "██" + RESET)
    return "  ".join(result)


def expand_format(value, args):
    if not args.data_file:
        return tmux("display-message", "-p", *target(args.pane), "--", value).rstrip(
            "\n"
        )
    variables = assignments(args.data_file)
    aliases = {
        "#S": "session_name",
        "#W": "window_name",
        "#I": "window_index",
        "#P": "pane_index",
        "#T": "pane_title",
        "#H": "host",
        "#h": "host_short",
        "#D": "pane_id",
        "#F": "window_flags",
    }
    rendered = re.sub(
        r"#\{([a-zA-Z0-9_]+)\}", lambda m: variables.get(m[1], m[0]), value
    )
    return re.sub(
        r"#[SWIPTHhDF]", lambda m: variables.get(aliases[m[0]], m[0]), rendered
    )


def options(args, mode):
    hooks = mode == "hooks"
    data = option_data(args, hooks)
    parents = {
        "session": "global-session",
        "window": "global-window",
        "pane": "global-window",
    }
    for scope, values in data.items():
        if args.option_scope != "all" and scope != args.option_scope:
            continue
        inherited = data.get(parents.get(scope), {})
        for name, raw in values.items():
            if (
                args.user_only
                and not name.startswith("@")
                or args.builtin_only
                and name.startswith("@")
            ):
                continue
            if mode == "styles" and not re.search(r"-style(?:\[|$)", name):
                continue
            if mode == "formats" and not (
                "-format" in name or name in ("status-left", "status-right")
            ):
                continue
            if mode == "status" and name not in ("status-left", "status-right"):
                continue
            override = name in inherited
            changed = scope in parents and inherited.get(name) != raw
            if "changed" in TOGGLES and not changed:
                continue
            value = unquote(raw)
            metadata = {
                "scope": scope,
                "value": value,
                "raw": raw,
                "inherited": unquote(inherited[name]) if override else None,
                "changed": changed,
                "hook": hooks,
            }
            decorated = syntax(value)
            if mode == "styles":
                decorated = (
                    style(value)
                    + " Sample "
                    + RESET
                    + "  "
                    + swatches(value)
                    + "  "
                    + syntax(value)
                )
            elif mode in ("formats", "status"):
                rendered = expand_format(value, args)
                base_name = (
                    name + "-style"
                    if name in ("status-left", "status-right")
                    else name.replace("-format", "-style")
                )
                base = next(
                    (
                        data[s][base_name]
                        for s in reversed(list(data))
                        if base_name in data[s]
                    ),
                    "",
                )
                if name in ("status-left", "status-right"):
                    status_base = next(
                        (
                            data[s]["status-style"]
                            for s in reversed(list(data))
                            if "status-style" in data[s]
                        ),
                        "",
                    )
                    base = unquote(status_base) + "," + unquote(base)
                metadata |= {"rendered": rendered, "base_style": unquote(base)}
                decorated = sample(rendered, base) + "  " + paint(value, "dim")
            mark = paint("*" if override else "+" if changed else " ", "changed")
            display = f"{paint(('[' + scope + ']').ljust(18), 'scope')} {mark} {paint(name.ljust(40), 'name')} {decorated}"
            row(name, display, metadata)


def commands(args):
    for line in tmux("list-commands").splitlines():
        match = re.match(r"(\S+)(?: \(([^)]+)\))?(.*)", line)
        if not match:
            continue
        name, alias, signature = match.groups()
        alias = alias or ""
        display = paint(name.ljust(26), "name") + " " + paint(alias.ljust(10), "dim")
        if "short" not in TOGGLES:
            display += " " + syntax(signature.strip())
        row(name, display, {"signature": line, "alias": alias})


def variables(args):
    values = (
        assignments(args.data_file)
        if args.data_file
        else dict(
            line.split("=", 1)
            for line in tmux("display-message", "-a", *target(args.pane)).splitlines()
            if "=" in line
        )
    )
    definitions = manual()["variables"]
    names = sorted(set(values) | (set(definitions) if "empty" in TOGGLES else set()))
    for name in names:
        value = values.get(name, "")
        if not value and "empty" not in TOGGLES:
            continue
        info = definitions.get(name, {})
        identifier = "#{" + name + "}"
        short_value = clean(value)
        short_value = short_value[:47] + "…" if len(short_value) > 48 else short_value
        display = (
            paint(identifier.ljust(38), "name")
            + " "
            + paint(info.get("alias", "").ljust(4), "flag")
        )
        display += (
            " "
            + paint(short_value.ljust(49), "value")
            + " "
            + paint(info.get("description", ""), "dim")
        )
        row(identifier, display, dict(value=value, **info))


def section(title, value, highlight=False):
    if value:
        print(paint(title.upper(), "title"))
        width = max(24, min(140, int(os.environ.get("FZF_PREVIEW_COLUMNS", "80"))))
        for paragraph in value.split("\n\n"):
            wrapped = textwrap.fill(clean(paragraph), width=width)
            print(
                "\n".join(syntax(line) for line in wrapped.splitlines())
                if highlight
                else wrapped
            )
            print()


def preview(args):
    info = json.loads(args.metadata or "{}")
    mode, name = args.mode, args.identifier
    print(paint(name if mode != "keys" else info.get("key", name), "title"))
    print(paint(info.get("scope", info.get("table", mode)), "scope"), "\n")
    if mode == "keys":
        if info.get("unassigned"):
            section("Unassigned", "This key is free in the selected table.")
            return
        section("Note", info.get("note", ""))
        section(
            "Current binding" + (" · repeatable" if info.get("repeat") else ""),
            info.get("command", ""),
            True,
        )
        original = info.get("default")
        section(
            "Default binding",
            original["command"] if original else "Unbound by default",
            True,
        )
        command = info.get("command", "").split(" ")[0]
        section("Command reference", documentation(command))
    else:
        if "value" in info:
            section("Current value", info["value"] or "(empty)", True)
        if info.get("inherited") is not None:
            section(
                "Parent value · overridden here", info["inherited"] or "(empty)", True
            )
        if info.get("signature"):
            section("Signature", info["signature"], True)
        if info.get("alias"):
            section("Alias", info["alias"])
        if mode == "styles":
            print(paint("SAMPLE", "title"))
            print(
                style(info.get("value", ""))
                + "  The quick brown fox 0123456789  "
                + RESET
                + "\n"
            )
            print(swatches(info.get("value", "")) + "\n")
        if "rendered" in info:
            print(paint("RENDERED", "title"))
            print(sample(info["rendered"], info.get("base_style", "")) + "\n")
        term = name[2:-1] if name.startswith("#{") else name
        reference = info.get("description") or documentation(term)
        if not reference and info.get("hook"):
            command = re.sub(r"\[\d+\]$", "", term).removeprefix("after-")
            reference = (
                "Run after " + command + " completes.\n\n" + documentation(command)
                if term.startswith("after-")
                else ""
            )
        section("Reference", reference)


def stream(args):
    for line in sys.stdin:
        fields = line.rstrip("\n").split("\t", 1)
        if len(fields) != 2:
            continue
        identifier, display = fields
        if args.mode in ("sessions", "windows", "panes"):
            first, _, rest = display.partition("  ")
            decorated = paint(first, "name") + "  " + paint(rest, "dim")
            decorated = decorated.replace("attached", paint("attached", "value"))
        elif args.mode == "buffers":
            first, _, rest = display.partition("  ")
            decorated = paint(first.ljust(22), "name") + " " + paint(rest, "dim")
        else:
            pane, _, text = display.partition("  ")
            decorated = paint(pane.ljust(6), "scope") + " " + paint(text, "value")
        row(identifier, decorated)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("operation", choices=("list", "preview", "stream"))
    parser.add_argument("mode")
    parser.add_argument("--pane", default="")
    parser.add_argument("--table", default="all")
    parser.add_argument("--option-scope", choices=("all", *SCOPES), default="all")
    parser.add_argument("--user-only", action="store_true")
    parser.add_argument("--builtin-only", action="store_true")
    parser.add_argument("--options-file", default="")
    parser.add_argument("--data-file", default="")
    parser.add_argument("--identifier", default="")
    parser.add_argument("--metadata", default="{}")
    args = parser.parse_args()
    if args.operation == "preview":
        preview(args)
    elif args.operation == "stream":
        stream(args)
    elif args.mode == "keys":
        keys(args)
    elif args.mode == "commands":
        commands(args)
    elif args.mode == "variables":
        variables(args)
    else:
        options(args, args.mode)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError) as error:
        print(f"tmux: {error}", file=sys.stderr)
        sys.exit(1)
