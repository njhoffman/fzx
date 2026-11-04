#!/usr/bin/env python3
"""Open tabs from what browsers keep on disk; standard library only.

stdin: "src<TAB>label<TAB>profile directory" per profile, src being "firefox:..." or "chrome:...".
stdout: "src<TAB>title<TAB>url<TAB>window<TAB><TAB><TAB>label" per tab, the fields browser::rows takes, by window
then tab order. A profile that cannot be read gets one row saying so, with no URL.

Firefox: sessionstore-backups/recovery.jsonlz4 while it runs, sessionstore.jsonlz4 after it closes: mozLz40 (an
8-byte magic, the size, an LZ4 block) around JSON.

Chromium family: Sessions/Session_* (or the older "Current Session"), SNSS: a log of commands the browser appends
to, undocumented and subject to change. A tab closed moments ago can linger until the next rewrite.
"""

import glob
import json
import os
import struct
import sys

# SNSS commands (components/sessions/core/session_service_commands.cc)
SET_TAB_WINDOW = 0
SET_TAB_INDEX_IN_WINDOW = 2
UPDATE_TAB_NAVIGATION = 6
SET_SELECTED_NAVIGATION_INDEX = 7
TAB_CLOSED = 16
WINDOW_CLOSED = 17


def clean(text):
    return " ".join(str(text).split())


def lz4_block(data):
    """The LZ4 block format: literal runs and back references."""
    out = bytearray()
    i = 0
    end = len(data)
    while i < end:
        token = data[i]
        i += 1
        length = token >> 4
        if length == 15:
            while True:
                more = data[i]
                i += 1
                length += more
                if more != 255:
                    break
        out += data[i : i + length]
        i += length
        if i >= end:
            break
        offset = data[i] | data[i + 1] << 8
        i += 2
        length = token & 15
        if length == 15:
            while True:
                more = data[i]
                i += 1
                length += more
                if more != 255:
                    break
        length += 4
        start = len(out) - offset
        if offset == 0 or start < 0:
            raise ValueError("bad back reference")
        for k in range(length):
            out.append(out[start + k])
    return bytes(out)


def firefox_tabs(directory):
    """(window, order, title, url) per open tab."""
    for name in ("sessionstore-backups/recovery.jsonlz4", "sessionstore.jsonlz4"):
        path = os.path.join(directory, name)
        if os.path.exists(path):
            break
    else:
        return []
    with open(path, "rb") as file:
        raw = file.read()
    if raw[:8] != b"mozLz40\0":
        raise ValueError("not a mozLz4 file")
    size = struct.unpack("<I", raw[8:12])[0]
    state = json.loads(lz4_block(raw[12:])[:size])
    tabs = []
    for w, window in enumerate(state.get("windows", []), 1):
        for t, tab in enumerate(window.get("tabs", [])):
            entries = tab.get("entries") or []
            # index counts from 1; a hidden tab is in another tab group's view, still open
            index = tab.get("index", len(entries))
            if not entries or not 1 <= index <= len(entries):
                continue
            entry = entries[index - 1]
            if entry.get("url"):
                tabs.append((w, t, entry.get("title", ""), entry["url"]))
    return tabs


def pickled_string(payload, at, wide=False):
    """A base::Pickle string: its length, then the text padded to 4 bytes."""
    count = struct.unpack("<i", payload[at : at + 4])[0]
    at += 4
    size = count * 2 if wide else count
    if count < 0 or at + size > len(payload):
        raise ValueError("bad string")
    text = payload[at : at + size].decode("utf-16-le" if wide else "utf-8", "replace")
    return text, at + (size + 3 & ~3)


def chromium_tabs(directory):
    """(window, order, title, url) per open tab, from the newest session file."""
    files = glob.glob(os.path.join(directory, "Sessions", "Session_*"))
    files += glob.glob(os.path.join(directory, "Current Session"))
    if not files:
        return []
    with open(max(files, key=os.path.getmtime), "rb") as file:
        raw = file.read()
    if raw[:4] != b"SNSS":
        raise ValueError("not an SNSS file")
    navigations, selected, window_of, index_of = {}, {}, {}, {}
    closed_tabs, closed_windows = set(), set()
    i = 8
    while i + 2 <= len(raw):
        size = struct.unpack("<H", raw[i : i + 2])[0]
        i += 2
        if size < 1 or i + size > len(raw):
            # the browser may be writing the last command
            break
        command, payload = raw[i], raw[i + 1 : i + size]
        i += size
        try:
            if command == UPDATE_TAB_NAVIGATION:
                # a pickle: its size, tab id, navigation index, URL, title
                tab, index = struct.unpack("<ii", payload[4:12])
                url, at = pickled_string(payload, 12)
                title, _ = pickled_string(payload, at, wide=True)
                navigations.setdefault(tab, {})[index] = (url, title)
            elif command == SET_SELECTED_NAVIGATION_INDEX:
                tab, index = struct.unpack("<ii", payload[:8])
                selected[tab] = index
            elif command == SET_TAB_WINDOW:
                window, tab = struct.unpack("<ii", payload[:8])
                window_of[tab] = window
            elif command == SET_TAB_INDEX_IN_WINDOW:
                tab, index = struct.unpack("<ii", payload[:8])
                index_of[tab] = index
            elif command == TAB_CLOSED:
                closed_tabs.add(struct.unpack("<i", payload[:4])[0])
            elif command == WINDOW_CLOSED:
                closed_windows.add(struct.unpack("<i", payload[:4])[0])
        except (struct.error, ValueError):
            continue
    if not navigations and len(raw) > 8:
        raise ValueError("no tabs found: the session format may have changed")
    numbers = {}
    tabs = []
    for tab, pages in navigations.items():
        window = window_of.get(tab)
        if tab in closed_tabs or window in closed_windows or window is None:
            continue
        page = pages.get(selected.get(tab, max(pages)))
        if not page or not page[0]:
            continue
        number = numbers.setdefault(window, len(numbers) + 1)
        tabs.append((number, index_of.get(tab, 0), page[1], page[0]))
    return tabs


def main():
    for line in sys.stdin:
        fields = line.rstrip("\n").split("\t")
        if len(fields) != 3:
            continue
        src, label, directory = fields
        read = firefox_tabs if src.startswith("firefox:") else chromium_tabs
        try:
            tabs = sorted(read(directory), key=lambda tab: tab[:2])
        except (OSError, ValueError, KeyError, IndexError, struct.error) as error:
            print(f"{src}\tcannot read its open tabs: {clean(error)}\t\t\t\t\t{label}")
            continue
        for window, _, title, url in tabs:
            print(f"{src}\t{clean(title)}\t{clean(url)}\twindow {window}\t\t\t{label}")


if __name__ == "__main__":
    main()
